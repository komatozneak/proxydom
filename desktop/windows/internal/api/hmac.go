package api

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strings"
	"time"
)

// SignHeaders builds ADR 012 X-Signature headers for a /v2 request.
//
// Canonical payload (must match backend hmac_signature.build_signature_payload):
//
//	timestamp \n nonce \n METHOD \n path \n sha256hex(body)
//
// Path is the URL path without query string (e.g. /v2/app/connect/get/v3).
func SignHeaders(apiSecret, method, path string, body []byte) (map[string]string, error) {
	if apiSecret == "" {
		return nil, fmt.Errorf("api_secret is empty")
	}
	ts := fmt.Sprintf("%d", time.Now().UTC().Unix())
	nonce, err := randomNonce()
	if err != nil {
		return nil, err
	}
	sig := SignPayload(apiSecret, ts, nonce, method, path, body)
	return map[string]string{
		"X-Timestamp": ts,
		"X-Nonce":     nonce,
		"X-Signature": sig,
	}, nil
}

// SignPayload is the testable HMAC body (hex lowercase).
func SignPayload(apiSecret, timestamp, nonce, method, path string, body []byte) string {
	sum := sha256.Sum256(body)
	bodyHash := hex.EncodeToString(sum[:])
	payload := timestamp + "\n" + nonce + "\n" + strings.ToUpper(method) + "\n" + path + "\n" + bodyHash
	mac := hmac.New(sha256.New, []byte(apiSecret))
	_, _ = mac.Write([]byte(payload))
	return hex.EncodeToString(mac.Sum(nil))
}

func randomNonce() (string, error) {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}
