//go:build windows

package hy2bind

import (
	"log"
	"net"
	"syscall"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

// physicalIF is the NIC chosen before the broker installs the /1 capture
// routes. Direct sockets bind to it so they do not re-enter ProxyDomTun.
var physicalIF uint32

// tunAdapterNames are the adapters this engine opens. A route through any of
// them is a route into ourselves, so they can never be the answer to "which
// interface does the tunnel leave by".
var tunAdapterNames = map[string]bool{"ProxyDomTun": true}

// isTunAdapter reports whether an interface index names one of our own adapters.
func isTunAdapter(index uint32) bool {
	if index == 0 {
		return false
	}
	iface, err := net.InterfaceByIndex(int(index))
	if err != nil {
		return false
	}
	return tunAdapterNames[iface.Name]
}

// defaultRouteIndexOutside answers with the interface carrying the best real
// default route, skipping our own adapters.
//
// Only prefix length zero counts. The broker's capture is two /1 routes, not a
// /0, so they are invisible here — which is exactly why this is the right
// fallback and not a second guess at the same question.
func defaultRouteIndexOutside() uint32 {
	var table *windows.MibIpForwardTable2
	if err := windows.GetIpForwardTable2(windows.AF_INET, &table); err != nil || table == nil {
		return 0
	}
	defer windows.FreeMibTable(unsafe.Pointer(table))

	var best uint32
	bestMetric := ^uint32(0)
	for _, row := range table.Rows() {
		if row.DestinationPrefix.PrefixLength != 0 {
			continue
		}
		if row.InterfaceIndex == 0 || isTunAdapter(row.InterfaceIndex) {
			continue
		}
		if row.Metric < bestMetric || (row.Metric == bestMetric && row.InterfaceIndex < best) {
			best, bestMetric = row.InterfaceIndex, row.Metric
		}
	}
	return best
}

// bestOutsideIndex is the interface the engine's own dials must leave by.
//
// GetBestInterfaceEx is asked first because it applies the whole routing policy,
// not just the default route. But it answers the question "where would a packet
// to 1.1.1.1 go", and once capture is up the answer is the tunnel — so it can
// return our own adapter, and binding to it makes the engine dial itself. That
// is not hypothetical: a session that died without cleanup leaves ProxyDomTun up
// with its /1 routes, and the broker tolerates those as its own rather than
// treating them as a foreign tunnel, so the next connect starts a core into
// exactly that state. The forwarding table is the tie-break.
func bestOutsideIndex() uint32 {
	sa := &windows.SockaddrInet4{Addr: [4]byte{1, 1, 1, 1}}
	var idx uint32
	err := windows.GetBestInterfaceEx(sa, &idx)
	if err == nil && idx != 0 && !isTunAdapter(idx) {
		return idx
	}
	return defaultRouteIndexOutside()
}

func prepareOutsideDial() {
	idx := bestOutsideIndex()
	if idx == 0 {
		log.Printf("hy2bind physical interface unknown")
		return
	}
	physicalIF = idx
	if iface, err := net.InterfaceByIndex(int(idx)); err == nil {
		log.Printf("hy2bind physical ifindex=%d name=%s", idx, iface.Name)
		return
	}
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
