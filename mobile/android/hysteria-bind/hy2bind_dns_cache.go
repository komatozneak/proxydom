package hy2bind

import (
	"encoding/binary"
	"errors"
	"strconv"
	"sync"
	"time"
)

var errDNSTimeout = errors.New("dns timeout")

const (
	dnsCacheMax        = 256
	dnsTTLMin          = time.Second
	dnsTTLMax          = 5 * time.Minute
	dnsNegTTL          = 5 * time.Second
	dnsInflightTimeout = 3 * time.Second
)

type dnsDecision int

const (
	dnsSend dnsDecision = iota
	dnsJoined
	dnsRepeat
	dnsHit
)

type dnsWaiter struct {
	id      uint16
	deliver func([]byte)
	fail    func(error)
}

type dnsSlot struct {
	gen     uint64
	pending bool
	leader  *hyPacketConn
	resp    []byte
	expire  time.Time
	waiters []dnsWaiter
}

var (
	dnsMu    sync.Mutex
	dnsTab   = map[string]*dnsSlot{}
	dnsEpoch uint64
)

func dnsCacheClear() {
	dnsMu.Lock()
	dnsEpoch++
	dnsTab = map[string]*dnsSlot{}
	dnsMu.Unlock()
}

func dnsQuestionKey(msg []byte) (key string, id uint16, ok bool) {
	if len(msg) < 12 || msg[2]&0x80 != 0 {
		return "", 0, false
	}
	if binary.BigEndian.Uint16(msg[4:6]) < 1 {
		return "", 0, false
	}
	name, next, err := readDNSName(msg, 12)
	if err != nil || name == "" || next+4 > len(msg) {
		return "", 0, false
	}
	qtype := binary.BigEndian.Uint16(msg[next : next+2])
	qclass := binary.BigEndian.Uint16(msg[next+2 : next+4])
	id = binary.BigEndian.Uint16(msg[:2])
	return name + "|" + strconv.Itoa(int(qtype)) + "|" + strconv.Itoa(int(qclass)), id, true
}

func rewriteDNSID(msg []byte, id uint16) []byte {
	out := append([]byte(nil), msg...)
	if len(out) >= 2 {
		binary.BigEndian.PutUint16(out[:2], id)
	}
	return out
}

// dnsPlan collapses parallel identical lookups. The first query is sent;
// the rest wait for that response. A fresh cached answer is returned immediately.
func dnsPlan(c *hyPacketConn, query []byte) (dnsDecision, []byte) {
	key, id, ok := dnsQuestionKey(query)
	if !ok {
		return dnsSend, nil
	}
	now := time.Now()
	dnsMu.Lock()
	defer dnsMu.Unlock()
	slot := dnsTab[key]
	if slot != nil && slot.resp != nil && now.Before(slot.expire) {
		return dnsHit, rewriteDNSID(slot.resp, id)
	}
	if slot != nil && slot.pending {
		if slot.leader == c {
			return dnsRepeat, nil
		}
		slot.waiters = append(slot.waiters, dnsWaiter{
			id:      id,
			deliver: c.deliverLocal,
			fail:    c.failLocal,
		})
		return dnsJoined, nil
	}
	if slot == nil {
		dnsEvictLocked(now)
		slot = &dnsSlot{}
		dnsTab[key] = slot
	}
	slot.gen++
	slot.pending = true
	slot.leader = c
	slot.resp = nil
	slot.expire = time.Time{}
	slot.waiters = nil
	c.rememberDNSKey(key)
	gen := slot.gen
	epoch := dnsEpoch
	time.AfterFunc(dnsInflightTimeout, func() {
		dnsExpirePending(key, gen, epoch)
	})
	return dnsSend, nil
}

func dnsEvictLocked(now time.Time) {
	if len(dnsTab) < dnsCacheMax {
		return
	}
	for k, slot := range dnsTab {
		if slot.pending {
			continue
		}
		if slot.resp != nil && now.Before(slot.expire) {
			continue
		}
		delete(dnsTab, k)
		if len(dnsTab) < dnsCacheMax {
			return
		}
	}
	if len(dnsTab) < dnsCacheMax {
		return
	}
	for k, slot := range dnsTab {
		if slot.pending {
			continue
		}
		delete(dnsTab, k)
		return
	}
}

func dnsComplete(c *hyPacketConn, key string, resp []byte) {
	if c == nil || key == "" || len(resp) == 0 || len(resp) > 4096 {
		return
	}
	dnsMu.Lock()
	slot := dnsTab[key]
	if slot == nil || slot.leader != c || !slot.pending {
		dnsMu.Unlock()
		return
	}
	slot.pending = false
	slot.leader = nil
	slot.gen++
	waiters := slot.waiters
	slot.waiters = nil
	if ttl := dnsCacheTTL(resp); ttl > 0 {
		slot.resp = append([]byte(nil), resp...)
		slot.expire = time.Now().Add(ttl)
	} else {
		slot.resp = nil
	}
	dnsMu.Unlock()
	for _, w := range waiters {
		w.deliver(rewriteDNSID(resp, w.id))
	}
}

func dnsFail(c *hyPacketConn, key string, err error) {
	if c == nil || key == "" || err == nil {
		return
	}
	dnsMu.Lock()
	slot := dnsTab[key]
	if slot == nil || slot.leader != c || !slot.pending {
		dnsMu.Unlock()
		return
	}
	slot.pending = false
	slot.leader = nil
	slot.gen++
	waiters := slot.waiters
	slot.waiters = nil
	dnsMu.Unlock()
	for _, w := range waiters {
		w.fail(err)
	}
}

func dnsExpirePending(key string, gen, epoch uint64) {
	dnsMu.Lock()
	if epoch != dnsEpoch {
		dnsMu.Unlock()
		return
	}
	slot := dnsTab[key]
	if slot == nil || !slot.pending || slot.gen != gen {
		dnsMu.Unlock()
		return
	}
	slot.pending = false
	slot.leader = nil
	waiters := slot.waiters
	slot.waiters = nil
	dnsMu.Unlock()
	for _, w := range waiters {
		w.fail(errDNSTimeout)
	}
}

func dnsCacheTTL(msg []byte) time.Duration {
	if len(msg) < 12 || msg[2]&0x80 == 0 {
		return 0
	}
	rcode := msg[3] & 0x0f
	switch rcode {
	case 0:
	case 3:
		return dnsNegTTL
	default:
		return 0
	}
	qd := int(binary.BigEndian.Uint16(msg[4:6]))
	an := int(binary.BigEndian.Uint16(msg[6:8]))
	off := 12
	for i := 0; i < qd; i++ {
		next, err := skipDNSName(msg, off)
		if err != nil || next+4 > len(msg) {
			return dnsTTLMin
		}
		off = next + 4
	}
	if an == 0 {
		return dnsTTLMin
	}
	var minTTL uint32
	found := false
	for i := 0; i < an; i++ {
		next, err := skipDNSName(msg, off)
		if err != nil || next+10 > len(msg) {
			break
		}
		ttl := binary.BigEndian.Uint32(msg[next+4 : next+8])
		rdlen := int(binary.BigEndian.Uint16(msg[next+8 : next+10]))
		if !found || ttl < minTTL {
			minTTL = ttl
			found = true
		}
		off = next + 10 + rdlen
		if off > len(msg) {
			break
		}
	}
	if !found {
		return dnsTTLMin
	}
	d := time.Duration(minTTL) * time.Second
	if d < dnsTTLMin {
		return dnsTTLMin
	}
	if d > dnsTTLMax {
		return dnsTTLMax
	}
	return d
}
