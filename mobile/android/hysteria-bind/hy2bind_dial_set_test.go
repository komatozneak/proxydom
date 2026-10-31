package hy2bind

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

// The Dart builder and this loader both decide whether a share line is
// dialable, and they answer with the same words on purpose: Dart builds the
// document Android hands the core, and Dart's answer is also what decides
// whether the Windows path hands the raw URI to the broker at all. A word one
// side admits and the other refuses is a line that either fails with a generic
// engine error or is offered as active and then goes nowhere.
//
// The fingerprint tables already drifted once and cost a release. These two
// lists are the same hazard, so they get the same guard: read the Dart sets out
// of the tree and require this loader to agree with them in both directions.
//
// Not skippable. A guard that steps aside when it cannot find its subject
// claims protection it does not give.
func dartEngineDialSets(t *testing.T) (transports, securities map[string]bool, normalize map[string]string) {
	t.Helper()
	const path = "../../lib/features/vpn/data/engine_share_config.dart"
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("cannot read %s: %v (the guard needs the whole repo checked out)", path, err)
	}
	text := string(raw)

	readSet := func(name string, atLeast int) map[string]bool {
		// Anchor on the declaration, not on the name. The name also appears in
		// the doc comment at the top of the file that lists both sets, and a
		// search for the bare name starts there and then runs to the first "};"
		// it meets -- which is a different table entirely. That misread made
		// this guard report `tag` as a transport on its first run.
		start := strings.Index(text, "const "+name)
		if start < 0 {
			t.Fatalf("no `const %s` in %s", name, path)
		}
		open := strings.Index(text[start:], "{")
		if open < 0 {
			t.Fatalf("no set literal after `const %s` in %s", name, path)
		}
		open += start
		close := strings.Index(text[open:], "}")
		if close < 0 {
			t.Fatalf("unterminated `const %s` set in %s", name, path)
		}
		body := text[open : open+close]
		word := regexp.MustCompile(`'([a-z0-9_]+)'`)
		found := word.FindAllStringSubmatch(body, -1)
		if len(found) < atLeast {
			t.Fatalf("read only %d words from `const %s`; the set or its shape changed", len(found), name)
		}
		out := map[string]bool{}
		for _, match := range found {
			out[match[1]] = true
		}
		return out
	}

	transports = readSet("_engineTransports", 4)
	securities = readSet("_engineSecurities", 2)

	// _stream normalises the link's word before the allowlist check, so a word
	// that is rewritten is admitted even though it is not in the set. The
	// rewrite has to be read too, or this guard would call `mkcp` a divergence
	// while the Dart side is happily accepting it.
	normalize = map[string]string{}
	rewrite := regexp.MustCompile(`'([a-z0-9_]+)'\s*=>\s*'([a-z0-9_]+)'`)
	// Same anchoring rule as above: the declaration, not the name.
	if start := strings.Index(text, "? _stream("); start >= 0 {
		if end := strings.Index(text[start:], "final scheme"); end > 0 {
			for _, match := range rewrite.FindAllStringSubmatch(text[start:start+end], -1) {
				normalize[match[1]] = match[2]
			}
		}
	}
	// A guard that silently reads nothing would pass by finding nothing to
	// disagree with. `mkcp` is the one rewrite that exists today.
	if normalize["mkcp"] != "kcp" {
		t.Fatalf("read no `mkcp` rewrite out of %s; the switch or its shape changed", path)
	}
	return transports, securities, normalize
}

// Everything Dart admits, this loader must admit. This is the dangerous
// direction: Dart lets the line through and the engine is the one that has to
// refuse it, which reaches the person as a failure rather than as a refusal.
func TestEveryDartTransportIsDialableHere(t *testing.T) {
	transports, _, normalize := dartEngineDialSets(t)
	for word := range transports {
		if !TransportDialable(word) {
			t.Fatalf("dart admits transport %q but this loader refuses it", word)
		}
	}
	// A word Dart rewrites is admitted too, so it has to be dialable as well.
	for from := range normalize {
		if !TransportDialable(from) {
			t.Fatalf("dart rewrites transport %q but this loader refuses it", from)
		}
	}
}

func TestEveryDartSecurityIsDialableHere(t *testing.T) {
	_, securities, _ := dartEngineDialSets(t)
	for word := range securities {
		if !SecurityDialable(word) {
			t.Fatalf("dart admits security %q but this loader refuses it", word)
		}
	}
}

// And the other direction: a transport this loader has learned to dial must not
// be invisible to Dart, or a line the engine can carry is refused before it is
// ever offered. The two sets are equal once Dart's rewrites are applied.
func TestThisLoaderAdmitsNoTransportDartWouldRefuse(t *testing.T) {
	transports, _, normalize := dartEngineDialSets(t)

	// Probed through the loader's own entry point rather than a second list, so
	// this cannot drift from what a dial actually uses.
	candidates := []string{
		"", "tcp", "ws", "websocket", "kcp", "mkcp",
		"grpc", "quic", "httpupgrade", "xhttp", "splithttp", "http",
	}
	for _, word := range candidates {
		if !TransportDialable(word) {
			continue
		}
		normalized := word
		if to, ok := normalize[word]; ok {
			normalized = to
		}
		if word == "" {
			// The empty word is the link saying nothing; Dart's _stream reads
			// that as tcp, so it is covered by the set.
			if !transports["tcp"] {
				t.Fatalf("this loader dials the default transport but dart's set has no tcp")
			}
			continue
		}
		if !transports[normalized] {
			t.Fatalf("this loader dials %q (as %q) but dart would refuse the line", word, normalized)
		}
	}
}

// The same in the other direction for securities. A security this loader can
// negotiate that Dart refuses is a line the engine could carry and the UI would
// show as inactive, which is a working line reported as broken.
func TestThisLoaderAdmitsNoSecurityDartWouldRefuse(t *testing.T) {
	_, securities, _ := dartEngineDialSets(t)

	// `reality` is deliberately not in this cross-check: it is not a v2ray
	// security, it has a second engine and a second Dart builder. The pair is
	// covered by TestRealitySecurityIsCarried below.
	candidates := []string{"", "none", "tls", "xtls", "tls13", "reality2"}
	for _, word := range candidates {
		if !SecurityDialable(word) {
			continue
		}
		// Dart reads the empty word as none.
		normalized := word
		if normalized == "" {
			normalized = "none"
		}
		if !securities[normalized] {
			t.Fatalf("this loader negotiates %q (as %q) but dart would refuse the line",
				word, normalized)
		}
	}
}

// The words that must stay refused, on both sides. A refusal here is what keeps
// an imported line from being offered as active and then failing at the dial.
//
// gRPC and HTTPUpgrade moved to the dialable side: this core registers both
// dialers, so refusing them would hide a line that works. What stays refused is
// what has no dialer at all — QUIC, XHTTP and the Xray-only split-http.
func TestParkedTransportsAndSecuritiesStayRefused(t *testing.T) {
	for _, word := range []string{"quic", "xhttp", "splithttp"} {
		if TransportDialable(word) {
			t.Fatalf("transport %q must stay refused: v2ray-core has no dialer for it", word)
		}
	}
	for _, word := range []string{"xtls"} {
		if SecurityDialable(word) {
			t.Fatalf("security %q must stay refused: no engine negotiates it", word)
		}
	}
	// And Dart has to refuse them too, or the Windows path would hand the raw
	// URI to a broker that cannot carry it. `reality` is absent here: it is
	// carried by the REALITY engine, not by the v2ray sets this helper reads.
	transports, securities, _ := dartEngineDialSets(t)
	for _, word := range []string{"quic", "xhttp", "splithttp"} {
		if transports[word] {
			t.Fatalf("dart admits transport %q, which the engine cannot dial", word)
		}
	}
	for _, word := range []string{"xtls"} {
		if securities[word] {
			t.Fatalf("dart admits security %q, which the engine cannot negotiate", word)
		}
	}
}

// REALITY is a second engine, so its security word is dialable even though the
// v2ray set does not contain it. The Dart side has a matching builder; this
// guards the Go half of that pair.
func TestRealitySecurityIsCarried(t *testing.T) {
	if !SecurityDialable("reality") {
		t.Fatal("the Windows engine would refuse a REALITY line before starting the second engine")
	}
	if !SecurityDialable("REALITY") {
		t.Fatal("security names are folded before the table is consulted")
	}
}
