package hy2bind

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"strconv"
	"sync"
	"sync/atomic"
	"time"

	v2core "github.com/v2fly/v2ray-core/v5"
	vnet "github.com/v2fly/v2ray-core/v5/common/net"
	"github.com/v2fly/v2ray-core/v5/transport/internet"
	"github.com/xjasonlyu/tun2socks/v2/core/device/fdbased"
	M "github.com/xjasonlyu/tun2socks/v2/metadata"
	"github.com/xjasonlyu/tun2socks/v2/proxy"
	"github.com/xjasonlyu/tun2socks/v2/tunnel"
)

var (
	shareMu   sync.Mutex
	shareInst *v2core.Instance
	shareAddr atomic.Value // string
)

// shareListenAddr reads the local SOCKS address out of the document, so the
// tunnel is pointed at the port the core was actually told to listen on rather
// than at a constant that can drift away from it.
//
// An empty answer means the document does not say, and the caller must refuse
// rather than guess. There used to be a `127.0.0.1:10809` fallback here, which
// was worse than useless: a port the core was never told to bind looks exactly
// like a working one until something dials it. This runs only after the core has
// started, and a core that started had a real inbound, so an empty answer means
// our reading of the document disagrees with the core's — and then the honest
// move is to stop, not to pick a number.
func shareListenAddr(configJSON string) string {
	var doc struct {
		Inbounds []struct {
			Listen string `json:"listen"`
			Port   int    `json:"port"`
		} `json:"inbounds"`
	}
	if err := json.Unmarshal([]byte(configJSON), &doc); err != nil || len(doc.Inbounds) == 0 {
		return ""
	}
	in := doc.Inbounds[0]
	if in.Port <= 0 {
		return ""
	}
	host := in.Listen
	if host == "" {
		host = "127.0.0.1"
	}
	return net.JoinHostPort(host, strconv.Itoa(in.Port))
}

// ShareSocksAddr is where the running VLESS core accepts SOCKS. Empty when the
// core is not running.
func ShareSocksAddr() string {
	if !shareRunning() {
		return ""
	}
	addr, _ := shareAddr.Load().(string)
	return addr
}

// shareSplitPolicy is the part of the VLESS document the core itself does not
// read. It is separated from the v2ray config so the same policy fields that
// the Hysteria2 start document uses also reach the TUN dialer for VLESS.
type shareSplitPolicy struct {
	Direct  []string `json:"direct_domain_suffixes"`
	Force   []string `json:"force_proxy_domains"`
	UDPMode string   `json:"udp_mode"`
}

func applyShareSplitPolicy(configJSON string) {
	var policy shareSplitPolicy
	if err := json.Unmarshal([]byte(configJSON), &policy); err != nil {
		return
	}
	setExtraForceSuffixes(policy.Force)
	setDirectSuffixes(policy.Direct)
	setUDPDirect(policy.UDPMode == "direct_non_forced")
}

// StartShare runs v2ray-core inside this gomobile runtime.
// A second gomobile runtime deadlocks on Pixel, so this is not a separate AAR.
// [configJSON] holds credentials; do not log it.
func StartShare(configJSON string) string {
	if configJSON == "" {
		return "empty share config"
	}
	// The REALITY engine is a second share core, not a v2ray document: it
	// carries a VLESS stream over a handshake v2ray-core does not implement.
	// The document names itself, so the same StartShare entry point serves
	// Android, iOS and the Windows engine.
	if isRealityDocument(configJSON) {
		return startRealityShare(configJSON)
	}
	// A v2ray start takes the share slot back from a previous REALITY session.
	stopRealityShare()
	// The VLESS document carries the same site policy as the Hy2 start
	// document. Applying it here, before the core starts, keeps one classifier
	// for both engines: the TUN dialer decides, v2ray only carries the flow.
	clearSplitState()
	applyShareSplitPolicy(configJSON)
	prepareCoreLog(configJSON)
	registerEngineProtector()
	lastProtectErr.Store("")
	cfg, err := loadShareConfig(configJSON)
	if err != nil {
		return fmt.Sprintf("engine: %v", err)
	}
	inst, err := v2core.New(cfg)
	if err != nil {
		return fmt.Sprintf("engine: %v", err)
	}
	// New() installs the core log handler. Bind after that so decision lines
	// reach the file instead of stdout.
	bindCoreLogHandler()
	if err := inst.Start(); err != nil {
		return fmt.Sprintf("engine: %v", err)
	}
	// Only now, and only once the core is up. The address used to be stored
	// before the config was even parsed, so a start that failed still left it
	// behind: ShareSocksAddr would then answer with a port nothing listens on
	// for as long as some other core was running, and the tunnel would be
	// pointed at it.
	shareAddr.Store(shareListenAddr(configJSON))
	shareMu.Lock()
	prev := shareInst
	shareInst = inst
	shareMu.Unlock()
	// After the swap, not before. ShareSocksAddr reports the running core's
	// address and answers empty until shareInst is set, so logging it first
	// recorded "socks=" on every session — the one line meant to say which port
	// the core listens on said nothing at all.
	noteShareCore()
	if prev != nil {
		_ = prev.Close()
	}
	return ""
}

func stopShare() {
	stopRealityShare()
	shareMu.Lock()
	inst := shareInst
	shareInst = nil
	shareMu.Unlock()
	if inst != nil {
		_ = inst.Close()
	}
	// Cleared with the core, so the recorded address never outlives the port it
	// names. ShareSocksAddr already guards on shareRunning, but leaving a dead
	// port in the variable means the next reader that forgets the guard dials it.
	shareAddr.Store("")
	// The policy belongs to this session. A later Hy2 or VLESS session applies
	// its own before dialling, and leaving the old suffixes here would route a
	// stopped session's domains if anything still called the classifier.
	clearSplitState()
}

func shareRunning() bool {
	return v2ShareRunning() || realityRunning()
}

func v2ShareRunning() bool {
	shareMu.Lock()
	defer shareMu.Unlock()
	return shareInst != nil
}

var engineProtectOnce sync.Once
var lastProtectErr atomic.Value

// LastProtectError is the latest VpnService.protect failure. Empty if the
// last dial was protected. A failed protect returns an error so the socket
// is not connected.
func LastProtectError() string {
	text, _ := lastProtectErr.Load().(string)
	return text
}

func registerEngineProtector() {
	engineProtectOnce.Do(func() {
		internet.UseAlternativeSystemDialer(protectedSystemDialer{})
	})
}

// protectedSystemDialer owns the socket the core dials its node on. What
// "owning" means is per platform, so the body lives in hy2bind_protect_*.go:
// Android protects the fd, Windows binds it to the physical NIC.
type protectedSystemDialer struct{}

func (protectedSystemDialer) Dial(
	ctx context.Context,
	_ vnet.Address,
	dest vnet.Destination,
	_ *internet.SocketConfig,
) (net.Conn, error) {
	return engineOutboundDial(ctx, dest.Network.SystemString(), dest.NetAddr())
}

// StartShareTun pumps VpnService TUN to the local share SOCKS inbound.
func StartShareTun(fd int, mtu int) string {
	if fd <= 0 {
		return "invalid tun fd"
	}
	if mtu <= 0 {
		mtu = 1500
	}
	if !shareRunning() {
		closeTunFd(fd)
		return "share core not started"
	}
	mu.Lock()
	defer mu.Unlock()
	if tunStk != nil {
		closeTunFd(fd)
		return "tun already running"
	}
	dev, err := fdbased.Open(strconv.Itoa(fd), uint32(mtu), 0)
	if err != nil {
		closeTunFd(fd)
		return fmt.Sprintf("tun fd: %v", err)
	}
	tunnel.T().SetProxy(&socksDialer{addr: ShareSocksAddr()})
	st, err := createTunStack(dev)
	if err != nil {
		dev.Close()
		return fmt.Sprintf("tun stack: %v", err)
	}
	tunDev = dev
	tunStk = st
	return ""
}

type socksDialer struct {
	addr string
}

var _ proxy.Proxy = (*socksDialer)(nil)

func (d *socksDialer) DialContext(ctx context.Context, m *M.Metadata) (net.Conn, error) {
	if m == nil {
		return nil, errNilMetadata
	}
	addr := m.DestinationAddress()
	if !sniffablePort(m.DstPort) {
		direct, why := routeFor("", m.DstIP)
		return d.dialRoute("tcp", addr, direct, why)
	}
	return newSniffConn(ctx, m.DstIP, m.DstPort, addr, d), nil
}

func (d *socksDialer) dialRoute(network, addr string, direct bool, why string) (net.Conn, error) {
	chain := "proxy"
	var conn net.Conn
	var err error
	if direct {
		chain = "direct"
		conn, err = dialOutsideTun(network, addr)
	} else {
		conn, err = d.dialSocks(addr)
	}
	if err != nil {
		return nil, err
	}
	log.Printf("hy2bind share route %s %s why=%s", chain, addr, why)
	return trackStream(conn, network, addr, chain), nil
}

func (d *socksDialer) dialSocks(dest string) (net.Conn, error) {
	conn, err := net.DialTimeout("tcp", d.addr, 5*time.Second)
	if err != nil {
		return nil, err
	}
	if err := socks5Connect(conn, dest); err != nil {
		_ = conn.Close()
		return nil, err
	}
	return conn, nil
}

func (d *socksDialer) DialUDP(m *M.Metadata) (net.PacketConn, error) {
	if shouldDirectUDP(m) {
		pc, err := dialOutsideUDP(m.DestinationAddress())
		if err != nil {
			return nil, err
		}
		return trackPacket(pc, "udp", m.DestinationAddress(), "direct"), nil
	}
	conn, err := net.DialTimeout("tcp", d.addr, 5*time.Second)
	if err != nil {
		return nil, err
	}
	bound, err := socks5UDPAssociate(conn)
	if err != nil {
		_ = conn.Close()
		return nil, err
	}
	udp, err := net.DialUDP("udp", nil, bound)
	if err != nil {
		_ = conn.Close()
		return nil, err
	}
	return &socksUDP{tcp: conn, udp: udp, dst: m.DestinationAddress()}, nil
}

func socks5Connect(conn net.Conn, dest string) error {
	if err := socks5Greet(conn); err != nil {
		return err
	}
	host, port, err := splitHostPort(dest)
	if err != nil {
		return err
	}
	req := append([]byte{0x05, 0x01, 0x00}, socksAddr(host, port)...)
	if _, err := conn.Write(req); err != nil {
		return err
	}
	return readSocksReply(conn)
}

func socks5UDPAssociate(conn net.Conn) (*net.UDPAddr, error) {
	if err := socks5Greet(conn); err != nil {
		return nil, err
	}
	req := []byte{0x05, 0x03, 0x00, 0x01, 0, 0, 0, 0, 0, 0}
	if _, err := conn.Write(req); err != nil {
		return nil, err
	}
	host, port, err := readSocksBound(conn)
	if err != nil {
		return nil, err
	}
	if host == "" || host == "0.0.0.0" || host == "::" {
		if tcp, ok := conn.RemoteAddr().(*net.TCPAddr); ok && tcp.IP != nil {
			host = tcp.IP.String()
		}
	}
	ip := net.ParseIP(host)
	if ip == nil {
		return nil, errors.New("socks udp bind")
	}
	return &net.UDPAddr{IP: ip, Port: port}, nil
}

func socks5Greet(conn net.Conn) error {
	if _, err := conn.Write([]byte{0x05, 0x01, 0x00}); err != nil {
		return err
	}
	buf := make([]byte, 2)
	if _, err := io.ReadFull(conn, buf); err != nil {
		return err
	}
	if buf[0] != 0x05 || buf[1] != 0x00 {
		return errors.New("socks auth")
	}
	return nil
}

func readSocksReply(conn net.Conn) error {
	_, _, err := readSocksBound(conn)
	return err
}

func readSocksBound(conn net.Conn) (string, int, error) {
	hdr := make([]byte, 4)
	if _, err := io.ReadFull(conn, hdr); err != nil {
		return "", 0, err
	}
	if hdr[1] != 0x00 {
		return "", 0, fmt.Errorf("socks reply %d", hdr[1])
	}
	switch hdr[3] {
	case 0x01:
		buf := make([]byte, 4+2)
		if _, err := io.ReadFull(conn, buf); err != nil {
			return "", 0, err
		}
		ip := net.IP(buf[:4]).String()
		port := int(binary.BigEndian.Uint16(buf[4:]))
		return ip, port, nil
	case 0x03:
		ln := make([]byte, 1)
		if _, err := io.ReadFull(conn, ln); err != nil {
			return "", 0, err
		}
		buf := make([]byte, int(ln[0])+2)
		if _, err := io.ReadFull(conn, buf); err != nil {
			return "", 0, err
		}
		host := string(buf[:len(buf)-2])
		port := int(binary.BigEndian.Uint16(buf[len(buf)-2:]))
		return host, port, nil
	case 0x04:
		buf := make([]byte, 16+2)
		if _, err := io.ReadFull(conn, buf); err != nil {
			return "", 0, err
		}
		ip := net.IP(buf[:16]).String()
		port := int(binary.BigEndian.Uint16(buf[16:]))
		return ip, port, nil
	default:
		return "", 0, errors.New("socks atyp")
	}
}

const socksUDPHeaderMax = 3 + 1 + 255 + 2

func socksUDPPayload(pkt []byte) ([]byte, error) {
	if len(pkt) < 4 {
		return nil, errors.New("socks udp short")
	}
	var rest int
	switch pkt[3] {
	case 0x01:
		rest = 4 + 2
	case 0x04:
		rest = 16 + 2
	case 0x03:
		if len(pkt) < 5 {
			return nil, errors.New("socks udp short")
		}
		rest = 1 + int(pkt[4]) + 2
	default:
		return nil, errors.New("socks udp atyp")
	}
	off := 4 + rest
	if len(pkt) < off {
		return nil, errors.New("socks udp short")
	}
	return pkt[off:], nil
}

func socksAddr(host string, port int) []byte {
	if ip := net.ParseIP(host); ip != nil {
		if v4 := ip.To4(); v4 != nil {
			out := []byte{0x01}
			out = append(out, v4...)
			var p [2]byte
			binary.BigEndian.PutUint16(p[:], uint16(port))
			return append(out, p[:]...)
		}
	}
	out := []byte{0x03, byte(len(host))}
	out = append(out, []byte(host)...)
	var p [2]byte
	binary.BigEndian.PutUint16(p[:], uint16(port))
	return append(out, p[:]...)
}

func splitHostPort(dest string) (string, int, error) {
	host, portStr, err := net.SplitHostPort(dest)
	if err != nil {
		return "", 0, err
	}
	port, err := strconv.Atoi(portStr)
	if err != nil {
		return "", 0, err
	}
	return host, port, nil
}

type socksUDP struct {
	tcp net.Conn
	udp *net.UDPConn
	dst string
}

func (s *socksUDP) ReadFrom(b []byte) (int, net.Addr, error) {
	// Reply is RSV, FRAG, address, then the datagram. tun2socks wants only
	// the datagram; leaving the header on makes DNS answers unreadable.
	buf := make([]byte, len(b)+socksUDPHeaderMax)
	n, _, err := s.udp.ReadFrom(buf)
	if err != nil {
		return 0, nil, err
	}
	payload, err := socksUDPPayload(buf[:n])
	if err != nil {
		return 0, nil, err
	}
	if len(payload) > len(b) {
		return 0, nil, io.ErrShortBuffer
	}
	copy(b, payload)
	return len(payload), nil, nil
}

func (s *socksUDP) WriteTo(b []byte, _ net.Addr) (int, error) {
	host, port, err := splitHostPort(s.dst)
	if err != nil {
		return 0, err
	}
	pkt := append([]byte{0, 0, 0}, socksAddr(host, port)...)
	pkt = append(pkt, b...)
	return s.udp.Write(pkt)
}

func (s *socksUDP) Close() error {
	_ = s.udp.Close()
	return s.tcp.Close()
}

func (s *socksUDP) LocalAddr() net.Addr                { return s.udp.LocalAddr() }
func (s *socksUDP) SetDeadline(t time.Time) error      { return s.udp.SetDeadline(t) }
func (s *socksUDP) SetReadDeadline(t time.Time) error  { return s.udp.SetReadDeadline(t) }
func (s *socksUDP) SetWriteDeadline(t time.Time) error { return s.udp.SetWriteDeadline(t) }
