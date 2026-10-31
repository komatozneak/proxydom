package hy2bind

import (
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// realityEndpoint is a parsed REALITY + VLESS share line. The raw link is not
// kept: it carries the UUID and, in some subscriptions, a short id that is
// part of the authentication.
type realityEndpoint struct {
	server      string
	port        int
	uuid        [16]byte
	publicKey   []byte
	shortID     [8]byte
	sni         string
	fingerprint string
	alpn        []string
	socksListen string
}

// realityDocument is what StartShare receives for a REALITY line.
//
// There is no allow_insecure: the certificate check is the half of REALITY that
// proves the peer holds the node's key. Skipping it hands the VLESS UUID to any
// middlebox that terminates TLS, so a link that asks for it is dialled with the
// check anyway, as Xray's own client does.
type realityDocument struct {
	Engine               string   `json:"engine"`
	Server               string   `json:"server"`
	Port                 int      `json:"port"`
	UUID                 string   `json:"uuid"`
	PublicKey            string   `json:"public_key"`
	ShortID              string   `json:"short_id"`
	SNI                  string   `json:"sni"`
	Fingerprint          string   `json:"fingerprint"`
	Flow                 string   `json:"flow"`
	Network              string   `json:"network"`
	ALPN                 []string `json:"alpn"`
	SocksListen          string   `json:"socks_listen"`
	DirectDomainSuffixes []string `json:"direct_domain_suffixes"`
	ForceProxyDomains    []string `json:"force_proxy_domains"`
	UDPMode              string   `json:"udp_mode"`
}

// realityDefaultSocks is the share SOCKS inbound. Both share engines use the
// same port: StartShare stops one before it starts the other, so they never
// listen at once, and one number keeps the TUN pump, the path watch and the
// Windows broker pointed at the same place.
const realityDefaultSocks = "127.0.0.1:10809"

func isRealityDocument(configJSON string) bool {
	var doc struct {
		Engine string `json:"engine"`
	}
	if json.Unmarshal([]byte(configJSON), &doc) != nil {
		return false
	}
	return strings.EqualFold(strings.TrimSpace(doc.Engine), "reality")
}

func parseRealityDocument(configJSON string) (realityEndpoint, error) {
	var doc realityDocument
	if err := json.Unmarshal([]byte(configJSON), &doc); err != nil {
		return realityEndpoint{}, fmt.Errorf("reality config: %w", err)
	}
	server := strings.TrimSpace(doc.Server)
	if server == "" {
		return realityEndpoint{}, errors.New("reality: server is empty")
	}
	port := doc.Port
	if port <= 0 || port > 65535 {
		port = 443
	}
	uuid, err := parseRealityUUID(doc.UUID)
	if err != nil {
		return realityEndpoint{}, err
	}
	publicKey, err := decodeRealityPublicKey(doc.PublicKey)
	if err != nil {
		return realityEndpoint{}, err
	}
	shortID, err := parseRealityShortID(doc.ShortID)
	if err != nil {
		return realityEndpoint{}, err
	}
	// TCP only. WebSocket, gRPC and XHTTP need their own framing on top of the
	// REALITY stream; refusing them here keeps a line inactive instead of
	// failing after the TLS handshake.
	network := strings.ToLower(strings.TrimSpace(doc.Network))
	if network != "" && network != "tcp" {
		return realityEndpoint{}, fmt.Errorf("reality: transport %q is not carried yet", network)
	}
	// XTLS Vision is another framing layer above VLESS, and a Vision user is
	// refused by the server without it. Plain VLESS only.
	if flow := strings.TrimSpace(doc.Flow); flow != "" && !strings.EqualFold(flow, "none") {
		return realityEndpoint{}, errors.New("reality: xtls-rprx-vision is not carried yet")
	}
	sni := strings.TrimSpace(doc.SNI)
	if sni == "" {
		sni = server
	}
	socksListen := strings.TrimSpace(doc.SocksListen)
	if socksListen == "" {
		socksListen = realityDefaultSocks
	}
	return realityEndpoint{
		server:      server,
		port:        port,
		uuid:        uuid,
		publicKey:   publicKey,
		shortID:     shortID,
		sni:         sni,
		fingerprint: strings.TrimSpace(doc.Fingerprint),
		alpn:        doc.ALPN,
		socksListen: socksListen,
	}, nil
}

func parseRealityUUID(text string) ([16]byte, error) {
	var id [16]byte
	clean := strings.ReplaceAll(strings.TrimSpace(text), "-", "")
	if len(clean) != 32 {
		return id, errors.New("reality: uuid is not a 16-byte id")
	}
	if _, err := hex.Decode(id[:], []byte(clean)); err != nil {
		return id, fmt.Errorf("reality: uuid: %w", err)
	}
	return id, nil
}

func decodeRealityPublicKey(text string) ([]byte, error) {
	clean := strings.TrimSpace(text)
	if clean == "" {
		return nil, errors.New("reality: public key is empty")
	}
	encodings := []*base64.Encoding{
		base64.RawURLEncoding,
		base64.URLEncoding,
		base64.RawStdEncoding,
		base64.StdEncoding,
	}
	for _, encoding := range encodings {
		decoded, err := encoding.DecodeString(clean)
		if err == nil && len(decoded) == 32 {
			return decoded, nil
		}
	}
	return nil, errors.New("reality: public key is not 32 bytes of base64")
}

// parseRealityShortID reads the `sid` hex string. A server's short ids are
// whole bytes (an even number of hex digits, at most 16), so an odd-length id
// can match no server and is refused rather than padded into a different one.
func parseRealityShortID(text string) ([8]byte, error) {
	var id [8]byte
	clean := strings.TrimSpace(text)
	if clean == "" {
		return id, nil
	}
	if len(clean)%2 == 1 {
		return id, errors.New("reality: short id has an odd number of hex digits")
	}
	if len(clean) > len(id)*2 {
		return id, errors.New("reality: short id is longer than 8 bytes")
	}
	decoded, err := hex.DecodeString(clean)
	if err != nil {
		return id, fmt.Errorf("reality: short id: %w", err)
	}
	copy(id[:], decoded)
	return id, nil
}

// realitySession is one running REALITY engine. Cancelling ctx closes the
// listener and every connection it accepted, so a stop or a server switch
// ends the old node's flows instead of leaving them running on it.
type realitySession struct {
	ln     net.Listener
	ctx    context.Context
	cancel context.CancelFunc
}

var (
	realityMu  sync.Mutex
	realityCur *realitySession
)

func realityRunning() bool {
	realityMu.Lock()
	defer realityMu.Unlock()
	return realityCur != nil
}

func stopRealityShare() {
	realityMu.Lock()
	session := realityCur
	realityCur = nil
	realityMu.Unlock()
	if session != nil {
		session.cancel()
		_ = session.ln.Close()
	}
	if !v2ShareRunning() {
		shareAddr.Store("")
	}
}

// startRealityShare starts the permissive REALITY + VLESS engine and serves a
// local SOCKS5 inbound. The TUN pump is the same one the v2ray share core
// uses: it reads ShareSocksAddr and does not care which engine produced it.
//
// It returns "" on success, like StartShare.
func startRealityShare(configJSON string) string {
	cfg, err := parseRealityDocument(configJSON)
	if err != nil {
		return fmt.Sprintf("engine: %v", err)
	}
	clearSplitState()
	applyShareSplitPolicy(configJSON)

	// Only one share engine may own the SOCKS port and the TUN dialer.
	shareMu.Lock()
	prev := shareInst
	shareInst = nil
	shareMu.Unlock()
	if prev != nil {
		_ = prev.Close()
	}
	stopRealityShare()

	ln, err := net.Listen("tcp", cfg.socksListen)
	if err != nil {
		return fmt.Sprintf("reality socks: %v", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	session := &realitySession{ln: ln, ctx: ctx, cancel: cancel}
	realityMu.Lock()
	realityCur = session
	realityMu.Unlock()
	shareAddr.Store(ln.Addr().String())
	noteRealityCore()
	go serveRealitySOCKS(session, cfg)
	return ""
}

func serveRealitySOCKS(session *realitySession, cfg realityEndpoint) {
	for {
		conn, err := session.ln.Accept()
		if err != nil {
			return
		}
		go handleRealitySOCKS(session.ctx, conn, cfg)
	}
}

func handleRealitySOCKS(ctx context.Context, conn net.Conn, cfg realityEndpoint) {
	defer conn.Close()
	// Closing the accepted socket is enough to unwind every path below: the
	// TCP relay's copies return and close the remote, and the UDP relay's
	// control read ends and closes its flows.
	stop := context.AfterFunc(ctx, func() { _ = conn.Close() })
	defer stop()
	_ = conn.SetDeadline(time.Now().Add(20 * time.Second))
	hdr := make([]byte, 2)
	if _, err := io.ReadFull(conn, hdr); err != nil || hdr[0] != 0x05 {
		return
	}
	methods := make([]byte, int(hdr[1]))
	if _, err := io.ReadFull(conn, methods); err != nil {
		return
	}
	if _, err := conn.Write([]byte{0x05, 0x00}); err != nil {
		return
	}
	req := make([]byte, 4)
	if _, err := io.ReadFull(conn, req); err != nil {
		return
	}
	if req[0] != 0x05 {
		return
	}
	switch req[1] {
	case 0x01:
		handleRealityConnect(ctx, conn, cfg, req[3])
	case 0x03:
		handleRealityUDP(ctx, conn, cfg, req[3])
	default:
		socksFail(conn, 0x07)
	}
}

func handleRealityConnect(ctx context.Context, conn net.Conn, cfg realityEndpoint, atyp byte) {
	host, port, ok := readSOCKSAddr(conn, atyp)
	if !ok {
		socksFail(conn, 0x08)
		return
	}
	target := net.JoinHostPort(host, strconv.Itoa(port))
	dialCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()
	remote, err := dialRealityStream(dialCtx, cfg, target, vlessCommandTCP)
	if err != nil {
		log.Printf("hy2bind reality TCP %s: %v", target, err)
		socksFail(conn, 0x04)
		return
	}
	defer remote.Close()
	_ = conn.SetDeadline(time.Time{})
	if _, err := conn.Write([]byte{0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0}); err != nil {
		return
	}
	errc := make(chan struct{}, 2)
	go func() { _, _ = io.Copy(remote, conn); errc <- struct{}{} }()
	go func() { _, _ = io.Copy(conn, remote); errc <- struct{}{} }()
	<-errc
}

// realityOutboundDial reaches the node: protected on Android, bound to the
// physical NIC on Windows. A variable so tests can dial loopback directly.
var realityOutboundDial = engineOutboundDial

// dialRealityStream opens one REALITY connection to the node and sends the
// VLESS request for [target]. TCP and UDP differ only in the command byte.
//
// The response header is not read here. Xray flushes it together with the
// first downstream payload; blocking on it before the caller has sent a
// request byte deadlocks a server that waits for the first payload. The
// returned conn strips it on the first Read instead.
func dialRealityStream(ctx context.Context, cfg realityEndpoint, target string, command byte) (net.Conn, error) {
	request, err := vlessRequest(cfg.uuid, target, command)
	if err != nil {
		return nil, err
	}
	raw, err := realityOutboundDial(ctx, "tcp", net.JoinHostPort(cfg.server, strconv.Itoa(cfg.port)))
	if err != nil {
		return nil, err
	}
	conn, err := realityHandshake(ctx, raw, cfg)
	if err != nil {
		_ = raw.Close()
		return nil, err
	}
	if _, err := conn.Write(request); err != nil {
		_ = conn.Close()
		return nil, err
	}
	return &vlessConn{Conn: conn}, nil
}

// vlessConn hides the VLESS response header from the layer above. The header
// arrives before the first byte of the target's response, not before the
// client sends anything.
type vlessConn struct {
	net.Conn
	headerOnce sync.Once
	headerErr  error
}

func (c *vlessConn) Read(p []byte) (int, error) {
	c.headerOnce.Do(func() {
		c.headerErr = readVlessResponse(c.Conn)
	})
	if c.headerErr != nil {
		return 0, c.headerErr
	}
	return c.Conn.Read(p)
}

const (
	vlessCommandTCP = 1
	vlessCommandUDP = 2
)

func vlessRequest(id [16]byte, address string, command byte) ([]byte, error) {
	host, portText, err := net.SplitHostPort(address)
	if err != nil {
		return nil, fmt.Errorf("vless target: %w", err)
	}
	port, err := strconv.Atoi(portText)
	if err != nil || port <= 0 || port > 65535 {
		return nil, fmt.Errorf("vless port %q", portText)
	}
	encoded, err := vlessAddress(host)
	if err != nil {
		return nil, err
	}
	request := make([]byte, 0, 1+len(id)+1+1+2+len(encoded))
	request = append(request, 0)
	request = append(request, id[:]...)
	request = append(request, 0)
	request = append(request, command)
	request = append(request, byte(port>>8), byte(port))
	request = append(request, encoded...)
	return request, nil
}

func vlessAddress(host string) ([]byte, error) {
	if ip := net.ParseIP(host); ip != nil {
		if ipv4 := ip.To4(); ipv4 != nil {
			return append([]byte{0x01}, ipv4...), nil
		}
		return append([]byte{0x03}, ip.To16()...), nil
	}
	if len(host) == 0 || len(host) > 255 {
		return nil, errors.New("vless: bad domain")
	}
	address := make([]byte, 0, 2+len(host))
	address = append(address, 0x02, byte(len(host)))
	address = append(address, host...)
	return address, nil
}

func readVlessResponse(conn net.Conn) error {
	header := make([]byte, 2)
	if _, err := io.ReadFull(conn, header); err != nil {
		return fmt.Errorf("vless response: %w", err)
	}
	if header[0] != 0 {
		return fmt.Errorf("vless response version %d", header[0])
	}
	if header[1] > 0 {
		addons := make([]byte, int(header[1]))
		if _, err := io.ReadFull(conn, addons); err != nil {
			return fmt.Errorf("vless addons: %w", err)
		}
	}
	return nil
}

const (
	// realityUDPIdle closes a destination nobody has used for this long. Each
	// destination costs a TCP connection and a TLS session to the node, and a
	// DNS lookup is one exchange, so without a bound every name ever resolved
	// would keep a connection open for the life of the association.
	realityUDPIdle = 2 * time.Minute
	// realityUDPQueue is how many datagrams wait for a destination that is
	// still dialling. Beyond it they are dropped, as a full socket buffer would.
	realityUDPQueue = 64
)

// handleRealityUDP is the SOCKS5 UDP ASSOCIATE path. Each destination gets its
// own VLESS UDP stream, dialled in its own goroutine: a node that takes seconds
// to answer one destination must not hold up datagrams for every other one,
// which is what a dial inside the read loop did to DNS.
func handleRealityUDP(ctx context.Context, conn net.Conn, cfg realityEndpoint, atyp byte) {
	if _, _, ok := readSOCKSAddr(conn, atyp); !ok {
		socksFail(conn, 0x08)
		return
	}
	// The address in the request is where the client will send from. Most
	// clients put 0.0.0.0:0 there and learn the relay address from the reply;
	// the source of the first datagram is the authority.
	pc, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 0})
	if err != nil {
		socksFail(conn, 0x01)
		return
	}
	defer pc.Close()
	bound := pc.LocalAddr().(*net.UDPAddr)
	reply := []byte{0x05, 0x00, 0x00, 0x01}
	reply = append(reply, bound.IP.To4()...)
	reply = append(reply, byte(bound.Port>>8), byte(bound.Port))
	if _, err := conn.Write(reply); err != nil {
		return
	}
	_ = conn.SetDeadline(time.Time{})

	// The association lives as long as its control connection.
	assoc, cancel := context.WithCancel(ctx)
	defer cancel()
	go func() {
		_, _ = io.Copy(io.Discard, conn)
		cancel()
		_ = pc.Close()
	}()

	relay := &realityUDPRelay{
		ctx:   assoc,
		cfg:   cfg,
		pc:    pc,
		flows: make(map[string]chan []byte),
	}
	buf := make([]byte, 65535)
	for {
		n, from, err := pc.ReadFromUDP(buf)
		if err != nil {
			return
		}
		relay.client.Store(from)
		datagram := buf[:n]
		if len(datagram) < 4 || datagram[0] != 0 || datagram[1] != 0 || datagram[2] != 0 {
			continue
		}
		host, port, offset, ok := parseSOCKSUDPAddress(datagram, 3)
		if !ok {
			continue
		}
		relay.send(net.JoinHostPort(host, strconv.Itoa(port)), datagram[offset:])
	}
}

type realityUDPRelay struct {
	ctx    context.Context
	cfg    realityEndpoint
	pc     *net.UDPConn
	client atomic.Pointer[net.UDPAddr]

	mu    sync.Mutex
	flows map[string]chan []byte
}

// send queues [payload] for [target], starting that destination's flow if it
// has none. It never blocks the read loop.
func (r *realityUDPRelay) send(target string, payload []byte) {
	packet := append([]byte(nil), payload...)
	r.mu.Lock()
	queue, ok := r.flows[target]
	if !ok {
		queue = make(chan []byte, realityUDPQueue)
		r.flows[target] = queue
		go r.run(target, queue)
	}
	r.mu.Unlock()
	select {
	case queue <- packet:
	default:
	}
}

func (r *realityUDPRelay) forget(target string, queue chan []byte) {
	r.mu.Lock()
	if r.flows[target] == queue {
		delete(r.flows, target)
	}
	r.mu.Unlock()
}

func (r *realityUDPRelay) run(target string, queue chan []byte) {
	defer r.forget(target, queue)
	dialCtx, cancel := context.WithTimeout(r.ctx, 20*time.Second)
	conn, err := dialRealityStream(dialCtx, r.cfg, target, vlessCommandUDP)
	cancel()
	if err != nil {
		log.Printf("hy2bind reality UDP %s: %v", target, err)
		return
	}
	defer conn.Close()
	stop := context.AfterFunc(r.ctx, func() { _ = conn.Close() })
	defer stop()

	idle := func() { _ = conn.SetReadDeadline(time.Now().Add(realityUDPIdle)) }
	idle()
	done := make(chan struct{})
	go func() {
		defer close(done)
		for {
			payload, err := readVlessUDP(conn)
			if err != nil {
				return
			}
			idle()
			addr := r.client.Load()
			if addr == nil {
				continue
			}
			packet, err := socksUDPPacket(target, payload)
			if err != nil {
				continue
			}
			_, _ = r.pc.WriteToUDP(packet, addr)
		}
	}()
	for {
		select {
		case payload := <-queue:
			if writeVlessUDP(conn, payload) != nil {
				return
			}
			idle()
		case <-done:
			return
		}
	}
}

// writeVlessUDP frames one datagram: a two-byte big-endian length, then the
// payload, in a single write so the frame never interleaves.
func writeVlessUDP(conn net.Conn, payload []byte) error {
	if len(payload) > 65535 {
		return errors.New("reality udp: payload too large")
	}
	packet := make([]byte, 2+len(payload))
	binary.BigEndian.PutUint16(packet[:2], uint16(len(payload)))
	copy(packet[2:], payload)
	_, err := conn.Write(packet)
	return err
}

func readVlessUDP(conn net.Conn) ([]byte, error) {
	header := make([]byte, 2)
	if _, err := io.ReadFull(conn, header); err != nil {
		return nil, err
	}
	payload := make([]byte, int(binary.BigEndian.Uint16(header)))
	if _, err := io.ReadFull(conn, payload); err != nil {
		return nil, err
	}
	return payload, nil
}

func parseSOCKSUDPAddress(datagram []byte, offset int) (string, int, int, bool) {
	if offset >= len(datagram) {
		return "", 0, 0, false
	}
	switch datagram[offset] {
	case 0x01:
		if offset+1+4+2 > len(datagram) {
			return "", 0, 0, false
		}
		host := net.IP(datagram[offset+1 : offset+5]).String()
		port := int(binary.BigEndian.Uint16(datagram[offset+5 : offset+7]))
		return host, port, offset + 7, true
	case 0x03:
		if offset+2 > len(datagram) {
			return "", 0, 0, false
		}
		length := int(datagram[offset+1])
		if offset+2+length+2 > len(datagram) {
			return "", 0, 0, false
		}
		host := string(datagram[offset+2 : offset+2+length])
		port := int(binary.BigEndian.Uint16(datagram[offset+2+length : offset+2+length+2]))
		return host, port, offset + 2 + length + 2, true
	case 0x04:
		if offset+1+16+2 > len(datagram) {
			return "", 0, 0, false
		}
		host := net.IP(datagram[offset+1 : offset+17]).String()
		port := int(binary.BigEndian.Uint16(datagram[offset+17 : offset+19]))
		return host, port, offset + 19, true
	default:
		return "", 0, 0, false
	}
}

func socksUDPPacket(target string, payload []byte) ([]byte, error) {
	host, portText, err := net.SplitHostPort(target)
	if err != nil {
		return nil, err
	}
	port, err := strconv.Atoi(portText)
	if err != nil || port <= 0 || port > 65535 {
		return nil, errors.New("socks udp: bad port")
	}
	address, err := socks5Address(host)
	if err != nil {
		return nil, err
	}
	packet := make([]byte, 0, 3+len(address)+2+len(payload))
	packet = append(packet, 0, 0, 0)
	packet = append(packet, address...)
	packet = append(packet, byte(port>>8), byte(port))
	packet = append(packet, payload...)
	return packet, nil
}

func socks5Address(host string) ([]byte, error) {
	if ip := net.ParseIP(host); ip != nil {
		if ipv4 := ip.To4(); ipv4 != nil {
			return append([]byte{0x01}, ipv4...), nil
		}
		return append([]byte{0x04}, ip.To16()...), nil
	}
	if len(host) == 0 || len(host) > 255 {
		return nil, errors.New("socks udp: bad domain")
	}
	address := make([]byte, 0, 2+len(host))
	address = append(address, 0x03, byte(len(host)))
	address = append(address, host...)
	return address, nil
}
