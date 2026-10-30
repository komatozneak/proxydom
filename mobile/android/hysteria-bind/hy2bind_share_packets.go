package hy2bind

import (
	"log"

	"github.com/xjasonlyu/tun2socks/v2/tunnel"
	"gvisor.dev/gvisor/pkg/tcpip/link/channel"
)

// StartSharePacketTun attaches the userspace gVisor stack that iOS needs.
//
// iOS never hands out a TUN file descriptor: the packet tunnel provider owns a
// packet flow and moves packets itself. [StartShareTun] takes an fd and is
// therefore Android-only, so without this the share core had a working SOCKS
// inbound and no way to carry the phone's traffic — the reason the v2ray family
// stayed closed on iOS.
//
// The outgoing half is the same writer Hysteria2 uses ([SetPacketWriter]); the
// incoming half is [InjectPacket]. Both act on the globals below, so a session
// has exactly one userspace stack whichever core filled it.
func StartSharePacketTun(mtu int) string {
	if mtu <= 0 {
		mtu = 1280
	}
	mu.Lock()
	defer mu.Unlock()
	if tunStk != nil {
		return "tun already running"
	}
	if !shareRunning() {
		return "share core not started"
	}
	addr := ShareSocksAddr()
	if addr == "" {
		// The document did not name a listen address, so there is nothing to
		// point the dialer at. Guessing a port would look healthy until the
		// first packet, which is the failure this check exists to prevent.
		return "share socks address unknown"
	}

	ep := channel.New(512, uint32(mtu), "")
	dev := &packetDevice{Endpoint: ep}
	ep.AddNotify(dev)

	tunnel.T().SetProxy(&socksDialer{addr: addr})
	st, err := createTunStack(ep)
	if err != nil {
		ep.Close()
		return "share packet tun stack: " + err.Error()
	}

	packetEp = ep
	tunDev = dev
	tunStk = st
	log.Printf("hy2bind share packet tun started mtu=%d socks=%s", mtu, addr)
	return ""
}
