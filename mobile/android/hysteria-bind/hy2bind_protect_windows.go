//go:build windows

package hy2bind

import (
	"context"
	"net"
)

// engineOutboundDial opens the socket the VLESS core uses to reach its node.
//
// Windows has no VpnService, so there is nothing to protect. What matters is
// that the socket leaves by the physical NIC: once the broker installs the /1
// capture routes, a socket that follows the default route re-enters
// ProxyDomTun and the tunnel dials itself. dialOutsideTun binds that interface.
//
// The same reason the Hy2 path already goes through it (hyDialer.dialDirect).
func engineOutboundDial(_ context.Context, network, addr string) (net.Conn, error) {
	return dialOutsideTun(network, addr)
}
