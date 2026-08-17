package api

import (
	"encoding/json"
	"fmt"
	"strings"
)

// ConnectResponse is GET /v2/app/connect/get/v3 (same body as /vpn/config).
type ConnectResponse struct {
	Username        string           `json:"username"`
	ActiveCore      string           `json:"active_core"`
	NodeHost        string           `json:"node_host"`
	HysteriaProfile *HysteriaProfile `json:"hysteria_profile"`
}

// HysteriaProfile is schema_version=1 from the control plane.
type HysteriaProfile struct {
	SchemaVersion int    `json:"schema_version"`
	NodeID        string `json:"node_id"`
	Server        string `json:"server"`
	Auth          string `json:"auth"`
	Username      string `json:"username"`
	SNI           string `json:"sni"`
	SocksListen   string `json:"socks_listen"`
	BandwidthUp   string `json:"bandwidth_up"`
	BandwidthDown string `json:"bandwidth_down"`
}

// ParseConnectBody decodes and validates a Hy2 connect payload.
func ParseConnectBody(raw []byte) (*ConnectResponse, error) {
	var resp ConnectResponse
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("connect json: %w", err)
	}
	if strings.TrimSpace(resp.ActiveCore) != "hysteria" {
		return nil, fmt.Errorf("active_core=%q, want hysteria", resp.ActiveCore)
	}
	if resp.HysteriaProfile == nil {
		return nil, fmt.Errorf("missing hysteria_profile")
	}
	p := resp.HysteriaProfile
	if p.SchemaVersion != 0 && p.SchemaVersion != 1 {
		return nil, fmt.Errorf("unsupported hysteria_profile schema_version=%d", p.SchemaVersion)
	}
	if strings.TrimSpace(p.Server) == "" || strings.TrimSpace(p.Auth) == "" {
		return nil, fmt.Errorf("incomplete hysteria_profile")
	}
	if strings.TrimSpace(p.SocksListen) == "" {
		p.SocksListen = "127.0.0.1:10808"
	}
	return &resp, nil
}
