package hy2bind

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"sync"
	"sync/atomic"
	"time"

	"github.com/apernet/hysteria/core/v2/client"
	coreErrs "github.com/apernet/hysteria/core/v2/errors"
)

// managedClient wraps official NewReconnectableClient and retries once after
// ClosedError so the dial that saw a dead QUIC transport does not fail open.
type managedClient struct {
	mu     sync.Mutex
	inner  client.Client
	closed bool
}

func (m *managedClient) TCP(addr string) (net.Conn, error) {
	return withClosedRetry(m, func(c client.Client) (net.Conn, error) {
		return c.TCP(addr)
	})
}

func (m *managedClient) UDP() (client.HyUDPConn, error) {
	return withClosedRetry(m, func(c client.Client) (client.HyUDPConn, error) {
		return c.UDP()
	})
}

func (m *managedClient) Close() error {
	m.mu.Lock()
	m.closed = true
	inner := m.inner
	m.inner = nil
	m.mu.Unlock()
	if inner == nil {
		return nil
	}
	return inner.Close()
}

// swapInner preserves the managedClient identity held by SOCKS and gVisor.
// The caller closes the returned old transport after the atomic swap.
func (m *managedClient) swapInner(next client.Client) (client.Client, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.closed {
		return nil, false
	}
	old := m.inner
	m.inner = next
	return old, true
}

func (m *managedClient) current() (client.Client, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.inner, m.closed
}

func withClosedRetry[T any](m *managedClient, fn func(client.Client) (T, error)) (T, error) {
	var zero T
	c, closed := m.current()
	if closed {
		return zero, coreErrs.ClosedError{}
	}
	if c == nil {
		return zero, errors.New("hy2 not started")
	}
	out, err := fn(c)
	if !isClosedError(err) {
		return out, err
	}
	c2, closed2 := m.current()
	if closed2 || c2 == nil {
		return zero, err
	}
	return fn(c2)
}

func isClosedError(err error) bool {
	if err == nil {
		return false
	}
	var closed coreErrs.ClosedError
	if errors.As(err, &closed) {
		return true
	}
	_, ok := err.(coreErrs.ClosedError)
	return ok
}

type clientHealth struct {
	ConnectCount    int64  `json:"connect_count"`
	ReconnectCount  int64  `json:"reconnect_count"`
	ResetCount      int64  `json:"reset_count"`
	LastConnectUnix int64  `json:"last_connect_unix_ms"`
	LastResetUnix   int64  `json:"last_reset_unix_ms"`
	LastErrorUnix   int64  `json:"last_error_unix_ms"`
	LastError       string `json:"last_error,omitempty"`
	LastResetReason string `json:"last_reset_reason,omitempty"`
	Running         bool   `json:"running"`
}

var (
	startCfgMu   sync.Mutex
	lastStartCfg startConfig

	healthConnectCount    atomic.Int64
	healthReconnectCount  atomic.Int64
	healthResetCount      atomic.Int64
	healthLastConnectMs   atomic.Int64
	healthLastResetMs     atomic.Int64
	healthLastErrorMs     atomic.Int64
	healthLastError       atomic.Value // string
	healthLastResetReason atomic.Value // string

	resetMu       sync.Mutex
	resetInFlight bool
)

func rememberStartConfig(cfg startConfig) {
	startCfgMu.Lock()
	lastStartCfg = cfg
	startCfgMu.Unlock()
}

func loadStartConfig() (startConfig, bool) {
	startCfgMu.Lock()
	defer startCfgMu.Unlock()
	if lastStartCfg.Server == "" || lastStartCfg.Auth == "" {
		return startConfig{}, false
	}
	return lastStartCfg, true
}

func noteConnect(count int) {
	now := time.Now().UnixMilli()
	healthLastConnectMs.Store(now)
	if count <= 1 {
		healthConnectCount.Add(1)
	} else {
		healthReconnectCount.Add(1)
	}
}

func noteError(err error) {
	if err == nil {
		return
	}
	healthLastErrorMs.Store(time.Now().UnixMilli())
	healthLastError.Store(err.Error())
}

func noteReset(reason string) {
	healthResetCount.Add(1)
	healthLastResetMs.Store(time.Now().UnixMilli())
	healthLastResetReason.Store(reason)
}

func buildClientConfig(cfg startConfig) (*client.Config, error) {
	if cfg.Server == "" || cfg.Auth == "" {
		return nil, errors.New("server and auth are required")
	}
	udpAddr, err := net.ResolveUDPAddr("udp", cfg.Server)
	if err != nil {
		return nil, fmt.Errorf("resolve: %w", err)
	}
	return &client.Config{
		ConnFactory: &protectedFactory{},
		ServerAddr:  udpAddr,
		Auth:        cfg.Auth,
		TLSConfig: client.TLSConfig{
			ServerName: cfg.SNI,
		},
		// Official TUN clients set this: TCP() returns before the server
		// confirms the dest, saving one RTT on every YouTube/page socket.
		FastOpen: true,
	}, nil
}

func newReconnectableFromConfig(cfg startConfig) (client.Client, error) {
	rc, err := client.NewReconnectableClient(func() (*client.Config, error) {
		return buildClientConfig(cfg)
	}, func(_ client.Client, _ *client.HandshakeInfo, count int) {
		noteConnect(count)
		log.Printf("hy2bind connected count=%d", count)
	}, false)
	if err != nil {
		noteError(err)
		return nil, err
	}
	return rc, nil
}

func newManagedFromConfig(cfg startConfig) (*managedClient, error) {
	inner, err := newReconnectableFromConfig(cfg)
	if err != nil {
		return nil, err
	}
	return &managedClient{inner: inner}, nil
}

// ResetNetwork rebuilds the Hy2 QUIC client after path/NAT changes without
// tearing down TUN/gVisor. Single-flight; failed rebuild keeps the live client.
func ResetNetwork(reason string) string {
	return resetNetworkWithBuilder(reason, newReconnectableFromConfig)
}

func resetNetworkWithBuilder(
	reason string,
	build func(startConfig) (client.Client, error),
) string {
	resetMu.Lock()
	if resetInFlight {
		resetMu.Unlock()
		return "reset_busy"
	}
	resetInFlight = true
	resetMu.Unlock()
	defer func() {
		resetMu.Lock()
		resetInFlight = false
		resetMu.Unlock()
	}()

	cfg, ok := loadStartConfig()
	if !ok {
		return "hy2 not started"
	}
	if reason == "" {
		reason = "unspecified"
	}

	next, err := build(cfg)
	if err != nil {
		noteError(err)
		return fmt.Sprintf("reset: %v", err)
	}

	mu.Lock()
	stable, ok := hyClient.(*managedClient)
	if !ok || stable == nil {
		mu.Unlock()
		_ = next.Close()
		return "hy2 not started"
	}
	old, swapped := stable.swapInner(next)
	mu.Unlock()
	if !swapped {
		_ = next.Close()
		return "hy2 closed"
	}

	if old != nil {
		_ = old.Close()
	}
	noteReset(reason)
	log.Printf("hy2bind ResetNetwork reason=%s", reason)
	return ""
}

// HealthJSON returns connect/reset counters for diagnostics (no user domains).
func HealthJSON() string {
	mu.Lock()
	running := hyClient != nil
	mu.Unlock()
	lastErr, _ := healthLastError.Load().(string)
	lastReason, _ := healthLastResetReason.Load().(string)
	h := clientHealth{
		ConnectCount:    healthConnectCount.Load(),
		ReconnectCount:  healthReconnectCount.Load(),
		ResetCount:      healthResetCount.Load(),
		LastConnectUnix: healthLastConnectMs.Load(),
		LastResetUnix:   healthLastResetMs.Load(),
		LastErrorUnix:   healthLastErrorMs.Load(),
		LastError:       lastErr,
		LastResetReason: lastReason,
		Running:         running,
	}
	b, err := json.Marshal(h)
	if err != nil {
		return `{"running":false}`
	}
	return string(b)
}
