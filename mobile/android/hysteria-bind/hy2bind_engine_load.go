package hy2bind

import (
	"encoding/json"
	"fmt"
	stdnet "net"
	"strings"

	v2core "github.com/v2fly/v2ray-core/v5"
	"github.com/v2fly/v2ray-core/v5/app/dispatcher"
	v2log "github.com/v2fly/v2ray-core/v5/app/log"
	"github.com/v2fly/v2ray-core/v5/app/proxyman"
	"github.com/v2fly/v2ray-core/v5/app/router"
	routercommon "github.com/v2fly/v2ray-core/v5/app/router/routercommon"
	clog "github.com/v2fly/v2ray-core/v5/common/log"
	"github.com/v2fly/v2ray-core/v5/common/net"
	"github.com/v2fly/v2ray-core/v5/common/protocol"
	"github.com/v2fly/v2ray-core/v5/common/serial"
	"github.com/v2fly/v2ray-core/v5/proxy/freedom"
	"github.com/v2fly/v2ray-core/v5/proxy/shadowsocks"
	"github.com/v2fly/v2ray-core/v5/proxy/socks"
	"github.com/v2fly/v2ray-core/v5/proxy/trojan"
	vless "github.com/v2fly/v2ray-core/v5/proxy/vless"
	vlessout "github.com/v2fly/v2ray-core/v5/proxy/vless/outbound"
	vmess "github.com/v2fly/v2ray-core/v5/proxy/vmess"
	vmessout "github.com/v2fly/v2ray-core/v5/proxy/vmess/outbound"
	"github.com/v2fly/v2ray-core/v5/transport/internet"
	"github.com/v2fly/v2ray-core/v5/transport/internet/kcp"
	"github.com/v2fly/v2ray-core/v5/transport/internet/tls"
	utls "github.com/v2fly/v2ray-core/v5/transport/internet/tls/utls"
	"github.com/v2fly/v2ray-core/v5/transport/internet/websocket"
	"google.golang.org/protobuf/types/known/anypb"
)

// shareDocument is the JSON emitted by buildShareSocksConfig. It is not the
// full v2ray JSON schema: that loader pulls WireGuard into this binary.
type shareDocument struct {
	Inbounds []struct {
		Listen   string `json:"listen"`
		Port     int    `json:"port"`
		Protocol string `json:"protocol"`
		Tag      string `json:"tag"`
		Settings struct {
			UDP bool `json:"udp"`
		} `json:"settings"`
	} `json:"inbounds"`
	Outbounds []shareOutbound `json:"outbounds"`
	Routing   struct {
		Rules []struct {
			IP          []string `json:"ip"`
			OutboundTag string   `json:"outboundTag"`
		} `json:"rules"`
	} `json:"routing"`
}

type shareOutbound struct {
	Protocol string `json:"protocol"`
	Tag      string `json:"tag"`
	Settings struct {
		Vnext []struct {
			Address string `json:"address"`
			Port    int    `json:"port"`
			Users   []struct {
				ID         string `json:"id"`
				Encryption string `json:"encryption"`
				Flow       string `json:"flow"`
				Security   string `json:"security"`
			} `json:"users"`
		} `json:"vnext"`
		Servers []struct {
			Address  string `json:"address"`
			Port     int    `json:"port"`
			Password string `json:"password"`
			Method   string `json:"method"`
		} `json:"servers"`
	} `json:"settings"`
	Stream *shareStream `json:"streamSettings"`
}

type shareStream struct {
	Network  string `json:"network"`
	Security string `json:"security"`
	TLS      *struct {
		ServerName  string   `json:"serverName"`
		Fingerprint string   `json:"fingerprint"`
		Allow       bool     `json:"allowInsecure"`
		ALPN        []string `json:"alpn"`
	} `json:"tlsSettings"`
	Reality *struct {
		ServerName  string `json:"serverName"`
		PublicKey   string `json:"publicKey"`
		ShortID     string `json:"shortId"`
		Fingerprint string `json:"fingerprint"`
	} `json:"realitySettings"`
	WS *struct {
		Path    string            `json:"path"`
		Headers map[string]string `json:"headers"`
	} `json:"wsSettings"`
	KCP *struct {
		Seed string `json:"seed"`
	} `json:"kcpSettings"`
}

func loadShareConfig(configJSON string) (*v2core.Config, error) {
	var doc shareDocument
	if err := json.Unmarshal([]byte(configJSON), &doc); err != nil {
		return nil, err
	}
	if len(doc.Inbounds) == 0 || len(doc.Outbounds) == 0 {
		return nil, fmt.Errorf("share config missing inbound or outbound")
	}
	inbound, err := shareInbound(doc.Inbounds[0])
	if err != nil {
		return nil, err
	}
	var outbounds []*v2core.OutboundHandlerConfig
	for _, item := range doc.Outbounds {
		outbound, err := shareOutboundHandler(item)
		if err != nil {
			return nil, err
		}
		outbounds = append(outbounds, outbound)
	}
	rules, err := shareRules(doc.Routing.Rules)
	if err != nil {
		return nil, err
	}
	return &v2core.Config{
		App: []*anypb.Any{
			// None: the core logger would write every Info line. Our handler
			// keeps the decision lines after New() replaces the process logger.
			serial.ToTypedMessage(&v2log.Config{
				Error:  &v2log.LogSpecification{Type: v2log.LogType_None, Level: clog.Severity_Info},
				Access: &v2log.LogSpecification{Type: v2log.LogType_None},
			}),
			serial.ToTypedMessage(&dispatcher.Config{}),
			serial.ToTypedMessage(&proxyman.InboundConfig{}),
			serial.ToTypedMessage(&proxyman.OutboundConfig{}),
			serial.ToTypedMessage(&router.Config{Rule: rules}),
		},
		Inbound:  []*v2core.InboundHandlerConfig{inbound},
		Outbound: outbounds,
	}, nil
}

func shareInbound(in struct {
	Listen   string `json:"listen"`
	Port     int    `json:"port"`
	Protocol string `json:"protocol"`
	Tag      string `json:"tag"`
	Settings struct {
		UDP bool `json:"udp"`
	} `json:"settings"`
}) (*v2core.InboundHandlerConfig, error) {
	if in.Protocol != "socks" {
		return nil, fmt.Errorf("unsupported inbound %q", in.Protocol)
	}
	listen := in.Listen
	if listen == "" {
		listen = "127.0.0.1"
	}
	port := uint32(in.Port)
	return &v2core.InboundHandlerConfig{
		Tag: in.Tag,
		ReceiverSettings: serial.ToTypedMessage(&proxyman.ReceiverConfig{
			PortRange: &net.PortRange{From: port, To: port},
			Listen:    net.NewIPOrDomain(net.ParseAddress(listen)),
		}),
		ProxySettings: serial.ToTypedMessage(&socks.ServerConfig{
			AuthType:   socks.AuthType_NO_AUTH,
			UdpEnabled: in.Settings.UDP,
		}),
	}, nil
}

func shareOutboundHandler(item shareOutbound) (*v2core.OutboundHandlerConfig, error) {
	proxySettings, err := shareProxy(item)
	if err != nil {
		return nil, err
	}
	var sender *anypb.Any
	if item.Stream != nil && item.Protocol != "freedom" {
		stream, err := shareStreamConfig(item.Stream)
		if err != nil {
			return nil, err
		}
		sender = serial.ToTypedMessage(&proxyman.SenderConfig{StreamSettings: stream})
	}
	return &v2core.OutboundHandlerConfig{
		Tag:            item.Tag,
		SenderSettings: sender,
		ProxySettings:  proxySettings,
	}, nil
}

func shareProxy(item shareOutbound) (*anypb.Any, error) {
	switch item.Protocol {
	case "freedom":
		return serial.ToTypedMessage(&freedom.Config{}), nil
	case "vless":
		return serial.ToTypedMessage(&vlessout.Config{Vnext: []*protocol.ServerEndpoint{vlessEndpoint(item)}}), nil
	case "vmess":
		return serial.ToTypedMessage(vmessOutbound(item)), nil
	case "trojan":
		return serial.ToTypedMessage(&trojan.ClientConfig{Server: []*protocol.ServerEndpoint{trojanEndpoint(item)}}), nil
	case "shadowsocks":
		if len(item.Settings.Servers) == 0 {
			return nil, fmt.Errorf("shadowsocks server missing")
		}
		server := item.Settings.Servers[0]
		cipher, err := ssCipher(server.Method)
		if err != nil {
			return nil, err
		}
		return serial.ToTypedMessage(&shadowsocks.ClientConfig{Server: []*protocol.ServerEndpoint{{
			Address: net.NewIPOrDomain(net.ParseAddress(server.Address)),
			Port:    uint32(server.Port),
			User: []*protocol.User{{
				Account: serial.ToTypedMessage(&shadowsocks.Account{
					Password:   server.Password,
					CipherType: cipher,
				}),
			}},
		}}}), nil
	default:
		return nil, fmt.Errorf("unsupported outbound %q", item.Protocol)
	}
}

type shareUser struct {
	ID         string
	Encryption string
	Flow       string
	Security   string
	Password   string
}

func vlessEndpoint(item shareOutbound) *protocol.ServerEndpoint {
	next := item.Settings.Vnext[0]
	user := shareUser{}
	if len(next.Users) > 0 {
		user = shareUser{
			ID:         next.Users[0].ID,
			Encryption: next.Users[0].Encryption,
			Flow:       next.Users[0].Flow,
		}
	}
	return &protocol.ServerEndpoint{
		Address: net.NewIPOrDomain(net.ParseAddress(next.Address)),
		Port:    uint32(next.Port),
		User: []*protocol.User{{
			Account: serial.ToTypedMessage(&vless.Account{
				Id:         user.ID,
				Encryption: orNone(user.Encryption),
				Flow:       user.Flow,
			}),
		}},
	}
}

func trojanEndpoint(item shareOutbound) *protocol.ServerEndpoint {
	server := item.Settings.Servers[0]
	return &protocol.ServerEndpoint{
		Address: net.NewIPOrDomain(net.ParseAddress(server.Address)),
		Port:    uint32(server.Port),
		User: []*protocol.User{{
			Account: serial.ToTypedMessage(&trojan.Account{Password: server.Password}),
		}},
	}
}

func vmessOutbound(item shareOutbound) *vmessout.Config {
	next := item.Settings.Vnext[0]
	user := next.Users[0]
	return &vmessout.Config{Receiver: []*protocol.ServerEndpoint{{
		Address: net.NewIPOrDomain(net.ParseAddress(next.Address)),
		Port:    uint32(next.Port),
		User: []*protocol.User{{
			Account: serial.ToTypedMessage(&vmess.Account{
				Id:               user.ID,
				SecuritySettings: &protocol.SecurityConfig{Type: vmessSecurity(user.Security)},
			}),
		}},
	}}}
}

// engineTransport maps a share-link network name onto the name v2ray-core
// registers. websocket/config.go sets protocolName = "websocket"; "ws" is
// only the JSON short name and is not a dialer.
func engineTransport(network string) (string, error) {
	switch strings.ToLower(strings.TrimSpace(network)) {
	case "", "tcp":
		return "tcp", nil
	case "ws", "websocket":
		return "websocket", nil
	case "kcp", "mkcp":
		return "mkcp", nil
	default:
		return "", fmt.Errorf("unsupported transport %q", network)
	}
}

func shareStreamConfig(stream *shareStream) (*internet.StreamConfig, error) {
	network, err := engineTransport(stream.Network)
	if err != nil {
		return nil, err
	}
	cfg := &internet.StreamConfig{ProtocolName: network}
	if network == "mkcp" {
		kcpCfg := &kcp.Config{}
		if stream.KCP != nil && stream.KCP.Seed != "" {
			kcpCfg.Seed = &kcp.EncryptionSeed{Seed: stream.KCP.Seed}
		}
		cfg.TransportSettings = []*internet.TransportConfig{{
			ProtocolName: "mkcp",
			Settings:     serial.ToTypedMessage(kcpCfg),
		}}
	}
	if stream.WS != nil {
		var headers []*websocket.Header
		for key, value := range stream.WS.Headers {
			headers = append(headers, &websocket.Header{Key: key, Value: value})
		}
		ws := serial.ToTypedMessage(&websocket.Config{Path: stream.WS.Path, Header: headers})
		cfg.TransportSettings = []*internet.TransportConfig{{
			ProtocolName: "websocket",
			Settings:     ws,
		}}
	}
	switch stream.Security {
	case "", "none":
	case "tls":
		tlsCfg := &tls.Config{}
		if stream.TLS != nil {
			tlsCfg.ServerName = stream.TLS.ServerName
			tlsCfg.AllowInsecure = stream.TLS.Allow
			if len(stream.TLS.ALPN) > 0 {
				tlsCfg.NextProtocol = append([]string(nil), stream.TLS.ALPN...)
			}
		}
		var msg *anypb.Any
		if stream.TLS != nil && stream.TLS.Fingerprint != "" {
			msg = serial.ToTypedMessage(&utls.Config{
				TlsConfig: tlsCfg,
				Imitate:   stream.TLS.Fingerprint,
			})
		} else {
			msg = serial.ToTypedMessage(tlsCfg)
		}
		// V2Type is the proto name without the types.v2fly.org/ prefix.
		// StreamConfig compares that name to SecurityType before unmarshalling.
		cfg.SecurityType = serial.V2Type(msg)
		cfg.SecuritySettings = []*anypb.Any{msg}
	case "reality":
		return nil, fmt.Errorf("unsupported security %q", stream.Security)
	default:
		return nil, fmt.Errorf("unsupported security %q", stream.Security)
	}
	return cfg, nil
}

func shareRules(rules []struct {
	IP          []string `json:"ip"`
	OutboundTag string   `json:"outboundTag"`
}) ([]*router.RoutingRule, error) {
	var out []*router.RoutingRule
	for _, rule := range rules {
		var cidrs []*routercommon.CIDR
		for _, raw := range rule.IP {
			cidr, err := parseCIDR(raw)
			if err != nil {
				return nil, err
			}
			cidrs = append(cidrs, cidr)
		}
		out = append(out, &router.RoutingRule{
			TargetTag: &router.RoutingRule_Tag{Tag: rule.OutboundTag},
			Geoip:     []*routercommon.GeoIP{{Cidr: cidrs}},
		})
	}
	return out, nil
}

func parseCIDR(raw string) (*routercommon.CIDR, error) {
	_, network, err := stdnet.ParseCIDR(raw)
	if err != nil {
		return nil, err
	}
	ones, _ := network.Mask.Size()
	return &routercommon.CIDR{Ip: network.IP, Prefix: uint32(ones)}, nil
}

func ssCipher(method string) (shadowsocks.CipherType, error) {
	switch strings.ToLower(method) {
	case "aes-128-gcm":
		return shadowsocks.CipherType_AES_128_GCM, nil
	case "aes-256-gcm":
		return shadowsocks.CipherType_AES_256_GCM, nil
	case "chacha20-ietf-poly1305", "chacha20-poly1305":
		return shadowsocks.CipherType_CHACHA20_POLY1305, nil
	case "none":
		return shadowsocks.CipherType_NONE, nil
	default:
		return 0, fmt.Errorf("unsupported shadowsocks method %q", method)
	}
}

func vmessSecurity(raw string) protocol.SecurityType {
	switch strings.ToLower(raw) {
	case "aes-128-gcm":
		return protocol.SecurityType_AES128_GCM
	case "chacha20-poly1305":
		return protocol.SecurityType_CHACHA20_POLY1305
	case "none":
		return protocol.SecurityType_NONE
	case "zero":
		return protocol.SecurityType_ZERO
	default:
		return protocol.SecurityType_AUTO
	}
}

func orNone(raw string) string {
	if raw == "" {
		return "none"
	}
	return raw
}
