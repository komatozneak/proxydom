// Package hy2bind is a gomobile bind of official apernet/hysteria (MIT).
//
// Pin the hysteria tag in go.mod / build-aar.sh. Not sing-box, not Bereznev.
package hy2bind

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/apernet/hysteria/core/v2/client"
	"github.com/xjasonlyu/tun2socks/v2/core/device"
	"github.com/xjasonlyu/tun2socks/v2/core/device/fdbased"
	"github.com/xjasonlyu/tun2socks/v2/tunnel"
	gstack "gvisor.dev/gvisor/pkg/tcpip/stack"
)

// Protector is implemented from Kotlin (VpnService.protect).
type Protector interface {
	Protect(fd int) bool
}

type startConfig struct {
	Server               string   `json:"server"`
	Auth                 string   `json:"auth"`
	SNI                  string   `json:"sni"`
	SocksListen          string   `json:"socks_listen"`
	DirectDomainSuffixes []string `json:"direct_domain_suffixes"`
	Insecure             bool     `json:"insecure"`
	Obfs                 string   `json:"obfs"`
	ObfsPassword         string   `json:"obfs_password"`
}

type protectedFactory struct{}

func (f *protectedFactory) New(addr net.Addr) (net.PacketConn, error) {
	pc, err := net.ListenUDP("udp", nil)
	if err != nil {
		return nil, err
	}
	raw, err := pc.SyscallConn()
	if err != nil {
		_ = pc.Close()
		return nil, err
	}
	var protErr error
	if err := raw.Control(func(fd uintptr) {
		mu.Lock()
		p := protector
		mu.Unlock()
		if p != nil && !p.Protect(int(fd)) {
			protErr = errors.New("protect failed")
		}
	}); err != nil {
		_ = pc.Close()
		return nil, err
	}
	if protErr != nil {
		_ = pc.Close()
		return nil, protErr
	}
	return pc, nil
}

func connFactoryFor(cfg startConfig) (client.ConnFactory, error) {
	kind := strings.TrimSpace(strings.ToLower(cfg.Obfs))
	if kind == "" {
		return &protectedFactory{}, nil
	}
	if kind != "salamander" {
		return nil, fmt.Errorf("unsupported obfs %q", cfg.Obfs)
	}
	if len(cfg.ObfsPassword) < 4 {
		return nil, errors.New("obfs password must be at least 4 bytes")
	}
	return &obfsFactory{password: cfg.ObfsPassword}, nil
}

type obfsFactory struct {
	password string
}

func (f *obfsFactory) New(addr net.Addr) (net.PacketConn, error) {
	pc, err := (&protectedFactory{}).New(addr)
	if err != nil {
		return nil, err
	}
	wrapped, err := wrapSalamander(pc, []byte(f.password))
	if err != nil {
		_ = pc.Close()
		return nil, err
	}
	return wrapped, nil
}

var (
	mu        sync.Mutex
	protector Protector
	hyClient  client.Client
	socksLn   net.Listener
	tunDev    device.Device
	tunStk    *gstack.Stack
)

// SetProtector installs VpnService.protect for QUIC sockets (required on Android).
func SetProtector(p Protector) {
	mu.Lock()
	defer mu.Unlock()
	protector = p
}

// Start connects the official Hy2 client and serves SOCKS5. Returns "" on success.
//
// Site-split suffixes are JSON-only (`direct_domain_suffixes`). Rebuild
// hysteria-client.aar after changing this package — an old AAR ignores the field.
func Start(configJSON string) string {
	applyTunnelLogLevel(configJSON)
	var cfg startConfig
	if err := json.Unmarshal([]byte(configJSON), &cfg); err != nil {
		return err.Error()
	}
	setDirectSuffixes(cfg.DirectDomainSuffixes)
	mu.Lock()
	alreadyRunning := hyClient != nil
	mu.Unlock()
	if alreadyRunning {
		prev, ok := loadStartConfig()
		if ok && prev.Server == cfg.Server && prev.Auth == cfg.Auth {
			return ""
		}
		return "already running"
	}
	if cfg.Server == "" || cfg.Auth == "" {
		return "server and auth are required"
	}
	if cfg.SocksListen == "" {
		cfg.SocksListen = "127.0.0.1:10808"
	}

	c, err := newManagedFromConfig(cfg)
	if err != nil {
		return fmt.Sprintf("hy2 client: %v", err)
	}

	ln, err := net.Listen("tcp", cfg.SocksListen)
	if err != nil {
		_ = c.Close()
		return fmt.Sprintf("socks listen: %v", err)
	}

	mu.Lock()
	if hyClient != nil {
		mu.Unlock()
		_ = ln.Close()
		_ = c.Close()
		return "already running"
	}
	rememberStartConfig(cfg)
	hyClient = c
	socksLn = ln
	mu.Unlock()
	go serveSOCKS(ln, c)
	return ""
}

// StartTun attaches VpnService TUN fd to gVisor inside this Go runtime and
// forwards TCP/UDP via HyClient.TCP/UDP (official TUN path). Do not use
// libXray as the pump — a second gomobile runtime deadlocks on Pixel.
func StartTun(fd int, mtu int) string {
	if fd <= 0 {
		return "invalid tun fd"
	}
	if mtu <= 0 {
		mtu = 1500
	}
	mu.Lock()
	defer mu.Unlock()
	if tunStk != nil {
		closeTunFd(fd)
		return "tun already running"
	}
	if hyClient == nil {
		closeTunFd(fd)
		return "hy2 not started"
	}
	dev, err := fdbased.Open(strconv.Itoa(fd), uint32(mtu), 0)
	if err != nil {
		closeTunFd(fd)
		return fmt.Sprintf("tun fd: %v", err)
	}
	tunnel.T().SetProxy(&hyDialer{c: hyClient})
	st, err := createTunStack(dev)
	if err != nil {
		dev.Close()
		return fmt.Sprintf("tun stack: %v", err)
	}
	tunDev = dev
	tunStk = st
	log.Printf("hy2bind tun started fd=%d mtu=%d", fd, mtu)
	return ""
}

// StopTun tears down the gVisor stack. Safe if TUN was never started.
//
// Close the stack first — it owns the LinkEndpoint and closes the TUN fd.
// Calling both st.Close() and dev.Close() double-closes the same fd (fdsan
// abort on Pixel: "double-close of file descriptor N").
func StopTun() {
	mu.Lock()
	dev := tunDev
	st := tunStk
	tunDev = nil
	tunStk = nil
	stopPacketTunLocked()
	mu.Unlock()
	if st != nil {
		st.Close()
		st.Wait()
		return
	}
	if dev != nil {
		dev.Close()
	}
}

// Stop closes TUN, SOCKS, and the Hy2 client.
func Stop() {
	StopTun()
	stopShare()
	dnsCacheClear()
	mu.Lock()
	ln := socksLn
	c := hyClient
	socksLn = nil
	hyClient = nil
	mu.Unlock()
	startCfgMu.Lock()
	lastStartCfg = startConfig{}
	startCfgMu.Unlock()
	if ln != nil {
		_ = ln.Close()
	}
	if c != nil {
		_ = c.Close()
	}
	clearSplitState()
}

func serveSOCKS(ln net.Listener, c client.Client) {
	for {
		conn, err := ln.Accept()
		if err != nil {
			return
		}
		go handleSOCKS(conn, c)
	}
}

func socksFail(conn net.Conn, rep byte) {
	_, _ = conn.Write([]byte{0x05, rep, 0x00, 0x01, 0, 0, 0, 0, 0, 0})
}

func handleSOCKS(conn net.Conn, c client.Client) {
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(20 * time.Second))
	hdr := make([]byte, 2)
	if _, err := io.ReadFull(conn, hdr); err != nil || hdr[0] != 0x05 {
		return
	}
	nmethods := int(hdr[1])
	if nmethods > 0 {
		if _, err := io.ReadFull(conn, make([]byte, nmethods)); err != nil {
			return
		}
	}
	if _, err := conn.Write([]byte{0x05, 0x00}); err != nil {
		return
	}
	req := make([]byte, 4)
	if _, err := io.ReadFull(conn, req); err != nil {
		return
	}
	if req[0] != 0x05 || req[1] != 0x01 {
		socksFail(conn, 0x07)
		return
	}
	host, port, ok := readSOCKSAddr(conn, req[3])
	if !ok {
		socksFail(conn, 0x08)
		return
	}
	target := net.JoinHostPort(host, strconv.Itoa(port))
	remote, err := c.TCP(target)
	if err != nil {
		log.Printf("hy2bind socks TCP %s: %v", target, err)
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

func readSOCKSAddr(conn net.Conn, atyp byte) (string, int, bool) {
	switch atyp {
	case 0x01:
		buf := make([]byte, 6)
		if _, err := io.ReadFull(conn, buf); err != nil {
			return "", 0, false
		}
		return net.IP(buf[0:4]).String(), int(buf[4])<<8 | int(buf[5]), true
	case 0x03:
		lb := make([]byte, 1)
		if _, err := io.ReadFull(conn, lb); err != nil {
			return "", 0, false
		}
		rest := make([]byte, int(lb[0])+2)
		if _, err := io.ReadFull(conn, rest); err != nil {
			return "", 0, false
		}
		host := string(rest[:len(rest)-2])
		port := int(rest[len(rest)-2])<<8 | int(rest[len(rest)-1])
		return host, port, true
	case 0x04:
		buf := make([]byte, 18)
		if _, err := io.ReadFull(conn, buf); err != nil {
			return "", 0, false
		}
		return net.IP(buf[0:16]).String(), int(buf[16])<<8 | int(buf[17]), true
	default:
		return "", 0, false
	}
}
