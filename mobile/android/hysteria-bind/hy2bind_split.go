package hy2bind

import (
	"errors"
	"log"
	"net"
	"net/netip"
	"strings"
	"sync"
	"syscall"
	"time"

	M "github.com/xjasonlyu/tun2socks/v2/metadata"
)

var errProtect = errors.New("protect failed")

// Keep in sync with mobile/lib/features/vpn/data/vpn_route_policy.dart
// kSmartProxyForceSuffixes — TSPU / YouTube must stay on Hy2.
var forceProxySuffixes = []string{
	"youtube.com",
	"youtu.be",
	"youtube-nocookie.com",
	"youtubekids.com",
	"googlevideo.com",
	"ytimg.com",
	"ggpht.com",
	"googleapis.com",
	"gstatic.com",
	"googleusercontent.com",
	"gvt1.com",
	"gvt2.com",
	"gvt3.com",
	"video.google.com",
	"play.google.com",
	"widevine.com",
	"withyoutube.com",
	"google.com",
}

const dnsCacheCap = 4096

var (
	splitMu      sync.RWMutex
	directSuffix []string
	extraForce   []string
	dnsIPToHost  = map[netip.Addr]string{}
	udpDirect    bool
	hijackDNS    netip.Addr
)

func setExtraForceSuffixes(raw []string) {
	out := make([]string, 0, len(raw))
	seen := map[string]struct{}{}
	for _, s := range raw {
		s = strings.ToLower(strings.TrimSpace(strings.TrimSuffix(s, ".")))
		if s == "" {
			continue
		}
		if _, ok := seen[s]; ok {
			continue
		}
		seen[s] = struct{}{}
		out = append(out, s)
	}
	splitMu.Lock()
	extraForce = out
	splitMu.Unlock()
}

func setUDPDirect(on bool) {
	splitMu.Lock()
	udpDirect = on
	splitMu.Unlock()
}

func udpDirectOn() bool {
	splitMu.RLock()
	defer splitMu.RUnlock()
	return udpDirect
}

func setHijackDNS(raw string) {
	ip, err := netip.ParseAddr(strings.TrimSpace(raw))
	splitMu.Lock()
	defer splitMu.Unlock()
	if err != nil {
		hijackDNS = netip.Addr{}
		return
	}
	hijackDNS = ip.Unmap()
}

func hijackDNSAddr(ip netip.Addr) bool {
	if !ip.IsValid() {
		return false
	}
	ip = ip.Unmap()
	splitMu.RLock()
	want := hijackDNS
	splitMu.RUnlock()
	return want.IsValid() && want == ip
}

func setDirectSuffixes(raw []string) {
	out := make([]string, 0, len(raw))
	seen := map[string]struct{}{}
	for _, s := range raw {
		s = strings.ToLower(strings.TrimSpace(strings.TrimSuffix(s, ".")))
		if s == "" || isForceProxyHost(s) {
			continue
		}
		if _, ok := seen[s]; ok {
			continue
		}
		seen[s] = struct{}{}
		out = append(out, s)
	}
	splitMu.Lock()
	directSuffix = out
	splitMu.Unlock()
}

func clearSplitState() {
	splitMu.Lock()
	directSuffix = nil
	extraForce = nil
	udpDirect = false
	hijackDNS = netip.Addr{}
	dnsIPToHost = map[netip.Addr]string{}
	splitMu.Unlock()
}

func rememberHostIP(host string, ip netip.Addr) {
	host = strings.ToLower(strings.TrimSpace(strings.TrimSuffix(host, ".")))
	if host == "" || !ip.IsValid() {
		return
	}
	ip = ip.Unmap()
	splitMu.Lock()
	defer splitMu.Unlock()
	if len(dnsIPToHost) >= dnsCacheCap {
		dnsIPToHost = map[netip.Addr]string{}
	}
	dnsIPToHost[ip] = host
}

func hostForIP(ip netip.Addr) string {
	if !ip.IsValid() {
		return ""
	}
	ip = ip.Unmap()
	splitMu.RLock()
	defer splitMu.RUnlock()
	return dnsIPToHost[ip]
}

func suffixMatches(host, suffix string) bool {
	host = strings.ToLower(strings.TrimSuffix(host, "."))
	suffix = strings.ToLower(strings.TrimSuffix(suffix, "."))
	if host == "" || suffix == "" {
		return false
	}
	return host == suffix || strings.HasSuffix(host, "."+suffix)
}

func isForceProxyHost(host string) bool {
	for _, s := range forceProxySuffixes {
		if suffixMatches(host, s) {
			return true
		}
	}
	splitMu.RLock()
	extra := extraForce
	splitMu.RUnlock()
	for _, s := range extra {
		if suffixMatches(host, s) {
			return true
		}
	}
	return false
}

func hostMatchesDirect(host string) bool {
	if host == "" || isForceProxyHost(host) {
		return false
	}
	splitMu.RLock()
	suffixes := directSuffix
	splitMu.RUnlock()
	for _, s := range suffixes {
		if suffixMatches(host, s) {
			return true
		}
	}
	return false
}

func shouldDirectTCP(m *M.Metadata) bool {
	if m == nil {
		return false
	}
	return hostMatchesDirect(hostForIP(m.DstIP))
}

func protectAndDial(network, address string) (net.Conn, error) {
	d := net.Dialer{
		Timeout: 20 * time.Second,
		Control: func(_, _ string, c syscall.RawConn) error {
			var protErr error
			if err := c.Control(func(fd uintptr) {
				mu.Lock()
				p := protector
				mu.Unlock()
				if p != nil && !p.Protect(int(fd)) {
					protErr = errProtect
				}
			}); err != nil {
				return err
			}
			return protErr
		},
	}
	return d.Dial(network, address)
}

func (d *hyDialer) dialDirect(network, addr string) (net.Conn, error) {
	if d.directDial != nil {
		return d.directDial(network, addr)
	}
	log.Printf("hy2bind direct %s %s", network, addr)
	return dialOutsideTun(network, addr)
}
