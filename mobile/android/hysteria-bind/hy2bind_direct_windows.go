//go:build windows

package hy2bind

import (
	"log"
	"net"
	"syscall"
	"time"

	"golang.org/x/sys/windows"
)

// physicalIF is the NIC chosen before the broker installs the /1 capture
// routes. Direct sockets bind to it so they do not re-enter ProxyDomTun.
var physicalIF uint32

func prepareOutsideDial() {
	sa := &windows.SockaddrInet4{Addr: [4]byte{1, 1, 1, 1}}
	var idx uint32
	err := windows.GetBestInterfaceEx(sa, &idx)
	if err != nil || idx == 0 {
		log.Printf("hy2bind physical interface unknown")
		return
	}
	physicalIF = idx
	log.Printf("hy2bind physical ifindex=%d", idx)
}

func bindOutsidePacket(pc net.PacketConn) {
	uc, ok := pc.(*net.UDPConn)
	if !ok {
		return
	}
	raw, err := uc.SyscallConn()
	if err != nil {
		return
	}
	_ = bindPhysical(raw)
}

func dialOutsideTun(network, addr string) (net.Conn, error) {
	d := net.Dialer{Timeout: 20 * time.Second, Control: controlOutside}
	return d.Dial(network, addr)
}

func dialOutsideUDP(addr string) (net.PacketConn, error) {
	d := net.Dialer{Control: controlOutside}
	conn, err := d.Dial("udp", addr)
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

func controlOutside(_, _ string, c syscall.RawConn) error {
	return bindPhysical(c)
}

func bindPhysical(c syscall.RawConn) error {
	idx := physicalIF
	if idx == 0 {
		return nil
	}
	var v [4]byte
	v[0] = byte(idx >> 24)
	v[1] = byte(idx >> 16)
	v[2] = byte(idx >> 8)
	v[3] = byte(idx)
	return c.Control(func(fd uintptr) {
		_ = windows.Setsockopt(
			windows.Handle(fd),
			windows.IPPROTO_IP,
			31, // IP_UNICAST_IF
			&v[0],
			int32(len(v)),
		)
	})
}
