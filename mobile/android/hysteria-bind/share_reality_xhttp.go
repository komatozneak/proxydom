package hy2bind

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/tls"
	"encoding/hex"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.org/x/net/http2"
)

// Xray's XHTTP transport in its default `auto` shape: a packet-up uplink and a
// stream-down downlink.
//
//	GET  /<path>/<session>        -> downstream bytes, raw response body
//	POST /<path>/<session>/<seq>  -> one upstream chunk, raw request body
//
// The session id is a UUID the client invents; the server creates the session
// on the first request that names it. The VLESS request header is the first
// upstream bytes, exactly as it is on a plain TCP line.
const (
	xhttpChunk       = 16 * 1024
	xhttpUserAgent   = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
	xhttpPostTimeout = 30 * time.Second
)

type realityXHTTPConn struct {
	conn      net.Conn
	transport *http2.Transport
	base      *url.URL
	session   string

	respCh   chan xhttpResponse
	respOnce sync.Once
	resp     *http.Response
	respErr  error

	// The write lock serialises upstream packets; it is deliberately separate
	// from Read. A single lock shared by both directions deadlocks the tunnel:
	// Reading blocks on the download body while Write waits to send the very
	// bytes the other side is waiting for.
	writeMu sync.Mutex
	seq     int64
	pending []byte

	closed bool
}

type xhttpResponse struct {
	resp *http.Response
	err  error
}

func dialRealityXHTTP(ctx context.Context, cfg realityEndpoint, target string, command byte) (net.Conn, error) {
	request, err := vlessRequestWithFlow(cfg.uuid, target, command, cfg.flow)
	if err != nil {
		return nil, err
	}
	tlsConn, err := openRealityTLS(ctx, cfg)
	if err != nil {
		return nil, err
	}
	authority := cfg.server
	if strings.TrimSpace(cfg.host) != "" {
		authority = strings.TrimSpace(cfg.host)
	}
	path := strings.TrimSpace(cfg.path)
	if path == "" {
		path = "/"
	}
	if !strings.HasPrefix(path, "/") {
		path = "/" + path
	}
	// Xray normalizes a path with the session in it to end with `/`; the
	// server slices the request path at that prefix and would otherwise read
	// the session one segment early.
	if !strings.HasSuffix(path, "/") {
		path += "/"
	}
	base := &url.URL{
		Scheme: "https",
		Host:   net.JoinHostPort(authority, strconv.Itoa(cfg.port)),
		Path:   path,
	}
	session := newXHTTPSession()
	transport := &http2.Transport{
		DialTLSContext: func(context.Context, string, string, *tls.Config) (net.Conn, error) {
			return tlsConn, nil
		},
	}
	conn := &realityXHTTPConn{
		conn:      tlsConn,
		transport: transport,
		base:      base,
		session:   session,
		respCh:    make(chan xhttpResponse, 1),
	}
	download := *base
	download.Path = base.Path + session
	// The download stream lives as long as the tunnel, not as long as the dial.
	// The dial context is cancelled as soon as the SOCKS reply is written, and
	// a request bound to it would be torn down before the first TLS handshake
	// through the tunnel had a chance to finish.
	req, err := http.NewRequestWithContext(context.WithoutCancel(ctx), http.MethodGet, download.String(), nil)
	if err != nil {
		_ = tlsConn.Close()
		return nil, err
	}
	req.Header = xhttpHeaders(&download)
	go func() {
		resp, err := transport.RoundTrip(req)
		conn.respCh <- xhttpResponse{resp: resp, err: err}
	}()
	// The VLESS request header is its own upstream packet, the way Xray's
	// outbound writes it: the server reads exactly those bytes before it starts
	// proxying, and a header glued to the first payload is one packet it has to
	// split itself.
	if err := conn.post(request); err != nil {
		_ = conn.Close()
		return nil, err
	}
	return &vlessConn{Conn: conn}, nil
}

// xhttpHeaders imitates the fetch headers Xray sends and carries the padding
// the server validates: a `Referer` whose `x_padding` length sits inside the
// 100..1000 range the default config expects. A request without it is a 400.
func xhttpHeaders(target *url.URL) http.Header {
	header := http.Header{}
	header.Set("User-Agent", xhttpUserAgent)
	header.Set("Accept", "*/*")
	referer := *target
	query := referer.Query()
	query.Set("x_padding", strings.Repeat("X", 100))
	referer.RawQuery = query.Encode()
	header.Set("Referer", referer.String())
	return header
}

func newXHTTPSession() string {
	var raw [16]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "00000000-0000-4000-8000-000000000000"
	}
	raw[6] = (raw[6] & 0x0f) | 0x40
	raw[8] = (raw[8] & 0x3f) | 0x80
	hexed := hex.EncodeToString(raw[:])
	return hexed[0:8] + "-" + hexed[8:12] + "-" + hexed[12:16] + "-" + hexed[16:20] + "-" + hexed[20:32]
}

func (c *realityXHTTPConn) awaitDownload() error {
	c.respOnce.Do(func() {
		result := <-c.respCh
		if result.err != nil {
			c.respErr = fmt.Errorf("xhttp: %w", result.err)
			return
		}
		resp := result.resp
		if resp.StatusCode != http.StatusOK {
			_ = resp.Body.Close()
			c.respErr = fmt.Errorf("xhttp: status %d", resp.StatusCode)
			return
		}
		c.resp = resp
	})
	return c.respErr
}

func (c *realityXHTTPConn) Read(p []byte) (int, error) {
	if err := c.awaitDownload(); err != nil {
		return 0, err
	}
	if len(c.pending) > 0 {
		n := copy(p, c.pending)
		c.pending = c.pending[n:]
		return n, nil
	}
	buf := make([]byte, 32*1024)
	n, err := c.resp.Body.Read(buf)
	if n > 0 {
		c.pending = append(c.pending, buf[:n]...)
	}
	if len(c.pending) > 0 {
		m := copy(p, c.pending)
		c.pending = c.pending[m:]
		return m, nil
	}
	return 0, err
}

func (c *realityXHTTPConn) Write(p []byte) (int, error) {
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	total := len(p)
	for len(p) > 0 {
		size := len(p)
		if size > xhttpChunk {
			size = xhttpChunk
		}
		if err := c.post(p[:size]); err != nil {
			return total - len(p), err
		}
		p = p[size:]
	}
	return total, nil
}

func (c *realityXHTTPConn) post(chunk []byte) error {
	upload := *c.base
	upload.Path = c.base.Path + c.session + "/" + strconv.FormatInt(c.seq, 10)
	c.seq++
	ctx, cancel := context.WithTimeout(context.Background(), xhttpPostTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, upload.String(), bytes.NewReader(chunk))
	if err != nil {
		return err
	}
	req.Header = xhttpHeaders(&upload)
	req.Header.Set("Content-Type", "application/octet-stream")
	resp, err := c.transport.RoundTrip(req)
	if err != nil {
		return fmt.Errorf("xhttp: post: %w", err)
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("xhttp: post status %d", resp.StatusCode)
	}
	return nil
}

func (c *realityXHTTPConn) Close() error {
	c.writeMu.Lock()
	if c.closed {
		c.writeMu.Unlock()
		return nil
	}
	c.closed = true
	c.writeMu.Unlock()
	// Closing the TLS connection aborts the HTTP/2 streams, including a Read
	// blocked on the download body. Touching resp here would be a race with
	// that Read and is unnecessary.
	return c.conn.Close()
}

func (c *realityXHTTPConn) LocalAddr() net.Addr                { return c.conn.LocalAddr() }
func (c *realityXHTTPConn) RemoteAddr() net.Addr               { return c.conn.RemoteAddr() }
func (c *realityXHTTPConn) SetDeadline(t time.Time) error      { return c.conn.SetDeadline(t) }
func (c *realityXHTTPConn) SetReadDeadline(t time.Time) error  { return c.conn.SetReadDeadline(t) }
func (c *realityXHTTPConn) SetWriteDeadline(t time.Time) error { return c.conn.SetWriteDeadline(t) }
