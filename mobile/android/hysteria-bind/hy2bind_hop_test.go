package hy2bind

import (
	"net"
	"sync"
	"testing"
	"time"

	"github.com/apernet/hysteria/core/v2/client"
)

// hopPacketStub is the datagram socket the hop wrapper writes through. It
// records every destination so a test can inspect the port the wrapper chose.
type hopPacketStub struct {
	mu       sync.Mutex
	writes   []net.Addr
	readData []byte
	readAddr net.Addr
}

func (s *hopPacketStub) ReadFrom(p []byte) (int, net.Addr, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.readData == nil {
		return 0, nil, net.ErrClosed
	}
	n := copy(p, s.readData)
	return n, s.readAddr, nil
}

func (s *hopPacketStub) WriteTo(p []byte, addr net.Addr) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.writes = append(s.writes, addr)
	return len(p), nil
}

func (s *hopPacketStub) Close() error                     { return nil }
func (s *hopPacketStub) LocalAddr() net.Addr              { return &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)} }
func (s *hopPacketStub) SetDeadline(time.Time) error      { return nil }
func (s *hopPacketStub) SetReadDeadline(time.Time) error  { return nil }
func (s *hopPacketStub) SetWriteDeadline(time.Time) error { return nil }

func (s *hopPacketStub) setRead(b []byte, addr net.Addr) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.readData = b
	s.readAddr = addr
}

func (s *hopPacketStub) written() []net.Addr {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]net.Addr(nil), s.writes...)
}

type hopFactoryStub struct {
	mu   sync.Mutex
	last *hopPacketStub
}

func (f *hopFactoryStub) New(net.Addr) (net.PacketConn, error) {
	pc := &hopPacketStub{}
	f.mu.Lock()
	f.last = pc
	f.mu.Unlock()
	return pc, nil
}

func (f *hopFactoryStub) packet() *hopPacketStub {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.last
}

// hopTestServer is the address the QUIC client dials. The hop wrapper rewrites
// only the port on the wire and keeps this address as the remote QUIC sees.
var hopTestServer = &net.UDPAddr{IP: net.IPv4(198, 51, 100, 7), Port: 443}

func newHopForTest(t *testing.T, low, high int, every time.Duration) (*hopConn, *hopPacketStub) {
	t.Helper()
	inner := &hopFactoryStub{}
	f := &hopFactory{inner: inner, low: low, high: high, every: every}
	pc, err := f.New(hopTestServer)
	if err != nil {
		t.Fatalf("hop factory: %v", err)
	}
	conn, ok := pc.(*hopConn)
	if !ok {
		t.Fatalf("factory returned %T, want *hopConn", pc)
	}
	return conn, inner.packet()
}

func TestParsePortRange(t *testing.T) {
	cases := []struct {
		raw  string
		low  int
		high int
		ok   bool
	}{
		{"20000:30000", 20000, 30000, true},
		{"443:443", 443, 443, true},
		{"1:65535", 1, 65535, true},
		{"", 0, 0, false},
		{":", 0, 0, false},
		{"20000", 0, 0, false},
		{"20000:", 0, 0, false},
		{":30000", 0, 0, false},
		{"30000:20000", 0, 0, false},
		{"0:100", 0, 0, false},
		{"100:65536", 0, 0, false},
		{"abc:def", 0, 0, false},
		{"20000:30x00", 0, 0, false},
		{"-1:100", 0, 0, false},
		{"20000:30000:40000", 0, 0, false},
		{"20000: 30000", 0, 0, false},
	}
	for _, c := range cases {
		low, high, ok := parsePortRange(c.raw)
		if ok != c.ok || low != c.low || high != c.high {
			t.Errorf("parsePortRange(%q) = (%d, %d, %t), want (%d, %d, %t)",
				c.raw, low, high, ok, c.low, c.high, c.ok)
		}
	}
}

func TestMaybeHopNeedsARange(t *testing.T) {
	var inner client.ConnFactory = &hopFactoryStub{}

	if got := maybeHop(inner, startConfig{}); got != inner {
		t.Fatal("without server_ports the factory must stay untouched")
	}
	if got := maybeHop(inner, startConfig{ServerPorts: "nonsense"}); got != inner {
		t.Fatal("an unparseable range must not wrap the factory")
	}

	f, ok := maybeHop(inner, startConfig{ServerPorts: "20000:20020", HopInterval: "5s"}).(*hopFactory)
	if !ok {
		t.Fatal("a valid range must wrap the factory")
	}
	if f.low != 20000 || f.high != 20020 {
		t.Fatalf("range = %d:%d, want 20000:20020", f.low, f.high)
	}
	if f.every != 5*time.Second {
		t.Fatalf("interval = %s, want 5s", f.every)
	}

	unset := maybeHop(inner, startConfig{ServerPorts: "20000:20020"}).(*hopFactory)
	if unset.every != 30*time.Second {
		t.Fatalf("interval = %s, want the 30s default", unset.every)
	}
	broken := maybeHop(inner, startConfig{ServerPorts: "20000:20020", HopInterval: "soon"}).(*hopFactory)
	if broken.every != 30*time.Second {
		t.Fatalf("an unparseable interval must fall back to 30s, got %s", broken.every)
	}
}

func TestHopRewritesTheDestinationPort(t *testing.T) {
	conn, inner := newHopForTest(t, 20000, 20005, time.Hour)
	for i := 0; i < 8; i++ {
		if _, err := conn.WriteTo([]byte("q"), hopTestServer); err != nil {
			t.Fatalf("write: %v", err)
		}
	}

	writes := inner.written()
	if len(writes) != 8 {
		t.Fatalf("writes = %d, want 8", len(writes))
	}
	first := writes[0].(*net.UDPAddr)
	if first.Port < 20000 || first.Port > 20005 {
		t.Fatalf("port %d left the declared range", first.Port)
	}
	for _, w := range writes {
		u := w.(*net.UDPAddr)
		if u.Port != first.Port {
			t.Fatalf("port moved inside one interval: %d then %d", first.Port, u.Port)
		}
		if !u.IP.Equal(hopTestServer.IP) {
			t.Fatalf("host changed to %v", u.IP)
		}
	}
	if hopTestServer.Port != 443 {
		t.Fatal("WriteTo mutated the caller's address")
	}
}

func TestHopPortMovesWhenTheIntervalExpires(t *testing.T) {
	conn, inner := newHopForTest(t, 20000, 20019, 0)
	for i := 0; i < 400; i++ {
		if _, err := conn.WriteTo([]byte("q"), hopTestServer); err != nil {
			t.Fatalf("write: %v", err)
		}
	}

	seen := map[int]int{}
	for _, w := range inner.written() {
		port := w.(*net.UDPAddr).Port
		if port < 20000 || port > 20019 {
			t.Fatalf("port %d left the declared range", port)
		}
		seen[port]++
	}
	if len(seen) < 2 {
		t.Fatalf("a zero-length interval must move the port, saw only %v", seen)
	}
}

func TestHopSinglePortRangeIsStable(t *testing.T) {
	conn, inner := newHopForTest(t, 25000, 25000, 0)
	for i := 0; i < 5; i++ {
		if _, err := conn.WriteTo([]byte("q"), hopTestServer); err != nil {
			t.Fatalf("write: %v", err)
		}
	}
	for _, w := range inner.written() {
		if port := w.(*net.UDPAddr).Port; port != 25000 {
			t.Fatalf("port = %d, want 25000", port)
		}
	}
}

func TestHopReadFromPresentsTheDialedAddress(t *testing.T) {
	conn, inner := newHopForTest(t, 20000, 20010, time.Hour)
	inner.setRead([]byte("answer"), &net.UDPAddr{IP: hopTestServer.IP, Port: 20003})

	buf := make([]byte, 32)
	n, addr, err := conn.ReadFrom(buf)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if string(buf[:n]) != "answer" {
		t.Fatalf("payload = %q", buf[:n])
	}
	if addr.String() != hopTestServer.String() {
		t.Fatalf("ReadFrom returned %v, want the dialed %v", addr, hopTestServer)
	}
}

func TestHopPassesANonUDPAddressThrough(t *testing.T) {
	conn, inner := newHopForTest(t, 20000, 20010, time.Hour)
	other := &net.TCPAddr{IP: net.IPv4(198, 51, 100, 9), Port: 8443}
	if _, err := conn.WriteTo([]byte("q"), other); err != nil {
		t.Fatalf("write: %v", err)
	}
	writes := inner.written()
	if len(writes) != 1 {
		t.Fatalf("writes = %d, want 1", len(writes))
	}
	if writes[0].String() != other.String() {
		t.Fatalf("got %v, want %v unchanged", writes[0], other)
	}
}
