package hy2bind

import (
	"encoding/binary"
	"errors"
	"io"
	"net"
	"testing"
	"time"

	"github.com/apernet/hysteria/core/v2/client"
)

type fakeHyClient struct {
	gotTarget string
}

func (f *fakeHyClient) TCP(addr string) (net.Conn, error) {
	f.gotTarget = addr
	a, b := net.Pipe()
	go func() {
		defer b.Close()
		_, _ = io.Copy(io.Discard, b)
	}()
	return a, nil
}

func (f *fakeHyClient) UDP() (client.HyUDPConn, error) {
	return nil, errors.New("udp unused")
}

func (f *fakeHyClient) Close() error { return nil }

func TestHandleSOCKSConnectIPv4Bytewise(t *testing.T) {
	clientConn, serverConn := net.Pipe()
	fake := &fakeHyClient{}
	done := make(chan struct{})
	go func() {
		handleSOCKS(serverConn, fake)
		close(done)
	}()

	// Greeting one byte at a time — the old handler closed on short Read.
	for _, b := range []byte{0x05, 0x01, 0x00} {
		if _, err := clientConn.Write([]byte{b}); err != nil {
			t.Fatal(err)
		}
		time.Sleep(5 * time.Millisecond)
	}
	reply := make([]byte, 2)
	if err := clientConn.SetReadDeadline(time.Now().Add(2 * time.Second)); err != nil {
		t.Fatal(err)
	}
	if _, err := io.ReadFull(clientConn, reply); err != nil {
		t.Fatalf("greeting reply: %v", err)
	}
	if reply[0] != 0x05 || reply[1] != 0x00 {
		t.Fatalf("greeting reply %v", reply)
	}

	req := []byte{0x05, 0x01, 0x00, 0x01, 1, 1, 1, 1}
	req = binary.BigEndian.AppendUint16(req, 443)
	for _, b := range req {
		if _, err := clientConn.Write([]byte{b}); err != nil {
			t.Fatal(err)
		}
		time.Sleep(5 * time.Millisecond)
	}
	crep := make([]byte, 10)
	if _, err := io.ReadFull(clientConn, crep); err != nil {
		t.Fatalf("connect reply: %v", err)
	}
	if crep[0] != 0x05 || crep[1] != 0x00 {
		t.Fatalf("connect rep=%v", crep)
	}
	if fake.gotTarget != "1.1.1.1:443" {
		t.Fatalf("target %q", fake.gotTarget)
	}
	_ = clientConn.Close()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("handler did not exit")
	}
}
