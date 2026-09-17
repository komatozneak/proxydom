package hy2bind

import (
	"errors"
	"net"
	"sync/atomic"
	"testing"
	"time"

	"github.com/apernet/hysteria/core/v2/client"
	coreErrs "github.com/apernet/hysteria/core/v2/errors"
)

type stubUDP struct{}

func (stubUDP) ReadFrom([]byte) (int, net.Addr, error) { return 0, nil, net.ErrClosed }
func (stubUDP) WriteTo([]byte, net.Addr) (int, error)  { return 0, net.ErrClosed }
func (stubUDP) Close() error                           { return nil }
func (stubUDP) LocalAddr() net.Addr                    { return &net.UDPAddr{} }
func (stubUDP) SetDeadline(time.Time) error            { return nil }
func (stubUDP) SetReadDeadline(time.Time) error        { return nil }
func (stubUDP) SetWriteDeadline(time.Time) error       { return nil }
func (stubUDP) Receive() ([]byte, string, error)       { return nil, "", net.ErrClosed }
func (stubUDP) Send([]byte, string) error              { return net.ErrClosed }

type stubClient struct {
	tcpCalls atomic.Int64
	failOnce atomic.Bool
	closed   atomic.Bool
}

func (s *stubClient) TCP(addr string) (net.Conn, error) {
	s.tcpCalls.Add(1)
	if s.closed.Load() {
		return nil, coreErrs.ClosedError{}
	}
	if s.failOnce.CompareAndSwap(true, false) {
		return nil, coreErrs.ClosedError{Err: errors.New("dead")}
	}
	c1, c2 := net.Pipe()
	_ = c2.Close()
	return c1, nil
}

func (s *stubClient) UDP() (client.HyUDPConn, error) {
	if s.closed.Load() {
		return nil, coreErrs.ClosedError{}
	}
	return stubUDP{}, nil
}

func (s *stubClient) Close() error {
	s.closed.Store(true)
	return nil
}

func TestManagedClientRetriesClosedErrorOnce(t *testing.T) {
	stub := &stubClient{}
	stub.failOnce.Store(true)
	m := &managedClient{inner: stub}
	conn, err := m.TCP("example.com:443")
	if err != nil {
		t.Fatalf("TCP after ClosedError retry: %v", err)
	}
	_ = conn.Close()
	if stub.tcpCalls.Load() != 2 {
		t.Fatalf("want 2 TCP calls, got %d", stub.tcpCalls.Load())
	}
}

func TestManagedClientCloseBlocksResurrection(t *testing.T) {
	stub := &stubClient{}
	m := &managedClient{inner: stub}
	if err := m.Close(); err != nil {
		t.Fatal(err)
	}
	if _, err := m.TCP("example.com:443"); !isClosedError(err) {
		t.Fatalf("want ClosedError after Close, got %v", err)
	}
}

func TestResetNetworkWhenIdle(t *testing.T) {
	Stop()
	if got := ResetNetwork("test"); got != "hy2 not started" {
		t.Fatalf("idle ResetNetwork: got %q", got)
	}
}

func TestResetNetworkKeepsStableClientIdentity(t *testing.T) {
	old := &stubClient{}
	stable := &managedClient{inner: old}
	installManagedTestState(t, stable)
	next := &stubClient{}

	got := resetNetworkWithBuilder("path_iface", func(startConfig) (client.Client, error) {
		return next, nil
	})
	if got != "" {
		t.Fatalf("ResetNetwork: %q", got)
	}
	mu.Lock()
	current := hyClient
	mu.Unlock()
	if current != stable {
		t.Fatal("ResetNetwork replaced managedClient identity")
	}
	if !old.closed.Load() {
		t.Fatal("old inner client was not closed")
	}

	// SOCKS and gVisor keep this stable pointer; it must reach the new inner.
	pinned := client.Client(stable)
	conn, err := pinned.TCP("example.com:443")
	if err != nil {
		t.Fatalf("pinned client after reset: %v", err)
	}
	_ = conn.Close()
	if next.tcpCalls.Load() != 1 {
		t.Fatalf("new inner TCP calls = %d, want 1", next.tcpCalls.Load())
	}
}

func TestResetNetworkFailedBuildKeepsOldClient(t *testing.T) {
	old := &stubClient{}
	stable := &managedClient{inner: old}
	installManagedTestState(t, stable)

	got := resetNetworkWithBuilder("path_iface", func(startConfig) (client.Client, error) {
		return nil, errors.New("handshake failed")
	})
	if got != "reset: handshake failed" {
		t.Fatalf("ResetNetwork: %q", got)
	}
	if old.closed.Load() {
		t.Fatal("failed reset closed the working client")
	}
	inner, closed := stable.current()
	if closed || inner != old {
		t.Fatal("failed reset changed the stable client")
	}
}

func TestResetNetworkSingleFlightReportsBusy(t *testing.T) {
	old := &stubClient{}
	stable := &managedClient{inner: old}
	installManagedTestState(t, stable)
	started := make(chan struct{})
	release := make(chan struct{})
	done := make(chan string, 1)

	go func() {
		done <- resetNetworkWithBuilder("path_iface", func(startConfig) (client.Client, error) {
			close(started)
			<-release
			return &stubClient{}, nil
		})
	}()
	<-started
	if got := resetNetworkWithBuilder("path_satisfied", func(startConfig) (client.Client, error) {
		t.Fatal("busy reset invoked builder")
		return nil, nil
	}); got != "reset_busy" {
		t.Fatalf("concurrent ResetNetwork = %q, want reset_busy", got)
	}
	close(release)
	if got := <-done; got != "" {
		t.Fatalf("first ResetNetwork: %q", got)
	}
}

func TestHealthJSONEmpty(t *testing.T) {
	Stop()
	raw := HealthJSON()
	if raw == "" {
		t.Fatal("empty health json")
	}
}

func installManagedTestState(t *testing.T, stable *managedClient) {
	t.Helper()
	mu.Lock()
	previousClient := hyClient
	hyClient = stable
	mu.Unlock()

	startCfgMu.Lock()
	previousConfig := lastStartCfg
	lastStartCfg = startConfig{
		Server: "127.0.0.1:443",
		Auth:   "test",
	}
	startCfgMu.Unlock()

	resetMu.Lock()
	previousReset := resetInFlight
	resetInFlight = false
	resetMu.Unlock()

	t.Cleanup(func() {
		_ = stable.Close()
		mu.Lock()
		hyClient = previousClient
		mu.Unlock()
		startCfgMu.Lock()
		lastStartCfg = previousConfig
		startCfgMu.Unlock()
		resetMu.Lock()
		resetInFlight = previousReset
		resetMu.Unlock()
	})
}
