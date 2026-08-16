package hy2bind

import (
	"encoding/binary"
	"net"
	"net/netip"
	"testing"
)

func encodeDNSName(labels ...string) []byte {
	var b []byte
	for _, l := range labels {
		b = append(b, byte(len(l)))
		b = append(b, l...)
	}
	return append(b, 0)
}

func dnsHeader(id uint16, flags uint16, qd, an, ns, ar uint16) []byte {
	h := make([]byte, 12)
	binary.BigEndian.PutUint16(h[0:2], id)
	binary.BigEndian.PutUint16(h[2:4], flags)
	binary.BigEndian.PutUint16(h[4:6], qd)
	binary.BigEndian.PutUint16(h[6:8], an)
	binary.BigEndian.PutUint16(h[8:10], ns)
	binary.BigEndian.PutUint16(h[10:12], ar)
	return h
}

func aAnswer(nameOff uint16, ip net.IP) []byte {
	rr := []byte{0xC0, byte(nameOff)}
	rr = binary.BigEndian.AppendUint16(rr, dnsTypeA)
	rr = binary.BigEndian.AppendUint16(rr, 1) // IN
	rr = binary.BigEndian.AppendUint32(rr, 60)
	rr = binary.BigEndian.AppendUint16(rr, 4)
	rr = append(rr, ip.To4()...)
	return rr
}

func buildAResponse(ips ...net.IP) []byte {
	qname := encodeDNSName("googlevideo", "com")
	msg := dnsHeader(0x1234, 0x8180, 1, uint16(len(ips)), 0, 0)
	msg = append(msg, qname...)
	msg = binary.BigEndian.AppendUint16(msg, dnsTypeA)
	msg = binary.BigEndian.AppendUint16(msg, 1)
	nameOff := uint16(12)
	for _, ip := range ips {
		msg = append(msg, aAnswer(nameOff, ip)...)
	}
	return msg
}

func collectA(msg []byte) []netip.Addr {
	if len(msg) < 12 {
		return nil
	}
	qd := int(binary.BigEndian.Uint16(msg[4:6]))
	an := int(binary.BigEndian.Uint16(msg[6:8]))
	off := 12
	var err error
	for i := 0; i < qd; i++ {
		off, err = skipDNSName(msg, off)
		if err != nil {
			return nil
		}
		off += 4
	}
	var out []netip.Addr
	for i := 0; i < an; i++ {
		off, err = skipDNSName(msg, off)
		if err != nil || off+10 > len(msg) {
			return nil
		}
		typ := binary.BigEndian.Uint16(msg[off : off+2])
		rdlen := int(binary.BigEndian.Uint16(msg[off+8 : off+10]))
		rdata := msg[off+10 : off+10+rdlen]
		off += 10 + rdlen
		if typ == dnsTypeA && len(rdata) == 4 {
			ip, _ := netip.AddrFromSlice(rdata)
			out = append(out, ip)
		}
	}
	return out
}

func TestFilterDNSResponseMixedKeepsGood(t *testing.T) {
	bad := net.ParseIP("211.114.64.205")
	good := net.ParseIP("142.250.185.14")
	in := buildAResponse(bad, good)
	out := filterDNSResponse(in)
	got := collectA(out)
	if len(got) != 1 || got[0].String() != "142.250.185.14" {
		t.Fatalf("got %v", got)
	}
	if binary.BigEndian.Uint16(out[6:8]) != 1 {
		t.Fatalf("ancount %d", binary.BigEndian.Uint16(out[6:8]))
	}
}

func TestFilterDNSResponseAllBadNODATA(t *testing.T) {
	in := buildAResponse(
		net.ParseIP("211.114.64.205"),
		net.ParseIP("59.18.35.215"),
	)
	out := filterDNSResponse(in)
	if binary.BigEndian.Uint16(out[6:8]) != 0 {
		t.Fatalf("want NODATA ancount=0 got %d", binary.BigEndian.Uint16(out[6:8]))
	}
	if got := collectA(out); len(got) != 0 {
		t.Fatalf("answers %v", got)
	}
	// Questions still present so the resolver can retry.
	if binary.BigEndian.Uint16(out[4:6]) != 1 {
		t.Fatal("qdcount")
	}
}

func TestFilterDNSResponseTruncatedFailOpen(t *testing.T) {
	in := buildAResponse(net.ParseIP("211.114.64.205"), net.ParseIP("142.250.185.14"))
	trunc := in[:len(in)-3]
	out := filterDNSResponse(trunc)
	if string(out) != string(trunc) {
		t.Fatal("truncated payload must pass through unchanged")
	}
}

func TestFilterDNSResponseQueryUntouched(t *testing.T) {
	qname := encodeDNSName("example", "com")
	msg := dnsHeader(0x1, 0x0100, 1, 0, 0, 0) // query, QR=0
	msg = append(msg, qname...)
	msg = binary.BigEndian.AppendUint16(msg, dnsTypeA)
	msg = binary.BigEndian.AppendUint16(msg, 1)
	out := filterDNSResponse(msg)
	if string(out) != string(msg) {
		t.Fatal("queries must not be rewritten")
	}
}

func TestHyPacketConnFiltersDNS(t *testing.T) {
	orig := &net.UDPAddr{IP: net.ParseIP("10.255.255.2").To4(), Port: 53}
	u := &fakeUDPConn{recv: make(chan udpMsg, 1)}
	pc := newHyPacketConn(u, orig, "1.1.1.1:53", true)
	defer pc.Close()
	in := buildAResponse(net.ParseIP("59.18.35.215"), net.ParseIP("142.250.185.14"))
	u.recv <- udpMsg{b: in, addr: "1.1.1.1:53"}
	buf := make([]byte, 512)
	n, _, err := pc.ReadFrom(buf)
	if err != nil {
		t.Fatal(err)
	}
	got := collectA(buf[:n])
	if len(got) != 1 || got[0].String() != "142.250.185.14" {
		t.Fatalf("filtered %v", got)
	}
}

func TestFilterDNSResponseAdditionalA(t *testing.T) {
	qname := encodeDNSName("googlevideo", "com")
	good := net.ParseIP("142.250.185.14")
	bad := net.ParseIP("211.114.64.205")
	msg := dnsHeader(0x22, 0x8180, 1, 1, 0, 1)
	msg = append(msg, qname...)
	msg = binary.BigEndian.AppendUint16(msg, dnsTypeA)
	msg = binary.BigEndian.AppendUint16(msg, 1)
	msg = append(msg, aAnswer(12, good)...)
	msg = append(msg, aAnswer(12, bad)...)
	out := filterDNSResponse(msg)
	if binary.BigEndian.Uint16(out[10:12]) != 0 {
		t.Fatalf("additional bad A must be stripped, arcount=%d", binary.BigEndian.Uint16(out[10:12]))
	}
	if got := collectA(out); len(got) != 1 || got[0].String() != "142.250.185.14" {
		t.Fatalf("got %v", got)
	}
}

func TestFilterHTTPSIPv4Hint(t *testing.T) {
	qname := encodeDNSName("googlevideo", "com")
	msg := dnsHeader(0x33, 0x8180, 1, 1, 0, 0)
	msg = append(msg, qname...)
	msg = binary.BigEndian.AppendUint16(msg, dnsTypeHTTPS)
	msg = binary.BigEndian.AppendUint16(msg, 1)
	nameOff := uint16(12)
	rdata := []byte{0, 1} // priority 1
	rdata = append(rdata, 0xC0, byte(nameOff))
	// ipv4hint: bad + good
	rdata = binary.BigEndian.AppendUint16(rdata, svcIPv4Hint)
	rdata = binary.BigEndian.AppendUint16(rdata, 8)
	rdata = append(rdata, net.ParseIP("59.18.35.215").To4()...)
	rdata = append(rdata, net.ParseIP("142.250.185.14").To4()...)
	rr := []byte{0xC0, byte(nameOff)}
	rr = binary.BigEndian.AppendUint16(rr, dnsTypeHTTPS)
	rr = binary.BigEndian.AppendUint16(rr, 1)
	rr = binary.BigEndian.AppendUint32(rr, 60)
	rr = binary.BigEndian.AppendUint16(rr, uint16(len(rdata)))
	rr = append(rr, rdata...)
	msg = append(msg, rr...)

	out := filterDNSResponse(msg)
	if binary.BigEndian.Uint16(out[6:8]) != 1 {
		t.Fatal("HTTPS RR must be kept")
	}
	_, nameEnd, err := parseFirstAnswerMeta(out)
	if err != nil {
		t.Fatal(err)
	}
	rdlen := int(binary.BigEndian.Uint16(out[nameEnd+8 : nameEnd+10]))
	rdataOff := nameEnd + 10
	hints := collectIPv4HintsFromMsg(out, rdataOff, rdlen)
	if len(hints) != 1 || hints[0].String() != "142.250.185.14" {
		t.Fatalf("ipv4hint %v", hints)
	}
}

func parseFirstAnswerMeta(msg []byte) (start, nameEnd int, err error) {
	qd := int(binary.BigEndian.Uint16(msg[4:6]))
	off := 12
	for i := 0; i < qd; i++ {
		off, err = skipDNSName(msg, off)
		if err != nil {
			return 0, 0, err
		}
		off += 4
	}
	start = off
	nameEnd, err = skipDNSName(msg, off)
	return start, nameEnd, err
}

func collectIPv4HintsFromMsg(msg []byte, rdataOff, rdlen int) []netip.Addr {
	end := rdataOff + rdlen
	nameEnd, err := skipDNSName(msg, rdataOff+2)
	if err != nil {
		return nil
	}
	off := nameEnd
	var out []netip.Addr
	for off+4 <= end {
		key := binary.BigEndian.Uint16(msg[off : off+2])
		plen := int(binary.BigEndian.Uint16(msg[off+2 : off+4]))
		val := msg[off+4 : off+4+plen]
		if key == svcIPv4Hint {
			for i := 0; i+4 <= len(val); i += 4 {
				ip, _ := netip.AddrFromSlice(val[i : i+4])
				out = append(out, ip)
			}
		}
		off += 4 + plen
	}
	return out
}

func TestIsDNSPacketDest(t *testing.T) {
	orig := &net.UDPAddr{IP: net.ParseIP("10.255.255.2").To4(), Port: 53}
	if !isDNSPacketDest(orig, "1.1.1.1:53") {
		t.Fatal("hijacked DNS")
	}
	if isDNSPacketDest(&net.UDPAddr{IP: net.ParseIP("1.1.1.1").To4(), Port: 443}, "1.1.1.1:443") {
		t.Fatal("QUIC must not be treated as DNS")
	}
}
