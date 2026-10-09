package hy2bind

import (
	"math/rand"
	"net"
	"sync"
	"time"

	"github.com/apernet/hysteria/core/v2/client"
)

// hopFactory sends each datagram to a port inside the declared range and
// presents the dialed address back to QUIC, which pins one remote.
type hopFactory struct {
	inner client.ConnFactory
	low   int
	high  int
	every time.Duration
}

func (f *hopFactory) New(addr net.Addr) (net.PacketConn, error) {
	pc, err := f.inner.New(addr)
	if err != nil {
		return nil, err
	}
	return &hopConn{
		inner: pc,
		fixed: addr,
		low:   f.low,
		high:  f.high,
		every: f.every,
		next:  time.Now(),
		port:  f.low,
	}, nil
}

type hopConn struct {
	inner net.PacketConn
	fixed net.Addr
	low   int
	high  int
	every time.Duration
	mu    sync.Mutex
	next  time.Time
	port  int
}

func (h *hopConn) currentPort() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.high <= h.low {
		return h.low
	}
	now := time.Now()
	if !now.Before(h.next) {
		h.port = h.low + rand.Intn(h.high-h.low+1)
		h.next = now.Add(h.every)
	}
	return h.port
}

func (h *hopConn) WriteTo(p []byte, addr net.Addr) (int, error) {
	udp, ok := addr.(*net.UDPAddr)
	if !ok || udp == nil {
		return h.inner.WriteTo(p, addr)
	}
	hopped := *udp
	hopped.Port = h.currentPort()
	return h.inner.WriteTo(p, &hopped)
}

func (h *hopConn) ReadFrom(p []byte) (int, net.Addr, error) {
	n, _, err := h.inner.ReadFrom(p)
	if h.fixed != nil {
		return n, h.fixed, err
	}
	return n, nil, err
}

func (h *hopConn) Close() error                       { return h.inner.Close() }
func (h *hopConn) LocalAddr() net.Addr                { return h.inner.LocalAddr() }
func (h *hopConn) SetDeadline(t time.Time) error      { return h.inner.SetDeadline(t) }
func (h *hopConn) SetReadDeadline(t time.Time) error  { return h.inner.SetReadDeadline(t) }
func (h *hopConn) SetWriteDeadline(t time.Time) error { return h.inner.SetWriteDeadline(t) }

func maybeHop(inner client.ConnFactory, cfg startConfig) client.ConnFactory {
	low, high, ok := parsePortRange(cfg.ServerPorts)
	if !ok {
		return inner
	}
	every := 30 * time.Second
	if d, err := time.ParseDuration(cfg.HopInterval); err == nil && d > 0 {
		every = d
	}
	return &hopFactory{inner: inner, low: low, high: high, every: every}
}

func parsePortRange(raw string) (int, int, bool) {
	if raw == "" {
		return 0, 0, false
	}
	sep := -1
	for i := 0; i < len(raw); i++ {
		if raw[i] == ':' {
			sep = i
			break
		}
	}
	if sep <= 0 || sep == len(raw)-1 {
		return 0, 0, false
	}
	low, err1 := atoi(raw[:sep])
	high, err2 := atoi(raw[sep+1:])
	if err1 != nil || err2 != nil || low < 1 || high > 65535 || low > high {
		return 0, 0, false
	}
	return low, high, true
}

func atoi(s string) (int, error) {
	n := 0
	if s == "" {
		return 0, errProtect
	}
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return 0, errProtect
		}
		n = n*10 + int(s[i]-'0')
	}
	return n, nil
}
