package hy2config

import (
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/komatozneak/teremok-connect/desktop/windows/internal/api"
)

const (
	// ControlPlaneIPv4 is api.teremokconnect.online (Selectel RF master).
	ControlPlaneIPv4 = "176.114.64.174"
	defaultSocks     = "127.0.0.1:10808"
)

// Mode selects inbound capture. SOCKS never needs UAC; TUN does.
type Mode string

const (
	ModeSOCKS Mode = "socks"
	ModeTUN   Mode = "tun"
)

// Options for official hysteria client YAML (app/v2.6.2 schema).
type Options struct {
	Profile          *api.HysteriaProfile
	NodeHost         string
	Mode             Mode
	ExtraIPv4Exclude []string
}

// Render writes a hysteria client YAML. SOCKS is always enabled for prove.
func Render(opt Options) (string, error) {
	p := opt.Profile
	if p == nil {
		return "", fmt.Errorf("nil hysteria_profile")
	}
	socks := strings.TrimSpace(p.SocksListen)
	if socks == "" {
		socks = defaultSocks
	}
	var b strings.Builder
	fmt.Fprintf(&b, "server: %s\n", yamlQuote(p.Server))
	fmt.Fprintf(&b, "auth: %s\n", yamlQuote(p.Auth))
	if sni := strings.TrimSpace(p.SNI); sni != "" {
		fmt.Fprintf(&b, "tls:\n  sni: %s\n", yamlQuote(sni))
	}
	if strings.TrimSpace(p.BandwidthUp) != "" || strings.TrimSpace(p.BandwidthDown) != "" {
		b.WriteString("bandwidth:\n")
		if strings.TrimSpace(p.BandwidthUp) != "" {
			fmt.Fprintf(&b, "  up: %s\n", yamlQuote(p.BandwidthUp))
		}
		if strings.TrimSpace(p.BandwidthDown) != "" {
			fmt.Fprintf(&b, "  down: %s\n", yamlQuote(p.BandwidthDown))
		}
	}
	fmt.Fprintf(&b, "socks5:\n  listen: %s\n", yamlQuote(socks))
	if opt.Mode == ModeTUN {
		excludes := ipv4Excludes(p.Server, opt.NodeHost, opt.ExtraIPv4Exclude)
		b.WriteString("tun:\n")
		b.WriteString("  name: teremokhy2\n")
		b.WriteString("  mtu: 1500\n")
		b.WriteString("  timeout: 5m\n")
		b.WriteString("  address:\n")
		b.WriteString("    ipv4: 100.100.100.101/30\n")
		b.WriteString("    ipv6: 2001::ffff:ffff:ffff:fff1/126\n")
		b.WriteString("  route:\n")
		b.WriteString("    ipv4:\n")
		b.WriteString("      - 0.0.0.0/0\n")
		b.WriteString("    ipv4Exclude:\n")
		for _, cidr := range excludes {
			fmt.Fprintf(&b, "      - %s\n", yamlQuote(cidr))
		}
	}
	return b.String(), nil
}

// WriteFile renders YAML next to the host binary's working config path.
func WriteFile(path string, opt Options) error {
	body, err := Render(opt)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(body), 0o600)
}

func ipv4Excludes(server, nodeHost string, extra []string) []string {
	seen := map[string]struct{}{}
	var out []string
	add := func(raw string) {
		cidr := toIPv4CIDR(raw)
		if cidr == "" {
			return
		}
		if _, ok := seen[cidr]; ok {
			return
		}
		seen[cidr] = struct{}{}
		out = append(out, cidr)
	}
	add(ControlPlaneIPv4)
	add(server)
	add(nodeHost)
	for _, ip := range lookupIPv4(hostOf(server)) {
		add(ip.String())
	}
	for _, ip := range lookupIPv4(hostOf(nodeHost)) {
		add(ip.String())
	}
	// Keep LAN/loopback off the TUN so the unelevated host can still reach the API
	// and local printers/RDP after Connect.
	add("127.0.0.0/8")
	add("10.0.0.0/8")
	add("172.16.0.0/12")
	add("192.168.0.0/16")
	for _, e := range extra {
		add(e)
	}
	return out
}

func hostOf(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	if strings.Contains(raw, "/") {
		return ""
	}
	host := raw
	if strings.Contains(host, ":") && net.ParseIP(host) == nil {
		h, _, err := net.SplitHostPort(host)
		if err == nil {
			host = h
		}
	}
	host = strings.Trim(host, "[]")
	if net.ParseIP(host) != nil {
		return ""
	}
	return host
}

// lookupIPv4 is swapped in tests. Live connect resolves Hy2 hostnames so TUN
// does not swallow the tunnel packets (exclude list needs /32s, not DNS names).
var lookupIPv4 = func(host string) []net.IP {
	host = strings.TrimSpace(host)
	if host == "" {
		return nil
	}
	ips, err := net.LookupIP(host)
	if err != nil {
		return nil
	}
	var out []net.IP
	for _, ip := range ips {
		if v4 := ip.To4(); v4 != nil {
			out = append(out, v4)
		}
	}
	return out
}

func toIPv4CIDR(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	if strings.Contains(raw, "/") {
		_, n, err := net.ParseCIDR(raw)
		if err != nil || n.IP.To4() == nil {
			return ""
		}
		ones, _ := n.Mask.Size()
		return n.IP.To4().String() + "/" + strconv.Itoa(ones)
	}
	host := raw
	if strings.Contains(host, ":") && net.ParseIP(host) == nil {
		h, _, err := net.SplitHostPort(host)
		if err == nil {
			host = h
		}
	}
	host = strings.Trim(host, "[]")
	parsed := net.ParseIP(host)
	if parsed == nil || parsed.To4() == nil {
		return ""
	}
	return parsed.To4().String() + "/32"
}

func yamlQuote(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `"`, `\"`)
	return `"` + s + `"`
}
