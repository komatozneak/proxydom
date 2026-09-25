package hy2bind

import (
	"testing"

	xcore "github.com/xtls/xray-core/core"
)

func TestLoadShareConfigVLESS(t *testing.T) {
	const raw = `{
	  "inbounds":[{"listen":"127.0.0.1","port":10809,"protocol":"socks","settings":{"udp":true,"auth":"noauth"},"tag":"socks-in"}],
	  "outbounds":[
	    {"protocol":"vless","tag":"proxy","settings":{"vnext":[{"address":"203.0.113.10","port":443,"users":[{"id":"11111111-1111-1111-1111-111111111111","encryption":"none"}]}]},
	     "streamSettings":{"network":"tcp","security":"reality","realitySettings":{"serverName":"www.example.com","publicKey":"EzoaRfOchWAdzsm2nNEaZeDgq7Z2PgoXzzZ-cZg13iY","shortId":"a1b2c3d4","fingerprint":"chrome"}}},
	    {"protocol":"freedom","tag":"direct"}
	  ],
	  "routing":{"rules":[{"type":"field","ip":["10.0.0.0/8","127.0.0.0/8"],"outboundTag":"direct"}]}
	}`
	cfg, err := loadShareConfig(raw)
	if err != nil {
		t.Fatal(err)
	}
	inst, err := xcore.New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	_ = inst.Close()
}
