package hy2config

import (
	"net"
	"strings"
	"testing"

	"github.com/komatozneak/teremok-connect/desktop/windows/internal/api"
)

func TestRenderSOCKSOmitsTUN(t *testing.T) {
	yml, err := Render(Options{
		Mode: ModeSOCKS,
		Profile: &api.HysteriaProfile{
			Server:      "217.60.3.9:443",
			Auth:        "u:p",
			SNI:         "hy2-eu.teremokconnect.online",
			SocksListen: "127.0.0.1:10808",
			BandwidthUp: "20 mbps",
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(yml, "tun:") {
		t.Fatal("socks mode must not emit tun")
	}
	if !strings.Contains(yml, `server: "217.60.3.9:443"`) {
		t.Fatalf("missing server:\n%s", yml)
	}
	if !strings.Contains(yml, "socks5:") {
		t.Fatal("socks5 inbound required for prove")
	}
}

func TestRenderTUNExcludesControlPlaneAndServer(t *testing.T) {
	yml, err := Render(Options{
		Mode:     ModeTUN,
		NodeHost: "217.60.3.9",
		Profile: &api.HysteriaProfile{
			Server: "217.60.3.9:443",
			Auth:   "u:p",
			SNI:    "hy2-eu.teremokconnect.online",
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(yml, "tun:") {
		t.Fatal("expected tun block")
	}
	if !strings.Contains(yml, `"176.114.64.174/32"`) {
		t.Fatalf("control plane must be excluded:\n%s", yml)
	}
	if !strings.Contains(yml, `"217.60.3.9/32"`) {
		t.Fatalf("Hy2 server must be excluded:\n%s", yml)
	}
	if !strings.Contains(yml, `"192.168.0.0/16"`) {
		t.Fatalf("LAN must stay off TUN:\n%s", yml)
	}
	if !strings.Contains(yml, "name: teremokhy2") {
		t.Fatalf("tun adapter name:\n%s", yml)
	}
}

func TestRenderTUNResolvesHostnameExclude(t *testing.T) {
	orig := lookupIPv4
	lookupIPv4 = func(host string) []net.IP {
		if host == "hy2-us.teremokconnect.online" {
			return []net.IP{net.ParseIP("45.91.248.91")}
		}
		return nil
	}
	t.Cleanup(func() { lookupIPv4 = orig })
	yml, err := Render(Options{
		Mode:     ModeTUN,
		NodeHost: "hy2-us.teremokconnect.online",
		Profile: &api.HysteriaProfile{
			Server: "hy2-us.teremokconnect.online:443",
			Auth:   "u:p",
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(yml, `"45.91.248.91/32"`) {
		t.Fatalf("resolved Hy2 IP must be excluded:\n%s", yml)
	}
}
