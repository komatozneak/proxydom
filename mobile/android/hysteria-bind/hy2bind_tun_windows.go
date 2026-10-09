//go:build windows

package hy2bind

import (
	"fmt"

	"github.com/xjasonlyu/tun2socks/v2/core/device/tun"
	"github.com/xjasonlyu/tun2socks/v2/tunnel"
)

// StartNamedTun opens the wintun adapter by name and feeds it to the same
// gVisor stack Android uses. TUN packets are not sent to the SOCKS listener.
func StartNamedTun(name string, mtu int) string {
	if name == "" {
		return "tun name required"
	}
	if mtu <= 0 {
		mtu = 1280
	}
	prepareOutsideDial()
	mu.Lock()
	defer mu.Unlock()
	if tunStk != nil {
		return "tun already running"
	}
	if hyClient == nil {
		return "hy2 not started"
	}
	dev, err := tun.Open(name, uint32(mtu))
	if err != nil {
		return fmt.Sprintf("tun open: %v", err)
	}
	tunnel.T().SetProxy(&hyDialer{c: hyClient})
	st, err := createTunStack(dev)
	if err != nil {
		dev.Close()
		return fmt.Sprintf("tun stack: %v", err)
	}
	tunDev = dev
	tunStk = st
	return ""
}
