//go:build !windows

package hy2bind

import "net"

func prepareOutsideDial() {}

func bindOutsidePacket(net.PacketConn) {}

func dialOutsideTun(network, addr string) (net.Conn, error) {
	return protectAndDial(network, addr)
}

func dialOutsideUDP(addr string) (net.PacketConn, error) {
	conn, err := protectAndDial("udp", addr)
	if err != nil {
		return nil, err
	}
	pc, ok := conn.(net.PacketConn)
	if !ok {
		_ = conn.Close()
		return nil, errProtect
	}
	return pc, nil
}
