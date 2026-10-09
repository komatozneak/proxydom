//go:build windows

package hy2bind

import (
	"fmt"
	"log"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/xjasonlyu/tun2socks/v2/core/device/tun"
	"github.com/xjasonlyu/tun2socks/v2/tunnel"
	"gvisor.dev/gvisor/pkg/tcpip"
	"gvisor.dev/gvisor/pkg/tcpip/header"
	"gvisor.dev/gvisor/pkg/tcpip/stack"
)

// tunStats counts what the adapter actually hands to the stack and what the
// stack writes back. A route Windows refuses to use reads as rx=0, which tells
// a routing failure apart from a proxy failure without guessing.
type tunStats struct {
	rx    atomic.Uint64
	tx    atomic.Uint64
	mu    sync.Mutex
	hosts []string
}

func (s *tunStats) note(pkt *stack.PacketBuffer) {
	s.rx.Add(1)
	hdr := pkt.NetworkHeader().Slice()
	if len(hdr) < header.IPv4MinimumSize || header.IPVersion(hdr) != header.IPv4Version {
		return
	}
	text := header.IPv4(hdr).DestinationAddress().String()
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, seen := range s.hosts {
		if seen == text {
			return
		}
	}
	if len(s.hosts) < 4 {
		s.hosts = append(s.hosts, text)
	}
}

func (s *tunStats) summary() string {
	s.mu.Lock()
	hosts := strings.Join(s.hosts, ",")
	s.mu.Unlock()
	return fmt.Sprintf("tun rx=%d tx=%d dst=%s", s.rx.Load(), s.tx.Load(), hosts)
}

// countedEndpoint forwards to the wintun endpoint and counts both directions.
type countedEndpoint struct {
	stack.LinkEndpoint
	stats *tunStats
}

func (e *countedEndpoint) WritePackets(pkts stack.PacketBufferList) (int, tcpip.Error) {
	n, err := e.LinkEndpoint.WritePackets(pkts)
	e.stats.tx.Add(uint64(n))
	return n, err
}

func (e *countedEndpoint) Attach(d stack.NetworkDispatcher) {
	e.LinkEndpoint.Attach(&countingDispatcher{NetworkDispatcher: d, stats: e.stats})
}

type countingDispatcher struct {
	stack.NetworkDispatcher
	stats *tunStats
}

func (d *countingDispatcher) DeliverNetworkPacket(protocol tcpip.NetworkProtocolNumber,
	pkt *stack.PacketBuffer) {
	d.stats.note(pkt)
	d.NetworkDispatcher.DeliverNetworkPacket(protocol, pkt)
}

// OpenNamedTun creates or opens the wintun adapter and leaves it unconfigured.
//
// The address must be assigned before StartTunStack. The gVisor read loop
// (iobased.dispatchLoop) breaks out for good on the first read error and Attach
// is guarded by sync.Once, so reconfiguring the adapter while it is already
// reading leaves a tunnel that exists, is up, carries an address and a route,
// and still never hands a packet to the stack. Windows reports that as host
// unreachable, which is what the broker's egress probe saw.
func OpenNamedTun(name string, mtu int) string {
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
	if tunDev != nil {
		return "tun already open"
	}
	if hyClient == nil {
		return "hy2 not started"
	}
	dev, err := tun.Open(name, uint32(mtu))
	if err != nil {
		return fmt.Sprintf("tun open: %v", err)
	}
	tunDev = dev
	return ""
}

// StartTunStack binds the configured adapter to the gVisor stack and starts
// reading. Call it only after the address is assigned: this is the point of no
// return for the read loop.
func StartTunStack() string {
	mu.Lock()
	defer mu.Unlock()
	if tunStk != nil {
		return "tun already running"
	}
	if tunDev == nil {
		return "tun not open"
	}
	if hyClient == nil {
		return "hy2 not started"
	}
	stats := &tunStats{}
	tunnel.T().SetProxy(&hyDialer{c: hyClient})
	st, err := createTunStack(&countedEndpoint{LinkEndpoint: tunDev, stats: stats})
	if err != nil {
		return fmt.Sprintf("tun stack: %v", err)
	}
	tunStk = st
	go reportTunStats(stats)
	return ""
}

// reportTunStats keeps saying what the adapter delivers until something
// arrives, then stops. It speaks at once and often: the broker gives the
// canary about a second, and a first line after a one second sleep landed in
// the journal too late to be read.
func reportTunStats(stats *tunStats) {
	log.Printf("%s", stats.summary())
	for i := 0; i < 120; i++ {
		time.Sleep(250 * time.Millisecond)
		if stats.rx.Load() > 0 {
			return
		}
		log.Printf("%s", stats.summary())
	}
}
