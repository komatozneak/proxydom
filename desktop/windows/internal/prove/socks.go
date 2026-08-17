package prove

import (
	"crypto/tls"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"time"
)

// ViaSOCKS5 GETs url through a SOCKS5 proxy (no-auth), matching Android SOCKS prove.
func ViaSOCKS5(proxyAddr, url string, timeout time.Duration) (string, error) {
	if timeout <= 0 {
		timeout = 20 * time.Second
	}
	dialer := &net.Dialer{Timeout: timeout}
	conn, err := dialer.Dial("tcp", proxyAddr)
	if err != nil {
		return "", fmt.Errorf("socks dial: %w", err)
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(timeout))
	if err := socks5Connect(conn, urlHostPort(url)); err != nil {
		return "", err
	}
	transport := &http.Transport{
		Dial: func(network, addr string) (net.Conn, error) {
			return conn, nil
		},
		TLSClientConfig:     &tls.Config{MinVersion: tls.VersionTLS12},
		DisableKeepAlives:   true,
		TLSHandshakeTimeout: timeout,
	}
	client := &http.Client{Transport: transport, Timeout: timeout}
	resp, err := client.Get(url)
	if err != nil {
		return "", fmt.Errorf("prove GET: %w", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("prove HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	return strings.TrimSpace(string(body)), nil
}

func urlHostPort(raw string) string {
	// https://ifconfig.me → ifconfig.me:443
	u := raw
	u = strings.TrimPrefix(u, "https://")
	u = strings.TrimPrefix(u, "http://")
	host, _, _ := strings.Cut(u, "/")
	if !strings.Contains(host, ":") {
		if strings.HasPrefix(raw, "http://") {
			return host + ":80"
		}
		return host + ":443"
	}
	return host
}

func socks5Connect(conn net.Conn, dest string) error {
	if _, err := conn.Write([]byte{0x05, 0x01, 0x00}); err != nil {
		return err
	}
	ack := make([]byte, 2)
	if _, err := io.ReadFull(conn, ack); err != nil {
		return fmt.Errorf("socks greeting: %w", err)
	}
	if ack[0] != 0x05 || ack[1] != 0x00 {
		return fmt.Errorf("socks greeting %v", ack)
	}
	host, portStr, err := net.SplitHostPort(dest)
	if err != nil {
		return err
	}
	var port uint16
	_, err = fmt.Sscanf(portStr, "%d", &port)
	if err != nil {
		return err
	}
	req := []byte{0x05, 0x01, 0x00, 0x03, byte(len(host))}
	req = append(req, host...)
	req = append(req, byte(port>>8), byte(port))
	if _, err := conn.Write(req); err != nil {
		return err
	}
	hdr := make([]byte, 4)
	if _, err := io.ReadFull(conn, hdr); err != nil {
		return fmt.Errorf("socks connect: %w", err)
	}
	if hdr[1] != 0x00 {
		return fmt.Errorf("socks connect status %d", hdr[1])
	}
	switch hdr[3] {
	case 0x01:
		_, err = io.ReadFull(conn, make([]byte, 6))
	case 0x03:
		l := make([]byte, 1)
		if _, err = io.ReadFull(conn, l); err != nil {
			return err
		}
		_, err = io.ReadFull(conn, make([]byte, int(l[0])+2))
	case 0x04:
		_, err = io.ReadFull(conn, make([]byte, 18))
	}
	return err
}
