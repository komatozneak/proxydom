//go:build windows

package hy2bind

import (
	"net"
	"syscall"
	"testing"

	"golang.org/x/sys/windows"
)

// ipUnicastIF is IP_UNICAST_IF. Windows uses it to force a socket out of one
// interface; bindPhysical sets it so the engine's own dial to the node does not
// re-enter ProxyDomTun once the broker installs the /1 capture routes.
const ipUnicastIF = 31

// socketUnicastIF reads the option back off a live socket. Asserting on what the
// kernel actually holds is the point: bindPhysical returns nil having done
// nothing at all when physicalIF is zero, so a test that only checked the error
// would pass on a socket that was never bound.
func socketUnicastIF(t *testing.T, conn net.Conn) uint32 {
	t.Helper()
	raw, ok := conn.(interface {
		SyscallConn() (syscall.RawConn, error)
	})
	if !ok {
		t.Fatalf("%T is not a raw connection", conn)
	}
	rc, err := raw.SyscallConn()
	if err != nil {
		t.Fatal(err)
	}
	var got int
	var readErr error
	if err := rc.Control(func(fd uintptr) {
		got, readErr = windows.GetsockoptInt(windows.Handle(fd), windows.IPPROTO_IP, ipUnicastIF)
	}); err != nil {
		t.Fatal(err)
	}
	if readErr != nil {
		t.Fatal(readErr)
	}
	// Windows normalises this option to host order on read, so it comes back as
	// the index itself and needs no byte swap — measured, not assumed.
	return uint32(got)
}

// addressOnInterface answers with an IPv4 address of one interface, so a test
// can reach a listener that sits behind the interface being bound. Loopback is
// no good for that: a socket pinned to Ethernet cannot reach 127.0.0.1.
func addressOnInterface(t *testing.T, index uint32) string {
	t.Helper()
	iface, err := net.InterfaceByIndex(int(index))
	if err != nil {
		t.Fatal(err)
	}
	addrs, err := iface.Addrs()
	if err != nil {
		t.Fatal(err)
	}
	for _, addr := range addrs {
		ipnet, ok := addr.(*net.IPNet)
		if !ok {
			continue
		}
		if ip4 := ipnet.IP.To4(); ip4 != nil && !ip4.IsLoopback() {
			return ip4.String()
		}
	}
	return ""
}

// The interface has to be chosen before the capture routes exist, because
// afterwards the default route leads into the tunnel and the engine would dial
// itself. prepareOutsideDial is what picks it, and it is called from
// OpenNamedTun for exactly that reason.
func TestPrepareOutsideDialPicksAnInterface(t *testing.T) {
	physicalIF = 0
	t.Cleanup(func() { physicalIF = 0 })

	prepareOutsideDial()
	if physicalIF == 0 {
		t.Fatal("no interface was chosen, so every direct dial would follow the default route into the tunnel")
	}
	// The index has to name a real interface, or the option would be set to a
	// number the kernel does not know and the dial would fail.
	if _, err := net.InterfaceByIndex(int(physicalIF)); err != nil {
		t.Fatalf("ifindex %d is not an interface on this machine: %v", physicalIF, err)
	}
}

// The engine must never bind its own dial to its own adapter. If it does, the
// core's connection to the node goes back into the tunnel the core is carrying,
// which is a dial into itself.
//
// This is reachable without anything going wrong: a session that died before
// cleanup leaves ProxyDomTun up with its /1 routes, and the broker treats those
// as its own rather than as a foreign tunnel, so the next connect starts a core
// into exactly that state. GetBestInterfaceEx answers "the tunnel" there, which
// is why it is not the only input.
func TestTheChosenInterfaceIsNeverOurOwnAdapter(t *testing.T) {
	physicalIF = 0
	t.Cleanup(func() { physicalIF = 0 })

	prepareOutsideDial()
	if physicalIF == 0 {
		t.Skip("this machine has no default route, so there is no interface to choose")
	}
	if isTunAdapter(physicalIF) {
		iface, _ := net.InterfaceByIndex(int(physicalIF))
		t.Fatalf("the engine bound its own dial to %q (ifindex %d), so it would dial itself",
			iface.Name, physicalIF)
	}
}

// The forwarding table is the fallback for the case above, so it has to name an
// interface that is not ours. It reads real routes, so this asserts the property
// rather than a particular machine's numbers.
func TestTheDefaultRouteFallbackSkipsOurAdapters(t *testing.T) {
	idx := defaultRouteIndexOutside()
	if idx == 0 {
		t.Skip("this machine has no default route outside the tunnel")
	}
	if isTunAdapter(idx) {
		t.Fatalf("the fallback chose our own adapter, ifindex %d", idx)
	}
	if _, err := net.InterfaceByIndex(int(idx)); err != nil {
		t.Fatalf("the fallback chose ifindex %d, which is not an interface: %v", idx, err)
	}
}

// dialOutsideTun is what the VLESS outbound uses to reach the node. Without the
// binding its socket follows the default route, which after capture is the
// tunnel: the engine dials itself and the session hangs. So the option has to be
// on the socket the dialer produced, not merely intended.
func TestDialOutsideTunBindsTheSocketToThePhysicalInterface(t *testing.T) {
	physicalIF = 0
	prepareOutsideDial()
	t.Cleanup(func() { physicalIF = 0 })
	if physicalIF == 0 {
		t.Skip("this machine has no default route, so there is no interface to bind")
	}
	host := addressOnInterface(t, physicalIF)
	if host == "" {
		t.Skipf("ifindex %d carries no IPv4 address to reach", physicalIF)
	}

	listener, err := net.Listen("tcp", net.JoinHostPort(host, "0"))
	if err != nil {
		t.Skipf("cannot listen on %s: %v", host, err)
	}
	defer func() { _ = listener.Close() }()
	go func() {
		conn, acceptErr := listener.Accept()
		if acceptErr == nil {
			_ = conn.Close()
		}
	}()

	conn, err := dialOutsideTun("tcp", listener.Addr().String())
	if err != nil {
		t.Fatalf("dialOutsideTun failed: %v", err)
	}
	defer func() { _ = conn.Close() }()

	if got := socketUnicastIF(t, conn); got != physicalIF {
		t.Fatalf("the socket is bound to ifindex %d, want %d", got, physicalIF)
	}
}

// With no interface chosen the option is deliberately left alone, and the socket
// must still work. That is the state the engine starts in: the Hy2 path calls
// prepareOutsideDial from Start, and a dial made before it must not fail for
// want of a binding.
func TestDialOutsideTunWorksBeforeAnInterfaceIsChosen(t *testing.T) {
	physicalIF = 0
	t.Cleanup(func() { physicalIF = 0 })

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = listener.Close() }()
	go func() {
		conn, acceptErr := listener.Accept()
		if acceptErr == nil {
			_ = conn.Close()
		}
	}()

	conn, err := dialOutsideTun("tcp", listener.Addr().String())
	if err != nil {
		t.Fatalf("an unbound direct dial must still work: %v", err)
	}
	defer func() { _ = conn.Close() }()

	if got := socketUnicastIF(t, conn); got != 0 {
		t.Fatalf("an unbound socket reports ifindex %d, want 0", got)
	}
}
