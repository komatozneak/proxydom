package hy2bind

import (
	"context"
	"encoding/json"
	"io"
	"net"
	"net/netip"
	"testing"

	M "github.com/xjasonlyu/tun2socks/v2/metadata"
)

func TestSuffixMatches(t *testing.T) {
	if !suffixMatches("example.com", "example.com") {
		t.Fatal("apex")
	}
	if !suffixMatches("www.example.com", "example.com") {
		t.Fatal("subdomain")
	}
	if suffixMatches("notexample.com", "example.com") {
		t.Fatal("must not match prefix-in-label")
	}
	if suffixMatches("example.com.evil.test", "example.com") {
		t.Fatal("must not match suffix-as-prefix")
	}
}

func TestForceProxyBlocksDirect(t *testing.T) {
	t.Cleanup(clearSplitState)
	setExtraForceSuffixes([]string{"youtube.com", "googlevideo.com"})
	setDirectSuffixes([]string{"youtube.com", "vk.com"})
	if hostMatchesDirect("youtube.com") || hostMatchesDirect("googlevideo.com") {
		t.Fatal("force-proxy domains must stay on the tunnel")
	}
	if !hostMatchesDirect("vk.com") {
		t.Fatal("vk.com should be direct")
	}
}

func TestNoBuiltInForceProxyList(t *testing.T) {
	t.Cleanup(clearSplitState)
	setDirectSuffixes([]string{"youtube.com"})
	if !hostMatchesDirect("youtube.com") {
		t.Fatal("no blocked-site list ships in the engine; a user suffix must be direct")
	}
}

func TestDNSCacheDirectDial(t *testing.T) {
	t.Cleanup(clearSplitState)
	setDirectSuffixes([]string{"yandex.ru"})
	ip := netip.MustParseAddr("77.88.8.8")
	rememberHostIP("yandex.ru", ip)
	m := &M.Metadata{DstIP: ip, DstPort: 22}
	if !shouldDirectTCP(m) {
		t.Fatal("cached yandex.ru A must be direct")
	}

	var got string
	d := &hyDialer{
		c: &fakeHyClient{},
		directDial: func(_, addr string) (net.Conn, error) {
			got = addr
			a, b := net.Pipe()
			go func() {
				defer b.Close()
				_, _ = io.Copy(io.Discard, b)
			}()
			return a, nil
		},
	}
	c, err := d.DialContext(context.Background(), m)
	if err != nil {
		t.Fatal(err)
	}
	_ = c.Close()
	if got != "77.88.8.8:22" {
		t.Fatalf("direct dest %q", got)
	}
}

func TestDNSCacheDoesNotDirectUnlisted(t *testing.T) {
	t.Cleanup(clearSplitState)
	setDirectSuffixes([]string{"vk.com"})
	ip := netip.MustParseAddr("1.1.1.1")
	rememberHostIP("cloudflare.com", ip)
	if shouldDirectTCP(&M.Metadata{DstIP: ip, DstPort: 443}) {
		t.Fatal("unlisted host must stay on Hy2")
	}
}

func TestRememberDNSFromAResponse(t *testing.T) {
	t.Cleanup(clearSplitState)
	setExtraForceSuffixes([]string{"googlevideo.com"})
	setDirectSuffixes([]string{"googlevideo.com"})
	ip := net.IPv4(142, 250, 185, 14)
	msg := buildAResponse(ip)
	rememberDNSFromMessage(msg)
	addr := netip.MustParseAddr("142.250.185.14")
	if hostForIP(addr) != "googlevideo.com" {
		t.Fatalf("host %q", hostForIP(addr))
	}
	if shouldDirectTCP(&M.Metadata{DstIP: addr, DstPort: 443}) {
		t.Fatal("googlevideo is force-proxy")
	}
}

func TestFilterDNSResponseCachesARecords(t *testing.T) {
	t.Cleanup(clearSplitState)
	setExtraForceSuffixes([]string{"googlevideo.com"})
	setDirectSuffixes([]string{"googlevideo.com"})
	ip := net.IPv4(142, 250, 185, 14)
	_ = filterDNSResponse(buildAResponse(ip))
	addr := netip.MustParseAddr("142.250.185.14")
	if hostForIP(addr) != "googlevideo.com" {
		t.Fatalf("host %q", hostForIP(addr))
	}
	if shouldDirectTCP(&M.Metadata{DstIP: addr, DstPort: 443}) {
		t.Fatal("googlevideo is force-proxy even after DNS cache")
	}
}

func TestStartConfigUnmarshalsSuffixes(t *testing.T) {
	t.Cleanup(clearSplitState)
	var cfg startConfig
	if err := json.Unmarshal([]byte(`{"direct_domain_suffixes":["VK.com","youtube.com"]}`), &cfg); err != nil {
		t.Fatal(err)
	}
	setExtraForceSuffixes([]string{"youtube.com"})
	setDirectSuffixes(cfg.DirectDomainSuffixes)
	if !hostMatchesDirect("m.vk.com") {
		t.Fatal("vk suffix from Start JSON")
	}
	if hostMatchesDirect("youtube.com") {
		t.Fatal("a force_proxy_domains entry must override a direct suffix")
	}
}

func TestTunDNSAddressIsHijacked(t *testing.T) {
	t.Cleanup(clearSplitState)
	ip := netip.MustParseAddr("198.18.0.2")
	if !shouldHijackDNS(ip, 53) {
		t.Fatal("adapter DNS must be hijacked")
	}
	if shouldHijackDNS(ip, 443) {
		t.Fatal("only port 53")
	}
	// A public resolver is hijacked too now: leaving it alone made the
	// classifier depend on which DNS the user had configured.
	if !shouldHijackDNS(netip.MustParseAddr("1.1.1.1"), 53) {
		t.Fatal("public DNS is hijacked on port 53")
	}
}

func TestUDPDirectYieldsToForceProxy(t *testing.T) {
	t.Cleanup(clearSplitState)
	setExtraForceSuffixes([]string{"game.example"})
	setUDPDirect(true)
	rememberHostIP("game.example", netip.MustParseAddr("203.0.113.9"))
	rememberHostIP("other.example", netip.MustParseAddr("203.0.113.8"))
	forced := &M.Metadata{DstIP: netip.MustParseAddr("203.0.113.9"), DstPort: 27015}
	other := &M.Metadata{DstIP: netip.MustParseAddr("203.0.113.8"), DstPort: 27015}
	bare := &M.Metadata{DstIP: netip.MustParseAddr("203.0.113.7"), DstPort: 27015}
	if shouldDirectUDP(forced) {
		t.Fatal("force-proxy host must stay on the tunnel")
	}
	if !shouldDirectUDP(other) || !shouldDirectUDP(bare) {
		t.Fatal("other UDP should leave the tunnel")
	}
	setUDPDirect(false)
	if shouldDirectUDP(bare) {
		t.Fatal("udp bypass is off")
	}
}
