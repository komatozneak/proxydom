package hy2bind

import (
	"context"
	"errors"
	"net"
	"net/netip"
	"sync"
	"time"

	"github.com/apernet/hysteria/core/v2/client"
	M "github.com/xjasonlyu/tun2socks/v2/metadata"
	"github.com/xjasonlyu/tun2socks/v2/proxy"
)

// Nested QUIC (YouTube HTTP/3 inside Hy2 QUIC) makes page clicks wait on a
// second handshake. UDP/443 is refused in the gVisor handler with ICMP port
// unreachable (see installUDPForwarder). This error is the backstop if a
// datagram is already inside a session. DNS UDP/53 still goes through Hy2.
var errQuicReject = errors.New("quic-reject")

var errNilMetadata = errors.New("nil metadata")

// EU Hy2 → these Google caches (SK Broadband / LG Uplus) stall YouTube
// first-frame ~20s. Fail-fast so Cronet uses 142.251/74.125. Not a /24 poison.
var errSkipCDN = errors.New("skip-cdn")

var skipCDNNets = []netip.Prefix{
	netip.MustParsePrefix("211.114.0.0/16"),
	netip.MustParsePrefix("59.18.0.0/16"),
}

func shouldSkipCDN(ip netip.Addr) bool {
	if !ip.IsValid() {
		return false
	}
	ip = ip.Unmap()
	for _, p := range skipCDNNets {
		if p.Contains(ip) {
			return true
		}
	}
	return false
}

// hyDialer sends TUN TCP/UDP through official Hy2 client APIs
// (apernet/hysteria TUN: HyClient.TCP / HyClient.UDP). SOCKS5 UDP ASSOCIATE
// is not used — our SOCKS listener is TCP CONNECT only, which broke DNS
// and QUIC/YouTube (UDP ASSOCIATE: command not supported).
type hyDialer struct {
	c          client.Client
	directDial func(network, addr string) (net.Conn, error)
}

var _ proxy.Proxy = (*hyDialer)(nil)

func (d *hyDialer) DialContext(ctx context.Context, m *M.Metadata) (net.Conn, error) {
	if m == nil {
		return nil, errNilMetadata
	}
	if shouldSkipCDN(m.DstIP) {
		return nil, errSkipCDN
	}
	addr := egressAddr(m)
	// One line per connection. The broker reads this to tell a tunnel that
	// never received the packet apart from one that received it and could not
	// dial, which is the difference between a routing fault and a proxy fault.
	connLogf("hy2bind dial tcp %s", addr)
	if shouldHijackDNS(m.DstIP, m.DstPort) {
		return d.dialRoute("tcp", addr, false, "dns")
	}
	if !sniffablePort(m.DstPort) {
		direct, why := routeFor("", m.DstIP)
		return d.dialRoute("tcp", addr, direct, why)
	}
	return newSniffConn(ctx, m.DstIP, m.DstPort, addr, d), nil
}

// dialRoute opens the socket the classifier chose and records the flow under
// the chain it actually used.
func (d *hyDialer) dialRoute(network, addr string, direct bool, why string) (net.Conn, error) {
	chain := "proxy"
	var conn net.Conn
	var err error
	if direct {
		chain = "direct"
		conn, err = d.dialDirect(network, addr)
	} else {
		conn, err = d.c.TCP(addr)
	}
	if err != nil {
		return nil, err
	}
	connLogf("hy2bind route %s %s why=%s", chain, addr, why)
	return trackStream(conn, network, addr, chain), nil
}

func (d *hyDialer) DialUDP(m *M.Metadata) (net.PacketConn, error) {
	if m.DstPort == 443 {
		return nil, errQuicReject
	}
	orig := m.UDPAddr()
	if orig == nil {
		orig = &net.UDPAddr{IP: net.IPv4zero, Port: int(m.DstPort)}
	}
	send := m.DestinationAddress()
	if shouldHijackDNS(m.DstIP, m.DstPort) {
		send = "1.1.1.1:53"
	} else if shouldDirectUDP(m) {
		pc, err := dialOutsideUDP(m.DestinationAddress())
		if err != nil {
			return nil, err
		}
		return trackPacket(pc, "udp", m.DestinationAddress(), "direct"), nil
	}
	// Open the Hy2 UDP session on the first real send. Identical DNS questions
	// share one lookup and never open a second session.
	pc := newLazyHyPacketConn(func() (client.HyUDPConn, error) {
		return d.c.UDP()
	}, orig, send, isDNSPacketDest(orig, send))
	return trackPacket(pc, "udp", send, "proxy"), nil
}

func shouldDirectUDP(m *M.Metadata) bool {
	if m == nil || m.DstPort == 53 {
		return false
	}
	// A name that the resolver answered and that is unambiguously in the list
	// may leave directly even in the default (proxy-all) mode. This is what
	// makes a listed voice/game service work while everything else is tunneled.
	if _, ok := ipAllDirect(m.DstIP); ok {
		return true
	}
	if !udpDirectOn() {
		return false
	}
	// Game mode is a protocol bypass, but it must never drag a force-proxied
	// name out of the tunnel. Check every known name on the address, not just
	// the first one.
	for _, host := range hostsForIP(m.DstIP) {
		if isForceProxyHost(host) {
			return false
		}
	}
	return true
}

func isDNSPacketDest(orig net.Addr, send string) bool {
	if ua, ok := orig.(*net.UDPAddr); ok && ua != nil && ua.Port == 53 {
		return true
	}
	_, port, err := net.SplitHostPort(send)
	return err == nil && port == "53"
}

func egressAddr(m *M.Metadata) string {
	if shouldHijackDNS(m.DstIP, m.DstPort) {
		return "1.1.1.1:53"
	}
	return m.DestinationAddress()
}

func shouldHijackDNS(ip netip.Addr, port uint16) bool {
	// Every DNS query that reached the tunnel is answered by the engine's
	// hijack. Leaving public resolvers alone made classification depend on
	// which resolver the user had configured, and leaked the query itself.
	return port == 53
}

type udpRecv struct {
	b    []byte
	addr string
	err  error
}

type timeoutError struct{}

func (timeoutError) Error() string   { return "i/o timeout" }
func (timeoutError) Timeout() bool   { return true }
func (timeoutError) Temporary() bool { return true }

type hyPacketConn struct {
	opener   func() (client.HyUDPConn, error)
	u        client.HyUDPConn
	orig     net.Addr
	send     string
	isDNS    bool
	dnsKey   string
	shut     bool
	incoming chan udpRecv
	closed   chan struct{}
	closeMu  sync.Once
	mu       sync.Mutex
	deadline time.Time
}

func newHyPacketConn(u client.HyUDPConn, orig net.Addr, send string, isDNS bool) *hyPacketConn {
	c := newLazyHyPacketConn(nil, orig, send, isDNS)
	c.u = u
	go c.recvLoop()
	return c
}

func newLazyHyPacketConn(
	opener func() (client.HyUDPConn, error),
	orig net.Addr,
	send string,
	isDNS bool,
) *hyPacketConn {
	return &hyPacketConn{
		opener:   opener,
		orig:     orig,
		send:     send,
		isDNS:    isDNS,
		incoming: make(chan udpRecv),
		closed:   make(chan struct{}),
	}
}

func (c *hyPacketConn) recvLoop() {
	defer close(c.incoming)
	for {
		b, addr, err := c.u.Receive()
		if c.isDNS {
			key := c.dnsKeySnapshot()
			if err != nil {
				dnsFail(c, key, err)
			} else if len(b) > 0 {
				b = filterDNSResponse(b)
				dnsComplete(c, key, b)
			}
		}
		pkt := udpRecv{b: b, addr: addr, err: err}
		select {
		case <-c.closed:
			return
		case c.incoming <- pkt:
			if err != nil {
				return
			}
		}
	}
}

func (c *hyPacketConn) ReadFrom(p []byte) (int, net.Addr, error) {
	c.mu.Lock()
	dl := c.deadline
	c.mu.Unlock()

	var timer <-chan time.Time
	if !dl.IsZero() {
		d := time.Until(dl)
		if d <= 0 {
			return 0, nil, timeoutError{}
		}
		t := time.NewTimer(d)
		defer t.Stop()
		timer = t.C
	}

	select {
	case r, ok := <-c.incoming:
		if !ok {
			return 0, nil, net.ErrClosed
		}
		if r.err != nil {
			return 0, nil, r.err
		}
		return copy(p, r.b), c.orig, nil
	case <-timer:
		return 0, nil, timeoutError{}
	case <-c.closed:
		return 0, nil, net.ErrClosed
	}
}

func (c *hyPacketConn) WriteTo(p []byte, addr net.Addr) (int, error) {
	if c.isDNS {
		switch decision, hit := dnsPlan(c, p); decision {
		case dnsHit:
			c.deliverLocal(hit)
			return len(p), nil
		case dnsJoined, dnsRepeat:
			return len(p), nil
		}
	}
	if err := c.ensureUpstream(); err != nil {
		dnsFail(c, c.dnsKeySnapshot(), err)
		return 0, err
	}
	dest := c.send
	if dest == "" && addr != nil {
		dest = addr.String()
	}
	if err := c.u.Send(p, dest); err != nil {
		dnsFail(c, c.dnsKeySnapshot(), err)
		return 0, err
	}
	return len(p), nil
}

func (c *hyPacketConn) rememberDNSKey(key string) {
	c.mu.Lock()
	if c.dnsKey == "" {
		c.dnsKey = key
	}
	c.mu.Unlock()
}

func (c *hyPacketConn) dnsKeySnapshot() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.dnsKey
}

func (c *hyPacketConn) ensureUpstream() error {
	c.mu.Lock()
	if c.u != nil {
		c.mu.Unlock()
		return nil
	}
	if c.shut {
		c.mu.Unlock()
		return net.ErrClosed
	}
	opener := c.opener
	c.mu.Unlock()
	if opener == nil {
		return net.ErrClosed
	}
	u, err := opener()
	if err != nil {
		return err
	}
	c.mu.Lock()
	if c.shut || c.u != nil {
		c.mu.Unlock()
		_ = u.Close()
		if c.shut {
			return net.ErrClosed
		}
		return nil
	}
	c.u = u
	c.mu.Unlock()
	go c.recvLoop()
	return nil
}

func (c *hyPacketConn) deliverLocal(b []byte) {
	if len(b) == 0 {
		return
	}
	pkt := udpRecv{b: append([]byte(nil), b...), addr: c.send}
	select {
	case <-c.closed:
	case c.incoming <- pkt:
	}
}

func (c *hyPacketConn) failLocal(err error) {
	if err == nil {
		return
	}
	select {
	case <-c.closed:
	case c.incoming <- udpRecv{err: err}:
	}
}

func (c *hyPacketConn) Close() error {
	c.mu.Lock()
	c.shut = true
	u := c.u
	c.mu.Unlock()
	c.closeMu.Do(func() { close(c.closed) })
	if u != nil {
		return u.Close()
	}
	return nil
}

func (c *hyPacketConn) LocalAddr() net.Addr {
	return &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 0}
}

func (c *hyPacketConn) SetDeadline(t time.Time) error {
	return c.SetReadDeadline(t)
}

func (c *hyPacketConn) SetReadDeadline(t time.Time) error {
	c.mu.Lock()
	c.deadline = t
	c.mu.Unlock()
	return nil
}

func (c *hyPacketConn) SetWriteDeadline(time.Time) error { return nil }
