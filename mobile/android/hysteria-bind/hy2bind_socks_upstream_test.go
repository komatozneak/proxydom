package hy2bind

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"io"
	"net"
	"testing"
	"time"

	M "github.com/xjasonlyu/tun2socks/v2/metadata"
)

// startStrictSocksUpstream is a SOCKS5 server that reads UDP ASSOCIATE the
// way RFC 1928 §7 and Xray do: DST.ADDR/DST.PORT name the address the client
// will send datagrams from, and the relay drops anything else. 0.0.0.0:0 means
// "not known yet" and admits any source. Each admitted datagram is echoed back
// with its SOCKS header, as if the target had answered.
func startStrictSocksUpstream(t *testing.T, users map[string]string) string {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = ln.Close() })
	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			go serveStrictSocks(conn, users)
		}
	}()
	return ln.Addr().String()
}

func serveStrictSocks(conn net.Conn, users map[string]string) {
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(15 * time.Second))
	head := make([]byte, 2)
	if _, err := io.ReadFull(conn, head); err != nil {
		return
	}
	if _, err := io.ReadFull(conn, make([]byte, head[1])); err != nil {
		return
	}
	if len(users) > 0 {
		_, _ = conn.Write([]byte{0x05, 0x02})
		ver := make([]byte, 2)
		if _, err := io.ReadFull(conn, ver); err != nil {
			return
		}
		user := make([]byte, ver[1])
		_, _ = io.ReadFull(conn, user)
		plen := make([]byte, 1)
		_, _ = io.ReadFull(conn, plen)
		pass := make([]byte, plen[0])
		_, _ = io.ReadFull(conn, pass)
		if users[string(user)] != string(pass) {
			_, _ = conn.Write([]byte{0x01, 0x01})
			return
		}
		_, _ = conn.Write([]byte{0x01, 0x00})
	} else {
		_, _ = conn.Write([]byte{0x05, 0x00})
	}
	req := make([]byte, 4)
	if _, err := io.ReadFull(conn, req); err != nil {
		return
	}
	if req[3] != 0x01 {
		return // the client under test only sends IPv4 here
	}
	addr := make([]byte, 6)
	if _, err := io.ReadFull(conn, addr); err != nil {
		return
	}
	if req[1] == 0x01 { // CONNECT is not what these tests are about
		_, _ = conn.Write([]byte{0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0})
		return
	}
	expect := &net.UDPAddr{IP: net.IP(addr[:4]), Port: int(binary.BigEndian.Uint16(addr[4:]))}
	anySource := expect.IP.IsUnspecified() && expect.Port == 0
	relay, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		return
	}
	defer relay.Close()
	bound := relay.LocalAddr().(*net.UDPAddr)
	reply := []byte{0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0, 0}
	binary.BigEndian.PutUint16(reply[8:], uint16(bound.Port))
	if _, err := conn.Write(reply); err != nil {
		return
	}
	go func() {
		buf := make([]byte, 2048)
		for {
			n, from, err := relay.ReadFromUDP(buf)
			if err != nil {
				return
			}
			if !anySource && !(from.IP.Equal(expect.IP) && from.Port == expect.Port) {
				continue // a strict relay drops a source it was not told about
			}
			_, _ = relay.WriteToUDP(buf[:n], from)
		}
	}()
	_, _ = io.Copy(io.Discard, conn) // the association lives as long as the control stream
}

func shareDocWithSocksOutbound(port int, upstream string, user, pass string) string {
	host, p, _ := net.SplitHostPort(upstream)
	var portNum int
	_ = json.Unmarshal([]byte(p), &portNum)
	server := map[string]any{"address": host, "port": portNum}
	if user != "" {
		server["users"] = []any{map[string]any{"user": user, "pass": pass}}
	}
	doc := map[string]any{
		"inbounds": []any{map[string]any{
			"listen": "127.0.0.1", "port": port, "protocol": "socks",
			"settings": map[string]any{"udp": true, "auth": "noauth"}, "tag": "socks-in",
		}},
		"outbounds": []any{
			map[string]any{"protocol": "socks", "tag": "proxy", "settings": map[string]any{"servers": []any{server}}},
			map[string]any{"protocol": "freedom", "tag": "direct"},
		},
	}
	raw, _ := json.Marshal(doc)
	return string(raw)
}

// UDP through a SOCKS5 key has to reach a server that reads ASSOCIATE by the
// RFC. v2ray-core's SOCKS client puts the first datagram's destination in
// DST.ADDR/DST.PORT; Xray then waits for datagrams from that address — the
// DNS server, say — and drops every one the client actually sends. On the
// stand that was every UDP flow of a SOCKS5 key, on Android and Windows alike.
func TestSocksKeyCarriesUdpToAStrictUpstream(t *testing.T) {
	for _, tc := range []struct{ name, user, pass string }{
		{"noauth", "", ""},
		{"password", "lab", "p@ss"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			users := map[string]string{}
			if tc.user != "" {
				users[tc.user] = tc.pass
			}
			upstream := startStrictSocksUpstream(t, users)
			port := freePort(t)
			t.Cleanup(func() { Stop() })
			withTestProtector(t)
			if msg := StartShare(shareDocWithSocksOutbound(port, upstream, tc.user, tc.pass)); msg != "" {
				t.Fatalf("the core did not start: %s", msg)
			}
			dialer := &socksDialer{addr: ShareSocksAddr()}
			packet, err := dialer.DialUDP(metaFor(t, "192.0.2.53:53", M.UDP))
			if err != nil {
				t.Fatalf("the udp associate failed: %v", err)
			}
			defer packet.Close()
			payload := bytes.Repeat([]byte{0x5A, 0xA5}, 8)
			if _, err := packet.WriteTo(payload, nil); err != nil {
				t.Fatalf("write failed: %v", err)
			}
			_ = packet.SetReadDeadline(time.Now().Add(5 * time.Second))
			buf := make([]byte, 512)
			n, _, err := packet.ReadFrom(buf)
			if err != nil {
				t.Fatalf("no answer through the socks key: %v", err)
			}
			if !bytes.Equal(buf[:n], payload) {
				t.Fatalf("read %x, want %x", buf[:n], payload)
			}
		})
	}
}

// Only ASSOCIATE changes. A CONNECT, and everything after it, reaches the
// server byte for byte, even when the client writes the handshake in pieces.
func TestSocksUpstreamLeavesConnectUntouched(t *testing.T) {
	client, server := net.Pipe()
	defer server.Close()
	conn := &socksAssociateConn{Conn: client}
	greeting := []byte{0x05, 0x01, 0x02, 0x01, 0x03, 'l', 'a', 'b', 0x02, 'p', 'w'}
	connect := []byte{0x05, 0x01, 0x00, 0x03, 0x07, 'e', 'x', 'a', 'm', 'p', 'l', 'e', 0x01, 0xBB}
	payload := []byte("GET / HTTP/1.1\r\n\r\n")
	want := append(append(append([]byte{}, greeting...), connect...), payload...)

	got := make(chan []byte, 1)
	go func() {
		b := make([]byte, len(want))
		_, _ = io.ReadFull(server, b)
		got <- b
	}()
	for _, part := range [][]byte{greeting[:4], greeting[4:], connect[:6], connect[6:], payload} {
		if _, err := conn.Write(part); err != nil {
			t.Fatal(err)
		}
	}
	select {
	case b := <-got:
		if !bytes.Equal(b, want) {
			t.Fatalf("server read %x, want %x", b, want)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("the handshake never reached the server")
	}
}

// The rewrite belongs to the document's SOCKS server and nothing else: a
// direct flow to some other host must not be parsed as a handshake.
func TestOnlyTheSocksServerConnectionIsWrapped(t *testing.T) {
	setSocksUpstreams(shareDocWithSocksOutbound(10809, "203.0.113.7:1080", "", ""))
	t.Cleanup(func() { setSocksUpstreams("") })
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()
	if _, ok := wrapSocksUpstream(client, "tcp", "203.0.113.7:1080").(*socksAssociateConn); !ok {
		t.Fatal("the socks server connection was not wrapped")
	}
	for _, other := range []struct{ network, addr string }{
		{"tcp", "203.0.113.7:443"},
		{"tcp", "198.51.100.1:1080"},
		{"udp", "203.0.113.7:1080"},
	} {
		if _, ok := wrapSocksUpstream(client, other.network, other.addr).(*socksAssociateConn); ok {
			t.Fatalf("%s %s was wrapped", other.network, other.addr)
		}
	}
}
