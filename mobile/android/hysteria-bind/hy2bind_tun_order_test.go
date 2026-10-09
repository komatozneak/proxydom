package hy2bind

import (
	"os"
	"strings"
	"testing"
)

// The Windows engine must configure the adapter before the gVisor stack starts
// reading from it.
//
// iobased.dispatchLoop breaks out of its read loop for good on the first read
// error and Attach is guarded by sync.Once, so an address change underneath a
// running loop leaves a tunnel that exists, is up, carries 198.18.0.1 and a
// route, and still hands the stack nothing. Windows reports that as
// win32=10065 and it looks like a routing fault rather than a dead reader.
// sing-box never met it because its tun inbound assigned the address while
// creating the interface.
func TestWindowsEngineConfiguresTheTunBeforeItReads(t *testing.T) {
	raw, err := os.ReadFile("cmd/proxydom-engine/main.go")
	if err != nil {
		t.Fatalf("read the engine entry point: %v", err)
	}
	src := string(raw)

	open := strings.Index(src, "hy2bind.OpenNamedTun(")
	assign := strings.Index(src, "assignTunIPv4(cfg.Tun.Name")
	stack := strings.Index(src, "hy2bind.StartTunStack()")
	if open < 0 || assign < 0 || stack < 0 {
		t.Fatalf("the start sequence changed shape: open=%d assign=%d stack=%d", open, assign, stack)
	}
	if !(open < assign && assign < stack) {
		t.Fatalf("the address must be assigned before the stack reads: open=%d assign=%d stack=%d",
			open, assign, stack)
	}
	if strings.Contains(src, "StartNamedTun") {
		t.Fatal("the combined start helper is back; it starts the read loop before the address exists")
	}
}

// The VLESS path has the same order and the same reason, and it is the newer of
// the two, so it is the one more likely to be written without it.
//
// StartShareTunStack refuses when no adapter is open, so getting the order wrong
// here does not produce a dead reader: it produces "tun not open" and the
// session ends before any traffic moves. That is a better failure, but it is
// still a failure, and only this order avoids it.
func TestWindowsEngineConfiguresTheTunBeforeTheShareStackReads(t *testing.T) {
	raw, err := os.ReadFile("cmd/proxydom-engine/main.go")
	if err != nil {
		t.Fatalf("read the engine entry point: %v", err)
	}
	src := string(raw)

	open := strings.Index(src, "hy2bind.OpenNamedTun(")
	assign := strings.Index(src, "assignTunIPv4(cfg.Tun.Name")
	share := strings.Index(src, "hy2bind.StartShareTunStack()")
	if open < 0 || assign < 0 || share < 0 {
		t.Fatalf("the share start sequence changed shape: open=%d assign=%d share=%d",
			open, assign, share)
	}
	if !(open < assign && assign < share) {
		t.Fatalf("the share stack must come after the adapter is open and addressed: open=%d assign=%d share=%d",
			open, assign, share)
	}
	// The choice has to be made by the scheme, or a VLESS session binds the Hy2
	// dialer and a Hy2 session binds a SOCKS port nothing is listening on.
	if !strings.Contains(src, "kind == engineVless") {
		t.Fatal("the engine no longer picks its tun stack by the scheme it started")
	}
}
