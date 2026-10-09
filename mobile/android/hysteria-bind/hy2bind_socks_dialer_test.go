package hy2bind

import (
	"bytes"
	"context"
	"io"
	"net"
	"net/netip"
	"testing"
	"time"

	M "github.com/xjasonlyu/tun2socks/v2/metadata"
)

// socksDialer is a hand-written SOCKS5 client: it carries every packet the
// Windows adapter delivers into the VLESS core, and it is the only thing
// standing between the tunnel and the core's inbound. Nothing had ever run it
// against a real v2ray-core SOCKS inbound -- the tests around it checked what
// address StartShare records, not whether the client can talk to the thing at
// that address.
//
// A client that gets the greeting, the request or the reply header wrong fails
// in the worst possible way: the session reports connected, the adapter is up,
// the core is running, and no page ever loads. There is no error to read,
// because the failure is on a socket the tunnel owns.
//
// So this drives the real dialer through the real core to a real echo server.

// startTCPEcho answers one connection at a time with a tagged reply, so the
// bytes that come back say which server was reached.
func startTCPEcho(t *testing.T, tag string) string {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("cannot start the echo server: %v", err)
	}
	t.Cleanup(func() { _ = listener.Close() })
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go func(c net.Conn) {
				defer c.Close()
				_ = c.SetDeadline(time.Now().Add(10 * time.Second))
				buf := make([]byte, 512)
				n, err := c.Read(buf)
				if err != nil {
					return
				}
				_, _ = c.Write(append([]byte(tag+":"), buf[:n]...))
			}(conn)
		}
	}()
	return listener.Addr().String()
}

// startUDPEcho is the same for datagrams. DNS travels this way, so a UDP
// associate that is wrong takes the browser down with it while the tunnel still
// looks healthy.
func startUDPEcho(t *testing.T) string {
	t.Helper()
	conn, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatalf("cannot start the udp echo server: %v", err)
	}
	t.Cleanup(func() { _ = conn.Close() })
	go func() {
		buf := make([]byte, 2048)
		for {
			n, from, err := conn.ReadFromUDP(buf)
			if err != nil {
				return
			}
			_, _ = conn.WriteToUDP(buf[:n], from)
		}
	}()
	return conn.LocalAddr().String()
}

// startCapturingSocks answers the SOCKS5 greeting and then hands the raw
// CONNECT request to the channel, so a test can assert the bytes rather than
// infer them from what happened afterwards.
func startCapturingSocks(t *testing.T, captured chan<- []byte) string {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("cannot start the fake inbound: %v", err)
	}
	t.Cleanup(func() { _ = listener.Close() })
	go func() {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		_ = conn.SetDeadline(time.Now().Add(10 * time.Second))

		greeting := make([]byte, 3)
		if _, err := io.ReadFull(conn, greeting); err != nil {
			return
		}
		if _, err := conn.Write([]byte{0x05, 0x00}); err != nil {
			return
		}
		head := make([]byte, 4)
		if _, err := io.ReadFull(conn, head); err != nil {
			return
		}
		request := append([]byte{}, head...)
		var tail int
		switch head[3] {
		case 0x01:
			tail = 4 + 2
		case 0x04:
			tail = 16 + 2
		case 0x03:
			length := make([]byte, 1)
			if _, err := io.ReadFull(conn, length); err != nil {
				return
			}
			request = append(request, length...)
			tail = int(length[0]) + 2
		default:
			return
		}
		rest := make([]byte, tail)
		if _, err := io.ReadFull(conn, rest); err != nil {
			return
		}
		request = append(request, rest...)
		captured <- request
		// A granted reply, so DialContext returns and the test can assert.
		_, _ = conn.Write([]byte{0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0})
		time.Sleep(200 * time.Millisecond)
	}()
	return listener.Addr().String()
}

// metaFor builds what tun2socks hands the proxy for one session.
func metaFor(t *testing.T, addr string, network M.Network) *M.Metadata {
	t.Helper()
	host, portStr, err := net.SplitHostPort(addr)
	if err != nil {
		t.Fatal(err)
	}
	port, err := net.LookupPort("tcp", portStr)
	if err != nil {
		t.Fatal(err)
	}
	ip, err := netip.ParseAddr(host)
	if err != nil {
		t.Fatal(err)
	}
	return &M.Metadata{Network: network, DstIP: ip, DstPort: uint16(port)}
}

// The whole point: dial through the real core, send, and read back what the
// server on the far side sent. If the greeting, the CONNECT request or the
// reply header were wrong, nothing would come back.
func TestTheSocksDialerCarriesTcpThroughTheRealCore(t *testing.T) {
	echo := startTCPEcho(t, "echo")
	port := freePort(t)
	t.Cleanup(func() { Stop() })

	if msg := StartShare(shareDocWithSocks(port)); msg != "" {
		t.Fatalf("the core did not start: %s", msg)
	}

	dialer := &socksDialer{addr: ShareSocksAddr()}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	conn, err := dialer.DialContext(ctx, metaFor(t, echo, M.TCP))
	if err != nil {
		t.Fatalf("the dialer could not reach the core's inbound: %v", err)
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(10 * time.Second))

	if _, err := conn.Write([]byte("hello-through-socks")); err != nil {
		t.Fatalf("write through the tunnel failed: %v", err)
	}
	got := make([]byte, 64)
	n, err := conn.Read(got)
	if err != nil {
		t.Fatalf("read through the tunnel failed: %v", err)
	}
	// The echo server tags its reply, so this can only be the far side
	// answering -- not a local buffer, and not the SOCKS handshake itself.
	if want := "echo:hello-through-socks"; string(got[:n]) != want {
		t.Fatalf("read %q, want %q", got[:n], want)
	}
}

// The destination is taken from the metadata, not from a constant or a
// wildcard, and this asserts the bytes on the wire rather than the outcome.
//
// The outcome cannot tell the two apart. My first attempt used two echo servers
// on loopback and checked which tag came back, and it did not catch a dialer
// that sent 0.0.0.0 in place of the real address: on Windows, and on Linux,
// connecting to 0.0.0.0 reaches the local machine, so both servers still
// answered. A mutation that survives the test is a test that proves nothing.
//
// So a fake inbound captures the CONNECT request and the request is compared
// byte for byte, which is the only way to see the address at all.
func TestTheSocksDialerPutsTheDestinationOnTheWire(t *testing.T) {
	captured := make(chan []byte, 1)
	addr := startCapturingSocks(t, captured)

	dialer := &socksDialer{addr: addr}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Port 0x1234 = 4660, distinctive so a swapped or truncated port shows up.
	const wantPort = 4660
	meta := &M.Metadata{
		Network: M.TCP,
		DstIP:   netip.MustParseAddr("127.0.0.1"),
		DstPort: wantPort,
	}
	conn, err := dialer.DialContext(ctx, meta)
	if err != nil {
		t.Fatalf("the dial failed: %v", err)
	}
	defer conn.Close()

	select {
	case got := <-captured:
		want := []byte{0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0x12, 0x34}
		if !bytes.Equal(got, want) {
			t.Fatalf("the CONNECT request was\n  %x\nwant\n  %x", got, want)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("the fake inbound saw no request")
	}
}

// A destination that is not loopback must be sent as itself. This is the case a
// wildcard would silently rewrite, and unlike the loopback pair above it cannot
// be confused with a working dial.
func TestTheSocksDialerSendsANonLoopbackAddressVerbatim(t *testing.T) {
	captured := make(chan []byte, 1)
	addr := startCapturingSocks(t, captured)

	dialer := &socksDialer{addr: addr}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	meta := &M.Metadata{
		Network: M.TCP,
		DstIP:   netip.MustParseAddr("203.0.113.7"),
		DstPort: 8443,
	}
	conn, err := dialer.DialContext(ctx, meta)
	if err != nil {
		t.Fatalf("the dial failed: %v", err)
	}
	defer conn.Close()

	select {
	case got := <-captured:
		want := []byte{0x05, 0x01, 0x00, 0x01, 203, 0, 113, 7, 0x20, 0xFB}
		if !bytes.Equal(got, want) {
			t.Fatalf("the CONNECT request was\n  %x\nwant\n  %x", got, want)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("the fake inbound saw no request")
	}
}

// UDP is a different conversation: a UDP ASSOCIATE request, a datagram socket
// handed back by the core, and a header on every packet. ReadFrom must strip
// that header -- leaving it on makes DNS answers unreadable, which is what
// "connected but nothing loads" looks like from the inside.
func TestTheSocksDialerCarriesUdpAndStripsTheHeader(t *testing.T) {
	echo := startUDPEcho(t)
	port := freePort(t)
	t.Cleanup(func() { Stop() })

	if msg := StartShare(shareDocWithSocks(port)); msg != "" {
		t.Fatalf("the core did not start: %s", msg)
	}

	dialer := &socksDialer{addr: ShareSocksAddr()}
	packet, err := dialer.DialUDP(metaFor(t, echo, M.UDP))
	if err != nil {
		t.Fatalf("the udp associate failed: %v", err)
	}
	defer packet.Close()

	// A DNS-shaped payload with a byte pattern that cannot be confused with a
	// SOCKS header, so a header left on the front is obvious in the diff.
	payload := bytes.Repeat([]byte{0xAB, 0xCD}, 8)
	if _, err := packet.WriteTo(payload, nil); err != nil {
		t.Fatalf("write failed: %v", err)
	}
	_ = packet.SetReadDeadline(time.Now().Add(10 * time.Second))
	buf := make([]byte, 512)
	n, _, err := packet.ReadFrom(buf)
	if err != nil {
		t.Fatalf("read failed: %v", err)
	}
	if !bytes.Equal(buf[:n], payload) {
		t.Fatalf("read %d bytes %x, want the payload %x: the socks udp header was not stripped",
			n, buf[:n], payload)
	}
}

// Close has to release both sockets. A leaked associate socket holds a port in
// the core and a session that reconnects keeps accumulating them.
func TestClosingTheUdpAssociateReleasesBothSockets(t *testing.T) {
	echo := startUDPEcho(t)
	port := freePort(t)
	t.Cleanup(func() { Stop() })

	if msg := StartShare(shareDocWithSocks(port)); msg != "" {
		t.Fatalf("the core did not start: %s", msg)
	}
	dialer := &socksDialer{addr: ShareSocksAddr()}
	packet, err := dialer.DialUDP(metaFor(t, echo, M.UDP))
	if err != nil {
		t.Fatalf("the udp associate failed: %v", err)
	}
	if err := packet.Close(); err != nil {
		t.Fatalf("close reported %v", err)
	}
	_ = packet.SetReadDeadline(time.Now().Add(time.Second))
	if _, _, err := packet.ReadFrom(make([]byte, 64)); err == nil {
		t.Fatal("a closed associate still reads")
	}
	// Both sockets, not just the datagram one. The control connection is what
	// the core holds the session on, so leaking it keeps a session alive that
	// the tunnel has finished with. Writing to a closed socket reports the
	// closure immediately, which is what makes this observable.
	control, ok := packet.(*socksUDP)
	if !ok {
		t.Fatalf("the associate is a %T, not the type this test closes", packet)
	}
	if _, err := control.tcp.Write([]byte{0}); err == nil {
		t.Fatal("the control connection is still writable after Close")
	}
}
