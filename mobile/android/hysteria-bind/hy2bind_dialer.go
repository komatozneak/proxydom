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
// second handshake. Same Cronet fail-fast as Xray `quic-reject`: drop UDP/443
// so the app retries TCP immediately. DNS UDP/53 still goes through Hy2.
var errQuicReject = errors.New("quic-reject")

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
	c client.Client
}

var _ proxy.Dialer = (*hyDialer)(nil)

func (d *hyDialer) DialContext(_ context.Context, m *M.Metadata) (net.Conn, error) {
	if shouldSkipCDN(m.DstIP) {
		return nil, errSkipCDN
	}
	return d.c.TCP(egressAddr(m))
}

func (d *hyDialer) DialUDP(m *M.Metadata) (net.PacketConn, error) {
	if m.DstPort == 443 {
		return nil, errQuicReject
	}
	u, err := d.c.UDP()
	if err != nil {
		return nil, err
	}
	orig := m.UDPAddr()
	if orig == nil {
		orig = &net.UDPAddr{IP: net.IPv4zero, Port: int(m.DstPort)}
	}
	send := m.DestinationAddress()
	if shouldHijackDNS(m.DstIP, m.DstPort) {
		send = "1.1.1.1:53"
	}
	return newHyPacketConn(u, orig, send, isDNSPacketDest(orig, send)), nil
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
	if port != 53 {
		return false
	}
	if !ip.IsValid() {
		return true
	}
	return ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast() || ip.IsUnspecified()
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
	u        client.HyUDPConn
	orig     net.Addr
	send     string
	isDNS    bool
	incoming chan udpRecv
	closed   chan struct{}
	closeMu  sync.Once
	mu       sync.Mutex
	deadline time.Time
}

func newHyPacketConn(u client.HyUDPConn, orig net.Addr, send string, isDNS bool) *hyPacketConn {
	c := &hyPacketConn{
		u:        u,
		orig:     orig,
		send:     send,
		isDNS:    isDNS,
		incoming: make(chan udpRecv),
		closed:   make(chan struct{}),
	}
	go c.recvLoop()
	return c
}

func (c *hyPacketConn) recvLoop() {
	defer close(c.incoming)
	for {
		b, addr, err := c.u.Receive()
		if c.isDNS && err == nil && len(b) > 0 {
			b = filterDNSResponse(b)
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
	dest := c.send
	if dest == "" && addr != nil {
		dest = addr.String()
	}
	if err := c.u.Send(p, dest); err != nil {
		return 0, err
	}
	return len(p), nil
}

func (c *hyPacketConn) Close() error {
	c.closeMu.Do(func() { close(c.closed) })
	return c.u.Close()
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
