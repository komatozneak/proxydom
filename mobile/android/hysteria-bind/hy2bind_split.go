package hy2bind

import (
	"container/list"
	"errors"
	"log"
	"net"
	"net/netip"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"

	M "github.com/xjasonlyu/tun2socks/v2/metadata"
)

var errProtect = errors.New("protect failed")

// No built-in force-proxy list ships with the app. The default is direct for
// the suffixes the user chose and tunnel for everything else; a subscription
// may add `force_proxy_domains`, which setExtraForceSuffixes merges here.

const (
	dnsCacheCap   = 4096
	maxHostsPerIP = 16

	// DNS TTLs for CDNs are often 30-60 seconds while the client keeps using
	// the address for minutes. The lease is clamped instead of copied so a
	// direct site does not flicker between direct and proxied mid-page.
	minHostLease     = time.Minute
	maxHostLease     = 30 * time.Minute
	defaultHostLease = 10 * time.Minute
)

// ipHostLeases is every name the resolver has answered with this address,
// with the moment its lease expires. One host per IP was the old model and it
// made shared CDN addresses decide by whichever answer arrived last.
type ipHostLeases struct {
	leases map[string]time.Time
	lru    *list.Element
}

var (
	splitMu      sync.RWMutex
	directSuffix []string
	extraForce   []string
	ipHosts      = map[netip.Addr]*ipHostLeases{}
	ipHostLRU    = list.New()
	udpDirect    bool
)

func normalizeHost(host string) string {
	return strings.ToLower(strings.TrimSpace(strings.TrimSuffix(host, ".")))
}

func setExtraForceSuffixes(raw []string) {
	out := make([]string, 0, len(raw))
	seen := map[string]struct{}{}
	for _, s := range raw {
		s = normalizeHost(s)
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

func setDirectSuffixes(raw []string) {
	out := make([]string, 0, len(raw))
	seen := map[string]struct{}{}
	for _, s := range raw {
		s = normalizeHost(s)
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
	ipHosts = map[netip.Addr]*ipHostLeases{}
	ipHostLRU = list.New()
	splitMu.Unlock()
}

func clampLease(ttl time.Duration) time.Duration {
	if ttl <= 0 {
		return defaultHostLease
	}
	if ttl < minHostLease {
		return minHostLease
	}
	if ttl > maxHostLease {
		return maxHostLease
	}
	return ttl
}

// rememberHostIP keeps the legacy signature: the DNS parser passes the wire
// TTL through rememberHostIPTTL, while tests and SVCB hints get the default.
func rememberHostIP(host string, ip netip.Addr) {
	rememberHostIPTTL(host, ip, defaultHostLease)
}

func rememberHostIPTTL(host string, ip netip.Addr, ttl time.Duration) {
	host = normalizeHost(host)
	if host == "" || !ip.IsValid() {
		return
	}
	ip = ip.Unmap()
	expire := time.Now().Add(clampLease(ttl))
	splitMu.Lock()
	defer splitMu.Unlock()
	entry := ipHosts[ip]
	if entry == nil {
		entry = &ipHostLeases{leases: map[string]time.Time{}}
		entry.lru = ipHostLRU.PushFront(ip)
		ipHosts[ip] = entry
	} else {
		ipHostLRU.MoveToFront(entry.lru)
	}
	if _, exists := entry.leases[host]; !exists && len(entry.leases) >= maxHostsPerIP {
		var oldestHost string
		var oldestExpire time.Time
		for h, e := range entry.leases {
			if oldestHost == "" || e.Before(oldestExpire) {
				oldestHost, oldestExpire = h, e
			}
		}
		delete(entry.leases, oldestHost)
	}
	entry.leases[host] = expire
	if len(ipHosts) > dnsCacheCap {
		evictLeasesLocked()
	}
}

// evictLeasesLocked drops expired names and then evicts one least-recently
// used address at a time. The old code emptied the whole table at the cap,
// which silently turned the whitelist off for the rest of the session.
func evictLeasesLocked() {
	now := time.Now()
	for ip, entry := range ipHosts {
		for host, expire := range entry.leases {
			if !expire.After(now) {
				delete(entry.leases, host)
			}
		}
		if len(entry.leases) == 0 {
			delete(ipHosts, ip)
			ipHostLRU.Remove(entry.lru)
		}
	}
	for len(ipHosts) > dnsCacheCap {
		back := ipHostLRU.Back()
		if back == nil {
			break
		}
		ip, _ := back.Value.(netip.Addr)
		entry := ipHosts[ip]
		delete(ipHosts, ip)
		if entry != nil {
			ipHostLRU.Remove(entry.lru)
		} else {
			ipHostLRU.Remove(back)
		}
	}
}

func hostsForIP(ip netip.Addr) []string {
	if !ip.IsValid() {
		return nil
	}
	ip = ip.Unmap()
	now := time.Now()
	splitMu.Lock()
	defer splitMu.Unlock()
	entry := ipHosts[ip]
	if entry == nil {
		return nil
	}
	out := make([]string, 0, len(entry.leases))
	for host, expire := range entry.leases {
		if expire.After(now) {
			out = append(out, host)
			continue
		}
		delete(entry.leases, host)
	}
	if len(entry.leases) == 0 {
		delete(ipHosts, ip)
		ipHostLRU.Remove(entry.lru)
		return nil
	}
	ipHostLRU.MoveToFront(entry.lru)
	sort.Strings(out)
	return out
}

// hostForIP is kept for logs and for the legacy shouldDirectUDP checks. The
// decision itself uses every known name on the address, not this first one.
func hostForIP(ip netip.Addr) string {
	hosts := hostsForIP(ip)
	if len(hosts) == 0 {
		return ""
	}
	return hosts[0]
}

// ipAllDirect answers "may this address go direct" for flows with no domain.
// It is fail-closed: one name outside the list, or one forced name, keeps the
// whole address on the tunnel. A CDN address is shared, so an unknown name is
// not evidence of anything, and leaking it is worse than proxying a direct one.
func ipAllDirect(ip netip.Addr) (string, bool) {
	hosts := hostsForIP(ip)
	if len(hosts) == 0 {
		return "", false
	}
	for _, host := range hosts {
		if isForceProxyHost(host) {
			return "", false
		}
	}
	for _, host := range hosts {
		if !hostMatchesDirect(host) {
			return "", false
		}
	}
	return hosts[0], true
}

// routeFor is the single decision both engines use once a domain is known (or
// not known). "why" is logged so support can tell a miss from a leak.
func routeFor(host string, dst netip.Addr) (bool, string) {
	host = normalizeHost(host)
	if host != "" {
		if isForceProxyHost(host) {
			return false, "force"
		}
		if hostMatchesDirect(host) {
			return true, "host"
		}
		return false, "host-miss"
	}
	if _, ok := ipAllDirect(dst); ok {
		return true, "dns"
	}
	return false, "unknown"
}

func suffixMatches(host, suffix string) bool {
	host = normalizeHost(host)
	suffix = normalizeHost(suffix)
	if host == "" || suffix == "" {
		return false
	}
	return host == suffix || strings.HasSuffix(host, "."+suffix)
}

func isForceProxyHost(host string) bool {
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

// shouldDirectTCP is the DNS-only fallback. New callers should use routeFor,
// which prefers the SNI/Host classifier and falls back to this.
func shouldDirectTCP(m *M.Metadata) bool {
	if m == nil {
		return false
	}
	direct, _ := routeFor("", m.DstIP)
	return direct
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
