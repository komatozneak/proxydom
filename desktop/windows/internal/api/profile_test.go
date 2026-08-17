package api

import "testing"

func TestParseConnectBodyHappy(t *testing.T) {
	raw := []byte(`{
		"username": "hy21xabcd",
		"active_core": "hysteria",
		"node_host": "217.60.3.9",
		"hysteria_profile": {
			"schema_version": 1,
			"node_id": "eu-hy2-1",
			"server": "217.60.3.9:443",
			"auth": "user:pass",
			"username": "user",
			"sni": "hy2-eu.teremokconnect.online",
			"socks_listen": "127.0.0.1:10808",
			"bandwidth_up": "20 mbps",
			"bandwidth_down": "100 mbps"
		}
	}`)
	got, err := ParseConnectBody(raw)
	if err != nil {
		t.Fatal(err)
	}
	if got.HysteriaProfile.Server != "217.60.3.9:443" {
		t.Fatalf("server: %s", got.HysteriaProfile.Server)
	}
}

func TestParseConnectBodyRejectsOtherCore(t *testing.T) {
	raw := []byte(`{"active_core":"trusttunnel","hysteria_profile":{"server":"x","auth":"y"}}`)
	if _, err := ParseConnectBody(raw); err == nil {
		t.Fatal("expected error")
	}
}
