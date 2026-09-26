package hy2bind

import (
	"fmt"
	"sync"
	"sync/atomic"
	"time"

	"github.com/xjasonlyu/tun2socks/v2/core"
	"github.com/xjasonlyu/tun2socks/v2/core/option"
	t2log "github.com/xjasonlyu/tun2socks/v2/log"
	"github.com/xjasonlyu/tun2socks/v2/tunnel"
	"gvisor.dev/gvisor/pkg/buffer"
	"gvisor.dev/gvisor/pkg/tcpip/adapters/gonet"
	"gvisor.dev/gvisor/pkg/tcpip/header"
	"gvisor.dev/gvisor/pkg/tcpip/stack"
	"gvisor.dev/gvisor/pkg/tcpip/transport/udp"
	"gvisor.dev/gvisor/pkg/waiter"
)

// pauseEndpoint delays the inner read loop until installUDPForwarder has
// replaced tun2socks' handler. Otherwise the first QUIC datagrams are
// accepted and only a later retransmit sees the reset.
type pauseEndpoint struct {
	stack.LinkEndpoint
	mu    sync.Mutex
	pause bool
	disp  stack.NetworkDispatcher
}

func (e *pauseEndpoint) Attach(d stack.NetworkDispatcher) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.pause {
		e.disp = d
		return
	}
	e.disp = d
	e.LinkEndpoint.Attach(d)
}

func (e *pauseEndpoint) IsAttached() bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.disp != nil
}

func (e *pauseEndpoint) resume() {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.pause = false
	if e.disp != nil {
		e.LinkEndpoint.Attach(e.disp)
	}
}

func createTunStack(ep stack.LinkEndpoint) (*stack.Stack, error) {
	paused := &pauseEndpoint{LinkEndpoint: ep, pause: true}
	st, err := core.CreateStack(&core.Config{
		LinkEndpoint:     paused,
		TransportHandler: tunnel.T(),
		Options: []option.Option{
			option.WithTCPModerateReceiveBuffer(true),
		},
	})
	if err != nil {
		return nil, err
	}
	installUDPForwarder(st)
	paused.resume()
	return st, nil
}

// installUDPForwarder answers UDP/443 with ICMP port unreachable before
// tun2socks dials. DialUDP's error only closes the accepted socket, so the
// first QUIC packet is eaten and Cronet waits out a PTO (about 300–800ms).
func installUDPForwarder(s *stack.Stack) {
	fwd := udp.NewForwarder(s, func(r *udp.ForwarderRequest) {
		var wq waiter.Queue
		ep, err := r.CreateEndpoint(&wq)
		if err != nil {
			return
		}
		id := r.ID()
		tunnel.T().HandleUDP(&stackUDP{
			UDPConn: gonet.NewUDPConn(&wq, ep),
			id:      id,
		})
	})
	s.SetTransportProtocolHandler(udp.ProtocolNumber, func(id stack.TransportEndpointID, pkt *stack.PacketBuffer) bool {
		if id.LocalPort == 443 {
			rejectQuicUDP(s, id, pkt)
			return true
		}
		return fwd.HandlePacket(id, pkt)
	})
}

type stackUDP struct {
	*gonet.UDPConn
	id stack.TransportEndpointID
}

func (c *stackUDP) ID() *stack.TransportEndpointID { return &c.id }

var quicRejectLogAt atomic.Int64

func noteQuicReject(dst string) {
	now := time.Now().UnixNano()
	prev := quicRejectLogAt.Load()
	if prev != 0 && now-prev < int64(time.Second) {
		return
	}
	if !quicRejectLogAt.CompareAndSwap(prev, now) {
		return
	}
	// Debug: a page load is dozens of these. Warn flooded logcat.
	t2log.Debugf("[UDP] dial %s: quic-reject", dst)
}

func rejectQuicUDP(s *stack.Stack, id stack.TransportEndpointID, pkt *stack.PacketBuffer) {
	noteQuicReject(fmt.Sprintf("%s:%d", id.LocalAddress, id.LocalPort))
	if pkt.NetworkProtocolNumber != header.IPv4ProtocolNumber {
		return
	}
	raw := buildICMPv4PortUnreachable(pkt.NetworkHeader().Slice(), pkt.TransportHeader().Slice())
	if raw == nil {
		return
	}
	_ = s.WriteRawPacket(pkt.NICID, header.IPv4ProtocolNumber, buffer.MakeWithData(raw))
}

// buildICMPv4PortUnreachable quotes the original IPv4 header and the first
// 8 bytes of UDP, then swaps the addresses (RFC 792, code 3).
func buildICMPv4PortUnreachable(netHdr, transHdr []byte) []byte {
	if len(netHdr) < header.IPv4MinimumSize {
		return nil
	}
	orig := header.IPv4(netHdr)
	ipHdrLen := int(orig.HeaderLength())
	if ipHdrLen < header.IPv4MinimumSize || ipHdrLen > len(netHdr) {
		return nil
	}
	quote := append([]byte(nil), netHdr[:ipHdrLen]...)
	n := 8
	if len(transHdr) < n {
		n = len(transHdr)
	}
	if n > 0 {
		quote = append(quote, transHdr[:n]...)
	}
	icmpLen := header.ICMPv4MinimumSize + len(quote)
	raw := make([]byte, header.IPv4MinimumSize+icmpLen)
	icmp := header.ICMPv4(raw[header.IPv4MinimumSize:])
	icmp.SetType(header.ICMPv4DstUnreachable)
	icmp.SetCode(header.ICMPv4PortUnreachable)
	copy(icmp.Payload(), quote)
	icmp.SetChecksum(header.ICMPv4Checksum(icmp, 0))

	ip := header.IPv4(raw)
	ip.Encode(&header.IPv4Fields{
		TotalLength: uint16(len(raw)),
		TTL:         64,
		Protocol:    uint8(header.ICMPv4ProtocolNumber),
		SrcAddr:     orig.DestinationAddress(),
		DstAddr:     orig.SourceAddress(),
	})
	ip.SetChecksum(^ip.CalculateChecksum())
	return raw
}
