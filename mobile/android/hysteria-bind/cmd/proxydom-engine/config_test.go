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

func TestVLESSIsTransportNotTCP(t *testing.T) {
	cfg, err := parseEngineConfig([]byte(`{"outbound":{"type":"vless","server":"203.0.113.11","server_port":443,"uuid":"11111111-2222-3333-4444-555555555555"}}`))
	if err != nil {
		t.Fatal(err)
	}
	if !cfg.rejectTransport() {
		t.Fatal("vless was accepted")
	}
	if _, err := cfg.hy2StartJSON(); err == nil || !strings.Contains(err.Error(), "error transport") {
		t.Fatalf("err = %v", err)
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
