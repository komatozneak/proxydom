package hy2bind

import (
	"bytes"
	"context"
	"encoding/binary"
	"errors"
	"net"
	"net/netip"
	"strings"
	"sync"
	"time"
)

// The TUN sees IP packets, so a dialer is asked for a connection before the
// first byte of the application protocol exists. A whitelist keyed by domain
// therefore has two options: wait for the first bytes and read the SNI/Host
// itself, or guess from the DNS answer. This file does the first; the DNS map
// in hy2bind_split.go is the fallback for flows that never reveal a name.
//
// Budgets are variables so tests do not sleep for real 80 ms.
var (
	sniffIdleBudget     = 120 * time.Millisecond
	sniffFirstByteLimit = 80 * time.Millisecond
)

const sniffBufferLimit = 4096

var errSniffClosed = errors.New("sniff connection closed")

// routeDialer is one dial decision away from a socket. hyDialer and the VLESS
// socks dialer both implement it, so the classifier is shared by both engines.
type routeDialer interface {
	dialRoute(network, addr string, direct bool, why string) (net.Conn, error)
}

// sniffConn is a net.Conn that has not dialled yet. tun2socks receives it from
// DialContext, calls LocalAddr once and then starts copying; the first Write
// (or the idle timer for server-first protocols) performs the real dial.
type sniffConn struct {
	ctx     context.Context
	dstIP   netip.Addr
	dstPort uint16
	addr    string
	dialer  routeDialer

	mu            sync.Mutex
	decided       bool
	conn          net.Conn
	err           error
	pending       []byte
	readDeadline  time.Time
	writeDeadline time.Time
	closed        bool
	decidedCh     chan struct{}
	timer         *time.Timer
}

func newSniffConn(ctx context.Context, dstIP netip.Addr, dstPort uint16, addr string, dialer routeDialer) *sniffConn {
	c := &sniffConn{
		ctx:       ctx,
		dstIP:     dstIP,
		dstPort:   dstPort,
		addr:      addr,
		dialer:    dialer,
		decidedCh: make(chan struct{}),
	}
	c.armLocked(sniffIdleBudget)
	go func() {
		select {
		case <-ctx.Done():
			c.fail(ctx.Err())
		case <-c.decidedCh:
		}
	}()
	return c
}

func (c *sniffConn) armLocked(d time.Duration) {
	if c.timer != nil {
		c.timer.Stop()
	}
	c.timer = time.AfterFunc(d, func() { c.decide("") })
}

// decide is called with no lock held. It picks the route, dials, replays the
// bytes that arrived while waiting, and only then releases readers.
func (c *sniffConn) decide(host string) {
	c.mu.Lock()
	if c.decided || c.closed {
		c.mu.Unlock()
		return
	}
	c.decided = true
	if c.timer != nil {
		c.timer.Stop()
		c.timer = nil
	}
	pending := c.pending
	c.pending = nil
	direct, why := routeFor(host, c.dstIP)
	c.mu.Unlock()

	conn, err := c.dialer.dialRoute("tcp", c.addr, direct, why)

	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed {
		// Close happened while the socket was being opened. The reader has
		// already been released by Close; do not close decidedCh twice.
		if conn != nil {
			_ = conn.Close()
		}
		return
	}
	if ctxErr := c.ctx.Err(); ctxErr != nil && err == nil {
		_ = conn.Close()
		c.err = ctxErr
		close(c.decidedCh)
		return
	}
	if err != nil {
		c.err = err
		close(c.decidedCh)
		return
	}
	c.conn = conn
	if !c.readDeadline.IsZero() {
		_ = conn.SetReadDeadline(c.readDeadline)
	}
	if !c.writeDeadline.IsZero() {
		_ = conn.SetWriteDeadline(c.writeDeadline)
	}
	if len(pending) > 0 {
		if _, werr := conn.Write(pending); werr != nil && c.err == nil {
			c.err = werr
		}
	}
	close(c.decidedCh)
}

func (c *sniffConn) fail(err error) {
	if err == nil {
		err = net.ErrClosed
	}
	c.mu.Lock()
	if c.decided {
		c.mu.Unlock()
		return
	}
	c.decided = true
	c.err = err
	if c.timer != nil {
		c.timer.Stop()
		c.timer = nil
	}
	close(c.decidedCh)
	c.mu.Unlock()
}

// waitConn blocks until the real dial finishes (or fails). The decision flag is
// set before the dial so the timer cannot start a second one, which means a
// writer that arrives during that window must wait rather than see a nil conn.
func (c *sniffConn) waitConn() (net.Conn, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	for {
		if c.decided && (c.conn != nil || c.err != nil) {
			return c.conn, c.err
		}
		ch := c.decidedCh
		c.mu.Unlock()
		<-ch
		c.mu.Lock()
	}
}

func (c *sniffConn) Write(p []byte) (int, error) {
	c.mu.Lock()
	if c.decided {
		c.mu.Unlock()
		conn, err := c.waitConn()
		if err != nil {
			return 0, err
		}
		if conn == nil {
			return 0, net.ErrClosed
		}
		return conn.Write(p)
	}
	if c.closed {
		c.mu.Unlock()
		return 0, net.ErrClosed
	}
	room := sniffBufferLimit - len(c.pending)
	if room < 0 {
		room = 0
	}
	buffered := len(p)
	if buffered > room {
		buffered = room
	}
	c.pending = append(c.pending, p[:buffered]...)
	host := sniffHost(c.pending)
	full := len(c.pending) >= sniffBufferLimit
	if host == "" && !full {
		c.armLocked(sniffFirstByteLimit)
	}
	c.mu.Unlock()

	if host != "" || full {
		c.decide(host)
	}
	if buffered < len(p) {
		// The first sniffBufferLimit bytes were replayed by decide; the rest of
		// this Write must follow them.
		conn, err := c.waitConn()
		if err != nil {
			return buffered, err
		}
		if conn == nil {
			return buffered, net.ErrClosed
		}
		if _, err := conn.Write(p[buffered:]); err != nil {
			return buffered, err
		}
	}
	return len(p), nil
}

func (c *sniffConn) Read(p []byte) (int, error) {
	conn, err := c.waitConn()
	if err != nil {
		return 0, err
	}
	if conn == nil {
		return 0, net.ErrClosed
	}
	return conn.Read(p)
}

func (c *sniffConn) LocalAddr() net.Addr {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.conn != nil {
		return c.conn.LocalAddr()
	}
	// tun2socks calls this right after DialContext to fill flow metadata, before
	// any payload exists. A zero address is the honest placeholder.
	return &net.TCPAddr{IP: net.IPv4zero, Port: 0}
}

func (c *sniffConn) RemoteAddr() net.Addr {
	return &net.TCPAddr{IP: net.IP(c.dstIP.AsSlice()), Port: int(c.dstPort)}
}

func (c *sniffConn) SetDeadline(t time.Time) error {
	c.mu.Lock()
	c.readDeadline = t
	c.writeDeadline = t
	conn := c.conn
	c.mu.Unlock()
	if conn != nil {
		return conn.SetDeadline(t)
	}
	return nil
}

func (c *sniffConn) SetReadDeadline(t time.Time) error {
	c.mu.Lock()
	c.readDeadline = t
	conn := c.conn
	c.mu.Unlock()
	if conn != nil {
		return conn.SetReadDeadline(t)
	}
	return nil
}

func (c *sniffConn) SetWriteDeadline(t time.Time) error {
	c.mu.Lock()
	c.writeDeadline = t
	conn := c.conn
	c.mu.Unlock()
	if conn != nil {
		return conn.SetWriteDeadline(t)
	}
	return nil
}

func (c *sniffConn) Close() error {
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return nil
	}
	c.closed = true
	if c.timer != nil {
		c.timer.Stop()
		c.timer = nil
	}
	conn := c.conn
	if !c.decided {
		c.decided = true
		c.err = errSniffClosed
		close(c.decidedCh)
	}
	c.mu.Unlock()
	if conn != nil {
		return conn.Close()
	}
	return nil
}

func (c *sniffConn) CloseRead() error {
	c.mu.Lock()
	conn := c.conn
	c.mu.Unlock()
	if cr, ok := conn.(interface{ CloseRead() error }); ok {
		return cr.CloseRead()
	}
	return nil
}

func (c *sniffConn) CloseWrite() error {
	c.mu.Lock()
	conn := c.conn
	c.mu.Unlock()
	if cw, ok := conn.(interface{ CloseWrite() error }); ok {
		return cw.CloseWrite()
	}
	return nil
}

// sniffablePort limits the wait to ports where a ClientHello or an HTTP
// request is expected. Everything else falls back to the DNS map immediately,
// so SSH and game TCP do not pay the idle budget.
func sniffablePort(port uint16) bool {
	switch port {
	case 80, 443, 2052, 2053, 2082, 2083, 2086, 2087, 2095, 2096, 8080, 8443, 8880:
		return true
	default:
		return false
	}
}

func sniffHost(b []byte) string {
	if len(b) == 0 {
		return ""
	}
	if b[0] == 0x16 && len(b) >= 2 && b[1] == 0x03 {
		if host, ok := sniffTLSSNI(b); ok {
			return host
		}
		return ""
	}
	if host, ok := sniffHTTPHost(b); ok {
		return host
	}
	return ""
}

// sniffTLSSNI walks the first ClientHello. It accepts a handshake split over
// several TLS records, but gives up on anything larger than the sniff buffer.
func sniffTLSSNI(b []byte) (string, bool) {
	hs, ok := tlsHandshake(b)
	if !ok || len(hs) < 4 || hs[0] != 0x01 {
		return "", false
	}
	hsLen := int(hs[1])<<16 | int(hs[2])<<8 | int(hs[3])
	if hsLen < 34 || len(hs) < 4+hsLen {
		return "", false
	}
	p := hs[4 : 4+hsLen]
	// legacy_version(2) + random(32)
	p = p[2+32:]
	if len(p) < 1 {
		return "", false
	}
	sid := int(p[0])
	p = p[1:]
	if len(p) < sid+2 {
		return "", false
	}
	p = p[sid:]
	csLen := int(binary.BigEndian.Uint16(p))
	p = p[2:]
	if len(p) < csLen+1 {
		return "", false
	}
	p = p[csLen:]
	compLen := int(p[0])
	p = p[1:]
	if len(p) < compLen+2 {
		return "", false
	}
	p = p[compLen:]
	extLen := int(binary.BigEndian.Uint16(p))
	p = p[2:]
	if len(p) < extLen {
		return "", false
	}
	p = p[:extLen]
	for len(p) >= 4 {
		typ := binary.BigEndian.Uint16(p)
		l := int(binary.BigEndian.Uint16(p[2:4]))
		p = p[4:]
		if len(p) < l {
			return "", false
		}
		data := p[:l]
		p = p[l:]
		if typ != 0 {
			continue
		}
		if len(data) < 5 {
			return "", false
		}
		listLen := int(binary.BigEndian.Uint16(data))
		if len(data) < 2+listLen {
			return "", false
		}
		list := data[2 : 2+listLen]
		for len(list) >= 3 {
			nameType := list[0]
			nameLen := int(binary.BigEndian.Uint16(list[1:3]))
			list = list[3:]
			if len(list) < nameLen {
				return "", false
			}
			name := strings.TrimSpace(string(list[:nameLen]))
			list = list[nameLen:]
			if nameType == 0 && name != "" && len(name) <= 253 {
				return normalizeHost(name), true
			}
		}
	}
	return "", false
}

// tlsHandshake concatenates the handshake records at the front of b. A partial
// record returns false so the caller keeps buffering.
func tlsHandshake(b []byte) ([]byte, bool) {
	var hs []byte
	off := 0
	for off+5 <= len(b) {
		if b[off] != 0x16 || b[off+1] != 0x03 {
			return nil, false
		}
		l := int(binary.BigEndian.Uint16(b[off+3 : off+5]))
		if l <= 0 || l > 16384 || off+5+l > len(b) {
			return nil, false
		}
		hs = append(hs, b[off+5:off+5+l]...)
		off += 5 + l
		if len(hs) >= 4 {
			hl := int(hs[1])<<16 | int(hs[2])<<8 | int(hs[3])
			if hl > 65535 {
				return nil, false
			}
			if len(hs) >= 4+hl {
				return hs[:4+hl], true
			}
		}
	}
	return nil, false
}

func sniffHTTPHost(b []byte) (string, bool) {
	if !hasHTTPMethod(b) {
		return "", false
	}
	end := bytes.Index(b, []byte("\r\n\r\n"))
	if end < 0 {
		return "", false
	}
	lines := bytes.Split(b[:end], []byte("\r\n"))
	for _, line := range lines[1:] {
		if len(line) < 5 || !bytes.EqualFold(line[:5], []byte("Host:")) {
			continue
		}
		host := strings.TrimSpace(string(line[5:]))
		if h, _, err := net.SplitHostPort(host); err == nil {
			host = h
		}
		host = normalizeHost(host)
		if host != "" && len(host) <= 253 {
			return host, true
		}
		return "", false
	}
	return "", false
}

func hasHTTPMethod(b []byte) bool {
	for _, method := range []string{"GET ", "POST ", "HEAD ", "PUT ", "DELETE ", "OPTIONS ", "PATCH ", "TRACE ", "CONNECT "} {
		if len(b) >= len(method) && string(b[:len(method)]) == method {
			return true
		}
	}
	return false
}
