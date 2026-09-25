package hy2bind

import "testing"

func TestSalamanderRoundTrip(t *testing.T) {
	ob, err := newSalamander([]byte("standObfsPass"))
	if err != nil {
		t.Fatal(err)
	}
	plain := []byte("quic-packet")
	wire := make([]byte, len(plain)+smSaltLen)
	if n := ob.obfuscate(plain, wire); n != len(wire) {
		t.Fatalf("obfuscate n=%d", n)
	}
	back := make([]byte, len(plain))
	if n := ob.deobfuscate(wire, back); n != len(plain) {
		t.Fatalf("deobfuscate n=%d", n)
	}
	if string(back) != string(plain) {
		t.Fatalf("got %q", back)
	}
}

func TestConnFactoryRejectsUnknownObfs(t *testing.T) {
	_, err := connFactoryFor(startConfig{Obfs: "http"})
	if err == nil {
		t.Fatal("expected error")
	}
}
