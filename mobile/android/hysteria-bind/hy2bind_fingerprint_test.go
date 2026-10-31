package hy2bind

import (
	"testing"
)

// A share link says `fp=chrome`; the core knows `chrome_auto` and no `chrome`.
// Passing the link's word straight through failed the dial before TLS started.
func TestCoreFingerprintTranslatesShareLinkWords(t *testing.T) {
	cases := map[string]string{
		"chrome":     "chrome_auto",
		"firefox":    "firefox_auto",
		"ios":        "ios_auto",
		"android":    "android_11_okhttp",
		"random":     "randomized",
		" CHROME ":   "chrome_auto",
		"chrome_102": "chrome_102",
	}
	for raw, want := range cases {
		if got := coreFingerprint(&shareTLS{Fingerprint: raw}); got != want {
			t.Fatalf("%q -> %q, want %q", raw, got, want)
		}
	}
}

// No fingerprint means the core's own TLS, not a guess at one.
func TestCoreFingerprintIsEmptyWhenUnasked(t *testing.T) {
	if got := coreFingerprint(nil); got != "" {
		t.Fatalf("nil tls -> %q", got)
	}
	if got := coreFingerprint(&shareTLS{}); got != "" {
		t.Fatalf("empty name -> %q", got)
	}
}

// An unrecognised name is dropped, not fatal. The fingerprint is a hardening
// detail, not the identity of the line: refusing to connect because a provider
// spelled a browser name differently would make a working line inert.
func TestCoreFingerprintDropsAnUnknownName(t *testing.T) {
	if got := coreFingerprint(&shareTLS{Fingerprint: "netscape_4"}); got != "" {
		t.Fatalf("unknown name -> %q, want empty", got)
	}
}
