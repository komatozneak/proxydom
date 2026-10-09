//go:build !windows

package hy2bind

import (
	"context"
	"errors"
	"net"
	"syscall"
	"time"
)

// engineOutboundDial opens the socket the VLESS core uses to reach its node.
//
// Android: VpnService.protect before connect, so the socket does not re-enter
// the tun. A failed protect is an error rather than a warning — connecting
// anyway would loop the tunnel through itself.
func engineOutboundDial(ctx context.Context, network, addr string) (net.Conn, error) {
	dialer := &net.Dialer{
		Timeout: 8 * time.Second,
		Control: func(_, _ string, c syscall.RawConn) error {
			var protectErr error
			ctrlErr := c.Control(func(fd uintptr) {
				mu.Lock()
				p := protector
				mu.Unlock()
				if p == nil || !p.Protect(int(fd)) {
					protectErr = errors.New("protect failed")
					lastProtectErr.Store("protect failed")
					return
				}
				lastProtectErr.Store("")
			})
			if ctrlErr != nil {
				return ctrlErr
			}
			return protectErr
		},
	}
	return dialer.DialContext(ctx, network, addr)
}
