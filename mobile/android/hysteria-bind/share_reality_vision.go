package hy2bind

import (
	"bytes"
	"crypto/rand"
	"encoding/binary"
	"io"
	"math/big"
	"net"
	"sync"
)

// Vision framing, as Xray's `xtls-rprx-vision` puts it on the wire.
//
// The VLESS request and response headers are plain. Everything after them is a
// sequence of frames:
//
//	[user uuid, 16 bytes, first frame only]
//	[command, 1]
//	[content length, 2]
//	[padding length, 2]
//	[content]
//	[padding, random]
//
// A command of 0 means another frame follows; 1 and 2 end the framed phase and
// the rest of the stream is raw. The server keeps the VLESS header hidden by
// making the first frame long, which is the only part of Vision a middlebox
// can see.
const (
	visionCommandContinue byte = 0
	visionCommandEnd      byte = 1
	visionCommandDirect   byte = 2

	visionFirstContent = 900
	visionFirstJitter  = 500
	visionPaddingMax   = 256
	visionMaxChunk     = 16 * 1024
)

// realityVisionConn carries one VLESS TCP stream over a Vision flow.
//
// It owns the VLESS response header too: the header arrives before the first
// frame and is not framed, so the first Read consumes it raw and only then
// starts unframing.
type realityVisionConn struct {
	net.Conn
	uuid [16]byte

	headerOnce sync.Once
	headerErr  error

	pending   []byte
	raw       bool
	sawUUID   bool
	wroteUUID bool
	padded    bool
}

func newRealityVisionConn(conn net.Conn, uuid [16]byte) *realityVisionConn {
	return &realityVisionConn{Conn: conn, uuid: uuid}
}

func (c *realityVisionConn) Read(p []byte) (int, error) {
	c.headerOnce.Do(func() { c.headerErr = readVlessResponse(c.Conn) })
	if c.headerErr != nil {
		return 0, c.headerErr
	}
	for len(c.pending) == 0 {
		if c.raw {
			return c.Conn.Read(p)
		}
		if err := c.fill(); err != nil {
			return 0, err
		}
	}
	n := copy(p, c.pending)
	c.pending = c.pending[n:]
	return n, nil
}

func (c *realityVisionConn) fill() error {
	if !c.sawUUID {
		head := make([]byte, len(c.uuid))
		if _, err := io.ReadFull(c.Conn, head); err != nil {
			return err
		}
		if !bytes.Equal(head, c.uuid[:]) {
			// The peer is not framing: hand the bytes up untouched and stop
			// looking for frames. This keeps a node that ignores the flow
			// header usable instead of turning its first response into noise.
			c.raw = true
			c.pending = append(c.pending, head...)
			return nil
		}
		c.sawUUID = true
	}
	header := make([]byte, 5)
	if _, err := io.ReadFull(c.Conn, header); err != nil {
		return err
	}
	command := header[0]
	contentLen := int(binary.BigEndian.Uint16(header[1:3]))
	paddingLen := int(binary.BigEndian.Uint16(header[3:5]))
	if contentLen > 0 {
		content := make([]byte, contentLen)
		if _, err := io.ReadFull(c.Conn, content); err != nil {
			return err
		}
		c.pending = append(c.pending, content...)
	}
	if paddingLen > 0 {
		if _, err := io.CopyN(io.Discard, c.Conn, int64(paddingLen)); err != nil {
			return err
		}
	}
	if command != visionCommandContinue {
		// The framed phase ends after this block; anything the peer sends next
		// is the payload itself.
		c.raw = true
	}
	return nil
}

func (c *realityVisionConn) Write(p []byte) (int, error) {
	total := len(p)
	for len(p) > 0 {
		size := len(p)
		if size > visionMaxChunk {
			size = visionMaxChunk
		}
		content := p[:size]
		padding := c.paddingFor(size)
		frame := make([]byte, 0, len(c.uuid)+5+size+padding)
		if !c.wroteUUID {
			frame = append(frame, c.uuid[:]...)
			c.wroteUUID = true
		}
		var header [5]byte
		header[0] = visionCommandContinue
		binary.BigEndian.PutUint16(header[1:3], uint16(size))
		binary.BigEndian.PutUint16(header[3:5], uint16(padding))
		frame = append(frame, header[:]...)
		frame = append(frame, content...)
		if padding > 0 {
			frame = append(frame, visionRandom(padding)...)
		}
		if _, err := c.Conn.Write(frame); err != nil {
			return total - len(p), err
		}
		p = p[size:]
	}
	return total, nil
}

// paddingFor mimics the sizes Xray's client uses: the first frame is long
// enough to hide the VLESS header behind ordinary-looking TLS records, the
// rest carry a small random tail.
func (c *realityVisionConn) paddingFor(contentLen int) int {
	if !c.padded {
		c.padded = true
		base := visionFirstContent - contentLen
		if base < 0 {
			base = 0
		}
		return base + visionRand(visionFirstJitter)
	}
	return visionRand(visionPaddingMax)
}

func visionRand(max int) int {
	if max <= 0 {
		return 0
	}
	n, err := rand.Int(rand.Reader, big.NewInt(int64(max)))
	if err != nil {
		return 0
	}
	return int(n.Int64())
}

func visionRandom(size int) []byte {
	out := make([]byte, size)
	if _, err := rand.Read(out); err != nil {
		return out
	}
	return out
}
