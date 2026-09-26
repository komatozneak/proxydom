package hy2bind

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	clog "github.com/xtls/xray-core/common/log"
)

func TestKeepCoreRecordDropsPacketNoise(t *testing.T) {
	noise := []string{
		"proxy/socks: send packet to udp:203.0.113.10:443 with 1250 bytes",
		"proxy/socks: writing back UDP response with 1176 bytes",
		"transport/internet/udp: dispatch request to: udp:203.0.113.10:443",
		"app/stats: create new counter outbound>>>proxy>>>traffic>>>uplink",
		"transport/internet/udp: establishing new connection for udp:203.0.113.10:53",
		"proxy/socks: client UDP connection from udp:127.0.0.1:53540",
		"proxy/socks: TCP Connect request to tcp:203.0.113.10:443",
	}
	for _, line := range noise {
		if keepCoreRecord("debug", clog.Severity_Debug, line) {
			t.Fatalf("kept noise: %s", line)
		}
	}
}

func TestKeepCoreRecordDecisions(t *testing.T) {
	keep := []string{
		"app/dispatcher: sniffed domain: youtube.com",
		"app/dispatcher: taking detour [proxy] for [udp:1.1.1.1:53]",
		"app/dispatcher: default route for tcp:youtube.com:443",
		"proxy/hysteria: tunneling request to tcp:203.0.113.8:443 via TCP:198.51.100.10:443",
		"app/dns: UDP:1.1.1.1:53 querying DNS for: youtube.com.",
		"app/dns: UDP:1.1.1.1:53 got answer: youtube.com. TypeA -> [203.0.113.8], rtt: 134ms",
		"transport/internet/tcp: listening TCP on 127.0.0.1:10809",
		"failed to process outbound traffic > proxy/hysteria: connection ends > write: broken pipe",
	}
	for _, line := range keep {
		if !keepCoreRecord("info", clog.Severity_Info, line) {
			t.Fatalf("dropped decision: %s", line)
		}
	}
	if keepCoreRecord("info", clog.Severity_Debug, "domain youtube.com will use DNS in order: [UDP:1.1.1.1:53]") {
		t.Fatal("dns order is debug-only")
	}
	if !keepCoreRecord("debug", clog.Severity_Debug, "transport/internet/hysteria: ECHAccepted false") {
		t.Fatal("ECH belongs at debug")
	}
	if keepCoreRecord("off", clog.Severity_Error, "failed to dial") {
		t.Fatal("off must stay quiet")
	}
	if !keepCoreRecord("error", clog.Severity_Info, "failed to process outbound traffic") {
		t.Fatal("failures stay visible at error")
	}
}

func TestRedactCoreSecrets(t *testing.T) {
	got := redactCoreSecrets("dial auth=super-secret host=203.0.113.10")
	if strings.Contains(got, "super-secret") {
		t.Fatal(got)
	}
	if !strings.Contains(got, "auth=***") {
		t.Fatal(got)
	}
}

func TestCoreLogRotatesWindow(t *testing.T) {
	dir := t.TempDir()
	oldWindow := coreWindowBytes
	coreWindowBytes = 40
	t.Cleanup(func() {
		coreMu.Lock()
		coreWindowBytes = oldWindow
		coreDir = ""
		coreLevel = "info"
		coreMu.Unlock()
	})
	coreMu.Lock()
	coreDir = dir
	coreLevel = "info"
	coreMu.Unlock()

	appendCoreLine("info", "core.xray first")
	appendCoreLine("info", "core.xray second line that pushes the window over the cap")
	prev, err := os.ReadFile(filepath.Join(dir, "core.1.log"))
	if err != nil {
		t.Fatal(err)
	}
	cur, err := os.ReadFile(filepath.Join(dir, "core.log"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(prev), "first") {
		t.Fatalf("previous window: %s", prev)
	}
	if !strings.Contains(string(cur), "8 MiB limit") {
		t.Fatalf("banner missing: %s", cur)
	}
	if !strings.Contains(string(cur), "second") {
		t.Fatalf("current window: %s", cur)
	}
}
