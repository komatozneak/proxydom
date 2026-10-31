package hy2bind

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"
)

// TestRealityLive is the end-to-end check that a REALITY + VLESS handshake
// reaches a real Xray listener. It is opt-in because it needs a running server
// and a public key that belongs to it:
//
//	PROXYDOM_REALITY_LIVE=1 \
//	PROXYDOM_REALITY_SERVER=127.0.0.1:18443 \
//	PROXYDOM_REALITY_UUID=f5d05d9a-... \
//	PROXYDOM_REALITY_PUBLIC_KEY=c9wH... \
//	PROXYDOM_REALITY_SHORT_ID=a1b2c3d4 \
//	PROXYDOM_REALITY_SNI=www.microsoft.com \
//	go test -run TestRealityLive -v .
//
// The test does not skip silently when the flag is set: a broken handshake is
// the failure it exists to report.
func TestRealityLive(t *testing.T) {
	if os.Getenv("PROXYDOM_REALITY_LIVE") != "1" {
		t.Skip("set PROXYDOM_REALITY_LIVE=1 and the PROXYDOM_REALITY_* variables to run")
	}
	server := os.Getenv("PROXYDOM_REALITY_SERVER")
	uuid := os.Getenv("PROXYDOM_REALITY_UUID")
	publicKey := os.Getenv("PROXYDOM_REALITY_PUBLIC_KEY")
	shortID := os.Getenv("PROXYDOM_REALITY_SHORT_ID")
	sni := os.Getenv("PROXYDOM_REALITY_SNI")
	if server == "" || uuid == "" || publicKey == "" || sni == "" {
		t.Fatal("PROXYDOM_REALITY_SERVER, _UUID, _PUBLIC_KEY and _SNI are required")
	}
	host, portText, err := net.SplitHostPort(server)
	if err != nil {
		t.Fatalf("server: %v", err)
	}
	port, err := strconv.Atoi(portText)
	if err != nil {
		t.Fatalf("port: %v", err)
	}

	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte("reality-ok"))
	}))
	defer target.Close()
	targetHost, targetPortText, _ := net.SplitHostPort(strings.TrimPrefix(target.URL, "http://"))
	targetPort, _ := strconv.Atoi(targetPortText)

	document, err := json.Marshal(map[string]any{
		"engine":       "reality",
		"server":       host,
		"port":         port,
		"uuid":         uuid,
		"public_key":   publicKey,
		"short_id":     shortID,
		"sni":          sni,
		"network":      "tcp",
		"socks_listen": "127.0.0.1:0",
	})
	if err != nil {
		t.Fatalf("document: %v", err)
	}
	if message := StartShare(string(document)); message != "" {
		t.Fatalf("start: %s", message)
	}
	defer Stop()
	addr := ShareSocksAddr()
	if addr == "" {
		t.Fatal("share socks address is empty")
	}

	conn, err := net.DialTimeout("tcp", addr, 5*time.Second)
	if err != nil {
		t.Fatalf("socks dial: %v", err)
	}
	defer conn.Close()
	if err := socks5Connect(conn, net.JoinHostPort(targetHost, strconv.Itoa(targetPort))); err != nil {
		t.Fatalf("socks connect: %v", err)
	}
	_ = conn.SetDeadline(time.Now().Add(10 * time.Second))
	request := "GET / HTTP/1.1\r\nHost: " + targetHost + "\r\nConnection: close\r\n\r\n"
	if _, err := conn.Write([]byte(request)); err != nil {
		t.Fatalf("write: %v", err)
	}
	responseBytes, err := io.ReadAll(conn)
	if err != nil && len(responseBytes) == 0 {
		t.Fatalf("read: %v", err)
	}
	if !strings.Contains(string(responseBytes), "reality-ok") {
		t.Fatalf("target response = %q", responseBytes)
	}

	echo, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 0})
	if err != nil {
		t.Fatalf("udp echo: %v", err)
	}
	defer echo.Close()
	go func() {
		buf := make([]byte, 2048)
		for {
			n, from, err := echo.ReadFromUDP(buf)
			if err != nil {
				return
			}
			_, _ = echo.WriteToUDP(buf[:n], from)
		}
	}()
	echoAddr := echo.LocalAddr().(*net.UDPAddr)

	control, err := net.DialTimeout("tcp", addr, 5*time.Second)
	if err != nil {
		t.Fatalf("socks udp control: %v", err)
	}
	defer control.Close()
	if err := socks5Greet(control); err != nil {
		t.Fatalf("socks udp greet: %v", err)
	}
	if _, err := control.Write([]byte{0x05, 0x03, 0x00, 0x01, 0, 0, 0, 0, 0, 0}); err != nil {
		t.Fatalf("socks udp associate: %v", err)
	}
	relayHost, relayPort, err := readSocksBound(control)
	if err != nil {
		t.Fatalf("socks udp bound: %v", err)
	}
	relay := &net.UDPAddr{IP: net.ParseIP(relayHost), Port: relayPort}
	udp, err := net.DialUDP("udp", nil, relay)
	if err != nil {
		t.Fatalf("udp relay: %v", err)
	}
	defer udp.Close()
	packet := []byte{0, 0, 0, 0x01}
	packet = append(packet, echoAddr.IP.To4()...)
	packet = append(packet, byte(echoAddr.Port>>8), byte(echoAddr.Port))
	packet = append(packet, []byte("ping")...)
	if _, err := udp.Write(packet); err != nil {
		t.Fatalf("udp write: %v", err)
	}
	_ = udp.SetReadDeadline(time.Now().Add(5 * time.Second))
	reply := make([]byte, 2048)
	n, err := udp.Read(reply)
	if err != nil {
		t.Fatalf("udp read: %v", err)
	}
	_, _, offset, ok := parseSOCKSUDPAddress(reply[:n], 3)
	if !ok || string(reply[offset:n]) != "ping" {
		t.Fatalf("udp reply = % x", reply[:n])
	}
	fmt.Println("reality live: ok (tcp + udp)")
}

// TestRealityRemoteLive is TestRealityLive for a node on another machine. The
// local test's targets live on this computer's loopback, which a remote node
// cannot reach, so this one asks the internet instead: an HTTP request to
// example.com over TCP and a DNS query to 1.1.1.1 over VLESS UDP.
//
//	PROXYDOM_REALITY_REMOTE=1 plus the PROXYDOM_REALITY_* variables above
func TestRealityRemoteLive(t *testing.T) {
	if os.Getenv("PROXYDOM_REALITY_REMOTE") != "1" {
		t.Skip("set PROXYDOM_REALITY_REMOTE=1 and the PROXYDOM_REALITY_* variables to run")
	}
	server := os.Getenv("PROXYDOM_REALITY_SERVER")
	host, portText, err := net.SplitHostPort(server)
	if err != nil {
		t.Fatalf("server: %v", err)
	}
	port, _ := strconv.Atoi(portText)
	document, _ := json.Marshal(map[string]any{
		"engine":       "reality",
		"server":       host,
		"port":         port,
		"uuid":         os.Getenv("PROXYDOM_REALITY_UUID"),
		"public_key":   os.Getenv("PROXYDOM_REALITY_PUBLIC_KEY"),
		"short_id":     os.Getenv("PROXYDOM_REALITY_SHORT_ID"),
		"sni":          os.Getenv("PROXYDOM_REALITY_SNI"),
		"network":      "tcp",
		"socks_listen": "127.0.0.1:0",
	})
	if message := StartShare(string(document)); message != "" {
		t.Fatalf("start: %s", message)
	}
	defer Stop()
	addr := ShareSocksAddr()

	started := time.Now()
	conn, err := net.DialTimeout("tcp", addr, 5*time.Second)
	if err != nil {
		t.Fatalf("socks dial: %v", err)
	}
	defer conn.Close()
	if err := socks5Connect(conn, "example.com:80"); err != nil {
		t.Fatalf("socks connect: %v", err)
	}
	_ = conn.SetDeadline(time.Now().Add(15 * time.Second))
	if _, err := conn.Write([]byte("GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n")); err != nil {
		t.Fatalf("write: %v", err)
	}
	status := make([]byte, 12)
	if _, err := io.ReadFull(conn, status); err != nil {
		t.Fatalf("read: %v", err)
	}
	if !strings.HasPrefix(string(status), "HTTP/1.") {
		t.Fatalf("status = %q", status)
	}
	tcpTook := time.Since(started)

	control, err := net.DialTimeout("tcp", addr, 5*time.Second)
	if err != nil {
		t.Fatalf("socks udp control: %v", err)
	}
	defer control.Close()
	if err := socks5Greet(control); err != nil {
		t.Fatalf("socks udp greet: %v", err)
	}
	if _, err := control.Write([]byte{0x05, 0x03, 0x00, 0x01, 0, 0, 0, 0, 0, 0}); err != nil {
		t.Fatalf("socks udp associate: %v", err)
	}
	relayHost, relayPort, err := readSocksBound(control)
	if err != nil {
		t.Fatalf("socks udp bound: %v", err)
	}
	udp, err := net.DialUDP("udp", nil, &net.UDPAddr{IP: net.ParseIP(relayHost), Port: relayPort})
	if err != nil {
		t.Fatalf("udp relay: %v", err)
	}
	defer udp.Close()
	// A query for example.com A, id 0x5d5d.
	query := []byte{0x5d, 0x5d, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0,
		7, 'e', 'x', 'a', 'm', 'p', 'l', 'e', 3, 'c', 'o', 'm', 0, 0, 1, 0, 1}
	packet, err := socksUDPPacket("1.1.1.1:53", query)
	if err != nil {
		t.Fatalf("packet: %v", err)
	}
	if _, err := udp.Write(packet); err != nil {
		t.Fatalf("udp write: %v", err)
	}
	_ = udp.SetReadDeadline(time.Now().Add(10 * time.Second))
	reply := make([]byte, 2048)
	n, err := udp.Read(reply)
	if err != nil {
		t.Fatalf("udp read: %v", err)
	}
	_, _, offset, ok := parseSOCKSUDPAddress(reply[:n], 3)
	if !ok || n-offset < 12 || reply[offset] != 0x5d || reply[offset+1] != 0x5d {
		t.Fatalf("dns reply = % x", reply[:n])
	}
	fmt.Printf("reality remote: ok (tcp %s + udp dns %d bytes)\n", tcpTook.Round(time.Millisecond), n-offset)
}
