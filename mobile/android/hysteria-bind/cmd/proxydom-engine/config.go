//go:build windows

package main

import (
	"encoding/json"
	"fmt"
	"net"
	"strconv"
	"strings"

	"github.com/komatozneak/proxydom/hy2bind"
)

// engineConfig is the document the Windows broker writes. It is not a
// sing-box config. Fields that this process does not apply are still present
// so a log line can say they were requested and ignored.
type engineConfig struct {
	LogLevel          string         `json:"log_level"`
	Probe             bool           `json:"probe"`
	SocksListen       string         `json:"socks_listen"`
	Tun               *tunConfig     `json:"tun"`
	DirectDomains     []string       `json:"direct_domains"`
	ForceProxyDomains []string       `json:"force_proxy_domains"`
	UDPDirect         bool           `json:"udp_direct"`
	DNSHijack         bool           `json:"dns_hijack"`
	APIPort           int            `json:"api_port"`
	APISecret         string         `json:"api_secret"`
	RoutingApplied    bool           `json:"routing_applied"`
	Outbound          outboundConfig `json:"outbound"`
}

type tunConfig struct {
	Name      string `json:"name"`
	Address   string `json:"address"`
	DNS       string `json:"dns"`
	MTU       int    `json:"mtu"`
	AutoRoute bool   `json:"auto_route"`
}

type outboundConfig struct {
	Type         string   `json:"type"`
	Server       string   `json:"server"`
	ServerPort   int      `json:"server_port"`
	Password     string   `json:"password"`
	SNI          string   `json:"sni"`
	Insecure     bool     `json:"insecure"`
	Obfs         string   `json:"obfs"`
	ObfsPassword string   `json:"obfs_password"`
	ServerPorts  string   `json:"server_ports"`
	HopInterval  string   `json:"hop_interval"`
	UUID         string   `json:"uuid"`
	Flow         string   `json:"flow"`
	Security     string   `json:"security"`
	Fingerprint  string   `json:"fingerprint"`
	PublicKey    string   `json:"public_key"`
	ShortID      string   `json:"short_id"`
	// Transport of a VLESS line. Without these a vless:// over WebSocket or
	// gRPC cannot be described at all, and the row that needs them is exactly
	// the one subscriptions hand out.
	Network string `json:"network"`
	Path    string `json:"path"`
	Host    string `json:"host"`
	// Comma separated: the broker writes one JSON string, and ALPN is a list
	// on the wire.
	ALPN string `json:"alpn"`
}

// networkName is the transport the core will be asked for. Empty means the
// default the link parsers use.
func (o outboundConfig) networkName() string {
	name := strings.ToLower(strings.TrimSpace(o.Network))
	if name == "" {
		return "tcp"
	}
	return name
}

// securityName defaults to tls, which is what every vless:// line means when it
// says nothing (engine_share_config.dart does the same).
func (o outboundConfig) securityName() string {
	name := strings.ToLower(strings.TrimSpace(o.Security))
	if name == "" {
		return "tls"
	}
	return name
}

func (o outboundConfig) alpnList() []string {
	var out []string
	for _, item := range strings.Split(o.ALPN, ",") {
		item = strings.TrimSpace(item)
		if item != "" {
			out = append(out, item)
		}
	}
	return out
}

// engineKind is which core a session needs. The two have separate start calls
// and separate TUN wiring, so the choice is made once.
type engineKind int

const (
	engineHy2 engineKind = iota
	engineVless
)

func (c engineConfig) kind() (engineKind, bool) {
	switch strings.ToLower(strings.TrimSpace(c.Outbound.Type)) {
	case "hysteria2", "hy2":
		return engineHy2, true
	case "vless":
		return engineVless, true
	default:
		return engineHy2, false
	}
}

// rejectTransport is the line the broker can see. A scheme this process does
// not carry is refused, not rewritten as TCP.
func (c engineConfig) rejectTransport() bool {
	_, ok := c.kind()
	return !ok
}

// shareRefusal names what the in-process core cannot carry, before a core is
// started at all. Empty means the document is dialable.
//
// The name is the user-facing one, not an internal category, so nothing has to
// translate it later and no table can drift between the two. The broker
// recognises these exact words and reports them as the refusal they are; a
// name it does not recognise stays a plain core exit, which is honest.
func (c engineConfig) shareRefusal() string {
	if !hy2bind.TransportDialable(c.Outbound.networkName()) {
		return "transport_unsupported"
	}
	if !hy2bind.SecurityDialable(c.Outbound.securityName()) {
		return "security_unsupported"
	}
	return ""
}

func parseEngineConfig(raw []byte) (engineConfig, error) {
	var cfg engineConfig
	if err := json.Unmarshal(raw, &cfg); err != nil {
		return engineConfig{}, err
	}
	if cfg.SocksListen == "" {
		cfg.SocksListen = "127.0.0.1:10808"
	}
	if cfg.Tun != nil {
		if cfg.Tun.Name == "" {
			cfg.Tun.Name = "ProxyDomTun"
		}
		if cfg.Tun.MTU <= 0 {
			cfg.Tun.MTU = 1280
		}
	}
	return cfg, nil
}

// hy2StartJSON is the document hy2bind.Start already accepts. The password
// stays in the JSON the core reads and is not returned as a log line.
func (c engineConfig) hy2StartJSON() ([]byte, error) {
	if kind, ok := c.kind(); !ok || kind != engineHy2 {
		return nil, fmt.Errorf("error scheme_unsupported")
	}
	if c.Outbound.Server == "" || c.Outbound.ServerPort <= 0 || c.Outbound.Password == "" {
		return nil, fmt.Errorf("hy2 start failed")
	}
	body := map[string]any{
		"server":       fmt.Sprintf("%s:%d", c.Outbound.Server, c.Outbound.ServerPort),
		"auth":         c.Outbound.Password,
		"sni":          c.Outbound.SNI,
		"socks_listen": c.SocksListen,
	}
	if c.Outbound.Insecure {
		body["insecure"] = true
	}
	if c.Outbound.Obfs != "" {
		body["obfs"] = c.Outbound.Obfs
		body["obfs_password"] = c.Outbound.ObfsPassword
	}
	if c.Outbound.ServerPorts != "" {
		body["server_ports"] = c.Outbound.ServerPorts
	}
	if c.Outbound.HopInterval != "" {
		body["hop_interval"] = c.Outbound.HopInterval
	}
	if len(c.DirectDomains) > 0 {
		body["direct_domain_suffixes"] = c.DirectDomains
	}
	if len(c.ForceProxyDomains) > 0 {
		body["force_proxy_domains"] = c.ForceProxyDomains
	}
	if c.UDPDirect {
		body["udp_direct"] = true
	}
	if c.Tun != nil && c.Tun.DNS != "" && !c.Probe {
		body["dns_address"] = c.Tun.DNS
	}
	if c.APIPort > 0 && c.APISecret != "" {
		body["api_port"] = c.APIPort
		body["api_secret"] = c.APISecret
	}
	return json.Marshal(body)
}

// vlessStartJSON is the document hy2bind.StartShare accepts.
//
// It is the same shape the Android client builds in
// mobile/lib/features/vpn/data/engine_share_config.dart, so one loader serves
// both platforms and the two cannot describe a line differently. The uuid
// stays in the document the core reads and is not returned as a log line.
func (c engineConfig) vlessStartJSON() ([]byte, error) {
	if c.Outbound.Server == "" || c.Outbound.ServerPort <= 0 || c.Outbound.UUID == "" {
		return nil, fmt.Errorf("vless start failed")
	}
	// The core listens where the broker already told it to. A second constant
	// here would drift from socks_listen and the tunnel would be pointed at a
	// port nothing is on.
	_, portText, err := net.SplitHostPort(c.SocksListen)
	if err != nil {
		return nil, fmt.Errorf("vless start failed")
	}
	port, err := strconv.Atoi(portText)
	if err != nil || port <= 0 || port > 65535 {
		return nil, fmt.Errorf("vless start failed")
	}

	user := map[string]any{"id": c.Outbound.UUID, "encryption": "none"}
	if c.Outbound.Flow != "" {
		user["flow"] = c.Outbound.Flow
	}
	stream := map[string]any{
		"network":  c.Outbound.networkName(),
		"security": c.Outbound.securityName(),
	}
	if c.Outbound.securityName() == "tls" {
		tls := map[string]any{
			"serverName":    c.Outbound.SNI,
			"allowInsecure": c.Outbound.Insecure,
		}
		if c.Outbound.Fingerprint != "" {
			tls["fingerprint"] = c.Outbound.Fingerprint
		}
		if alpn := c.Outbound.alpnList(); len(alpn) > 0 {
			tls["alpn"] = alpn
		}
		stream["tlsSettings"] = tls
	}
	if network := c.Outbound.networkName(); network == "ws" || network == "websocket" {
		ws := map[string]any{}
		if c.Outbound.Path != "" {
			ws["path"] = c.Outbound.Path
		}
		if c.Outbound.Host != "" {
			ws["headers"] = map[string]string{"Host": c.Outbound.Host}
		}
		stream["wsSettings"] = ws
	}

	doc := map[string]any{
		"log": map[string]any{"loglevel": "warning"},
		"inbounds": []any{map[string]any{
			"listen":   "127.0.0.1",
			"port":     port,
			"protocol": "socks",
			"settings": map[string]any{"udp": true, "auth": "noauth"},
			"tag":      "socks-in",
		}},
		"outbounds": []any{
			map[string]any{
				"protocol": "vless",
				"tag":      "proxy",
				"settings": map[string]any{
					"vnext": []any{map[string]any{
						"address": c.Outbound.Server,
						"port":    c.Outbound.ServerPort,
						"users":   []any{user},
					}},
				},
				"streamSettings": stream,
			},
			map[string]any{"protocol": "freedom", "tag": "direct"},
		},
		// Private ranges stay off the tunnel. The broker's capture routes
		// already exclude the LAN; this keeps the core from sending them out
		// even if a rule is added later.
		"routing": map[string]any{
			"domainStrategy": "AsIs",
			"rules": []any{map[string]any{
				"type":        "field",
				"ip":          []string{"10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8"},
				"outboundTag": "direct",
			}},
		},
	}
	return json.Marshal(doc)
}

// statusLine names what reached the process. It has counts, not domain names
// or the api secret.
func (c engineConfig) statusLine() string {
	tun := ""
	if c.Tun != nil && !c.Probe {
		tun = c.Tun.Name
	}
	hop := "false"
	if c.Outbound.ServerPorts != "" {
		hop = "applied"
	}
	clash := "false"
	if c.APIPort != 0 {
		clash = "applied"
	}
	dns := "false"
	if c.DNSHijack || (c.Tun != nil && c.Tun.DNS != "" && !c.Probe) {
		dns = "true"
	}
	routing := "false"
	if c.RoutingApplied || len(c.DirectDomains) > 0 || len(c.ForceProxyDomains) > 0 || c.UDPDirect {
		routing = "true"
	}
	return fmt.Sprintf(
		"proxydom-engine scheme=%s transport=%s tun=%s socks=%s routing_applied=%s dns_hijack=%s udp_direct=%t clash_api=%s direct_domains=%d force_proxy_domains=%d hop=%s",
		strings.ToLower(strings.TrimSpace(c.Outbound.Type)), c.Outbound.networkName(),
		tun, c.SocksListen, routing, dns, c.UDPDirect, clash, len(c.DirectDomains), len(c.ForceProxyDomains), hop,
	)
}
