package hy2bind

import (
	"strings"
	"testing"

	v2core "github.com/v2fly/v2ray-core/v5"
)

func TestLoadShareConfigRefusesReality(t *testing.T) {
	const raw = `{
	  "inbounds":[{"listen":"127.0.0.1","port":10809,"protocol":"socks","settings":{"udp":true,"auth":"noauth"},"tag":"socks-in"}],
	  "outbounds":[
	    {"protocol":"vless","tag":"proxy","settings":{"vnext":[{"address":"203.0.113.10","port":443,"users":[{"id":"11111111-1111-1111-1111-111111111111","encryption":"none"}]}]},
	     "streamSettings":{"network":"tcp","security":"reality","realitySettings":{"serverName":"www.example.com","publicKey":"EzoaRfOchWAdzsm2nNEaZeDgq7Z2PgoXzzZ-cZg13iY","shortId":"a1b2c3d4","fingerprint":"chrome"}}},
	    {"protocol":"freedom","tag":"direct"}
	  ],
	  "routing":{"rules":[{"type":"field","ip":["10.0.0.0/8","127.0.0.0/8"],"outboundTag":"direct"}]}
	}`
	_, err := loadShareConfig(raw)
	if err == nil || !strings.Contains(err.Error(), "unsupported security") {
		t.Fatalf("reality must be refused, got %v", err)
	}
}

func TestLoadShareConfigVLESSWebSocket(t *testing.T) {
	const raw = `{
	  "inbounds":[{"listen":"127.0.0.1","port":10809,"protocol":"socks","settings":{"udp":true},"tag":"socks-in"}],
	  "outbounds":[
	    {"protocol":"vless","tag":"proxy","settings":{"vnext":[{"address":"203.0.113.10","port":2083,"users":[{"id":"11111111-1111-1111-1111-111111111111","encryption":"none"}]}]},
	     "streamSettings":{"network":"ws","security":"tls","tlsSettings":{"serverName":"example.com","alpn":["http/1.1"]},"wsSettings":{"path":"/ws"}}},
	    {"protocol":"freedom","tag":"direct"}
	  ],
	  "routing":{"rules":[{"ip":["10.0.0.0/8"],"outboundTag":"direct"}]}
	}`
	cfg, err := loadShareConfig(raw)
	if err != nil {
		t.Fatal(err)
	}
	inst, err := v2core.New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	_ = inst.Close()
}

func TestEngineTransportNormalizesWebSocket(t *testing.T) {
	name, err := engineTransport("ws")
	if err != nil || name != "websocket" {
		t.Fatalf("ws -> %q %v", name, err)
	}
	if _, err := engineTransport("grpc"); err == nil {
		t.Fatal("grpc must be refused")
	}
}
