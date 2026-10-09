//go:build windows

package main

import (
	"encoding/json"
	"fmt"
	"strings"
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
	Type         string `json:"type"`
	Server       string `json:"server"`
	ServerPort   int    `json:"server_port"`
	Password     string `json:"password"`
	SNI          string `json:"sni"`
	Insecure     bool   `json:"insecure"`
	Obfs         string `json:"obfs"`
	ObfsPassword string `json:"obfs_password"`
	ServerPorts  string `json:"server_ports"`
	HopInterval  string `json:"hop_interval"`
	UUID         string `json:"uuid"`
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

// rejectTransport is the line the broker can see. VLESS and any other
// outbound are not carried by this process; they are not rewritten as TCP.
func (c engineConfig) rejectTransport() bool {
	switch strings.ToLower(strings.TrimSpace(c.Outbound.Type)) {
	case "hysteria2", "hy2":
		return false
	default:
		return true
	}
}

// hy2StartJSON is the document hy2bind.Start already accepts. The password
// stays in the JSON the core reads and is not returned as a log line.
func (c engineConfig) hy2StartJSON() ([]byte, error) {
	if c.rejectTransport() {
		return nil, fmt.Errorf("error transport")
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
		"proxydom-engine tun=%s socks=%s routing_applied=%s dns_hijack=%s udp_direct=%t clash_api=%s direct_domains=%d force_proxy_domains=%d hop=%s",
		tun, c.SocksListen, routing, dns, c.UDPDirect, clash, len(c.DirectDomains), len(c.ForceProxyDomains), hop,
	)
}
