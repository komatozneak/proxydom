package hy2bind

import (
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	stdnet "net"
	"strings"

	"github.com/xtls/xray-core/app/dispatcher"
	"github.com/xtls/xray-core/app/proxyman"
	"github.com/xtls/xray-core/app/router"
	"github.com/xtls/xray-core/common/net"
	"github.com/xtls/xray-core/common/protocol"
	"github.com/xtls/xray-core/common/serial"
	xcore "github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/proxy/freedom"
	"github.com/xtls/xray-core/proxy/shadowsocks"
	"github.com/xtls/xray-core/proxy/socks"
	"github.com/xtls/xray-core/proxy/trojan"
	vless "github.com/xtls/xray-core/proxy/vless"
	vlessout "github.com/xtls/xray-core/proxy/vless/outbound"
	vmess "github.com/xtls/xray-core/proxy/vmess"
	vmessout "github.com/xtls/xray-core/proxy/vmess/outbound"
	"github.com/xtls/xray-core/transport/internet"
	"github.com/xtls/xray-core/transport/internet/reality"
	"github.com/xtls/xray-core/transport/internet/tls"
	"github.com/xtls/xray-core/transport/internet/kcp"
	"github.com/xtls/xray-core/transport/internet/websocket"
	"google.golang.org/protobuf/proto"
)

// shareDocument is the JSON emitted by buildXraySocksConfig. It is not the
// full Xray JSON schema: that loader pulls WireGuard into this binary.
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
		ServerName  string `json:"serverName"`
		Fingerprint string `json:"fingerprint"`
		Allow       bool   `json:"allowInsecure"`
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

func loadShareConfig(configJSON string) (*xcore.Config, error) {
	var doc shareDocument
	if err := json.Unmarshal([]byte(configJSON), &doc); err != nil {
		return nil, err
	}
	if len(doc.Inbounds) == 0 || len(doc.Outbounds) == 0 {
		return nil, fmt.Errorf("xray config missing inbound or outbound")
	}
	inbound, err := shareInbound(doc.Inbounds[0])
	if err != nil {
		return nil, err
	}
	var outbounds []*xcore.OutboundHandlerConfig
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
	return &xcore.Config{
		App: []*serial.TypedMessage{
			serial.ToTypedMessage(&dispatcher.Config{}),
			serial.ToTypedMessage(&proxyman.InboundConfig{}),
			serial.ToTypedMessage(&proxyman.OutboundConfig{}),
			serial.ToTypedMessage(&router.Config{Rule: rules}),
		},
		Inbound:  []*xcore.InboundHandlerConfig{inbound},
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
}) (*xcore.InboundHandlerConfig, error) {
	if in.Protocol != "socks" {
		return nil, fmt.Errorf("unsupported inbound %q", in.Protocol)
	}
	listen := in.Listen
	if listen == "" {
		listen = "127.0.0.1"
	}
	port := uint32(in.Port)
	return &xcore.InboundHandlerConfig{
		Tag: in.Tag,
		ReceiverSettings: serial.ToTypedMessage(&proxyman.ReceiverConfig{
			PortList: &net.PortList{Range: []*net.PortRange{{From: port, To: port}}},
			Listen:   net.NewIPOrDomain(net.ParseAddress(listen)),
		}),
		ProxySettings: serial.ToTypedMessage(&socks.ServerConfig{
			AuthType:   socks.AuthType_NO_AUTH,
			UdpEnabled: in.Settings.UDP,
		}),
	}, nil
}

func shareOutboundHandler(item shareOutbound) (*xcore.OutboundHandlerConfig, error) {
	proxySettings, err := shareProxy(item)
	if err != nil {
		return nil, err
	}
	var sender *serial.TypedMessage
	if item.Stream != nil && item.Protocol != "freedom" {
		stream, err := shareStreamConfig(item.Stream)
		if err != nil {
			return nil, err
		}
		sender = serial.ToTypedMessage(&proxyman.SenderConfig{StreamSettings: stream})
	}
	return &xcore.OutboundHandlerConfig{
		Tag:            item.Tag,
		SenderSettings: sender,
		ProxySettings:  proxySettings,
	}, nil
}

func shareProxy(item shareOutbound) (*serial.TypedMessage, error) {
	switch item.Protocol {
	case "freedom":
		return serial.ToTypedMessage(&freedom.Config{}), nil
	case "vless":
		return serial.ToTypedMessage(&vlessout.Config{Vnext: []*protocol.ServerEndpoint{mustEndpoint(item, func(user shareUser) proto.Message {
			return &vless.Account{Id: user.ID, Encryption: orNone(user.Encryption), Flow: user.Flow}
		})}}), nil
	case "vmess":
		return serial.ToTypedMessage(vmessOutbound(item)), nil
	case "trojan":
		return serial.ToTypedMessage(&trojan.ClientConfig{Server: []*protocol.ServerEndpoint{mustEndpoint(item, func(user shareUser) proto.Message {
			return &trojan.Account{Password: user.Password}
		})}}), nil
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

func mustEndpoint(item shareOutbound, account func(shareUser) proto.Message) *protocol.ServerEndpoint {
	if len(item.Settings.Vnext) > 0 {
		next := item.Settings.Vnext[0]
		user := shareUser{}
		if len(next.Users) > 0 {
			user = shareUser{
				ID:         next.Users[0].ID,
				Encryption: next.Users[0].Encryption,
				Flow:       next.Users[0].Flow,
				Security:   next.Users[0].Security,
			}
		}
		return &protocol.ServerEndpoint{
			Address: net.NewIPOrDomain(net.ParseAddress(next.Address)),
			Port:    uint32(next.Port),
			User:    []*protocol.User{{Account: serial.ToTypedMessage(account(user))}},
		}
	}
	server := item.Settings.Servers[0]
	return &protocol.ServerEndpoint{
		Address: net.NewIPOrDomain(net.ParseAddress(server.Address)),
		Port:    uint32(server.Port),
		User: []*protocol.User{{
			Account: serial.ToTypedMessage(account(shareUser{Password: server.Password})),
		}},
	}
}

func vmessOutbound(item shareOutbound) proto.Message {
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

func shareStreamConfig(stream *shareStream) (*internet.StreamConfig, error) {
	network := stream.Network
	if network == "" {
		network = "tcp"
	}
	if network == "kcp" {
		network = "mkcp"
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
		headers := stream.WS.Headers
		if headers == nil {
			headers = map[string]string{}
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
			tlsCfg.Fingerprint = stream.TLS.Fingerprint
			tlsCfg.AllowInsecure = stream.TLS.Allow
		}
		msg := serial.ToTypedMessage(tlsCfg)
		cfg.SecurityType = msg.Type
		cfg.SecuritySettings = []*serial.TypedMessage{msg}
	case "reality":
		if stream.Reality == nil {
			return nil, fmt.Errorf("reality settings missing")
		}
		pub, err := decodeKey(stream.Reality.PublicKey)
		if err != nil {
			return nil, fmt.Errorf("reality public key: %w", err)
		}
		sid, err := decodeShortID(stream.Reality.ShortID)
		if err != nil {
			return nil, err
		}
		msg := serial.ToTypedMessage(&reality.Config{
			ServerName:  stream.Reality.ServerName,
			PublicKey:   pub,
			ShortId:     sid,
			Fingerprint: stream.Reality.Fingerprint,
		})
		cfg.SecurityType = msg.Type
		cfg.SecuritySettings = []*serial.TypedMessage{msg}
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
		var cidrs []*router.CIDR
		for _, raw := range rule.IP {
			cidr, err := parseCIDR(raw)
			if err != nil {
				return nil, err
			}
			cidrs = append(cidrs, cidr)
		}
		out = append(out, &router.RoutingRule{
			TargetTag: &router.RoutingRule_Tag{Tag: rule.OutboundTag},
			Geoip:     []*router.GeoIP{{Cidr: cidrs}},
		})
	}
	return out, nil
}

func parseCIDR(raw string) (*router.CIDR, error) {
	_, network, err := stdnet.ParseCIDR(raw)
	if err != nil {
		return nil, err
	}
	ones, _ := network.Mask.Size()
	return &router.CIDR{Ip: network.IP, Prefix: uint32(ones)}, nil
}

func decodeKey(raw string) ([]byte, error) {
	raw = strings.TrimSpace(raw)
	if decoded, err := base64.RawURLEncoding.DecodeString(raw); err == nil {
		return decoded, nil
	}
	return base64.URLEncoding.DecodeString(raw)
}

func decodeShortID(raw string) ([]byte, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil, nil
	}
	if decoded, err := hex.DecodeString(raw); err == nil {
		return decoded, nil
	}
	return []byte(raw), nil
}

func ssCipher(method string) (shadowsocks.CipherType, error) {
	switch strings.ToLower(method) {
	case "aes-128-gcm":
		return shadowsocks.CipherType_AES_128_GCM, nil
	case "aes-256-gcm":
		return shadowsocks.CipherType_AES_256_GCM, nil
	case "chacha20-ietf-poly1305", "chacha20-poly1305":
		return shadowsocks.CipherType_CHACHA20_POLY1305, nil
	case "xchacha20-ietf-poly1305", "xchacha20-poly1305":
		return shadowsocks.CipherType_XCHACHA20_POLY1305, nil
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
