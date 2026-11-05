package hy2bind

import (
	"context"
	"crypto/tls"
	"encoding/binary"
	"errors"
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

// Xray's gRPC transport: one bidirectional HTTP/2 stream per VLESS connection,
// method `/<service_name>/Tun`, body a sequence of gRPC messages each carrying
// the protobuf `Hunk{ bytes data = 1 }`. The VLESS request header is the first
// hunk; the response header is the first two bytes the server sends back.
//
// Only the framing is ours: `x/net/http2` carries the stream over the REALITY
// TLS connection, and no gRPC runtime or generated stubs enter the graph.
const (
	grpcHunkChunk   = 32 * 1024
	grpcMaxMessage  = 16 << 20
	grpcContentType = "application/grpc"
	grpcStreamName  = "Tun"
)

// realityGRPCConn is a net.Conn whose bytes are VLESS stream bytes carried in
// gRPC hunks.
type realityGRPCConn struct {
	conn   net.Conn
	body   *hunkBody
	resp   *http.Response
	respCh chan grpcResponse

	respOnce sync.Once
	respErr  error

	// Read owns pending; Close never waits for it. Sharing one mutex between a
	// blocking Read and Close deadlocks a tunnel that is stopped while a read
	// is in flight.
	closeOnce sync.Once
	pending   []byte
}

type grpcResponse struct {
	resp *http.Response
	err  error
}

func dialRealityGRPC(ctx context.Context, cfg realityEndpoint, target string, command byte) (net.Conn, error) {
	request, err := vlessRequestWithFlow(cfg.uuid, target, command, cfg.flow)
	if err != nil {
		return nil, err
	}
	tlsConn, err := openRealityTLS(ctx, cfg)
	if err != nil {
		return nil, err
	}
	service := strings.TrimSpace(cfg.serviceName)
	if service == "" {
		service = "grpc"
	}
	multi := strings.EqualFold(strings.TrimSpace(cfg.mode), "multi")
	path := "/" + service + "/" + grpcStreamName
	if multi {
		path = "/" + service + "/TunMulti"
	}
	authority := cfg.server
	if strings.TrimSpace(cfg.host) != "" {
		authority = strings.TrimSpace(cfg.host)
	}
	u := &url.URL{
		Scheme: "https",
		Host:   net.JoinHostPort(authority, strconv.Itoa(cfg.port)),
		Path:   path,
	}

	body := newHunkBody()
	// The VLESS request is the first hunk and has to be readable before the
	// HTTP/2 round trip starts, so the body owns it rather than a Write after
	// the response headers.
	if err := body.push(grpcMessage(request)); err != nil {
		_ = tlsConn.Close()
		return nil, err
	}
	transport := &http2.Transport{
		DialTLSContext: func(context.Context, string, string, *tls.Config) (net.Conn, error) {
			return tlsConn, nil
		},
	}
	req := &http.Request{
		Method:        http.MethodPost,
		URL:           u,
		Proto:         "HTTP/2",
		ProtoMajor:    2,
		ProtoMinor:    0,
		Body:          body,
		ContentLength: -1,
		Host:          u.Host,
		Header: http.Header{
			"Content-Type": []string{grpcContentType},
			"Te":           []string{"trailers"},
			"User-Agent":   []string{"grpc-go/1.0"},
		},
	}
	// Same reason as the XHTTP download: the gRPC stream outlives the dial.
	req = req.WithContext(context.WithoutCancel(ctx))
	conn := &realityGRPCConn{
		conn:   tlsConn,
		body:   body,
		respCh: make(chan grpcResponse, 1),
	}
	// The round trip is started but not awaited: a gRPC server answers only
	// after it has the first payload, and the caller writes that payload right
	// after Dial returns. Waiting here would stall every connection for the
	// server's first-byte timeout.
	go func() {
		resp, err := transport.RoundTrip(req)
		conn.respCh <- grpcResponse{resp: resp, err: err}
	}()
	return &vlessConn{Conn: conn}, nil
}

func (c *realityGRPCConn) awaitResponse() error {
	c.respOnce.Do(func() {
		result := <-c.respCh
		if result.err != nil {
			c.respErr = fmt.Errorf("grpc: %w", result.err)
			return
		}
		resp := result.resp
		if resp.StatusCode != http.StatusOK {
			_ = resp.Body.Close()
			c.respErr = fmt.Errorf("grpc: status %d", resp.StatusCode)
			return
		}
		if contentType := resp.Header.Get("Content-Type"); !strings.HasPrefix(contentType, grpcContentType) {
			_ = resp.Body.Close()
			c.respErr = fmt.Errorf("grpc: content type %q", contentType)
			return
		}
		c.resp = resp
	})
	return c.respErr
}

func (c *realityGRPCConn) Read(p []byte) (int, error) {
	if err := c.awaitResponse(); err != nil {
		return 0, err
	}
	for len(c.pending) == 0 {
		msg, err := readGRPCMessage(c.resp.Body)
		if err != nil {
			return 0, err
		}
		data, err := parseHunk(msg)
		if err != nil {
			return 0, err
		}
		c.pending = data
	}
	n := copy(p, c.pending)
	c.pending = c.pending[n:]
	return n, nil
}

func (c *realityGRPCConn) Write(p []byte) (int, error) {
	total := len(p)
	for len(p) > 0 {
		size := len(p)
		if size > grpcHunkChunk {
			size = grpcHunkChunk
		}
		if err := c.body.push(grpcMessage(p[:size])); err != nil {
			return total - len(p), err
		}
		p = p[size:]
	}
	return total, nil
}

func (c *realityGRPCConn) Close() error {
	var err error
	c.closeOnce.Do(func() {
		// Closing the body ends the request half; closing the TLS connection
		// aborts the HTTP/2 stream a Read may be blocked on.
		_ = c.body.Close()
		err = c.conn.Close()
	})
	return err
}

func (c *realityGRPCConn) LocalAddr() net.Addr                { return c.conn.LocalAddr() }
func (c *realityGRPCConn) RemoteAddr() net.Addr               { return c.conn.RemoteAddr() }
func (c *realityGRPCConn) SetDeadline(t time.Time) error      { return c.conn.SetDeadline(t) }
func (c *realityGRPCConn) SetReadDeadline(t time.Time) error  { return c.conn.SetReadDeadline(t) }
func (c *realityGRPCConn) SetWriteDeadline(t time.Time) error { return c.conn.SetWriteDeadline(t) }

// hunkBody feeds the HTTP/2 request body. One channel item is one complete
// gRPC message, so the transport never has to split a message itself.
type hunkBody struct {
	ch     chan []byte
	closed chan struct{}
	once   sync.Once
	cur    []byte
}

func newHunkBody() *hunkBody {
	return &hunkBody{ch: make(chan []byte, 32), closed: make(chan struct{})}
}

func (b *hunkBody) push(msg []byte) error {
	select {
	case b.ch <- msg:
		return nil
	case <-b.closed:
		return io.ErrClosedPipe
	}
}

func (b *hunkBody) Read(p []byte) (int, error) {
	for len(b.cur) == 0 {
		select {
		case msg := <-b.ch:
			b.cur = msg
		case <-b.closed:
			return 0, io.EOF
		}
	}
	n := copy(p, b.cur)
	b.cur = b.cur[n:]
	return n, nil
}

func (b *hunkBody) Close() error {
	b.once.Do(func() { close(b.closed) })
	return nil
}

// grpcMessage wraps one protobuf Hunk in the 5-byte gRPC length prefix.
func grpcMessage(data []byte) []byte {
	hunk := make([]byte, 0, len(data)+5)
	hunk = append(hunk, 0x0a)
	hunk = append(hunk, uvarint(uint64(len(data)))...)
	hunk = append(hunk, data...)
	out := make([]byte, 5, 5+len(hunk))
	out[0] = 0 // uncompressed
	binary.BigEndian.PutUint32(out[1:], uint32(len(hunk)))
	return append(out, hunk...)
}

func readGRPCMessage(r io.Reader) ([]byte, error) {
	var header [5]byte
	if _, err := io.ReadFull(r, header[:]); err != nil {
		return nil, err
	}
	if header[0] != 0 {
		return nil, errors.New("grpc: compressed message is not supported")
	}
	size := int(binary.BigEndian.Uint32(header[1:]))
	if size > grpcMaxMessage {
		return nil, fmt.Errorf("grpc: message size %d", size)
	}
	body := make([]byte, size)
	if _, err := io.ReadFull(r, body); err != nil {
		return nil, err
	}
	return body, nil
}

// parseHunk reads the protobuf `Hunk` and returns its `data` field.
func parseHunk(message []byte) ([]byte, error) {
	var out []byte
	for len(message) > 0 {
		tag, n := binary.Uvarint(message)
		if n <= 0 {
			return nil, errors.New("grpc: bad hunk tag")
		}
		message = message[n:]
		field := tag >> 3
		wire := tag & 7
		switch wire {
		case 2:
			length, n := binary.Uvarint(message)
			if n <= 0 || uint64(len(message)-n) < length {
				return nil, errors.New("grpc: bad hunk length")
			}
			message = message[n:]
			if field == 1 {
				out = append(out, message[:length]...)
			}
			message = message[length:]
		case 0:
			_, n := binary.Uvarint(message)
			if n <= 0 {
				return nil, errors.New("grpc: bad varint")
			}
			message = message[n:]
		default:
			return nil, fmt.Errorf("grpc: wire type %d", wire)
		}
	}
	return out, nil
}

func uvarint(v uint64) []byte {
	var buf [10]byte
	n := binary.PutUvarint(buf[:], v)
	return buf[:n]
}
