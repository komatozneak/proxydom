package hy2bind

import (
	"encoding/json"
	"net"
	"strconv"
	"sync"
)

// v2ray-core's SOCKS client sends UDP ASSOCIATE with the first datagram's
// destination in DST.ADDR/DST.PORT. RFC 1928 §7 defines those fields as the
// address the client will send datagrams from, and a server that reads them
// that way — Xray does — relays only datagrams from, say, 1.1.1.1:53 and drops
// every one the client sends. A SOCKS5 key then carried TCP and lost all UDP,
// DNS included.
//
// The core is not vendored, so the fix sits on the one seam we own: the system
// dialer. A connection to a configured SOCKS server is wrapped, and an
// ASSOCIATE request leaving on it says 0.0.0.0:0, "not known yet", which every
// server accepts. The datagrams themselves keep their real destination: the
// core builds their headers from its own request, not from these bytes.

var (
	socksUpstreamMu sync.RWMutex
	socksUpstreams  map[string]bool
)

// setSocksUpstreams records the SOCKS servers the document dials, as
// "host:port" exactly as written, which is how the core names them to the
// system dialer.
func setSocksUpstreams(configJSON string) {
	var doc struct {
		Outbounds []struct {
			Protocol string `json:"protocol"`
			Settings struct {
				Servers []struct {
					Address string `json:"address"`
					Port    int    `json:"port"`
				} `json:"servers"`
			} `json:"settings"`
		} `json:"outbounds"`
	}
	next := map[string]bool{}
	if json.Unmarshal([]byte(configJSON), &doc) == nil {
		for _, out := range doc.Outbounds {
			if out.Protocol != "socks" {
				continue
			}
			for _, s := range out.Settings.Servers {
				if s.Address != "" && s.Port > 0 {
					next[net.JoinHostPort(s.Address, strconv.Itoa(s.Port))] = true
				}
			}
		}
	}
	socksUpstreamMu.Lock()
	socksUpstreams = next
	socksUpstreamMu.Unlock()
}

func isSocksUpstream(addr string) bool {
	socksUpstreamMu.RLock()
	defer socksUpstreamMu.RUnlock()
	return socksUpstreams[addr]
}

// socksAssociateConn passes the client's SOCKS5 handshake through and rewrites
// only the DST of an ASSOCIATE request. Once the request is out it is a plain
// connection. Bytes that do not parse as SOCKS5 are sent as they are.
type socksAssociateConn struct {
	net.Conn
	mu      sync.Mutex
	stage   int // 0 greeting, 1 auth or request, 2 done
	pending []byte
}

func (c *socksAssociateConn) Write(p []byte) (int, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.stage == 2 {
		return c.Conn.Write(p)
	}
	c.pending = append(c.pending, p...)
	for c.stage < 2 {
		n, out := c.nextMessage()
		if n == 0 {
			return len(p), nil // wait for the rest of the message
		}
		c.pending = c.pending[n:]
		if _, err := c.Conn.Write(out); err != nil {
			return 0, err
		}
	}
	if len(c.pending) > 0 {
		rest := c.pending
		c.pending = nil
		if _, err := c.Conn.Write(rest); err != nil {
			return 0, err
		}
	}
	return len(p), nil
}

// nextMessage returns how many pending bytes form the next handshake message
// and what to send for them, or 0 when the message is not complete yet.
func (c *socksAssociateConn) nextMessage() (int, []byte) {
	b := c.pending
	if len(b) == 0 {
		return 0, nil
	}
	pass := func(n int, stage int) (int, []byte) {
		c.stage = stage
		return n, b[:n]
	}
	switch {
	case c.stage == 0:
		if b[0] != 0x05 {
			return pass(len(b), 2)
		}
		if len(b) < 2 || len(b) < 2+int(b[1]) {
			return 0, nil
		}
		return pass(2+int(b[1]), 1)
	case b[0] == 0x01: // RFC 1929 username/password
		if len(b) < 2 || len(b) < 3+int(b[1]) {
			return 0, nil
		}
		n := 3 + int(b[1]) + int(b[2+int(b[1])])
		if len(b) < n {
			return 0, nil
		}
		return pass(n, 1)
	case b[0] == 0x05:
		if len(b) < 5 {
			return 0, nil
		}
		var n int
		switch b[3] {
		case 0x01:
			n = 4 + 4 + 2
		case 0x04:
			n = 4 + 16 + 2
		case 0x03:
			n = 4 + 1 + int(b[4]) + 2
		default:
			return pass(len(b), 2)
		}
		if len(b) < n {
			return 0, nil
		}
		if b[1] != 0x03 {
			return pass(n, 2)
		}
		c.stage = 2
		return n, []byte{0x05, 0x03, 0x00, 0x01, 0, 0, 0, 0, 0, 0}
	default:
		return pass(len(b), 2)
	}
}

// wrapSocksUpstream applies the rewrite to a TCP connection the core opened to
// one of the document's SOCKS servers and leaves every other connection alone.
func wrapSocksUpstream(conn net.Conn, network, addr string) net.Conn {
	if conn == nil || network != "tcp" || !isSocksUpstream(addr) {
		return conn
	}
	return &socksAssociateConn{Conn: conn}
}
