package api

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestConnectSignsPathWithoutQuery(t *testing.T) {
	const secret = "unit-secret"
	var sawPath, sawRawQuery, sawSig, sawTS, sawNonce string
	var sawPlatform, sawAuth, sawDevice string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v2/auth/register":
			_ = json.NewEncoder(w).Encode(tokenResponse{
				AccessToken:  "access-token",
				RefreshToken: "refresh-token",
				APISecret:    secret,
				RecoveryCode: "recover-me",
			})
		case "/v2/app/connect/get/v3":
			sawPath = r.URL.Path
			sawRawQuery = r.URL.RawQuery
			sawSig = r.Header.Get("X-Signature")
			sawTS = r.Header.Get("X-Timestamp")
			sawNonce = r.Header.Get("X-Nonce")
			sawPlatform = r.URL.Query().Get("platform")
			sawAuth = r.Header.Get("Authorization")
			sawDevice = r.Header.Get("X-Device-UUID")
			_, _ = w.Write([]byte(`{
				"username": "hy21xabcd",
				"active_core": "hysteria",
				"node_host": "217.60.3.9",
				"hysteria_profile": {
					"schema_version": 1,
					"node_id": "eu-hy2-1",
					"server": "217.60.3.9:443",
					"auth": "user:pass",
					"sni": "hy2-eu.teremokconnect.online",
					"socks_listen": "127.0.0.1:10808"
				}
			}`))
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)

	c := NewClient(srv.URL)
	if _, err := c.Register("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee", "testhost"); err != nil {
		t.Fatal(err)
	}
	got, err := c.Connect("eu-hy2-1", "testhost")
	if err != nil {
		t.Fatal(err)
	}
	if got.HysteriaProfile.NodeID != "eu-hy2-1" {
		t.Fatalf("node: %s", got.HysteriaProfile.NodeID)
	}
	if sawPath != connectPath {
		t.Fatalf("path: %s", sawPath)
	}
	if sawPlatform != "windows" {
		t.Fatalf("platform: %s", sawPlatform)
	}
	if sawRawQuery == "" || sawPath+"?"+sawRawQuery == connectPath {
		t.Fatalf("query must not be in HMAC path, got %q", sawRawQuery)
	}
	if sawAuth != "Bearer access-token" || sawDevice == "" {
		t.Fatalf("auth headers missing: %s %s", sawAuth, sawDevice)
	}
	want := SignPayload(secret, sawTS, sawNonce, http.MethodGet, connectPath, nil)
	if sawSig != want {
		t.Fatalf("HMAC used the wrong canonical path/body:\n got %s\nwant %s", sawSig, want)
	}
}

func TestRegisterHTTPError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = io.WriteString(w, `{"error":{"code":"bad"}}`)
	}))
	t.Cleanup(srv.Close)
	c := NewClient(srv.URL)
	if _, err := c.Register("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee", "x"); err == nil {
		t.Fatal("expected error")
	}
}
