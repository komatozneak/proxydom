package hy2bind

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

// The Dart builder and this loader both carry a fingerprint table, because
// Android pre-translates and the loader normalises whatever reaches it. Two
// tables can drift, and the one that drifts is the platform that stops working:
// a name Dart knows and Go does not fails the Windows dial before TLS starts,
// with "unknown preset name" and nothing else.
//
// So read the Dart table out of the tree and require this loader to know every
// key in it. A new alias on one side fails here instead of on a phone.
func TestEveryDartFingerprintAliasIsKnownHere(t *testing.T) {
	const path = "../../lib/features/vpn/data/engine_share_config.dart"
	raw, err := os.ReadFile(path)
	if err != nil {
		// Fail rather than skip. A guard that quietly steps aside when it cannot
		// find its subject is a test that claims protection and gives none.
		t.Fatalf("cannot read %s: %v (the guard needs the whole repo checked out)", path, err)
	}
	text := string(raw)
	start := strings.Index(text, "_fingerprintAliases")
	if start < 0 {
		t.Fatalf("no _fingerprintAliases table in %s", path)
	}
	end := strings.Index(text[start:], "};")
	if end < 0 {
		t.Fatalf("unterminated _fingerprintAliases table in %s", path)
	}
	body := text[start : start+end]

	entry := regexp.MustCompile(`'([a-z0-9_]+)'\s*:\s*'([a-z0-9_]+)'`)
	found := entry.FindAllStringSubmatch(body, -1)
	if len(found) < 40 {
		t.Fatalf("read only %d aliases from %s; the table or its shape changed", len(found), path)
	}
	for _, match := range found {
		key, want := match[1], match[2]
		got, ok := fingerprintAliases[key]
		if !ok {
			t.Fatalf("dart maps %q but this loader does not know it", key)
		}
		if got != want {
			t.Fatalf("%q: dart says %q, loader says %q", key, want, got)
		}
	}
}

// A share link says `fp=chrome`; the core knows `chrome_auto` and no `chrome`.
// Passing the link's word straight through failed the dial before TLS started.
func TestCoreFingerprintTranslatesShareLinkWords(t *testing.T) {
	cases := map[string]string{
		"chrome":   "chrome_auto",
		"firefox":  "firefox_auto",
		"ios":      "ios_auto",
		"android":  "android_11_okhttp",
		"random":   "randomized",
		" CHROME ": "chrome_auto",
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
