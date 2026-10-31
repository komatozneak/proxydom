package hy2bind

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdh"
	"crypto/ed25519"
	"crypto/hmac"
	"crypto/sha256"
	"crypto/sha512"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"strings"
	"time"

	utls "github.com/refraction-networking/utls"
	"golang.org/x/crypto/hkdf"
)

// realityVersion mirrors the client version bytes an Xray REALITY server
// checks against its MinClientVer / MaxClientVer. The three numbers are the
// date-shaped version of the core the handshake was specified against.
const (
	realityVersionX = 26
	realityVersionY = 3
	realityVersionZ = 27
)

// realityClientHelloID maps the `fp` spelling used by share links to the
// uTLS profile with the same name. Unknown names fall back to Chrome rather
// than failing: a provider that writes a newer name still gets a modern
// ClientHello, and the REALITY handshake itself does not depend on which
// browser was imitated.
func realityClientHelloID(name string) utls.ClientHelloID {
	switch strings.ToLower(strings.TrimSpace(name)) {
	case "", "chrome":
		return utls.HelloChrome_Auto
	case "firefox":
		return utls.HelloFirefox_Auto
	case "safari":
		return utls.HelloSafari_Auto
	case "ios":
		return utls.HelloIOS_Auto
	case "android":
		return utls.HelloAndroid_11_OkHttp
	case "edge":
		return utls.HelloEdge_Auto
	case "random", "randomized":
		return utls.HelloRandomizedALPN
	default:
		return utls.HelloChrome_Auto
	}
}

// realityHandshake opens the REALITY TLS layer on raw.
//
// The protocol is the one Xray's client implements: a uTLS ClientHello whose
// 32-byte SessionID carries the client version, a timestamp, the configured
// short id, and an AES-GCM tag bound to the X25519 shared secret. A server that
// does not know the key treats the connection as an ordinary TLS visit to the
// cover site; a server that does know it authenticates the session and then
// carries the VLESS stream.
func realityHandshake(ctx context.Context, raw net.Conn, cfg realityEndpoint) (net.Conn, error) {
	fingerprint := realityClientHelloID(cfg.fingerprint)
	tlsConfig := &utls.Config{
		ServerName:             cfg.sni,
		InsecureSkipVerify:     true,
		SessionTicketsDisabled: true,
		MinVersion:             utls.VersionTLS13,
	}
	if len(cfg.alpn) > 0 {
		tlsConfig.NextProtos = cfg.alpn
	}
	uconn := utls.UClient(raw, tlsConfig, fingerprint)
	if err := uconn.BuildHandshakeState(); err != nil {
		return nil, fmt.Errorf("reality hello: %w", err)
	}
	hello := uconn.HandshakeState.Hello
	if hello == nil || len(hello.Raw) < 71 || len(hello.Random) < 32 {
		return nil, errors.New("reality hello: fingerprint has no TLS 1.3 session id slot")
	}

	// The fixed location of the Session ID in a ClientHello: handshake header
	// (4) + legacy version (2) + random (32) + session id length (1).
	hello.SessionId = make([]byte, 32)
	copy(hello.Raw[39:], hello.SessionId)
	hello.SessionId[0] = realityVersionX
	hello.SessionId[1] = realityVersionY
	hello.SessionId[2] = realityVersionZ
	hello.SessionId[3] = 0
	binary.BigEndian.PutUint32(hello.SessionId[4:], uint32(time.Now().Unix()))
	copy(hello.SessionId[8:], cfg.shortID[:])

	publicKey, err := ecdh.X25519().NewPublicKey(cfg.publicKey)
	if err != nil {
		return nil, fmt.Errorf("reality public key: %w", err)
	}
	keys := uconn.HandshakeState.State13.KeyShareKeys
	if keys == nil {
		return nil, errors.New("reality hello: no TLS 1.3 key share")
	}
	ecdhe := keys.Ecdhe
	if ecdhe == nil {
		ecdhe = keys.MlkemEcdhe
	}
	if ecdhe == nil {
		return nil, errors.New("reality hello: fingerprint has no X25519 key share")
	}
	shared, err := ecdhe.ECDH(publicKey)
	if err != nil {
		return nil, fmt.Errorf("reality shared key: %w", err)
	}

	authKey := make([]byte, 32)
	if _, err := io.ReadFull(hkdf.New(sha256.New, shared, hello.Random[:20], []byte("REALITY")), authKey); err != nil {
		return nil, fmt.Errorf("reality hkdf: %w", err)
	}
	block, err := aes.NewCipher(authKey)
	if err != nil {
		return nil, fmt.Errorf("reality aes: %w", err)
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("reality gcm: %w", err)
	}
	sealed := aead.Seal(hello.SessionId[:0], hello.Random[20:], hello.SessionId[:16], hello.Raw)
	copy(hello.SessionId, sealed)
	copy(hello.Raw[39:], hello.SessionId)

	if deadline, ok := ctx.Deadline(); ok {
		_ = raw.SetDeadline(deadline)
	}
	if err := uconn.HandshakeContext(ctx); err != nil {
		return nil, fmt.Errorf("reality handshake: %w", err)
	}
	_ = raw.SetDeadline(time.Time{})

	if err := verifyRealityCertificate(uconn, authKey); err != nil {
		return nil, err
	}
	return uconn, nil
}

// verifyRealityCertificate checks the signature the REALITY server puts on its
// ephemeral certificate. A certificate that is not signed with the shared key
// is a real certificate from the cover site (or a middlebox), and the session
// must not be used: the peer is not the node the key names.
func verifyRealityCertificate(uconn *utls.UConn, authKey []byte) error {
	state := uconn.ConnectionState()
	if len(state.PeerCertificates) == 0 {
		return errors.New("reality: peer sent no certificate")
	}
	cert := state.PeerCertificates[0]
	publicKey, ok := cert.PublicKey.(ed25519.PublicKey)
	if !ok {
		return errors.New("reality: peer certificate is not the node's ephemeral key")
	}
	mac := hmac.New(sha512.New, authKey)
	mac.Write(publicKey)
	if !hmac.Equal(mac.Sum(nil), cert.Signature) {
		return errors.New("reality: peer certificate is not signed by the node")
	}
	return nil
}
