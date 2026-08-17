package api

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const (
	DefaultOrigin    = "https://api.teremokconnect.online:8443"
	registerPath     = "/v2/auth/register"
	connectPath      = "/v2/app/connect/get/v3"
	defaultUserAgent = "TeremokConnect-Windows/0.1"
)

// Client talks to the v2 control plane (HMAC after register).
type Client struct {
	Origin     string
	HTTP       *http.Client
	DeviceUUID string
	APISecret  string
	Access     string
	Refresh    string
}

func NewClient(origin string) *Client {
	o := strings.TrimRight(strings.TrimSpace(origin), "/")
	if o == "" {
		o = DefaultOrigin
	}
	return &Client{
		Origin: o,
		HTTP: &http.Client{
			Timeout: 90 * time.Second,
		},
	}
}

type registerRequest struct {
	DeviceUUID string `json:"device_uuid"`
	Platform   string `json:"platform"`
	DeviceName string `json:"device_name"`
}

type tokenResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	APISecret    string `json:"api_secret"`
	RecoveryCode string `json:"recovery_code"`
	HasAccess    bool   `json:"has_access"`
}

// Register is HMAC-exempt (ADR 012).
func (c *Client) Register(deviceUUID, deviceName string) (recovery string, err error) {
	body, err := json.Marshal(registerRequest{
		DeviceUUID: deviceUUID,
		Platform:   "windows",
		DeviceName: deviceName,
	})
	if err != nil {
		return "", err
	}
	req, err := http.NewRequest(http.MethodPost, c.Origin+registerPath, bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", defaultUserAgent)
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("register HTTP %d: %s", resp.StatusCode, truncate(raw, 400))
	}
	var tok tokenResponse
	if err := json.Unmarshal(raw, &tok); err != nil {
		return "", fmt.Errorf("register json: %w", err)
	}
	if tok.AccessToken == "" || tok.APISecret == "" {
		return "", fmt.Errorf("register missing access_token/api_secret")
	}
	c.DeviceUUID = deviceUUID
	c.Access = tok.AccessToken
	c.Refresh = tok.RefreshToken
	c.APISecret = tok.APISecret
	return tok.RecoveryCode, nil
}

// Connect mints a Hy2 profile. HMAC path is /v2/app/connect/get/v3 (no query).
func (c *Client) Connect(nodeID, deviceName string) (*ConnectResponse, error) {
	if c.Access == "" || c.APISecret == "" || c.DeviceUUID == "" {
		return nil, fmt.Errorf("not registered")
	}
	q := url.Values{}
	q.Set("device_id", c.DeviceUUID)
	q.Set("platform", "windows")
	if strings.TrimSpace(deviceName) != "" {
		q.Set("device_name", deviceName)
	}
	if strings.TrimSpace(nodeID) != "" {
		q.Set("node_id", nodeID)
	}
	raw, err := c.signedGet(connectPath, q)
	if err != nil {
		return nil, err
	}
	return ParseConnectBody(raw)
}

func (c *Client) signedGet(path string, query url.Values) ([]byte, error) {
	u := c.Origin + path
	if len(query) > 0 {
		u += "?" + query.Encode()
	}
	req, err := http.NewRequest(http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	hdrs, err := SignHeaders(c.APISecret, http.MethodGet, path, nil)
	if err != nil {
		return nil, err
	}
	for k, v := range hdrs {
		req.Header.Set(k, v)
	}
	req.Header.Set("Authorization", "Bearer "+c.Access)
	req.Header.Set("X-Device-UUID", c.DeviceUUID)
	req.Header.Set("User-Agent", defaultUserAgent)
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("%s HTTP %d: %s", path, resp.StatusCode, truncate(raw, 400))
	}
	return raw, nil
}

func truncate(b []byte, n int) string {
	s := string(b)
	if len(s) > n {
		return s[:n] + "…"
	}
	return s
}
