package hy2bind

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"testing"
	"time"
)

// flowMetadataKeys are the metadata keys desktop/windows/service/flow_probe.cpp
// reads with read_string. Every one of them must stay a JSON string: the
// broker's parser rejects a number where it expects a string and drops the row,
// which empties the sites screen counters.
var flowMetadataKeys = []string{"network", "host", "destinationIP", "destinationPort", "processPath"}

type flowStubConn struct{ readData []byte }

func (c *flowStubConn) Read(p []byte) (int, error) {
	if len(c.readData) == 0 {
		return 0, io.EOF
	}
	n := copy(p, c.readData)
	c.readData = c.readData[n:]
	return n, nil
}

func (c *flowStubConn) Write(p []byte) (int, error)      { return len(p), nil }
func (c *flowStubConn) Close() error                     { return nil }
func (c *flowStubConn) LocalAddr() net.Addr              { return &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)} }
func (c *flowStubConn) RemoteAddr() net.Addr             { return &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)} }
func (c *flowStubConn) SetDeadline(time.Time) error      { return nil }
func (c *flowStubConn) SetReadDeadline(time.Time) error  { return nil }
func (c *flowStubConn) SetWriteDeadline(time.Time) error { return nil }

func clearFlowTable(t *testing.T) {
	t.Helper()
	drop := func() {
		flowMu.Lock()
		flowTable = map[string]*flowRec{}
		flowMu.Unlock()
	}
	drop()
	t.Cleanup(drop)
}

type flowRow struct {
	ID       string         `json:"id"`
	Metadata map[string]any `json:"metadata"`
	Upload   int64          `json:"upload"`
	Download int64          `json:"download"`
	Chains   []string       `json:"chains"`
}

type flowSnapshot struct {
	Connections []flowRow `json:"connections"`
}

func snapshotForTest(t *testing.T) flowSnapshot {
	t.Helper()
	raw, err := json.Marshal(map[string]any{"connections": snapshotFlows()})
	if err != nil {
		t.Fatalf("marshal snapshot: %v", err)
	}
	var top flowSnapshot
	if err := json.Unmarshal(raw, &top); err != nil {
		t.Fatalf("unmarshal snapshot: %v", err)
	}
	return top
}

func TestFlowSnapshotMatchesTheBrokerContract(t *testing.T) {
	clearFlowTable(t)
	addFlow("tcp", "example.com:443", "proxy")
	addFlow("udp", "203.0.113.9:27015", "direct")

	top := snapshotForTest(t)
	if len(top.Connections) != 2 {
		t.Fatalf("connections = %d, want 2", len(top.Connections))
	}

	destinations := map[string]string{}
	chains := map[string]bool{}
	for _, row := range top.Connections {
		if row.ID == "" {
			t.Fatal("every row needs an id")
		}
		if len(row.Metadata) != len(flowMetadataKeys) {
			t.Fatalf("metadata has %d keys, want %d: %v",
				len(row.Metadata), len(flowMetadataKeys), row.Metadata)
		}
		for _, key := range flowMetadataKeys {
			value, ok := row.Metadata[key]
			if !ok {
				t.Fatalf("metadata is missing %q, which flow_probe reads", key)
			}
			if _, isString := value.(string); !isString {
				t.Fatalf("metadata[%q] = %#v, flow_probe needs a JSON string", key, value)
			}
		}
		if len(row.Chains) == 0 {
			t.Fatal("chains must carry the outbound the connection used")
		}
		chains[row.Chains[0]] = true

		network := row.Metadata["network"].(string)
		destinations[network] = row.Metadata["destinationIP"].(string) + ":" +
			row.Metadata["destinationPort"].(string)
	}

	if got := destinations["tcp"]; got != "example.com:443" {
		t.Fatalf("tcp destination = %q, want example.com:443", got)
	}
	if got := destinations["udp"]; got != "203.0.113.9:27015" {
		t.Fatalf("udp destination = %q, want 203.0.113.9:27015", got)
	}
	if !chains["proxy"] || !chains["direct"] {
		t.Fatalf("chains = %v, want both proxy and direct", chains)
	}
}

func TestTrackStreamRegistersARowAndForgetsItOnClose(t *testing.T) {
	clearFlowTable(t)
	tracked := trackStream(&flowStubConn{}, "tcp", "example.com:443", "proxy")
	if len(snapshotForTest(t).Connections) != 1 {
		t.Fatal("trackStream must register the connection")
	}
	if err := tracked.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}
	if got := len(snapshotForTest(t).Connections); got != 0 {
		t.Fatalf("rows after close = %d, want 0", got)
	}
}

func TestFlowCountersCountBothDirections(t *testing.T) {
	clearFlowTable(t)
	rec := addFlow("tcp", "example.com:443", "proxy")
	conn := &countingConn{Conn: &flowStubConn{readData: []byte("12345")}, rec: rec}

	buf := make([]byte, 5)
	if _, err := io.ReadFull(conn, buf); err != nil {
		t.Fatalf("read: %v", err)
	}
	if _, err := conn.Write([]byte("abc")); err != nil {
		t.Fatalf("write: %v", err)
	}

	if got := rec.download.Load(); got != 5 {
		t.Fatalf("download = %d, want 5", got)
	}
	if got := rec.upload.Load(); got != 3 {
		t.Fatalf("upload = %d, want 3", got)
	}
}

func freeLoopbackPort(t *testing.T) int {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("reserve a loopback port: %v", err)
	}
	port := ln.Addr().(*net.TCPAddr).Port
	if err := ln.Close(); err != nil {
		t.Fatalf("release the loopback port: %v", err)
	}
	return port
}

func startFlowAPIForTest(t *testing.T, secret string) int {
	t.Helper()
	clearFlowTable(t)
	port := freeLoopbackPort(t)
	startFlowAPI(port, secret)
	t.Cleanup(stopFlowAPI)

	deadline := time.Now().Add(5 * time.Second)
	addr := fmt.Sprintf("127.0.0.1:%d", port)
	for {
		conn, err := net.DialTimeout("tcp", addr, 100*time.Millisecond)
		if err == nil {
			_ = conn.Close()
			return port
		}
		if time.Now().After(deadline) {
			t.Fatalf("flow api never listened on %s: %v", addr, err)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

func getConnections(t *testing.T, port int, authorization string) (int, string) {
	t.Helper()
	req, err := http.NewRequest(http.MethodGet, fmt.Sprintf("http://127.0.0.1:%d/connections", port), nil)
	if err != nil {
		t.Fatalf("request: %v", err)
	}
	if authorization != "" {
		req.Header.Set("Authorization", authorization)
	}
	resp, err := (&http.Client{Timeout: 3 * time.Second}).Do(req)
	if err != nil {
		t.Fatalf("get /connections: %v", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read body: %v", err)
	}
	return resp.StatusCode, string(body)
}

func TestFlowAPIBindsLoopbackOnly(t *testing.T) {
	startFlowAPIForTest(t, "0123456789abcdef")
	flowMu.Lock()
	addr := ""
	if flowServer != nil {
		addr = flowServer.Addr
	}
	flowMu.Unlock()
	const loopback = "127.0.0.1:"
	if len(addr) < len(loopback) || addr[:len(loopback)] != loopback {
		t.Fatalf("flow api listens on %q, want loopback only", addr)
	}
}

func TestFlowAPIRefusesAMissingOrWrongSecret(t *testing.T) {
	port := startFlowAPIForTest(t, "0123456789abcdef")

	if code, _ := getConnections(t, port, ""); code != http.StatusUnauthorized {
		t.Fatalf("without a header the status is %d, want 401", code)
	}
	if code, _ := getConnections(t, port, "Bearer wrong"); code != http.StatusUnauthorized {
		t.Fatalf("with the wrong secret the status is %d, want 401", code)
	}
	if code, _ := getConnections(t, port, "0123456789abcdef"); code != http.StatusUnauthorized {
		t.Fatalf("without the Bearer prefix the status is %d, want 401", code)
	}
	if code, _ := getConnections(t, port, "Bearer 0123456789abcdef"); code != http.StatusOK {
		t.Fatalf("with the secret the status is %d, want 200", code)
	}
}

func TestFlowAPIServesTheOpenConnections(t *testing.T) {
	port := startFlowAPIForTest(t, "0123456789abcdef")
	addFlow("udp", "203.0.113.9:27015", "direct")

	code, body := getConnections(t, port, "Bearer 0123456789abcdef")
	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200", code)
	}
	var top flowSnapshot
	if err := json.Unmarshal([]byte(body), &top); err != nil {
		t.Fatalf("the body is not the broker's JSON: %v (%s)", err, body)
	}
	if len(top.Connections) != 1 {
		t.Fatalf("connections = %d, want 1", len(top.Connections))
	}
	if got := top.Connections[0].Metadata["destinationPort"]; got != "27015" {
		t.Fatalf("destinationPort = %#v, want the string 27015", got)
	}
}

func TestFlowAPINeedsAPortAndASecret(t *testing.T) {
	t.Cleanup(stopFlowAPI)
	stopFlowAPI()

	for _, bad := range []struct {
		port   int
		secret string
	}{
		{0, "0123456789abcdef"},
		{-1, "0123456789abcdef"},
		{65536, "0123456789abcdef"},
		{9000, ""},
	} {
		startFlowAPI(bad.port, bad.secret)
		flowMu.Lock()
		started := flowServer != nil
		flowMu.Unlock()
		if started {
			t.Fatalf("port=%d secret=%q must not start a server", bad.port, bad.secret)
		}
	}
}

func TestFlowAPIStopsListening(t *testing.T) {
	port := startFlowAPIForTest(t, "0123456789abcdef")
	stopFlowAPI()

	deadline := time.Now().Add(3 * time.Second)
	addr := fmt.Sprintf("127.0.0.1:%d", port)
	for {
		conn, err := net.DialTimeout("tcp", addr, 100*time.Millisecond)
		if err != nil {
			return
		}
		_ = conn.Close()
		if time.Now().After(deadline) {
			t.Fatalf("flow api still accepts connections on %s after stop", addr)
		}
		time.Sleep(20 * time.Millisecond)
	}
}
