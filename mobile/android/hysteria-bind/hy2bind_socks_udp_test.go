package hy2bind

import "testing"

func TestSocksUDPPayloadStripsHeader(t *testing.T) {
	payload := []byte{0xde, 0xad, 0xbe}
	pkt := append([]byte{0, 0, 0}, socksAddr("1.1.1.1", 53)...)
	pkt = append(pkt, payload...)
	got, err := socksUDPPayload(pkt)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != string(payload) {
		t.Fatalf("got %x", got)
	}
}
