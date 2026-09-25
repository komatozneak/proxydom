package hy2bind

import (
	"bytes"
	"context"
	"encoding/binary"
	"net"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/apernet/hysteria/core/v2/client"
	"gvisor.dev/gvisor/pkg/buffer"
	"gvisor.dev/gvisor/pkg/tcpip"
	"gvisor.dev/gvisor/pkg/tcpip/checksum"
	"gvisor.dev/gvisor/pkg/tcpip/header"
	"gvisor.dev/gvisor/pkg/tcpip/link/channel"
	"gvisor.dev/gvisor/pkg/tcpip/stack"
)

func TestAndroidLogPriorityMapsZapLevels(t *testing.T) {
	if androidLogPriority(-1) != androidLogDebug {
		t.Fatal("debug")
	}
	if androidLogPriority(0) != androidLogInfo {
		t.Fatal("info")
	}
	if androidLogPriority(1) != androidLogWarn {
		t.Fatal("warn")
	}
	if androidLogPriority(2) != androidLogError {
		t.Fatal("error")
	}
}

func TestBuildICMPv4PortUnreachable(t *testing.T) {
	raw := ipv4UDPPacket(
		net.IPv4(10, 255, 255, 1),
		net.IPv4(142, 251, 20, 119),
		40000,
		443,
	)
	icmp := buildICMPv4PortUnreachable(raw[:header.IPv4MinimumSize], raw[header.IPv4MinimumSize:header.IPv4MinimumSize+8])
	if icmp == nil {
		t.Fatal("nil icmp")
	}
	ip := header.IPv4(icmp)
	if !ip.IsValid(len(icmp)) {
		t.Fatalf("invalid ipv4 len=%d", len(icmp))
	}
	if checksum.Checksum(icmp[:ip.HeaderLength()], 0) != 0xffff {
		t.Fatal("ip checksum")
	}
	if ip.Protocol() != uint8(header.ICMPv4ProtocolNumber) {
		t.Fatalf("proto %d", ip.Protocol())
	}
	srcAddr := ip.SourceAddress()
	dstAddr := ip.DestinationAddress()
	if !bytes.Equal(srcAddr.AsSlice(), []byte{142, 251, 20, 119}) ||
		!bytes.Equal(dstAddr.AsSlice(), []byte{10, 255, 255, 1}) {
		t.Fatalf("addrs %s -> %s", srcAddr, dstAddr)
	}
	body := header.ICMPv4(icmp[ip.HeaderLength():])
	if body.Type() != header.ICMPv4DstUnreachable || body.Code() != header.ICMPv4PortUnreachable {
		t.Fatalf("type/code %d/%d", body.Type(), body.Code())
	}
	if checksum.Checksum(icmp[ip.HeaderLength():], 0) != 0xffff {
		t.Fatal("icmp checksum")
	}
	if buildICMPv4PortUnreachable(nil, nil) != nil {
		t.Fatal("short header should be nil")
	}
}

func TestDNSInflightDedupAndCache(t *testing.T) {
	dnsCacheClear()
	t.Cleanup(dnsCacheClear)

	var opened atomic.Int32
	var mu sync.Mutex
	var upstream *scriptUDP
	opener := func() (client.HyUDPConn, error) {
		opened.Add(1)
		u := newScriptUDP()
		mu.Lock()
		upstream = u
		mu.Unlock()
		return u, nil
	}
	c1 := newLazyHyPacketConn(opener, &net.UDPAddr{IP: net.IPv4(10, 255, 255, 1), Port: 41000}, "1.1.1.1:53", true)
	c2 := newLazyHyPacketConn(opener, &net.UDPAddr{IP: net.IPv4(10, 255, 255, 1), Port: 41001}, "1.1.1.1:53", true)
	defer c1.Close()
	defer c2.Close()

	r1 := readPacket(c1)
	r2 := readPacket(c2)
	q1 := testDNSQuery(0x1111, "example.com")
	q2 := testDNSQuery(0x2222, "example.com")
	if _, err := c1.WriteTo(q1, nil); err != nil {
		t.Fatal(err)
	}
	if _, err := c2.WriteTo(q2, nil); err != nil {
		t.Fatal(err)
	}
	if opened.Load() != 1 {
		t.Fatalf("hy2 udp sessions %d, want 1", opened.Load())
	}
	mu.Lock()
	up := upstream
	mu.Unlock()
	if up == nil || up.sends.Load() != 1 {
		t.Fatalf("sends %v", up)
	}

	up.push(testDNSResponse(q1, net.IPv4(1, 2, 3, 4), 30))
	a := <-r1
	b := <-r2
	if a.err != nil || b.err != nil {
		t.Fatalf("read %v %v", a.err, b.err)
	}
	if id := binary.BigEndian.Uint16(a.b[:2]); id != 0x1111 {
		t.Fatalf("leader id %x", id)
	}
	if id := binary.BigEndian.Uint16(b.b[:2]); id != 0x2222 {
		t.Fatalf("joiner id %x", id)
	}

	c3 := newLazyHyPacketConn(opener, &net.UDPAddr{IP: net.IPv4(10, 255, 255, 1), Port: 41002}, "1.1.1.1:53", true)
	defer c3.Close()
	r3 := readPacket(c3)
	q3 := testDNSQuery(0x3333, "example.com")
	if _, err := c3.WriteTo(q3, nil); err != nil {
		t.Fatal(err)
	}
	if opened.Load() != 1 {
		t.Fatalf("cache hit opened another session: %d", opened.Load())
	}
	c := <-r3
	if c.err != nil {
		t.Fatal(c.err)
	}
	if id := binary.BigEndian.Uint16(c.b[:2]); id != 0x3333 {
		t.Fatalf("cached id %x", id)
	}
}

func TestDNSDistinctNamesBothSend(t *testing.T) {
	dnsCacheClear()
	t.Cleanup(dnsCacheClear)
	var opened atomic.Int32
	opener := func() (client.HyUDPConn, error) {
		opened.Add(1)
		return newScriptUDP(), nil
	}
	c1 := newLazyHyPacketConn(opener, &net.UDPAddr{Port: 1}, "1.1.1.1:53", true)
	c2 := newLazyHyPacketConn(opener, &net.UDPAddr{Port: 2}, "1.1.1.1:53", true)
	defer c1.Close()
	defer c2.Close()
	if _, err := c1.WriteTo(testDNSQuery(1, "a.example"), nil); err != nil {
		t.Fatal(err)
	}
	if _, err := c2.WriteTo(testDNSQuery(2, "b.example"), nil); err != nil {
		t.Fatal(err)
	}
	if opened.Load() != 2 {
		t.Fatalf("opens %d", opened.Load())
	}
}

func TestDNSCacheTTLClamps(t *testing.T) {
	q := testDNSQuery(1, "example.com")
	resp := testDNSResponse(q, net.IPv4(1, 2, 3, 4), 0)
	if dnsCacheTTL(resp) != dnsTTLMin {
		t.Fatalf("zero ttl %s", dnsCacheTTL(resp))
	}
	long := testDNSResponse(q, net.IPv4(1, 2, 3, 4), 86400)
	if dnsCacheTTL(long) != dnsTTLMax {
		t.Fatalf("long ttl %s", dnsCacheTTL(long))
	}
	nx := append([]byte(nil), q...)
	nx[2] |= 0x80
	nx[3] = (nx[3] & 0xf0) | 3
	if dnsCacheTTL(nx) != dnsNegTTL {
		t.Fatalf("nxdomain %s", dnsCacheTTL(nx))
	}
}

type packetRead struct {
	b   []byte
	err error
}

func readPacket(c *hyPacketConn) <-chan packetRead {
	ch := make(chan packetRead, 1)
	go func() {
		_ = c.SetReadDeadline(time.Now().Add(2 * time.Second))
		buf := make([]byte, 512)
		n, _, err := c.ReadFrom(buf)
		if err != nil {
			ch <- packetRead{err: err}
			return
		}
		ch <- packetRead{b: append([]byte(nil), buf[:n]...)}
	}()
	return ch
}

type scriptUDP struct {
	recv  chan []byte
	sends atomic.Int32
	once  sync.Once
}

func newScriptUDP() *scriptUDP {
	return &scriptUDP{recv: make(chan []byte, 1)}
}

func (s *scriptUDP) push(b []byte) { s.recv <- append([]byte(nil), b...) }

func (s *scriptUDP) Receive() ([]byte, string, error) {
	b, ok := <-s.recv
	if !ok {
		return nil, "", net.ErrClosed
	}
	return b, "1.1.1.1:53", nil
}

func (s *scriptUDP) Send([]byte, string) error {
	s.sends.Add(1)
	return nil
}

func (s *scriptUDP) Close() error {
	s.once.Do(func() { close(s.recv) })
	return nil
}

func testDNSQuery(id uint16, host string) []byte {
	var qname []byte
	for _, lab := range splitHost(host) {
		qname = append(qname, byte(len(lab)))
		qname = append(qname, lab...)
	}
	qname = append(qname, 0)
	msg := make([]byte, 12+len(qname)+4)
	binary.BigEndian.PutUint16(msg[0:2], id)
	binary.BigEndian.PutUint16(msg[2:4], 0x0100)
	binary.BigEndian.PutUint16(msg[4:6], 1)
	copy(msg[12:], qname)
	off := 12 + len(qname)
	binary.BigEndian.PutUint16(msg[off:off+2], 1)
	binary.BigEndian.PutUint16(msg[off+2:off+4], 1)
	return msg
}

func testDNSResponse(query []byte, ip net.IP, ttl uint32) []byte {
	msg := append([]byte(nil), query...)
	msg[2] |= 0x80
	binary.BigEndian.PutUint16(msg[6:8], 1)
	ans := []byte{0xC0, 0x0C, 0x00, 0x01, 0x00, 0x01}
	tb := make([]byte, 4)
	binary.BigEndian.PutUint32(tb, ttl)
	ans = append(ans, tb...)
	ans = append(ans, 0, 4)
	ans = append(ans, ip.To4()...)
	return append(msg, ans...)
}

func splitHost(host string) []string {
	var out []string
	start := 0
	for i := 0; i < len(host); i++ {
		if host[i] == '.' {
			out = append(out, host[start:i])
			start = i + 1
		}
	}
	return append(out, host[start:])
}

func TestQuicRejectWritesICMP(t *testing.T) {
	ep := channel.New(8, 1500, "")
	st, err := createTunStack(ep)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		st.Close()
		st.Wait()
		ep.Close()
	})
	raw := ipv4UDPPacket(
		net.IPv4(10, 255, 255, 1),
		net.IPv4(142, 251, 20, 119),
		40000,
		443,
	)
	pkt := stack.NewPacketBuffer(stack.PacketBufferOptions{
		Payload: buffer.MakeWithData(raw),
	})
	ep.InjectInbound(header.IPv4ProtocolNumber, pkt)
	pkt.DecRef()

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	out := ep.ReadContext(ctx)
	got := pktBytes(out)
	if len(got) < header.IPv4MinimumSize || got[9] != uint8(header.ICMPv4ProtocolNumber) {
		t.Fatalf("want ICMP port unreachable, got %x", got)
	}
	if !bytes.Equal(got[12:16], []byte{142, 251, 20, 119}) {
		t.Fatalf("icmp src %v", got[12:16])
	}
	if got[header.IPv4MinimumSize] != uint8(header.ICMPv4DstUnreachable) ||
		got[header.IPv4MinimumSize+1] != uint8(header.ICMPv4PortUnreachable) {
		t.Fatalf("icmp type/code %d/%d", got[header.IPv4MinimumSize], got[header.IPv4MinimumSize+1])
	}
}

func ipv4UDPPacket(src, dst net.IP, sport, dport uint16) []byte {
	payload := []byte{1}
	udpLen := header.UDPMinimumSize + len(payload)
	total := header.IPv4MinimumSize + udpLen
	raw := make([]byte, total)
	var src4, dst4 [4]byte
	copy(src4[:], src.To4())
	copy(dst4[:], dst.To4())
	ip := header.IPv4(raw)
	ip.Encode(&header.IPv4Fields{
		TotalLength: uint16(total),
		TTL:         64,
		Protocol:    uint8(header.UDPProtocolNumber),
		SrcAddr:     tcpip.AddrFrom4(src4),
		DstAddr:     tcpip.AddrFrom4(dst4),
	})
	ip.SetChecksum(^ip.CalculateChecksum())
	u := header.UDP(raw[header.IPv4MinimumSize:])
	u.Encode(&header.UDPFields{
		SrcPort: sport,
		DstPort: dport,
		Length:  uint16(udpLen),
	})
	copy(u.Payload(), payload)
	return raw
}
