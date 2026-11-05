package hy2bind

import (
	"bytes"
	"encoding/binary"
	"io"
	"net"
	"net/url"
	"regexp"
	"testing"
	"time"
)

var visionUUID = [16]byte{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16}

func TestVisionWriteStartsWithTheUserUUID(t *testing.T) {
	client, server := net.Pipe()
	defer server.Close()
	conn := newRealityVisionConn(client, visionUUID)
	done := make(chan error, 1)
	go func() {
		_, err := conn.Write([]byte("hello"))
		done <- err
	}()
	_ = server.SetReadDeadline(time.Now().Add(2 * time.Second))

	head := make([]byte, 16)
	if _, err := io.ReadFull(server, head); err != nil {
		t.Fatalf("uuid: %v", err)
	}
	if !bytes.Equal(head, visionUUID[:]) {
		t.Fatalf("uuid = %x", head)
	}
	var header [5]byte
	if _, err := io.ReadFull(server, header[:]); err != nil {
		t.Fatalf("header: %v", err)
	}
	if header[0] != visionCommandContinue {
		t.Fatalf("command = %d", header[0])
	}
	contentLen := int(binary.BigEndian.Uint16(header[1:3]))
	paddingLen := int(binary.BigEndian.Uint16(header[3:5]))
	if contentLen != 5 {
		t.Fatalf("content length = %d", contentLen)
	}
	content := make([]byte, contentLen)
	if _, err := io.ReadFull(server, content); err != nil {
		t.Fatalf("content: %v", err)
	}
	if string(content) != "hello" {
		t.Fatalf("content = %q", content)
	}
	if _, err := io.CopyN(io.Discard, server, int64(paddingLen)); err != nil {
		t.Fatalf("padding: %v", err)
	}
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("write: %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("write did not finish")
	}
}

func TestVisionReadStripsFramesAndThenPassesRawBytes(t *testing.T) {
	client, server := net.Pipe()
	defer server.Close()
	conn := newRealityVisionConn(client, visionUUID)
	go func() {
		// VLESS response header, then one framed block with three bytes of
		// padding and a direct block that ends the framed phase.
		_, _ = server.Write([]byte{0, 0})
		frame := []byte{}
		frame = append(frame, visionUUID[:]...)
		frame = append(frame, visionCommandContinue, 0, 5, 0, 3)
		frame = append(frame, []byte("hello")...)
		frame = append(frame, []byte("XXX")...)
		frame = append(frame, visionCommandDirect, 0, 4, 0, 0)
		frame = append(frame, []byte("raw!")...)
		_, _ = server.Write(frame)
		_, _ = server.Write([]byte("tail"))
	}()

	body := make([]byte, 5)
	if _, err := io.ReadFull(conn, body); err != nil {
		t.Fatalf("first read: %v", err)
	}
	if string(body) != "hello" {
		t.Fatalf("first read = %q", body)
	}
	rest := make([]byte, 8)
	if _, err := io.ReadFull(conn, rest); err != nil {
		t.Fatalf("second read: %v", err)
	}
	if string(rest) != "raw!tail" {
		t.Fatalf("second read = %q", rest)
	}
}

func TestVisionReadFallsBackWhenThePeerDoesNotFrame(t *testing.T) {
	client, server := net.Pipe()
	defer server.Close()
	conn := newRealityVisionConn(client, visionUUID)
	go func() {
		_, _ = server.Write([]byte{0, 0})
		// Sixteen bytes that are not the UUID: the peer is not framing, so the
		// stream passes through unchanged.
		_, _ = server.Write([]byte("0123456789abcdef"))
		_, _ = server.Write([]byte("tail"))
	}()
	body := make([]byte, 20)
	if _, err := io.ReadFull(conn, body); err != nil {
		t.Fatalf("read: %v", err)
	}
	if string(body) != "0123456789abcdeftail" {
		t.Fatalf("body = %q", body)
	}
}

func TestVLESSFlowAddonIsEncodedOnlyWhenAsked(t *testing.T) {
	id := visionUUID
	plain, err := vlessRequestWithFlow(id, "example.com:80", vlessCommandTCP, "")
	if err != nil {
		t.Fatal(err)
	}
	if plain[17] != 0 {
		t.Fatalf("plain addons length = %d", plain[17])
	}
	vision, err := vlessRequestWithFlow(id, "example.com:80", vlessCommandTCP, "xtls-rprx-vision")
	if err != nil {
		t.Fatal(err)
	}
	want := byte(len("xtls-rprx-vision") + 2) // protobuf tag + length + name
	if vision[17] != want {
		t.Fatalf("vision addons length = %d, want %d", vision[17], want)
	}
	if vision[18] != 0x0a {
		t.Fatalf("addons tag = %#x", vision[18])
	}
	if vision[19] != byte(len("xtls-rprx-vision")) {
		t.Fatalf("addons string length = %d", vision[19])
	}
	if string(vision[20:20+len("xtls-rprx-vision")]) != "xtls-rprx-vision" {
		t.Fatalf("addons = %q", vision[20:20+len("xtls-rprx-vision")])
	}
}

func TestVisionFlowIsCarriedOnTCPOnly(t *testing.T) {
	if got := vlessFlowFor(vlessCommandTCP, "xtls-rprx-vision"); got != "xtls-rprx-vision" {
		t.Fatalf("tcp flow = %q", got)
	}
	// Xray's inbound refuses a UDP request that names a flow; a Vision account
	// still serves UDP as plain VLESS.
	if got := vlessFlowFor(vlessCommandUDP, "xtls-rprx-vision"); got != "" {
		t.Fatalf("udp flow = %q", got)
	}
}

func TestGRPCMessageRoundTripsAHunk(t *testing.T) {
	message := grpcMessage([]byte("payload"))
	if message[0] != 0 {
		t.Fatalf("compression flag = %d", message[0])
	}
	body, err := readGRPCMessage(bytes.NewReader(message))
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	data, err := parseHunk(body)
	if err != nil {
		t.Fatalf("hunk: %v", err)
	}
	if string(data) != "payload" {
		t.Fatalf("data = %q", data)
	}
}

func TestXHTTPHeadersCarryAPaddingLengthTheServerAccepts(t *testing.T) {
	target := &url.URL{Scheme: "https", Host: "203.0.113.10:8080", Path: "/x/session"}
	referer, err := url.Parse(xhttpHeaders(target).Get("Referer"))
	if err != nil {
		t.Fatalf("referer: %v", err)
	}
	padding := referer.Query().Get("x_padding")
	// Xray's default accepted range is 100..1000 bytes of padding.
	if len(padding) < 100 || len(padding) > 1000 {
		t.Fatalf("padding length = %d", len(padding))
	}
}

func TestXHTTPSessionIsAUUIDShape(t *testing.T) {
	session := newXHTTPSession()
	if !regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`).MatchString(session) {
		t.Fatalf("session = %q", session)
	}
	if session == newXHTTPSession() {
		t.Fatal("two sessions are equal")
	}
}
