//go:build windows

package main

import (
	"strings"
	"testing"
)

func TestHy2StartOmitsThePasswordFromTheStatusLine(t *testing.T) {
	raw := []byte(`{
		"socks_listen":"127.0.0.1:10808",
		"direct_domains":["lan.example"],
		"force_proxy_domains":["youtube.com"],
		"udp_direct":true,
		"api_port":19090,
		"api_secret":"abc123",
		"outbound":{
			"type":"hysteria2",
			"server":"203.0.113.10",
			"server_port":443,
			"password":"secret+pass",
			"sni":"cdn.example",
			"obfs":"salamander",
			"obfs_password":"hide",
			"server_ports":"1000:2000"
		}
	}`)
	cfg, err := parseEngineConfig(raw)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.rejectTransport() {
		t.Fatal("hysteria2 was rejected")
	}
	start, err := cfg.hy2StartJSON()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(start), "203.0.113.10:443") {
		t.Fatalf("start json missing server: %s", start)
	}
	line := cfg.statusLine()
	if strings.Contains(line, "secret+pass") || strings.Contains(line, "abc123") || strings.Contains(line, "hide") {
		t.Fatalf("status line leaked a secret: %s", line)
	}
	if !strings.Contains(line, "routing_applied=true") || !strings.Contains(line, "hop=applied") || !strings.Contains(line, "clash_api=applied") {
		t.Fatalf("status line: %s", line)
	}
	if !strings.Contains(line, "direct_domains=1") || !strings.Contains(line, "force_proxy_domains=1") {
		t.Fatalf("status line counts: %s", line)
	}
}

// VLESS used to be refused by name. The Windows broker carries it now, so the
// contract is the opposite: a dialable line is accepted and the document is
// built, and only what this core cannot carry is refused.
func TestVLESSBuildsAShareDocument(t *testing.T) {
	cfg, err := parseEngineConfig([]byte(`{"socks_listen":"127.0.0.1:18099","outbound":{"type":"vless","server":"203.0.113.11","server_port":443,"uuid":"11111111-2222-3333-4444-555555555555","sni":"cdn.example","network":"ws","path":"/ray","host":"cdn.example","alpn":"h2,http/1.1","security":"tls","fingerprint":"chrome"}}`))
	if err != nil {
		t.Fatal(err)
	}
	if cfg.rejectTransport() {
		t.Fatal("vless was refused")
	}
	if refusal := cfg.shareRefusal(); refusal != "" {
		t.Fatalf("a dialable line was refused as %q", refusal)
	}
	doc, err := cfg.vlessStartJSON()
	if err != nil {
		t.Fatal(err)
	}
	text := string(doc)
	for _, want := range []string{
		`"protocol":"vless"`,
		`"network":"ws"`,
		`"security":"tls"`,
		`"path":"/ray"`,
		`"Host":"cdn.example"`,
		`"h2"`,
		`"http/1.1"`,
		`"serverName":"cdn.example"`,
		`"fingerprint":"chrome"`,
		`"11111111-2222-3333-4444-555555555555"`,
	} {
		if !strings.Contains(text, want) {
			t.Fatalf("document missing %s: %s", want, text)
		}
	}
	// The core listens where the broker told it to, not on a constant.
	if !strings.Contains(text, `"port":18099`) {
		t.Fatalf("document ignored socks_listen: %s", text)
	}
	line := cfg.statusLine()
	if !strings.Contains(line, "scheme=vless") || !strings.Contains(line, "transport=ws") {
		t.Fatalf("status line: %s", line)
	}
	if strings.Contains(line, "11111111-2222-3333-4444-555555555555") {
		t.Fatalf("status line leaked the uuid: %s", line)
	}
}

// A transport the core cannot dial is refused before a core is started, so the
// person is told which part of the line is unsupported instead of watching a
// timeout and blaming their network. The name is the user-facing one: the
// broker matches it literally, so a rename here has to reach the broker too.
func TestVLESSBuildsKCPSeed(t *testing.T) {
	cfg, err := parseEngineConfig([]byte(`{"socks_listen":"127.0.0.1:18099","outbound":{"type":"vless","server":"203.0.113.11","server_port":443,"uuid":"11111111-2222-3333-4444-555555555555","sni":"cdn.example","network":"kcp","kcp_seed":"obfuscate-me","security":"tls"}}`))
	if err != nil {
		t.Fatal(err)
	}
	if refusal := cfg.shareRefusal(); refusal != "" {
		t.Fatalf("a dialable kcp line was refused as %q", refusal)
	}
	doc, err := cfg.vlessStartJSON()
	if err != nil {
		t.Fatal(err)
	}
	text := string(doc)
	// The loader reads kcpSettings.seed and hands it to the core. Without this
	// the engine dialled a server that was expecting obfuscation and failed as
	// a generic core exit, with nothing naming the seed as the cause.
	if !strings.Contains(text, `"kcpSettings"`) || !strings.Contains(text, `"seed":"obfuscate-me"`) {
		t.Fatalf("kcp seed did not reach the document: %s", text)
	}
	// A kcp line with no seed must not grow an empty settings block: the core
	// then uses its own default, which is what the line asked for.
	bare, err := parseEngineConfig([]byte(`{"socks_listen":"127.0.0.1:18099","outbound":{"type":"vless","server":"203.0.113.11","server_port":443,"uuid":"11111111-2222-3333-4444-555555555555","sni":"cdn.example","network":"kcp","security":"tls"}}`))
	if err != nil {
		t.Fatal(err)
	}
	bareDoc, err := bare.vlessStartJSON()
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(bareDoc), "kcpSettings") {
		t.Fatalf("a kcp line with no seed invented settings: %s", bareDoc)
	}
}

// The status line is the journal's record of what the engine did. Both engines
// now run the same TUN-level classifier, so a VLESS session with lists really
// applies them; only DNS hijacking stays a hysteria2 feature. This document is
// deliberately the old broker's shape (udp_direct instead of udp_mode): the
// engine must ignore the legacy flag and report the policy it actually used.
func TestVLESSStatusReportsRoutingWithoutDNSHijack(t *testing.T) {
	cfg, err := parseEngineConfig([]byte(`{
		"socks_listen":"127.0.0.1:18099",
		"tun":{"name":"ProxyDomTun","address":"198.18.0.1/30","dns":"198.18.0.2","mtu":1280,"auto_route":false},
		"force_proxy_domains":["youtube.com"],
		"direct_domains":["lan.example"],
		"udp_direct":true,
		"dns_hijack":true,
		"routing_applied":true,
		"outbound":{"type":"vless","server":"203.0.113.11","server_port":443,"uuid":"11111111-2222-3333-4444-555555555555","sni":"cdn.example","network":"ws","path":"/ray","security":"tls"}
	}`))
	if err != nil {
		t.Fatal(err)
	}
	line := cfg.statusLine()
	if !strings.Contains(line, "scheme=vless") {
		t.Fatalf("status line does not name the scheme: %s", line)
	}
	if !strings.Contains(line, "routing_applied=true") {
		t.Fatalf("vless with lists no longer reports the routing it applies: %s", line)
	}
	if strings.Contains(line, "dns_hijack=true") {
		t.Fatalf("vless was journalled as dns-hijacked: %s", line)
	}
	if !strings.Contains(line, "udp_mode=proxy_all") || strings.Contains(line, "udp_direct=true") {
		t.Fatalf("the legacy udp_direct flag leaked into the policy: %s", line)
	}
	// The same document for hysteria2 does apply them, and must keep saying so.
	hy2, err := parseEngineConfig([]byte(`{
		"socks_listen":"127.0.0.1:18099",
		"tun":{"name":"ProxyDomTun","address":"198.18.0.1/30","dns":"198.18.0.2","mtu":1280,"auto_route":false},
		"force_proxy_domains":["youtube.com"],
		"direct_domains":["lan.example"],
		"dns_hijack":true,
		"routing_applied":true,
		"outbound":{"type":"hysteria2","server":"203.0.113.10","server_port":443,"password":"p","sni":"cdn.example"}
	}`))
	if err != nil {
		t.Fatal(err)
	}
	hy2Line := hy2.statusLine()
	if !strings.Contains(hy2Line, "routing_applied=true") || !strings.Contains(hy2Line, "dns_hijack=true") {
		t.Fatalf("hysteria2 stopped reporting the routing it applies: %s", hy2Line)
	}
}

func TestVLESSTransportIsRefusedBeforeTheCoreStarts(t *testing.T) {
	for _, network := range []string{"grpc", "xhttp", "quic", "httpupgrade"} {
		cfg, err := parseEngineConfig([]byte(`{"outbound":{"type":"vless","server":"203.0.113.11","server_port":443,"uuid":"u","network":"` + network + `"}}`))
		if err != nil {
			t.Fatal(err)
		}
		if got := cfg.shareRefusal(); got != "transport_unsupported" {
			t.Fatalf("%s: refusal = %q, want transport_unsupported", network, got)
		}
	}
}

// Reality arrived with xray-core, which is GPL and is not linked (ADR 036).
func TestVLESSRealityIsRefused(t *testing.T) {
	cfg, err := parseEngineConfig([]byte(`{"outbound":{"type":"vless","server":"203.0.113.11","server_port":443,"uuid":"u","security":"reality","public_key":"k"}}`))
	if err != nil {
		t.Fatal(err)
	}
	if got := cfg.shareRefusal(); got != "security_unsupported" {
		t.Fatalf("refusal = %q, want security_unsupported", got)
	}
}

func TestVLESSSaysNothingMeansTCPOverTLS(t *testing.T) {
	cfg, err := parseEngineConfig([]byte(`{"outbound":{"type":"vless","server":"203.0.113.11","server_port":443,"uuid":"u"}}`))
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Outbound.networkName() != "tcp" || cfg.Outbound.securityName() != "tls" {
		t.Fatalf("defaults = %s/%s", cfg.Outbound.networkName(), cfg.Outbound.securityName())
	}
	doc, err := cfg.vlessStartJSON()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(doc), `"tlsSettings"`) {
		t.Fatalf("a line that says nothing must still get TLS: %s", doc)
	}
}

func TestVLESSNeedsAUUID(t *testing.T) {
	cfg, err := parseEngineConfig([]byte(`{"outbound":{"type":"vless","server":"203.0.113.11","server_port":443}}`))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := cfg.vlessStartJSON(); err == nil {
		t.Fatal("a vless line without a uuid was accepted")
	}
}

// The two cores have separate starters. Handing one the other's document would
// start nothing and report success.
func TestHy2StartRefusesAVLESSDocument(t *testing.T) {
	cfg, err := parseEngineConfig([]byte(`{"outbound":{"type":"vless","server":"203.0.113.11","server_port":443,"uuid":"u"}}`))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := cfg.hy2StartJSON(); err == nil {
		t.Fatal("a vless outbound was handed to the hy2 starter")
	}
}

func TestOtherSchemesAreStillRefused(t *testing.T) {
	for _, kind := range []string{"vmess", "trojan", "ss", "shadowsocks", ""} {
		cfg, err := parseEngineConfig([]byte(`{"outbound":{"type":"` + kind + `","server":"203.0.113.11","server_port":443}}`))
		if err != nil {
			t.Fatal(err)
		}
		if !cfg.rejectTransport() {
			t.Fatalf("%q was accepted", kind)
		}
	}
}

func TestProbeHasNoTunName(t *testing.T) {
	cfg, err := parseEngineConfig([]byte(`{"probe":true,"socks_listen":"127.0.0.1:17890","outbound":{"type":"hysteria2","server":"203.0.113.10","server_port":443,"password":"secret"}}`))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(cfg.statusLine(), "tun= ") && !strings.HasPrefix(cfg.statusLine(), "proxydom-engine tun= socks=") {
		t.Fatalf("probe status should not name a tun: %s", cfg.statusLine())
	}
	if strings.Contains(cfg.statusLine(), "ProxyDomTun") {
		t.Fatalf("probe named the tun: %s", cfg.statusLine())
	}
}
