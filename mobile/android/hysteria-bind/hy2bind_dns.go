package hy2bind

import (
	"encoding/binary"
	"errors"
	"log"
	"net/netip"
	"strings"
	"time"
)

// Minimal DNS (RFC 1035 + RFC 9460 hints) post-filter for Hy2 UDP/53.
// Strips A/AAAA (and HTTPS/SVCB ipv4hint) in skipCDNNets. Parse errors fail-open.
const (
	dnsTypeA     = 1
	dnsTypeAAAA  = 28
	dnsTypeSVCB  = 64
	dnsTypeHTTPS = 65
	svcIPv4Hint  = 4
)

var (
	errDNSTrunc = errors.New("dns truncated")
	errDNSBad   = errors.New("dns malformed")
	errDNSLoop  = errors.New("dns name loop")
)

func filterDNSResponse(msg []byte) []byte {
	if len(msg) < 12 {
		return msg
	}
	if msg[2]&0x80 == 0 {
		return msg
	}
	qd := int(binary.BigEndian.Uint16(msg[4:6]))
	an := int(binary.BigEndian.Uint16(msg[6:8]))
	ns := int(binary.BigEndian.Uint16(msg[8:10]))
	ar := int(binary.BigEndian.Uint16(msg[10:12]))

	off := 12
	var err error
	for i := 0; i < qd; i++ {
		off, err = skipDNSName(msg, off)
		if err != nil || off+4 > len(msg) {
			return msg
		}
		off += 4
	}
	qEnd := off

	var anKept, nsKept, arKept [][]byte
	var dropped, rewritten int
	var ok bool
	off, anKept, dropped, rewritten, ok = filterDNSSection(msg, off, an, dropped, rewritten)
	if !ok {
		return msg
	}
	off, nsKept, dropped, rewritten, ok = filterDNSSection(msg, off, ns, dropped, rewritten)
	if !ok {
		return msg
	}
	off, arKept, dropped, rewritten, ok = filterDNSSection(msg, off, ar, dropped, rewritten)
	if !ok {
		return msg
	}
	if dropped == 0 && rewritten == 0 {
		rememberDNSFromMessage(msg)
		return msg
	}

	out := make([]byte, 0, 12+(qEnd-12)+rrBytes(anKept)+rrBytes(nsKept)+rrBytes(arKept))
	out = append(out, msg[:12]...)
	binary.BigEndian.PutUint16(out[6:8], uint16(len(anKept)))
	binary.BigEndian.PutUint16(out[8:10], uint16(len(nsKept)))
	binary.BigEndian.PutUint16(out[10:12], uint16(len(arKept)))
	out = append(out, msg[12:qEnd]...)
	for _, rr := range anKept {
		out = append(out, rr...)
	}
	for _, rr := range nsKept {
		out = append(out, rr...)
	}
	for _, rr := range arKept {
		out = append(out, rr...)
	}
	log.Printf("hy2bind dns-filter dropped=%d rewritten=%d kept=%d", dropped, rewritten, len(anKept))
	rememberDNSFromMessage(out)
	return out
}

func filterDNSSection(
	msg []byte, off int, n int, dropped, rewritten int,
) (int, [][]byte, int, int, bool) {
	kept := make([][]byte, 0, n)
	for i := 0; i < n; i++ {
		start := off
		nameEnd, err := skipDNSName(msg, off)
		if err != nil || nameEnd+10 > len(msg) {
			return 0, nil, dropped, rewritten, false
		}
		typ := binary.BigEndian.Uint16(msg[nameEnd : nameEnd+2])
		rdlen := int(binary.BigEndian.Uint16(msg[nameEnd+8 : nameEnd+10]))
		rdataOff := nameEnd + 10
		end := rdataOff + rdlen
		if end > len(msg) {
			return 0, nil, dropped, rewritten, false
		}
		switch {
		case shouldDropDNSAnswer(typ, msg[rdataOff:end]):
			dropped++
		case typ == dnsTypeHTTPS || typ == dnsTypeSVCB:
			newRdata, changed, parsed := rewriteSVCBHints(msg, rdataOff, rdlen)
			if !parsed {
				kept = append(kept, msg[start:end])
			} else if changed {
				rewritten++
				kept = append(kept, rebuildRR(msg, start, rdataOff, newRdata))
			} else {
				kept = append(kept, msg[start:end])
			}
		default:
			kept = append(kept, msg[start:end])
		}
		off = end
	}
	return off, kept, dropped, rewritten, true
}

func rebuildRR(msg []byte, start, rdataOff int, newRdata []byte) []byte {
	out := make([]byte, 0, (rdataOff-start-2)+2+len(newRdata))
	out = append(out, msg[start:rdataOff-2]...)
	out = binary.BigEndian.AppendUint16(out, uint16(len(newRdata)))
	return append(out, newRdata...)
}

func rewriteSVCBHints(msg []byte, rdataOff, rdlen int) ([]byte, bool, bool) {
	end := rdataOff + rdlen
	if rdataOff+2 > end {
		return nil, false, false
	}
	nameEnd, err := skipDNSName(msg, rdataOff+2)
	if err != nil || nameEnd > end {
		return nil, false, false
	}
	changed := false
	params := make([][]byte, 0, 4)
	off := nameEnd
	for off < end {
		if off+4 > end {
			return nil, false, false
		}
		key := binary.BigEndian.Uint16(msg[off : off+2])
		plen := int(binary.BigEndian.Uint16(msg[off+2 : off+4]))
		valOff := off + 4
		if valOff+plen > end {
			return nil, false, false
		}
		if key == svcIPv4Hint {
			kept := filterIPv4Hints(msg[valOff : valOff+plen])
			if len(kept) != plen {
				changed = true
			}
			if len(kept) == 0 {
				off = valOff + plen
				continue
			}
			p := make([]byte, 4+len(kept))
			binary.BigEndian.PutUint16(p[0:2], key)
			binary.BigEndian.PutUint16(p[2:4], uint16(len(kept)))
			copy(p[4:], kept)
			params = append(params, p)
		} else {
			params = append(params, msg[off:valOff+plen])
		}
		off = valOff + plen
	}
	if off != end {
		return nil, false, false
	}
	if !changed {
		return msg[rdataOff:end], false, true
	}
	out := append([]byte{}, msg[rdataOff:nameEnd]...)
	for _, p := range params {
		out = append(out, p...)
	}
	return out, true, true
}

func filterIPv4Hints(val []byte) []byte {
	if len(val)%4 != 0 {
		return val
	}
	out := make([]byte, 0, len(val))
	for i := 0; i < len(val); i += 4 {
		ip, ok := netip.AddrFromSlice(val[i : i+4])
		if ok && shouldSkipCDN(ip) {
			continue
		}
		out = append(out, val[i:i+4]...)
	}
	return out
}

func shouldDropDNSAnswer(typ uint16, rdata []byte) bool {
	switch typ {
	case dnsTypeA:
		if len(rdata) != 4 {
			return false
		}
		ip, ok := netip.AddrFromSlice(rdata)
		return ok && shouldSkipCDN(ip)
	case dnsTypeAAAA:
		if len(rdata) != 16 {
			return false
		}
		ip, ok := netip.AddrFromSlice(rdata)
		return ok && shouldSkipCDN(ip)
	default:
		return false
	}
}

func rrBytes(kept [][]byte) int {
	n := 0
	for _, rr := range kept {
		n += len(rr)
	}
	return n
}

// skipDNSName returns the offset after this name on the wire (compression
// pointers consume 2 bytes at the first pointer; labels are followed).
func skipDNSName(msg []byte, off int) (int, error) {
	consumed := 0
	cur := off
	jumped := false
	for i := 0; i < 128; i++ {
		if cur >= len(msg) {
			return 0, errDNSTrunc
		}
		c := int(msg[cur])
		if c == 0 {
			if !jumped {
				consumed++
			}
			return off + consumed, nil
		}
		switch c >> 6 {
		case 0:
			cur += 1 + c
			if !jumped {
				consumed += 1 + c
			}
			if cur > len(msg) {
				return 0, errDNSTrunc
			}
		case 3:
			if cur+1 >= len(msg) {
				return 0, errDNSTrunc
			}
			ptr := (c&0x3F)<<8 | int(msg[cur+1])
			if ptr >= len(msg) {
				return 0, errDNSBad
			}
			if !jumped {
				consumed += 2
				jumped = true
			}
			cur = ptr
		default:
			return 0, errDNSBad
		}
	}
	return 0, errDNSLoop
}

func readDNSName(msg []byte, off int) (string, int, error) {
	var labels []string
	consumed := 0
	cur := off
	jumped := false
	for i := 0; i < 128; i++ {
		if cur >= len(msg) {
			return "", 0, errDNSTrunc
		}
		c := int(msg[cur])
		if c == 0 {
			if !jumped {
				consumed++
			}
			return strings.ToLower(strings.Join(labels, ".")), off + consumed, nil
		}
		switch c >> 6 {
		case 0:
			if cur+1+c > len(msg) {
				return "", 0, errDNSTrunc
			}
			labels = append(labels, string(msg[cur+1:cur+1+c]))
			cur += 1 + c
			if !jumped {
				consumed += 1 + c
			}
		case 3:
			if cur+1 >= len(msg) {
				return "", 0, errDNSTrunc
			}
			ptr := (c&0x3F)<<8 | int(msg[cur+1])
			if ptr >= len(msg) {
				return "", 0, errDNSBad
			}
			if !jumped {
				consumed += 2
				jumped = true
			}
			cur = ptr
		default:
			return "", 0, errDNSBad
		}
	}
	return "", 0, errDNSLoop
}

func rememberDNSFromMessage(msg []byte) {
	if len(msg) < 12 || msg[2]&0x80 == 0 {
		return
	}
	qd := int(binary.BigEndian.Uint16(msg[4:6]))
	an := int(binary.BigEndian.Uint16(msg[6:8]))
	off := 12
	host := ""
	for i := 0; i < qd; i++ {
		name, next, err := readDNSName(msg, off)
		if err != nil || next+4 > len(msg) {
			return
		}
		if host == "" && name != "" {
			host = name
		}
		off = next + 4
	}
	if host == "" {
		return
	}
	for i := 0; i < an; i++ {
		_, next, err := readDNSName(msg, off)
		if err != nil || next+10 > len(msg) {
			return
		}
		typ := binary.BigEndian.Uint16(msg[next : next+2])
		ttl := time.Duration(binary.BigEndian.Uint32(msg[next+4:next+8])) * time.Second
		rdlen := int(binary.BigEndian.Uint16(msg[next+8 : next+10]))
		rdataOff := next + 10
		end := rdataOff + rdlen
		if end > len(msg) {
			return
		}
		switch typ {
		case dnsTypeA, dnsTypeAAAA:
			ip, ok := netip.AddrFromSlice(msg[rdataOff:end])
			if ok {
				rememberHostIPTTL(host, ip, ttl)
			}
		}
		off = end
	}
}
