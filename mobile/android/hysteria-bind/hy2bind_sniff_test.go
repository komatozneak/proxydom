package hy2bind

import (
	"bytes"
	"context"
	"fmt"
	"net"
	"net/netip"
	"sync"
	"testing"
	"time"

	M "github.com/xjasonlyu/tun2socks/v2/metadata"
)

func buildClientHello(host string) []byte {
	name := []byte(host)
	serverName := append([]byte{0, byte(len(name) >> 8), byte(len(name))}, name...)
	sniData := append([]byte{byte(len(serverName) >> 8), byte(len(serverName))}, serverName...)
	ext := append([]byte{0, 0, byte(len(sniData) >> 8), byte(len(sniData))}, sniData...)

	body := []byte{0x03, 0x03}
	body = append(body, bytes.Repeat([]byte{0x11}, 32)...)
	body = append(body, 0)                // session id length
	body = append(body, 0, 2, 0x13, 0x01) // one cipher suite
	body = append(body, 1, 0)             // one compression method
	body = append(body, byte(len(ext)>>8), byte(len(ext)))
	body = append(body, ext...)

	hs := append([]byte{0x01, byte(len(body) >> 16), byte(len(body) >> 8), byte(len(body))}, body...)
	return append([]byte{0x16, 0x03, 0x01, byte(len(hs) >> 8), byte(len(hs))}, hs...)
}

type fakeRouteDialer struct {
	once   sync.Once
	ch     chan struct{}
	direct bool
	why    string
	addr   string
	writes chan []byte
}

func (f *fakeRouteDialer) dialRoute(network, addr string, direct bool, why string) (net.Conn, error) {
	f.direct = direct
	f.why = why
	f.addr = addr
	a, b := net.Pipe()
	// decide writes the buffered ClientHello before it releases readers, so the
	// peer must consume it. Without this goroutine net.Pipe deadlocks the test.
	go func() {
		defer b.Close()
		buf := make([]byte, 4096)
		for {
			n, err := b.Read(buf)
			if n > 0 {
				f.writes <- append([]byte(nil), buf[:n]...)
			}
			if err != nil {
				return
			}
		}
	}()
	f.once.Do(func() { close(f.ch) })
	return a, nil
}

func TestSniffTLSSNI(t *testing.T) {
	hello := buildClientHello("m.vk.com")
	host, ok := sniffTLSSNI(hello)
	if !ok || host != "m.vk.com" {
		t.Fatalf("host=%q ok=%v", host, ok)
	}
	if _, ok := sniffTLSSNI(hello[:20]); ok {
		t.Fatal("a partial ClientHello must not decide")
	}
}

func TestSniffHTTPHost(t *testing.T) {
	req := []byte("GET / HTTP/1.1\r\nHost: Static.Example.RU:8080\r\n\r\n")
	host, ok := sniffHTTPHost(req)
	if !ok || host != "static.example.ru" {
		t.Fatalf("host=%q ok=%v", host, ok)
	}
	if _, ok := sniffHTTPHost([]byte("GET / HTTP/1.1\r\nHost: example.com\r\n")); ok {
		t.Fatal("headers without the final blank line are incomplete")
	}
}

func TestSniffConnUsesSNI(t *testing.T) {
	t.Cleanup(clearSplitState)
	setDirectSuffixes([]string{"vk.com"})
	dialer := &fakeRouteDialer{ch: make(chan struct{}), writes: make(chan []byte, 4)}
	ip := netip.MustParseAddr("203.0.113.9")
	conn := newSniffConn(context.Background(), ip, 443, "203.0.113.9:443", dialer)
	defer conn.Close()

	hello := buildClientHello("m.vk.com")
	if _, err := conn.Write(hello); err != nil {
		t.Fatal(err)
	}
	select {
	case <-dialer.ch:
	case <-time.After(time.Second):
		t.Fatal("the classifier never dialled")
	}
	if !dialer.direct || dialer.why != "host" {
		t.Fatalf("direct=%v why=%q", dialer.direct, dialer.why)
	}
	var got []byte
	select {
	case got = <-dialer.writes:
	case <-time.After(time.Second):
		t.Fatal("the ClientHello was not replayed")
	}
	if !bytes.Equal(got, hello) {
		t.Fatal("the ClientHello was not replayed to the chosen socket")
	}
}

func TestSniffConnUnknownHostStaysProxied(t *testing.T) {
	t.Cleanup(clearSplitState)
	dialer := &fakeRouteDialer{ch: make(chan struct{}), writes: make(chan []byte, 4)}
	conn := newSniffConn(context.Background(), netip.MustParseAddr("203.0.113.9"), 443, "203.0.113.9:443", dialer)
	defer conn.Close()
	if _, err := conn.Write([]byte("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n")); err != nil {
		t.Fatal(err)
	}
	select {
	case <-dialer.ch:
	case <-time.After(time.Second):
		t.Fatal("no decision")
	}
	if dialer.direct || dialer.why != "host-miss" {
		t.Fatalf("direct=%v why=%q", dialer.direct, dialer.why)
	}
}

func TestSniffConnFallsBackToDNS(t *testing.T) {
	t.Cleanup(clearSplitState)
	old := sniffIdleBudget
	sniffIdleBudget = 5 * time.Millisecond
	t.Cleanup(func() { sniffIdleBudget = old })

	setDirectSuffixes([]string{"vk.com"})
	ip := netip.MustParseAddr("203.0.113.10")
	rememberHostIP("vk.com", ip)
	dialer := &fakeRouteDialer{ch: make(chan struct{}), writes: make(chan []byte, 4)}
	conn := newSniffConn(context.Background(), ip, 22, "203.0.113.10:22", dialer)
	defer conn.Close()

	select {
	case <-dialer.ch:
	case <-time.After(time.Second):
		t.Fatal("the idle timer never dialled")
	}
	if !dialer.direct || dialer.why != "dns" {
		t.Fatalf("direct=%v why=%q", dialer.direct, dialer.why)
	}
}

func TestSharedIPFailsClosed(t *testing.T) {
	t.Cleanup(clearSplitState)
	setDirectSuffixes([]string{"vk.com"})
	ip := netip.MustParseAddr("203.0.113.20")
	rememberHostIP("vk.com", ip)
	rememberHostIP("unlisted.example", ip)
	if _, ok := ipAllDirect(ip); ok {
		t.Fatal("an address with an unlisted name must not go direct")
	}
	if direct, why := routeFor("", ip); direct || why != "unknown" {
		t.Fatalf("direct=%v why=%q", direct, why)
	}
}

func TestSharedIPAllDirect(t *testing.T) {
	t.Cleanup(clearSplitState)
	setDirectSuffixes([]string{"vk.com", "ok.ru"})
	ip := netip.MustParseAddr("203.0.113.21")
	rememberHostIP("vk.com", ip)
	rememberHostIP("ok.ru", ip)
	if _, ok := ipAllDirect(ip); !ok {
		t.Fatal("both names are in the list")
	}
}

func TestLeaseExpiry(t *testing.T) {
	t.Cleanup(clearSplitState)
	setDirectSuffixes([]string{"vk.com"})
	ip := netip.MustParseAddr("203.0.113.22")
	rememberHostIPTTL("vk.com", ip, time.Hour)
	splitMu.Lock()
	ipHosts[ip].leases["vk.com"] = time.Now().Add(-time.Second)
	splitMu.Unlock()
	if hosts := hostsForIP(ip); len(hosts) != 0 {
		t.Fatalf("expired lease survived: %v", hosts)
	}
}

func TestLRUEvictionKeepsTheTable(t *testing.T) {
	t.Cleanup(clearSplitState)
	ip := func(i int) netip.Addr {
		return netip.AddrFrom4([4]byte{10, byte(i >> 8), byte(i), 1})
	}
	for i := 0; i < dnsCacheCap; i++ {
		rememberHostIPTTL(fmt.Sprintf("h%d.example", i), ip(i), time.Hour)
	}
	rememberHostIPTTL("overflow.example", ip(dnsCacheCap), time.Hour)
	if got := len(hostsForIP(ip(0))); got != 0 {
		t.Fatalf("the least recently used address was not evicted: %v", got)
	}
	if got := len(hostsForIP(ip(dnsCacheCap))); got != 1 {
		t.Fatalf("the new address is missing: %v", got)
	}
	splitMu.RLock()
	size := len(ipHosts)
	splitMu.RUnlock()
	if size != dnsCacheCap {
		t.Fatalf("table size=%d, want %d", size, dnsCacheCap)
	}
}

type blockingRouteDialer struct {
	release chan struct{}
	writes  chan []byte
}

func (f *blockingRouteDialer) dialRoute(network, addr string, direct bool, why string) (net.Conn, error) {
	<-f.release
	a, b := net.Pipe()
	go func() {
		defer b.Close()
		buf := make([]byte, 4096)
		for {
			n, err := b.Read(buf)
			if n > 0 {
				f.writes <- append([]byte(nil), buf[:n]...)
			}
			if err != nil {
				return
			}
		}
	}()
	return a, nil
}

func TestSniffConnWriteWaitsForDial(t *testing.T) {
	t.Cleanup(clearSplitState)
	dialer := &blockingRouteDialer{release: make(chan struct{}), writes: make(chan []byte, 4)}
	conn := newSniffConn(context.Background(), netip.MustParseAddr("203.0.113.40"), 443, "203.0.113.40:443", dialer)
	defer conn.Close()

	first := make(chan error, 1)
	go func() {
		_, err := conn.Write(buildClientHello("example.com"))
		first <- err
	}()
	time.Sleep(10 * time.Millisecond)
	second := make(chan error, 1)
	go func() {
		_, err := conn.Write([]byte("second"))
		second <- err
	}()
	time.Sleep(10 * time.Millisecond)
	close(dialer.release)

	for _, ch := range []chan error{first, second} {
		select {
		case err := <-ch:
			if err != nil {
				t.Fatalf("a write failed during the dial window: %v", err)
			}
		case <-time.After(time.Second):
			t.Fatal("a write stuck during the dial window")
		}
	}
	// The buffered ClientHello is replayed before the second write.
	var seen []byte
	for i := 0; i < 2; i++ {
		select {
		case b := <-dialer.writes:
			seen = append(seen, b...)
		case <-time.After(time.Second):
			t.Fatalf("write %d never reached the chosen socket", i+1)
		}
	}
	if !bytes.HasPrefix(seen, buildClientHello("example.com")) || !bytes.HasSuffix(seen, []byte("second")) {
		t.Fatalf("unexpected payload order: %q", seen)
	}
}

func TestUDPGameModeChecksEveryForceName(t *testing.T) {
	t.Cleanup(clearSplitState)
	setExtraForceSuffixes([]string{"youtube.com"})
	setUDPDirect(true)
	ip := netip.MustParseAddr("203.0.113.33")
	rememberHostIP("example.com", ip)
	rememberHostIP("youtube.com", ip)
	if shouldDirectUDP(&M.Metadata{DstIP: ip, DstPort: 3478}) {
		t.Fatal("game mode must respect a force-proxy name on the same address")
	}
}

func TestUDPPolicy(t *testing.T) {
	t.Cleanup(clearSplitState)
	setExtraForceSuffixes([]string{"youtube.com"})
	setDirectSuffixes([]string{"vk.com"})
	direct := netip.MustParseAddr("203.0.113.30")
	forced := netip.MustParseAddr("203.0.113.31")
	unknown := netip.MustParseAddr("203.0.113.32")
	rememberHostIP("vk.com", direct)
	rememberHostIP("youtube.com", forced)

	if shouldDirectUDP(&M.Metadata{DstIP: unknown, DstPort: 3478}) {
		t.Fatal("unknown UDP must stay proxied by default")
	}
	if !shouldDirectUDP(&M.Metadata{DstIP: direct, DstPort: 3478}) {
		t.Fatal("a listed UDP address may go direct")
	}
	if shouldDirectUDP(&M.Metadata{DstIP: forced, DstPort: 3478}) {
		t.Fatal("force-proxy must win over UDP direct")
	}
	if shouldDirectUDP(&M.Metadata{DstIP: unknown, DstPort: 53}) {
		t.Fatal("DNS is always hijacked, never direct")
	}

	setUDPDirect(true)
	if !shouldDirectUDP(&M.Metadata{DstIP: unknown, DstPort: 3478}) {
		t.Fatal("game mode sends unclassified UDP direct")
	}
	if shouldDirectUDP(&M.Metadata{DstIP: forced, DstPort: 3478}) {
		t.Fatal("game mode still respects force-proxy")
	}
	if shouldDirectUDP(&M.Metadata{DstIP: unknown, DstPort: 53}) {
		t.Fatal("game mode never sends DNS direct")
	}
}
