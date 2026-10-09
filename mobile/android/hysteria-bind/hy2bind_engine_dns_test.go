package hy2bind

import (
	"os"
	"strings"
	"testing"
)

// The engine must not advertise a resolver on the tun adapter.
//
// This process hijacks DNS that arrives through the tun and forwards it, but it
// is not a DNS server. Pointing Windows at an address nothing answers on makes
// every lookup wait out a timeout: the broker's resolve gate failed after eight
// seconds on the owner's machine once the address became Preferred, while the
// same gate had passed instantly moments before, when the adapter still had no
// usable address and Windows was still using the physical resolver.
//
// Leaving the adapter alone keeps that resolver. Before capture its queries go
// out directly, and afterwards they enter the tun and the hijack forwards them,
// so nothing is lost.
func TestEngineDoesNotAdvertiseATunResolver(t *testing.T) {
	src, err := os.ReadFile("cmd/proxydom-engine/main.go")
	if err != nil {
		t.Fatal(err)
	}
	text := string(src)
	if strings.Contains(text, "dnsservers") {
		t.Fatal("the engine must not set dnsservers on the tun adapter")
	}
	if !strings.Contains(text, `netsh("interface", "ipv4", "set", "address"`) {
		t.Fatal("the engine must still assign the tun address")
	}
}
