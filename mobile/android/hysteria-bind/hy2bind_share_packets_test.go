package hy2bind

import (
	"testing"

	"gvisor.dev/gvisor/pkg/tcpip/stack"
)

// Without a running core there is nothing to point the userspace stack at, and
// the answer has to say so: a silent success would make the provider report
// Connected over a tunnel that has no upstream.
func TestStartSharePacketTunRequiresTheShareCore(t *testing.T) {
	mu.Lock()
	saved := tunStk
	tunStk = nil
	mu.Unlock()
	defer func() {
		mu.Lock()
		tunStk = saved
		mu.Unlock()
	}()

	if err := StartSharePacketTun(1280); err != "share core not started" {
		t.Fatalf("refusal = %q, want share core not started", err)
	}
}

// An already attached stack is refused rather than replaced: two stacks would
// both write into the same packet flow, and the second would keep the first
// session's dialer.
func TestStartSharePacketTunRefusesASecondStack(t *testing.T) {
	mu.Lock()
	saved := tunStk
	tunStk = stack.New(stack.Options{})
	mu.Unlock()
	defer func() {
		mu.Lock()
		tunStk = saved
		mu.Unlock()
	}()

	if err := StartSharePacketTun(1280); err != "tun already running" {
		t.Fatalf("refusal = %q, want tun already running", err)
	}
}
