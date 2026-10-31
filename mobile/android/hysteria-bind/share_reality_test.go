package hy2bind

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"io"
	"net"
	"strconv"
	"testing"
	"time"
)

func realityTestDocument(t *testing.T, overrides map[string]any) string {
	publicKey := base64.RawURLEncoding.EncodeToString(bytes.Repeat([]byte{7}, 32))
	doc := map[string]any{
		"engine":     "reality",
		"server":     "203.0.113.10",
		"port":       443,
		"uuid":       "11111111-2222-3333-4444-555555555555",
		"public_key": publicKey,
		"short_id":   "a1b2c3d4",
		"sni":        "cover.example",
		"network":    "tcp",
	}
	for key, value := range overrides {
		doc[key] = value
	}
	return mustJSON(t, doc)
}

func mustJSON(t *testing.T, value any) string {
	t.Helper()
	encoded, err := json.Marshal(value)
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	return string(encoded)
}

func TestParseRealityDocument(t *testing.T) {
	cfg, err := parseRealityDocument(realityTestDocument(t, nil))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if cfg.server != "203.0.113.10" || cfg.port != 443 {
		t.Fatalf("endpoint = %s:%d", cfg.server, cfg.port)
	}
	if cfg.sni != "cover.example" {
		t.Fatalf("sni = %q", cfg.sni)
	}
	if cfg.shortID != [8]byte{0xa1, 0xb2, 0xc3, 0xd4} {
		t.Fatalf("short id = %x", cfg.shortID)
	}
	if len(cfg.publicKey) != 32 {
		t.Fatalf("public key length = %d", len(cfg.publicKey))
	}
	if cfg.uuid != [16]byte{0x11, 0x11, 0x11, 0x11, 0x22, 0x22, 0x33, 0x33, 0x44, 0x44, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55} {
		t.Fatalf("uuid = %x", cfg.uuid)
	}
}

func TestParseRealityDocumentRefusesUncarriedTransport(t *testing.T) {
	_, err := parseRealityDocument(realityTestDocument(t, map[string]any{"network": "xhttp"}))
	if err == nil {
		t.Fatal("xhttp must not parse as a carried REALITY transport yet")
	}
}

func TestParseRealityDocumentRefusesVision(t *testing.T) {
	_, err := parseRealityDocument(realityTestDocument(t, map[string]any{
		"flow": "xtls-rprx-vision",
	}))
	if err == nil {
		t.Fatal("xtls-rprx-vision must stay inactive until Vision is carried")
	}
}

func TestParseRealityDocumentDefaults(t *testing.T) {
	doc := realityTestDocument(t, map[string]any{
		"port":         0,
		"sni":          "",
		"short_id":     "",
		"socks_listen": "",
	})
	cfg, err := parseRealityDocument(doc)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if cfg.port != 443 {
		t.Fatalf("port = %d, want 443", cfg.port)
	}
	if cfg.sni != "203.0.113.10" {
		t.Fatalf("sni = %q", cfg.sni)
	}
	if cfg.shortID != [8]byte{} {
		t.Fatalf("short id = %x", cfg.shortID)
	}
	// The same inbound as the v2ray share core: one engine runs at a time.
	if cfg.socksListen != "127.0.0.1:10809" {
		t.Fatalf("socks = %q", cfg.socksListen)
	}
}

func TestRealityShortIDIsWholeBytes(t *testing.T) {
	id, err := parseRealityShortID("a1b2")
	if err != nil {
		t.Fatalf("short id: %v", err)
	}
	if want := [8]byte{0xa1, 0xb2}; id != want {
		t.Fatalf("short id = %x, want %x", id, want)
	}
	// A server's short ids are whole bytes, so padding "abc" would produce an
	// id that matches no server.
	if _, err := parseRealityShortID("abc"); err == nil {
		t.Fatal("an odd-length short id must be refused")
	}
	if _, err := parseRealityShortID("00112233445566778899"); err == nil {
		t.Fatal("a short id longer than 8 bytes must be refused")
	}
}

// Stopping the engine (a disconnect or a server switch) must end the flows it
// already carries, not only stop accepting new ones: otherwise traffic keeps
// leaving through the node the person just switched away from.
func TestRealityStopEndsLiveConnections(t *testing.T) {
	doc := realityTestDocument(t, map[string]any{"socks_listen": "127.0.0.1:0"})
	if msg := startRealityShare(doc); msg != "" {
		t.Fatalf("start: %s", msg)
	}
	t.Cleanup(stopRealityShare)
	conn, err := net.Dial("tcp", ShareSocksAddr())
	if err != nil {
		t.Fatalf("dial socks: %v", err)
	}
	defer conn.Close()
	// Greet, then hold the connection open the way an idle client would.
	if _, err := conn.Write([]byte{0x05, 0x01, 0x00}); err != nil {
		t.Fatalf("greet: %v", err)
	}
	reply := make([]byte, 2)
	if _, err := io.ReadFull(conn, reply); err != nil {
		t.Fatalf("greeting reply: %v", err)
	}

	stopRealityShare()
	_ = conn.SetReadDeadline(time.Now().Add(3 * time.Second))
	if _, err := conn.Read(make([]byte, 1)); err == nil {
		t.Fatal("the connection survived the stop")
	} else if ne, ok := err.(net.Error); ok && ne.Timeout() {
		t.Fatal("the connection was still open 3s after the stop")
	}
	if realityRunning() {
		t.Fatal("engine still reports running")
	}
}

// One slow destination must not hold up datagrams for the others. The node
// here accepts TCP and never answers the TLS handshake; both destinations must
// still be dialled at once instead of the second waiting out the first.
func TestRealityUDPDialsDestinationsConcurrently(t *testing.T) {
	node, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	defer node.Close()
	accepted := make(chan net.Conn, 4)
	go func() {
		for {
			c, err := node.Accept()
			if err != nil {
				return
			}
			accepted <- c
		}
	}()
	prev := realityOutboundDial
	realityOutboundDial = func(ctx context.Context, network, addr string) (net.Conn, error) {
		var d net.Dialer
		return d.DialContext(ctx, network, addr)
	}
	t.Cleanup(func() { realityOutboundDial = prev })

	host, portText, _ := net.SplitHostPort(node.Addr().String())
	port, _ := strconv.Atoi(portText)
	cfg, err := parseRealityDocument(realityTestDocument(t, map[string]any{
		"server": host,
		"port":   port,
	}))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	pc, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatalf("udp: %v", err)
	}
	defer pc.Close()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	relay := &realityUDPRelay{ctx: ctx, cfg: cfg, pc: pc, flows: make(map[string]chan []byte)}

	started := time.Now()
	relay.send("198.51.100.1:53", []byte("a"))
	relay.send("198.51.100.2:53", []byte("b"))
	if elapsed := time.Since(started); elapsed > time.Second {
		t.Fatalf("send blocked for %s while the node was dialled", elapsed)
	}
	for i := 0; i < 2; i++ {
		select {
		case c := <-accepted:
			defer c.Close()
		case <-time.After(3 * time.Second):
			t.Fatalf("only %d of 2 destinations were dialled", i)
		}
	}
}

func TestVlessRequestCarriesIPv4DomainAndIPv6(t *testing.T) {
	id := [16]byte{1, 2, 3}
	cases := []struct {
		target string
		atyp   byte
		addr   []byte
	}{
		{"203.0.113.7:443", 0x01, []byte{203, 0, 113, 7}},
		{"example.com:8443", 0x02, append([]byte{11}, []byte("example.com")...)},
		{"[2001:db8::1]:1080", 0x03, net.ParseIP("2001:db8::1").To16()},
	}
	for _, tc := range cases {
		request, err := vlessRequest(id, tc.target, vlessCommandTCP)
		if err != nil {
			t.Fatalf("%s: %v", tc.target, err)
		}
		// version + uuid + addons + command + port
		header := 1 + 16 + 1 + 1 + 2
		if len(request) < header+1 {
			t.Fatalf("%s: request too short", tc.target)
		}
		if request[0] != 0 || request[17] != 0 || request[18] != vlessCommandTCP {
			t.Fatalf("%s: bad header % x", tc.target, request[:header])
		}
		if got := request[header]; got != tc.atyp {
			t.Fatalf("%s: atyp = %#x, want %#x", tc.target, got, tc.atyp)
		}
		if !bytes.Equal(request[header+1:len(request)], tc.addr) {
			t.Fatalf("%s: address = % x, want % x", tc.target, request[header+1:], tc.addr)
		}
		port := binary.BigEndian.Uint16(request[19:21])
		if port == 0 {
			t.Fatalf("%s: port missing", tc.target)
		}
	}
}

func TestReadVlessResponseReadsAndSkipsAddons(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()
	go func() {
		_, _ = server.Write([]byte{0, 3, 1, 2, 3, 'p', 'a', 'y'})
	}()
	if err := readVlessResponse(client); err != nil {
		t.Fatalf("response: %v", err)
	}
	buf := make([]byte, 3)
	if _, err := client.Read(buf); err != nil {
		t.Fatalf("payload: %v", err)
	}
	if string(buf) != "pay" {
		t.Fatalf("payload = %q", buf)
	}
}

func TestSOCKSUDPPacketRoundTrip(t *testing.T) {
	packet, err := socksUDPPacket("example.com:53", []byte("dns"))
	if err != nil {
		t.Fatalf("packet: %v", err)
	}
	if packet[0] != 0 || packet[1] != 0 || packet[2] != 0 || packet[3] != 0x03 {
		t.Fatalf("socks udp header = % x", packet[:4])
	}
	host, port, offset, ok := parseSOCKSUDPAddress(packet, 3)
	if !ok || host != "example.com" || port != 53 || string(packet[offset:]) != "dns" {
		t.Fatalf("parsed = %q:%d offset=%d ok=%v", host, port, offset, ok)
	}
}
