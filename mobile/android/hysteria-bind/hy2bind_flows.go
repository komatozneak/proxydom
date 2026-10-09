package hy2bind

import (
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"sync"
	"sync/atomic"
)

// flowRec is one row the broker reads from GET /connections. The last chain
// entry is the outbound name flow_probe.cpp keeps.
type flowRec struct {
	id       string
	network  string
	dest     string
	chain    string
	upload   atomic.Int64
	download atomic.Int64
}

var (
	flowMu     sync.Mutex
	flowTable  = map[string]*flowRec{}
	flowSeq    atomic.Uint64
	flowServer *http.Server
)

func trackStream(conn net.Conn, network, dest, chain string) net.Conn {
	rec := addFlow(network, dest, chain)
	return &countingConn{Conn: conn, rec: rec}
}

func trackPacket(pc net.PacketConn, network, dest, chain string) net.PacketConn {
	rec := addFlow(network, dest, chain)
	return &countingPacket{PacketConn: pc, rec: rec}
}

func addFlow(network, dest, chain string) *flowRec {
	id := fmt.Sprintf("%x", flowSeq.Add(1))
	rec := &flowRec{id: id, network: network, dest: dest, chain: chain}
	flowMu.Lock()
	flowTable[id] = rec
	flowMu.Unlock()
	return rec
}

func forgetFlow(id string) {
	flowMu.Lock()
	delete(flowTable, id)
	flowMu.Unlock()
}

func snapshotFlows() []map[string]any {
	flowMu.Lock()
	defer flowMu.Unlock()
	out := make([]map[string]any, 0, len(flowTable))
	for _, rec := range flowTable {
		host, port, _ := net.SplitHostPort(rec.dest)
		out = append(out, map[string]any{
			"id": rec.id,
			"metadata": map[string]string{
				"network":         rec.network,
				"host":            host,
				"destinationIP":   host,
				"destinationPort": port,
				"processPath":     "",
			},
			"upload":   rec.upload.Load(),
			"download": rec.download.Load(),
			"chains":   []string{rec.chain},
		})
	}
	return out
}

type countingConn struct {
	net.Conn
	rec *flowRec
}

func (c *countingConn) Read(p []byte) (int, error) {
	n, err := c.Conn.Read(p)
	if n > 0 {
		c.rec.download.Add(int64(n))
	}
	return n, err
}

func (c *countingConn) Write(p []byte) (int, error) {
	n, err := c.Conn.Write(p)
	if n > 0 {
		c.rec.upload.Add(int64(n))
	}
	return n, err
}

func (c *countingConn) Close() error {
	forgetFlow(c.rec.id)
	return c.Conn.Close()
}

type countingPacket struct {
	net.PacketConn
	rec *flowRec
}

func (c *countingPacket) ReadFrom(p []byte) (int, net.Addr, error) {
	n, addr, err := c.PacketConn.ReadFrom(p)
	if n > 0 {
		c.rec.download.Add(int64(n))
	}
	return n, addr, err
}

func (c *countingPacket) WriteTo(p []byte, addr net.Addr) (int, error) {
	n, err := c.PacketConn.WriteTo(p, addr)
	if n > 0 {
		c.rec.upload.Add(int64(n))
	}
	return n, err
}

func (c *countingPacket) Close() error {
	forgetFlow(c.rec.id)
	return c.PacketConn.Close()
}

func startFlowAPI(port int, secret string) {
	if port <= 0 || port > 65535 || secret == "" {
		return
	}
	stopFlowAPI()
	mux := http.NewServeMux()
	mux.HandleFunc("/connections", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer "+secret {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"connections": snapshotFlows()})
	})
	srv := &http.Server{Addr: fmt.Sprintf("127.0.0.1:%d", port), Handler: mux}
	flowMu.Lock()
	flowServer = srv
	flowMu.Unlock()
	go func() { _ = srv.ListenAndServe() }()
}

func stopFlowAPI() {
	flowMu.Lock()
	srv := flowServer
	flowServer = nil
	flowMu.Unlock()
	if srv != nil {
		_ = srv.Close()
	}
}
