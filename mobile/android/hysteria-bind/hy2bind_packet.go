package hy2bind

import (
	"context"
	"fmt"
	"log"

	"github.com/xjasonlyu/tun2socks/v2/tunnel"
	"gvisor.dev/gvisor/pkg/buffer"
	"gvisor.dev/gvisor/pkg/tcpip/header"
	"gvisor.dev/gvisor/pkg/tcpip/link/channel"
	"gvisor.dev/gvisor/pkg/tcpip/stack"
)

// PacketWriter is implemented in Swift (NEPacketTunnelFlow.writePackets).
// gomobile bind requires an interface, not a func.
type PacketWriter interface {
	WritePacket(packet []byte) error
}

type packetDevice struct {
	*channel.Endpoint
}

func (d *packetDevice) Name() string { return "packetflow" }
func (d *packetDevice) Type() string { return "packetflow" }

func (d *packetDevice) WriteNotify() {
	for {
		pkt := d.Endpoint.Read()
		if pkt == nil {
			return
		}
		out := pktBytes(pkt)
		pkt.DecRef()
		mu.Lock()
		w := packetWriter
		mu.Unlock()
		if w == nil || len(out) == 0 {
			continue
		}
		if err := w.WritePacket(out); err != nil {
			log.Printf("hy2bind packet write: %v", err)
		}
	}
}

var (
	packetWriter PacketWriter
	packetEp     *channel.Endpoint
	packetCancel context.CancelFunc
)

// SetPacketWriter installs the iOS packetFlow sink for gVisor outbound IP.
func SetPacketWriter(w PacketWriter) {
	mu.Lock()
	defer mu.Unlock()
	packetWriter = w
}

// StartPacketTun attaches a userspace (no TUN fd) gVisor stack for iOS
// NEPacketTunnelFlow. Call after Start. Does not change Android StartTun(fd).
func StartPacketTun(mtu int) string {
	if mtu <= 0 {
		mtu = 1280
	}
	mu.Lock()
	defer mu.Unlock()
	if tunStk != nil {
		return "tun already running"
	}
	if hyClient == nil {
		return "hy2 not started"
	}

	ep := channel.New(512, uint32(mtu), "")
	dev := &packetDevice{Endpoint: ep}
	ep.AddNotify(dev)

	tunnel.T().SetDialer(&hyDialer{c: hyClient})
	st, err := createTunStack(ep)
	if err != nil {
		ep.Close()
		return fmt.Sprintf("packet tun stack: %v", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	packetEp = ep
	packetCancel = cancel
	tunDev = dev
	tunStk = st
	go drainOutbound(ctx, ep)
	log.Printf("hy2bind packet tun started mtu=%d", mtu)
	return ""
}

// InjectPacket delivers one IPv4/IPv6 packet from Swift packetFlow into gVisor.
func InjectPacket(packet []byte) string {
	if len(packet) < 1 {
		return "empty packet"
	}
	mu.Lock()
	ep := packetEp
	mu.Unlock()
	if ep == nil {
		return "packet tun not started"
	}
	proto := header.IPv4ProtocolNumber
	if packet[0]>>4 == 6 {
		proto = header.IPv6ProtocolNumber
	}
	copyBuf := append([]byte(nil), packet...)
	pkt := stack.NewPacketBuffer(stack.PacketBufferOptions{
		Payload: buffer.MakeWithData(copyBuf),
	})
	ep.InjectInbound(proto, pkt)
	pkt.DecRef()
	return ""
}

func drainOutbound(ctx context.Context, ep *channel.Endpoint) {
	for {
		pkt := ep.ReadContext(ctx)
		if pkt == nil {
			return
		}
		out := pktBytes(pkt)
		pkt.DecRef()
		mu.Lock()
		w := packetWriter
		mu.Unlock()
		if w == nil || len(out) == 0 {
			continue
		}
		if err := w.WritePacket(out); err != nil {
			log.Printf("hy2bind packet write: %v", err)
		}
	}
}

func pktBytes(pkt *stack.PacketBuffer) []byte {
	if pkt == nil {
		return nil
	}
	buf := pkt.ToBuffer()
	flat := buf.Flatten()
	out := append([]byte(nil), flat...)
	buf.Release()
	return out
}

func stopPacketTunLocked() {
	cancel := packetCancel
	packetCancel = nil
	packetEp = nil
	packetWriter = nil
	if cancel != nil {
		cancel()
	}
}
