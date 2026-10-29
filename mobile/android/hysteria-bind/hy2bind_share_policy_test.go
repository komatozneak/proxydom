package hy2bind

import "testing"

// The Windows service now writes the same policy fields into the VLESS
// document that the Hysteria2 start document carries. StartShare reads them
// before the core starts, so the TUN dialer — not v2ray's router — decides.
func TestSharePolicyAppliesListsAndMode(t *testing.T) {
	t.Cleanup(clearSplitState)
	applyShareSplitPolicy(`{
		"direct_domain_suffixes":["vk.com"],
		"force_proxy_domains":["youtube.com"],
		"udp_mode":"direct_non_forced"
	}`)
	if !hostMatchesDirect("m.vk.com") {
		t.Fatal("the VLESS document did not reach the direct list")
	}
	if hostMatchesDirect("youtube.com") {
		t.Fatal("the force-proxy list was lost")
	}
	if !udpDirectOn() {
		t.Fatal("the explicit game mode was not applied")
	}
}

func TestSharePolicyDefaultsToProxyAll(t *testing.T) {
	t.Cleanup(clearSplitState)
	applyShareSplitPolicy(`{"direct_domain_suffixes":["vk.com"]}`)
	if udpDirectOn() {
		t.Fatal("UDP bypass must be opt-in, not the default")
	}
	if !hostMatchesDirect("vk.com") {
		t.Fatal("the direct list was not applied")
	}
}
