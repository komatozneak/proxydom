package hy2bind

import (
	"context"
	"errors"
	"net"
	"net/netip"
	"sync"
	"testing"

	M "github.com/xjasonlyu/tun2socks/v2/metadata"
)

type udpMsg struct {
	b    []byte
	addr string
}

type fakeUDPConn struct {
	recv   chan udpMsg
	sentTo string
	once   sync.Once
}

func (f *fakeUDPConn) Receive() ([]byte, string, error) {
	m, ok := <-f.recv
	if !ok {
		return nil, "", net.ErrClosed
	}
	return m.b, m.addr, nil
}

func (f *fakeUDPConn) Send(_ []byte, addr string) error {
	f.sentTo = addr
	return nil
}

func (f *fakeUDPConn) Close() error {
	f.once.Do(func() { close(f.recv) })
	return nil
}

func TestShouldHijackDNS(t *testing.T) {
	peer := netip.MustParseAddr("10.255.255.2")
	lan := netip.MustParseAddr("192.168.0.1")
	cf := netip.MustParseAddr("1.1.1.1")
	yt := netip.MustParseAddr("142.250.185.14")

	if !shouldHijackDNS(peer, 53) {
		t.Fatal("TUN peer DNS must be hijacked")
	}
	if !shouldHijackDNS(lan, 53) {
		t.Fatal("LAN DNS must be hijacked")
	}
	if shouldHijackDNS(cf, 53) {
		t.Fatal("public DNS must pass through Hy2 UDP")
	}
	if shouldHijackDNS(yt, 443) {
		t.Fatal("YouTube QUIC must not be rewritten")
	}
}

func TestShouldSkipCDN(t *testing.T) {
	if !shouldSkipCDN(netip.MustParseAddr("211.114.67.143")) {
		t.Fatal("211.114/16 must skip")
	}
	if !shouldSkipCDN(netip.MustParseAddr("59.18.30.80")) {
		t.Fatal("59.18/16 must skip")
	}
	if shouldSkipCDN(netip.MustParseAddr("142.250.185.14")) {
		t.Fatal("Google must not skip")
	}
	if shouldSkipCDN(netip.MustParseAddr("87.240.139.193")) {
		t.Fatal("VK must not skip")
	}
}

func TestDialContextSkipsKRCDN(t *testing.T) {
	d := &hyDialer{c: &fakeHyClient{}}
	_, err := d.DialContext(context.Background(), &M.Metadata{
		DstIP:   netip.MustParseAddr("211.114.67.143"),
		DstPort: 443,
	})
	if !errors.Is(err, errSkipCDN) {
		t.Fatalf("211.114 got %v", err)
	}
	_, err = d.DialContext(context.Background(), &M.Metadata{
		DstIP:   netip.MustParseAddr("59.18.30.80"),
		DstPort: 443,
	})
	if !errors.Is(err, errSkipCDN) {
		t.Fatalf("59.18 got %v", err)
	}
	fake := &fakeHyClient{}
	d = &hyDialer{c: fake}
	c, err := d.DialContext(context.Background(), &M.Metadata{
		DstIP:   netip.MustParseAddr("142.250.185.14"),
		DstPort: 443,
	})
	if err != nil {
		t.Fatal(err)
	}
	_ = c.Close()
	if fake.gotTarget != "142.250.185.14:443" {
		t.Fatalf("got %q", fake.gotTarget)
	}
}

func TestDialUDPRejectsQUIC(t *testing.T) {
	d := &hyDialer{c: &fakeHyClient{}}
	m := &M.Metadata{
		Network: M.UDP,
		DstIP:   netip.MustParseAddr("142.250.185.14"),
		DstPort: 443,
	}
	_, err := d.DialUDP(m)
	if !errors.Is(err, errQuicReject) {
		t.Fatalf("got %v", err)
	}
}

func TestEgressAddrRewritesPrivateDNS(t *testing.T) {
	m := &M.Metadata{
		DstIP:   netip.MustParseAddr("10.255.255.2"),
		DstPort: 53,
	}
	if got := egressAddr(m); got != "1.1.1.1:53" {
		t.Fatalf("got %q", got)
	}
	m.DstIP = netip.MustParseAddr("142.250.185.14")
	m.DstPort = 443
	if got := egressAddr(m); got != "142.250.185.14:443" {
		t.Fatalf("got %q", got)
	}
}

func TestHyPacketConnHijackPreservesOrigAddr(t *testing.T) {
	orig := &net.UDPAddr{IP: net.ParseIP("10.255.255.2").To4(), Port: 53}
	u := &fakeUDPConn{recv: make(chan udpMsg, 1)}
	pc := newHyPacketConn(u, orig, "1.1.1.1:53")
	defer pc.Close()
	if _, err := pc.WriteTo([]byte("q"), orig); err != nil {
		t.Fatal(err)
	}
	if u.sentTo != "1.1.1.1:53" {
		t.Fatalf("send dest %q", u.sentTo)
	}
	u.recv <- udpMsg{b: []byte("a"), addr: "1.1.1.1:53"}
	buf := make([]byte, 8)
	n, from, err := pc.ReadFrom(buf)
	if err != nil {
		t.Fatal(err)
	}
	if n != 1 || buf[0] != 'a' {
		t.Fatalf("payload n=%d %q", n, buf[:n])
	}
	if from.String() != orig.String() {
		t.Fatalf("from %v want %v (tun2socks symmetric NAT)", from, orig)
	}
}
