package hy2bind

import (
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"strconv"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	v2core "github.com/v2fly/v2ray-core/v5"
	vnet "github.com/v2fly/v2ray-core/v5/common/net"
	"github.com/v2fly/v2ray-core/v5/transport/internet"
	"github.com/xjasonlyu/tun2socks/v2/core/device/fdbased"
	M "github.com/xjasonlyu/tun2socks/v2/metadata"
	"github.com/xjasonlyu/tun2socks/v2/proxy"
	"github.com/xjasonlyu/tun2socks/v2/tunnel"
)

// shareSocks is the local VLESS-core SOCKS inbound. Hy2 keeps :10808.
const shareSocks = "127.0.0.1:10809"

var (
	shareMu   sync.Mutex
	shareInst *v2core.Instance
)

// StartShare runs v2ray-core inside this gomobile runtime.
// A second gomobile runtime deadlocks on Pixel, so this is not a separate AAR.
// [configJSON] holds credentials; do not log it.
func StartShare(configJSON string) string {
	if configJSON == "" {
		return "empty share config"
	}
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
	noteShareCore()
	shareMu.Lock()
	prev := shareInst
	shareInst = inst
	shareMu.Unlock()
	if prev != nil {
		_ = prev.Close()
	}
	return ""
}

func stopShare() {
	shareMu.Lock()
	inst := shareInst
	shareInst = nil
	shareMu.Unlock()
	if inst != nil {
		_ = inst.Close()
	}
}

func shareRunning() bool {
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

// protectedSystemDialer owns the socket: protect(fd) then connect.
// A failed protect returns an error. The fd is not closed inside Control,
// because the core has not handed the socket to connect yet.
type protectedSystemDialer struct{}

func (protectedSystemDialer) Dial(
	ctx context.Context,
	_ vnet.Address,
	dest vnet.Destination,
	_ *internet.SocketConfig,
) (net.Conn, error) {
	dialer := &net.Dialer{
		Timeout: 8 * time.Second,
		Control: func(network, address string, c syscall.RawConn) error {
			var protectErr error
			ctrlErr := c.Control(func(fd uintptr) {
				mu.Lock()
				p := protector
				mu.Unlock()
				if p == nil || !p.Protect(int(fd)) {
					protectErr = errors.New("protect failed")
					lastProtectErr.Store("protect failed")
					return
				}
				lastProtectErr.Store("")
			})
			if ctrlErr != nil {
				return ctrlErr
			}
			return protectErr
		},
	}
	return dialer.DialContext(ctx, dest.Network.SystemString(), dest.NetAddr())
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
	tunnel.T().SetProxy(&socksDialer{addr: shareSocks})
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
	conn, err := net.DialTimeout("tcp", d.addr, 5*time.Second)
	if err != nil {
		return nil, err
	}
	if err := socks5Connect(conn, m.DestinationAddress()); err != nil {
		_ = conn.Close()
		return nil, err
	}
	return conn, nil
}

func (d *socksDialer) DialUDP(m *M.Metadata) (net.PacketConn, error) {
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
