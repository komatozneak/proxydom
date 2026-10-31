//go:build windows

package main

import (
	"encoding/json"
	"fmt"
	"net"
	"strconv"
	"strings"

	"proxydom/hy2bind"
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
	UDPMode           string         `json:"udp_mode"`
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
	Flow         string `json:"flow"`
	Security     string `json:"security"`
	Fingerprint  string `json:"fingerprint"`
	PublicKey    string `json:"public_key"`
	ShortID      string `json:"short_id"`
	// Username and Method belong to the two outbounds that need them beside a
	// password: SOCKS5 takes a user, Shadowsocks takes a cipher name. The
	// broker writes one flat document for every protocol, so the field is
	// present for all of them and read only by the one it applies to.
	Username string `json:"username"`
	Method   string `json:"method"`
	// Transport of a VLESS line. Without these a vless:// over WebSocket or
	// gRPC cannot be described at all, and the row that needs them is exactly
	// the one subscriptions hand out.
	Network string `json:"network"`
	Path    string `json:"path"`
	Host    string `json:"host"`
	// Comma separated: the broker writes one JSON string, and ALPN is a list
	// on the wire.
	ALPN string `json:"alpn"`
	// KCPSeed is the kcp obfuscation seed. The loader already carries it into
	// the core; without it here a kcp line dialled a server that was expecting
	// obfuscation, and failed as a generic core exit.
	KCPSeed string `json:"kcp_seed"`
	// ServiceName is the gRPC path. Empty means the server's empty service,
	// which is what many providers serve; the link's own word travels when it
	// has one.
	ServiceName string `json:"service_name"`
}

// networkName is the transport the core will be asked for. Empty means the
// default the link parsers use.
func (o outboundConfig) networkName() string {
	name := strings.ToLower(strings.TrimSpace(o.Network))
	if name == "" || name == "raw" {
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

// udpMode is the policy the engine will apply. "direct_non_forced" is the
// explicit game mode; everything else is proxy_all, including an old client
// that only knew the legacy udp_direct flag.
func (c engineConfig) udpMode() string {
	if strings.EqualFold(strings.TrimSpace(c.UDPMode), "direct_non_forced") {
		return "direct_non_forced"
	}
	return "proxy_all"
}

// engineKind is which core a session needs. The two have separate start calls
// and separate TUN wiring, so the choice is made once.
type engineKind int

const (
	engineHy2 engineKind = iota
	// engineShare is the in-process v2ray-core. One engine carries every
	// outbound the share loader can describe, so adding a protocol here is a
	// line in [engineConfig.shareOutbound], not a third start call.
	engineShare
)

// shareScheme normalises the broker's `outbound.type` for the share engine.
// Empty means the field was not written, which is not a scheme.
func (c engineConfig) shareScheme() string {
	switch strings.ToLower(strings.TrimSpace(c.Outbound.Type)) {
	case "ss":
		return "shadowsocks"
	case "socks5":
		return "socks"
	default:
		return strings.ToLower(strings.TrimSpace(c.Outbound.Type))
	}
}

// socksOutbound reports whether this document has no transport and no TLS at
// all. SOCKS5 is a bare hop: asking the loader about `tls` for it would be a
// question about a layer the protocol does not have.
func (c engineConfig) socksOutbound() bool {
	return c.shareScheme() == "socks"
}

func (c engineConfig) kind() (engineKind, bool) {
	switch strings.ToLower(strings.TrimSpace(c.Outbound.Type)) {
	case "hysteria2", "hy2":
		return engineHy2, true
	case "vless", "vmess", "trojan", "ss", "shadowsocks", "socks", "socks5":
		return engineShare, true
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
	if c.socksOutbound() {
		return ""
	}
	// The REALITY engine carries its own stream framing and currently speaks
	// TCP only. A WebSocket or gRPC REALITY line would otherwise pass the
	// generic table and fail after the TLS handshake. SOCKS5 has no TLS layer
	// at all, so the word `reality` on such a line is not this branch's.
	if c.shareScheme() == "vless" && c.Outbound.securityName() == "reality" && c.Outbound.networkName() != "tcp" {
		return "transport_unsupported"
	}
	if c.shareScheme() == "vless" && c.Outbound.securityName() == "reality" &&
		c.Outbound.Flow != "" && !strings.EqualFold(c.Outbound.Flow, "none") {
		return "security_unsupported"
	}
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
	body["udp_mode"] = c.udpMode()
	if c.Tun != nil && c.Tun.DNS != "" && !c.Probe {
		body["dns_address"] = c.Tun.DNS
	}
	if c.APIPort > 0 && c.APISecret != "" {
		body["api_port"] = c.APIPort
		body["api_secret"] = c.APISecret
	}
	return json.Marshal(body)
}

// shareStartJSON is the document hy2bind.StartShare accepts.
//
// It is the same shape the Android client builds in
// mobile/lib/features/vpn/data/engine_share_config.dart, so one loader serves
// both platforms and the two cannot describe a line differently. Credentials
// stay in the document the core reads and are not returned as a log line.
func (c engineConfig) shareStartJSON() ([]byte, error) {
	if c.Outbound.Server == "" || c.Outbound.ServerPort <= 0 {
		return nil, fmt.Errorf("share start failed")
	}
	// REALITY is not a v2ray-core stream setting. It is a second share engine
	// with its own SOCKS inbound, selected by the document's `engine` field.
	// Only VLESS carries it; a SOCKS5 outbound that happens to spell
	// `security:reality` is still a bare socket and goes through shareOutbound.
	if c.shareScheme() == "vless" && c.Outbound.securityName() == "reality" {
		return c.realityStartJSON()
	}
	// The core listens where the broker already told it to. A second constant
	// here would drift from socks_listen and the tunnel would be pointed at a
	// port nothing is on.
	_, portText, err := net.SplitHostPort(c.SocksListen)
	if err != nil {
		return nil, fmt.Errorf("share start failed")
	}
	port, err := strconv.Atoi(portText)
	if err != nil || port <= 0 || port > 65535 {
		return nil, fmt.Errorf("share start failed")
	}
	outbound, err := c.shareOutbound()
	if err != nil {
		return nil, err
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
			outbound,
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
	// The TUN dialer in front of this core reads these fields; v2ray itself
	// ignores unknown top-level keys. One policy document, two engines.
	if len(c.DirectDomains) > 0 {
		doc["direct_domain_suffixes"] = c.DirectDomains
	}
	if len(c.ForceProxyDomains) > 0 {
		doc["force_proxy_domains"] = c.ForceProxyDomains
	}
	doc["udp_mode"] = c.udpMode()
	return json.Marshal(doc)
}

// realityStartJSON is the document hy2bind's REALITY engine reads.
//
// It is not a v2ray document: no inbounds, outbounds or routing. The engine
// owns a SOCKS5 listener and the TUN pump dials it exactly as it dials the
// v2ray share core. The split policy is still carried, because the classifier
// in front of both engines is the same one.
func (c engineConfig) realityStartJSON() ([]byte, error) {
	if c.Outbound.UUID == "" || c.Outbound.PublicKey == "" {
		return nil, fmt.Errorf("share start failed")
	}
	if c.Outbound.networkName() != "tcp" {
		return nil, fmt.Errorf("share start failed")
	}
	doc := map[string]any{
		"engine":       "reality",
		"server":       c.Outbound.Server,
		"port":         c.Outbound.ServerPort,
		"uuid":         c.Outbound.UUID,
		"public_key":   c.Outbound.PublicKey,
		"short_id":     c.Outbound.ShortID,
		"sni":          c.Outbound.SNI,
		"fingerprint":  c.Outbound.Fingerprint,
		"flow":         c.Outbound.Flow,
		"network":      "tcp",
		"alpn":         c.Outbound.alpnList(),
		"socks_listen": c.SocksListen,
	}
	if len(c.DirectDomains) > 0 {
		doc["direct_domain_suffixes"] = c.DirectDomains
	}
	if len(c.ForceProxyDomains) > 0 {
		doc["force_proxy_domains"] = c.ForceProxyDomains
	}
	doc["udp_mode"] = c.udpMode()
	return json.Marshal(doc)
}

// shareOutbound is the one outbound object, per protocol.
//
// Every branch mirrors a builder in engine_share_config.dart field for field.
// A protocol added on one side only would describe the same line two ways
// depending on the platform, which is the drift this function exists to stop.
func (c engineConfig) shareOutbound() (map[string]any, error) {
	var outbound map[string]any
	switch c.shareScheme() {
	case "vless":
		if c.Outbound.UUID == "" {
			return nil, fmt.Errorf("share start failed")
		}
		user := map[string]any{"id": c.Outbound.UUID, "encryption": "none"}
		if c.Outbound.Flow != "" {
			user["flow"] = c.Outbound.Flow
		}
		outbound = map[string]any{
			"protocol": "vless",
			"settings": map[string]any{
				"vnext": []any{map[string]any{
					"address": c.Outbound.Server,
					"port":    c.Outbound.ServerPort,
					"users":   []any{user},
				}},
			},
			"streamSettings": c.shareStream(),
		}
	case "vmess":
		if c.Outbound.UUID == "" {
			return nil, fmt.Errorf("share start failed")
		}
		security := strings.ToLower(strings.TrimSpace(c.Outbound.Method))
		if security == "" {
			security = "auto"
		}
		outbound = map[string]any{
			"protocol": "vmess",
			"settings": map[string]any{
				"vnext": []any{map[string]any{
					"address": c.Outbound.Server,
					"port":    c.Outbound.ServerPort,
					"users":   []any{map[string]any{"id": c.Outbound.UUID, "security": security}},
				}},
			},
			"streamSettings": c.shareStream(),
		}
	case "trojan":
		if c.Outbound.Password == "" {
			return nil, fmt.Errorf("share start failed")
		}
		outbound = map[string]any{
			"protocol": "trojan",
			"settings": map[string]any{
				"servers": []any{map[string]any{
					"address":  c.Outbound.Server,
					"port":     c.Outbound.ServerPort,
					"password": c.Outbound.Password,
				}},
			},
			"streamSettings": c.shareStream(),
		}
	case "shadowsocks":
		if c.Outbound.Password == "" || c.Outbound.Method == "" {
			return nil, fmt.Errorf("share start failed")
		}
		// Shadowsocks carries its own AEAD; the builder on Android passes
		// `security: none`, and the loader refuses a cipher it does not have
		// long before a dial.
		stream := c.shareStream()
		stream["security"] = "none"
		delete(stream, "tlsSettings")
		outbound = map[string]any{
			"protocol": "shadowsocks",
			"settings": map[string]any{
				"servers": []any{map[string]any{
					"address":  c.Outbound.Server,
					"port":     c.Outbound.ServerPort,
					"method":   c.Outbound.Method,
					"password": c.Outbound.Password,
				}},
			},
			"streamSettings": stream,
		}
	case "socks":
		// No stream block at all: SOCKS5 is a bare hop, and the loader leaves
		// SenderSettings unset for an outbound without one.
		server := map[string]any{
			"address": c.Outbound.Server,
			"port":    c.Outbound.ServerPort,
		}
		if c.Outbound.Username != "" || c.Outbound.Password != "" {
			server["users"] = []any{map[string]any{
				"user": c.Outbound.Username,
				"pass": c.Outbound.Password,
			}}
		}
		outbound = map[string]any{
			"protocol": "socks",
			"settings": map[string]any{"servers": []any{server}},
		}
	default:
		return nil, fmt.Errorf("share start failed")
	}
	outbound["tag"] = "proxy"
	return outbound, nil
}

// shareStream is the transport and TLS block every protocol but SOCKS5 uses.
func (c engineConfig) shareStream() map[string]any {
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
	if network := c.Outbound.networkName(); network == "kcp" || network == "mkcp" {
		if seed := strings.TrimSpace(c.Outbound.KCPSeed); seed != "" && seed != "/" {
			stream["kcpSettings"] = map[string]any{"seed": seed}
		}
	}
	if c.Outbound.networkName() == "grpc" {
		grpc := map[string]any{}
		if name := strings.TrimSpace(c.Outbound.ServiceName); name != "" {
			grpc["serviceName"] = name
		}
		stream["grpcSettings"] = grpc
	}
	if c.Outbound.networkName() == "httpupgrade" {
		upgrade := map[string]any{}
		if c.Outbound.Path != "" {
			upgrade["path"] = c.Outbound.Path
		}
		if c.Outbound.Host != "" {
			upgrade["host"] = c.Outbound.Host
		}
		stream["httpupgradeSettings"] = upgrade
	}
	return stream
}

// echoesSecret reports whether a core error quotes a credential from this
// document. The broker journal is a log, and a uuid or password in it is a leak
// with a line number next to it.
func (c engineConfig) echoesSecret(msg string) bool {
	for _, secret := range []string{c.Outbound.UUID, c.Outbound.Password, c.Outbound.Username} {
		if secret != "" && strings.Contains(msg, secret) {
			return true
		}
	}
	return false
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
	// routing_applied and dns_hijack name what the engine did, not what the
	// document asked for. Both engines now run the same TUN-level classifier,
	// so a VLESS session applies its lists too; only the hysteria2 dialer
	// hijacks DNS, the VLESS one sends DNS through the core.
	kind, kindOK := c.kind()
	appliesSplit := kindOK && (len(c.DirectDomains) > 0 || len(c.ForceProxyDomains) > 0 ||
		c.udpMode() == "direct_non_forced")
	dns := "false"
	if kindOK && kind == engineHy2 && !c.Probe {
		dns = "true"
	}
	routing := "false"
	if appliesSplit {
		routing = "true"
	}
	return fmt.Sprintf(
		"proxydom-engine scheme=%s transport=%s tun=%s socks=%s routing_applied=%s dns_hijack=%s udp_mode=%s udp_direct=%t clash_api=%s direct_domains=%d force_proxy_domains=%d hop=%s",
		strings.ToLower(strings.TrimSpace(c.Outbound.Type)), c.Outbound.networkName(),
		tun, c.SocksListen, routing, dns, c.udpMode(), c.udpMode() == "direct_non_forced", clash,
		len(c.DirectDomains), len(c.ForceProxyDomains), hop,
	)
}
