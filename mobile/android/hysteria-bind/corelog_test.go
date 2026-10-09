package hy2bind

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	clog "github.com/v2fly/v2ray-core/v5/common/log"
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
		"V2Ray 5.54.2 (V2Fly, a community-driven edition of V2Ray.)",
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

// The uuid is a credential and these lines reach the broker's service log on
// Windows, which is a file the owner sends around. Android keeps them in a file
// the app owns, so this matters more here, not less.
func TestRedactCoreSecretsHidesTheUUID(t *testing.T) {
	const id = "11111111-2222-3333-4444-555555555555"
	got := redactCoreSecrets("vless: user id " + id + " accepted")
	if strings.Contains(strings.ToLower(got), id) {
		t.Fatal(got)
	}
	if !strings.Contains(got, "***") {
		t.Fatal(got)
	}
	// A line with no credential is left alone.
	plain := "transport/internet/tcp: listening TCP on 127.0.0.1:10809"
	if redactCoreSecrets(plain) != plain {
		t.Fatal(redactCoreSecrets(plain))
	}
}

// Windows injects no log directory. Without a fallback the core's own account
// of a failed dial is written nowhere, and the live failure is undiagnosable.
func TestCoreLogFallsBackToStderrWithoutADirectory(t *testing.T) {
	coreMu.Lock()
	oldDir, oldToErr := coreDir, coreToErr
	coreDir = ""
	coreToErr = true
	coreMu.Unlock()
	t.Cleanup(func() {
		coreMu.Lock()
		coreDir, coreToErr = oldDir, oldToErr
		coreMu.Unlock()
	})

	read, write, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	oldStderr := os.Stderr
	os.Stderr = write
	appendCoreLine("info", "core.vless failed to dial the node")
	_ = write.Close()
	os.Stderr = oldStderr
	t.Cleanup(func() { _ = read.Close() })

	buf := make([]byte, 4096)
	n, _ := read.Read(buf)
	got := string(buf[:n])
	if !strings.Contains(got, "failed to dial the node") {
		t.Fatalf("stderr did not receive the core line: %q", got)
	}
	if !strings.Contains(got, "core.info") {
		t.Fatalf("the level is not named: %q", got)
	}
}

// The fallback is opt-in: Android reads a file and must not gain a second copy
// of every line on a stream nothing reads.
func TestCoreLogStaysQuietWhenTheFallbackIsOff(t *testing.T) {
	coreMu.Lock()
	oldDir, oldToErr := coreDir, coreToErr
	coreDir = ""
	coreToErr = false
	coreMu.Unlock()
	t.Cleanup(func() {
		coreMu.Lock()
		coreDir, coreToErr = oldDir, oldToErr
		coreMu.Unlock()
	})

	read, write, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	oldStderr := os.Stderr
	os.Stderr = write
	appendCoreLine("info", "core.vless must not appear")
	_ = write.Close()
	os.Stderr = oldStderr
	t.Cleanup(func() { _ = read.Close() })

	buf := make([]byte, 4096)
	n, _ := read.Read(buf)
	if n != 0 {
		t.Fatalf("wrote to stderr with the fallback off: %q", string(buf[:n]))
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

	appendCoreLine("info", "core.vless first")
	appendCoreLine("info", "core.vless second line that pushes the window over the cap")
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
