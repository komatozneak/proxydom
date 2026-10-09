//go:build windows

package hy2bind

import (
	"testing"

	"github.com/xjasonlyu/tun2socks/v2/core/device"
)

// typedNilDevice satisfies device.Device without being usable. The embedded
// interface is nil, so any method call would panic — which is exactly the point:
// the guards below must return before anything touches the device.
type typedNilDevice struct{ device.Device }

// swapShareTunState clears the two halves of a Windows session for one test and
// puts them back afterwards.
//
// The address is restored only when it was set: shareAddr is an atomic.Value and
// storing an untyped nil into one panics, which is how the first version of this
// file failed. A fresh process has never stored anything, so "no address" is the
// state to return to, not a nil to write.
func swapShareTunState(t *testing.T, dev device.Device, addr string) {
	t.Helper()
	mu.Lock()
	oldStk, oldDev, oldAddr := tunStk, tunDev, ShareSocksAddr()
	tunStk, tunDev = nil, dev
	shareAddr.Store(addr)
	mu.Unlock()
	t.Cleanup(func() {
		mu.Lock()
		tunStk, tunDev = oldStk, oldDev
		if oldAddr != "" {
			shareAddr.Store(oldAddr)
		}
		mu.Unlock()
	})
}

// StartShareTunStack is the seam between the two halves of a Windows VLESS
// session: the core, which owns a loopback SOCKS port, and the adapter, which
// OpenNamedTun opened. It needs both, and each missing half has to be its own
// refusal rather than a crash or a tunnel that reads packets with nowhere to
// send them.
//
// This file is windows-only because the function is. It is compiled but not run
// on the ubuntu runner, so the cross-compile step in mobile-build.yml is what
// typechecks it there. Run it with GOOS=windows go test ./... .
func TestShareTunStackRefusesWithoutAnAdapter(t *testing.T) {
	swapShareTunState(t, nil, "")

	if got := StartShareTunStack(); got != "tun not open" {
		t.Fatalf("the share stack must refuse without an adapter, got %q", got)
	}
}

// With an adapter but no core there is nothing to proxy through. Binding the
// stack anyway would leave a tunnel that reads packets and has nowhere to send
// them, which the owner would see as a routing fault rather than a missing core.
func TestShareTunStackRefusesWithoutACore(t *testing.T) {
	swapShareTunState(t, typedNilDevice{}, "")

	if got := StartShareTunStack(); got != "share core not started" {
		t.Fatalf("the share stack must refuse without a core, got %q", got)
	}
}

// A running stack is never silently replaced: the read loop cannot survive it.
// That guard sits behind the other two and needs a live core to reach, so it is
// covered where a core can actually be started rather than faked here.
