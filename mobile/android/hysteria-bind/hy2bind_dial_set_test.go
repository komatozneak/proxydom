package hy2bind

import "testing"

// The tables the Windows engine consults before it starts a core. A transport
// or security admitted here must have a dialer behind it, and one refused here
// must have none: otherwise a line is offered as active and fails at the dial,
// or a working line is shown as unsupported.

func TestCarriedTransportsAreDialable(t *testing.T) {
	// The empty word is the link saying nothing, which means TCP. `raw` is
	// Xray's newer name for the same stream, `websocket` and `mkcp` the long
	// spellings of `ws` and `kcp`.
	for _, word := range []string{"", "tcp", "raw", "ws", "websocket", "kcp", "mkcp", "grpc", "httpupgrade", "TCP", " ws "} {
		if !TransportDialable(word) {
			t.Fatalf("transport %q has a dialer but is refused", word)
		}
	}
}

func TestParkedTransportsStayRefused(t *testing.T) {
	// QUIC, XHTTP and Xray's split-http have no dialer in this core.
	for _, word := range []string{"quic", "xhttp", "splithttp", "http"} {
		if TransportDialable(word) {
			t.Fatalf("transport %q must stay refused: no engine dials it", word)
		}
	}
}

func TestSecurities(t *testing.T) {
	// `reality` is carried by the REALITY engine, not by v2ray-core; it is in
	// this table so the broker does not refuse the line before that engine is
	// selected.
	for _, word := range []string{"", "none", "tls", "TLS", "reality", "REALITY"} {
		if !SecurityDialable(word) {
			t.Fatalf("security %q is negotiated but refused", word)
		}
	}
	for _, word := range []string{"xtls", "tls13", "reality2"} {
		if SecurityDialable(word) {
			t.Fatalf("security %q must stay refused: no engine negotiates it", word)
		}
	}
}
