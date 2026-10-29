package hy2bind

import (
	"encoding/json"
	"fmt"
	"net"
	"testing"
)

// shareDocWithSocks is a minimal share document: a SOCKS inbound on a port we
// choose and a freedom outbound. It starts a real core, which is the only way
// to see what StartShare records about a core that is actually running.
func shareDocWithSocks(port int) string {
	doc := map[string]any{
		"inbounds": []any{map[string]any{
			"listen": "127.0.0.1", "port": port, "protocol": "socks",
			"settings": map[string]any{"udp": true, "auth": "noauth"}, "tag": "socks-in",
		}},
		"outbounds": []any{map[string]any{"protocol": "freedom", "tag": "direct"}},
	}
	raw, _ := json.Marshal(doc)
	return string(raw)
}

// freePort returns a port number nothing is using on both TCP and UDP.
//
// Both, because a v2ray-core SOCKS inbound with `udp: true` binds the TCP and
// the UDP side of the same number, and on Windows those two are not equally
// available: the OS keeps excluded port ranges (Hyper-V and WinNAT reserve
// blocks of the ephemeral range), where a bind fails with WSAEACCES rather than
// "in use". A port that came from a TCP-only probe can therefore be free for TCP
// and forbidden for UDP, and the core fails to start for a reason that has
// nothing to do with the test.
//
// That is not hypothetical: it is what the first run of the socks dialer tests
// hit, on a machine with Hyper-V, as
// `listen udp 127.0.0.1:49632: bind: An attempt was made to access a socket in a
// way forbidden by its access permissions`.
func freePort(t *testing.T) int {
	t.Helper()
	// Ask for :0 at your peril. Windows hands out ephemeral ports from a range
	// that WinNAT and Hyper-V have partly excluded, and when the allocator lands
	// in a blocked block every retry fails the same way: this machine produced
	// "no port was free on both tcp and udp after 20 attempts" in roughly half
	// the runs, while 24000–31999 answered every time. The band is below the
	// dynamic range, so it is not subject to that allocator at all.
	for port := 24000; port < 32000; port++ {
		listener, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
		if err != nil {
			continue
		}
		_ = listener.Close()

		udp, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: port})
		if err != nil {
			continue
		}
		_ = udp.Close()
		return port
	}
	t.Fatal("no port was free on both tcp and udp in 24000-31999")
	return 0
}

// ShareSocksAddr is what StartShareTunStack dials, so a core that is running
// must be answerable by address. This starts a real core: the address is
// recorded only after inst.Start() returns, and that is exactly the ordering a
// test has to exercise, because getting it wrong is invisible — the session
// still connects, it just connects to nothing.
func TestStartShareRecordsTheRunningCoreAddress(t *testing.T) {
	port := freePort(t)
	t.Cleanup(func() { Stop() })

	if msg := StartShare(shareDocWithSocks(port)); msg != "" {
		t.Fatalf("the core did not start: %s", msg)
	}
	want := fmt.Sprintf("127.0.0.1:%d", port)
	if got := ShareSocksAddr(); got != want {
		t.Fatalf("ShareSocksAddr = %q, want %q", got, want)
	}
	// And it is a real listener, not just a recorded string.
	conn, err := net.Dial("tcp", want)
	if err != nil {
		t.Fatalf("nothing is listening on the recorded address: %v", err)
	}
	_ = conn.Close()
}

// A start that failed must leave no address behind. It used to be stored before
// the config was parsed, so a broken document still pointed the tunnel at a port
// nothing listens on for as long as another core was running.
func TestAFailedStartLeavesNoAddressBehind(t *testing.T) {
	t.Cleanup(func() { Stop() })

	before := ShareSocksAddr()
	if msg := StartShare("{not json at all}"); msg == "" {
		t.Fatal("a document that is not json must be refused")
	}
	if after := ShareSocksAddr(); after != before {
		t.Fatalf("a failed start changed the address from %q to %q", before, after)
	}
	// Nothing was recorded at all, which is the state a fresh process is in.
	if stored, _ := shareAddr.Load().(string); stored != "" {
		t.Fatalf("a failed start stored %q", stored)
	}
}

// Stop clears the address with the core. A stale address after Stop is what
// makes a later session dial a port that closed.
func TestStopClearsTheAddress(t *testing.T) {
	port := freePort(t)
	t.Cleanup(func() { Stop() })

	if msg := StartShare(shareDocWithSocks(port)); msg != "" {
		t.Fatalf("the core did not start: %s", msg)
	}
	if ShareSocksAddr() == "" {
		t.Fatal("the address was not recorded")
	}
	Stop()
	if got := ShareSocksAddr(); got != "" {
		t.Fatalf("Stop left the address as %q", got)
	}
}

// shareListenAddr is what gets recorded, so it has to read the inbound the
// document actually carries rather than a constant. An empty answer means the
// caller must refuse: a guessed port looks exactly like a working one until
// something dials it.
func TestShareListenAddrReadsTheDocument(t *testing.T) {
	if got := shareListenAddr(shareDocWithSocks(12345)); got != "127.0.0.1:12345" {
		t.Fatalf("shareListenAddr = %q", got)
	}
	if got := shareListenAddr("{}"); got != "" {
		t.Fatalf("a document with no inbound must answer empty, got %q", got)
	}
	if got := shareListenAddr("{not json at all}"); got != "" {
		t.Fatalf("a document that is not json must answer empty, got %q", got)
	}
	if got := shareListenAddr(`{"inbounds":[{"listen":"127.0.0.1","port":0}]}`); got != "" {
		t.Fatalf("a port of zero means the core chose one and we do not know it, got %q", got)
	}
	// A host that is omitted still means loopback, which is what the core does.
	if got := shareListenAddr(`{"inbounds":[{"port":12345}]}`); got != "127.0.0.1:12345" {
		t.Fatalf("an omitted host must mean loopback, got %q", got)
	}
}
