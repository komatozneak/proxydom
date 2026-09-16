package hy2bind

import "testing"

type discardWriter struct{}

func (discardWriter) WritePacket([]byte) error { return nil }

func TestInjectPacketWithoutTun(t *testing.T) {
	Stop()
	if err := InjectPacket([]byte{0x45, 0, 0, 20}); err == "" {
		t.Fatal("expected error when packet tun is down")
	}
}

func TestStartPacketTunRequiresHy2(t *testing.T) {
	Stop()
	if err := StartPacketTun(1280); err == "" {
		t.Fatal("expected hy2 not started")
	}
	if err := StartPacketTun(1280); err != "hy2 not started" {
		t.Fatalf("got %q", err)
	}
}

func TestSetPacketWriterAndStop(t *testing.T) {
	Stop()
	SetPacketWriter(discardWriter{})
	Stop()
	SetPacketWriter(nil)
}

func TestInjectEmptyPacket(t *testing.T) {
	if err := InjectPacket(nil); err == "" {
		t.Fatal("empty packet should fail")
	}
}
