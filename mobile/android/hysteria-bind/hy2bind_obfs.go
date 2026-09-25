package hy2bind

import (
	"crypto/rand"
	"fmt"
	"net"
	"sync"

	"golang.org/x/crypto/blake2b"
)

// Salamander is the Hysteria2 packet obfuscator: 8-byte salt plus XOR with
// BLAKE2b-256(password || salt). Same wire format as apernet/hysteria extras.

const (
	smPSKMinLen = 4
	smSaltLen   = 8
	smKeyLen    = blake2b.Size256
)

type salamander struct {
	psk      []byte
	keyInput []byte
	mu       sync.Mutex
}

func newSalamander(psk []byte) (*salamander, error) {
	if len(psk) < smPSKMinLen {
		return nil, fmt.Errorf("PSK must be at least %d bytes", smPSKMinLen)
	}
	copyPSK := append([]byte(nil), psk...)
	keyInput := make([]byte, len(copyPSK)+smSaltLen)
	copy(keyInput, copyPSK)
	return &salamander{psk: copyPSK, keyInput: keyInput}, nil
}

func (o *salamander) obfuscate(in, out []byte) int {
	outLen := len(in) + smSaltLen
	if len(out) < outLen {
		return 0
	}
	if _, err := rand.Read(out[:smSaltLen]); err != nil {
		return 0
	}
	o.mu.Lock()
	key := o.key(out[:smSaltLen])
	o.mu.Unlock()
	for i, c := range in {
		out[i+smSaltLen] = c ^ key[i%smKeyLen]
	}
	return outLen
}

func (o *salamander) deobfuscate(in, out []byte) int {
	outLen := len(in) - smSaltLen
	if outLen <= 0 || len(out) < outLen {
		return 0
	}
	o.mu.Lock()
	key := o.key(in[:smSaltLen])
	o.mu.Unlock()
	for i, c := range in[smSaltLen:] {
		out[i] = c ^ key[i%smKeyLen]
	}
	return outLen
}

func (o *salamander) key(salt []byte) [smKeyLen]byte {
	copy(o.keyInput[len(o.psk):], salt[:smSaltLen])
	return blake2b.Sum256(o.keyInput)
}

type salamanderConn struct {
	net.PacketConn
	ob *salamander
}

func wrapSalamander(conn net.PacketConn, psk []byte) (net.PacketConn, error) {
	ob, err := newSalamander(psk)
	if err != nil {
		return nil, err
	}
	return &salamanderConn{PacketConn: conn, ob: ob}, nil
}

func (c *salamanderConn) WriteTo(p []byte, addr net.Addr) (int, error) {
	buf := make([]byte, len(p)+smSaltLen)
	n := c.ob.obfuscate(p, buf)
	if n == 0 {
		return 0, fmt.Errorf("salamander obfuscate")
	}
	if _, err := c.PacketConn.WriteTo(buf[:n], addr); err != nil {
		return 0, err
	}
	return len(p), nil
}

func (c *salamanderConn) ReadFrom(p []byte) (int, net.Addr, error) {
	buf := make([]byte, len(p)+smSaltLen)
	n, addr, err := c.PacketConn.ReadFrom(buf)
	if err != nil {
		return 0, addr, err
	}
	dn := c.ob.deobfuscate(buf[:n], p)
	if dn == 0 {
		return 0, addr, fmt.Errorf("salamander deobfuscate")
	}
	return dn, addr, nil
}
