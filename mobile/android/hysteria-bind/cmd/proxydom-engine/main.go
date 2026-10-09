//go:build windows

// Command proxydom-engine is the Windows tunnel process. The broker starts it
// as `proxydom-engine.exe run -c <config>` and reads this process's stdout and
// stderr as one stream. Ctrl+Break is os.Interrupt here and must exit within
// about two seconds.
package main

import (
	"fmt"
	"log"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"strings"

	"github.com/komatozneak/proxydom/hy2bind"
)

func main() {
	log.SetFlags(0)
	if len(os.Args) != 4 || os.Args[1] != "run" || os.Args[2] != "-c" {
		log.Printf("win32=%d", 87) // ERROR_INVALID_PARAMETER
		os.Exit(2)
	}
	raw, err := os.ReadFile(os.Args[3])
	if err != nil {
		log.Printf("win32=%d", 2) // ERROR_FILE_NOT_FOUND
		os.Exit(1)
	}
	cfg, err := parseEngineConfig(raw)
	if err != nil {
		log.Printf("win32=%d", 13) // ERROR_INVALID_DATA
		os.Exit(1)
	}
	if cfg.rejectTransport() {
		// Not a Win32 code. "error " followed by a non-number is ignored by
		// the broker's digit scan, and the word is the refusal itself.
		log.Printf("error transport")
		os.Exit(1)
	}
	start, err := cfg.hy2StartJSON()
	if err != nil {
		log.Printf("hy2 start failed")
		os.Exit(1)
	}
	if msg := hy2bind.Start(string(start)); msg != "" {
		// The core's error can echo the auth string. The broker log must not.
		if strings.Contains(msg, cfg.Outbound.Password) || cfg.Outbound.Password == "" {
			log.Printf("hy2 start failed")
		} else {
			log.Printf("hy2 start failed: %s", msg)
		}
		os.Exit(1)
	}
	log.Printf("%s", cfg.statusLine())
	if !cfg.Probe {
		if err := startTUN(cfg); err != nil {
			log.Printf("%s", err.Error())
			if strings.Contains(strings.ToLower(err.Error()), "already exists") {
				log.Printf("already exists")
			}
			hy2bind.Stop()
			os.Exit(1)
		}
	}
	waitForBreak()
	hy2bind.Stop()
}

func startTUN(cfg engineConfig) error {
	if cfg.Tun == nil || cfg.Tun.AutoRoute {
		return fmt.Errorf("win32=%d", 87)
	}
	if msg := hy2bind.OpenNamedTun(cfg.Tun.Name, cfg.Tun.MTU); msg != "" {
		return fmt.Errorf("%s", msg)
	}
	if err := assignTunIPv4(cfg.Tun.Name, cfg.Tun.Address); err != nil {
		hy2bind.StopTun()
		return err
	}
	if msg := hy2bind.StartTunStack(); msg != "" {
		hy2bind.StopTun()
		return fmt.Errorf("%s", msg)
	}
	return nil
}

// assignTunIPv4 sets the address the broker already expects. It does not add
// routes: C++ owns install_capture.
//
// It deliberately does not advertise the config's dns address as a resolver on
// the adapter. This process hijacks DNS that arrives through the tun and
// forwards it, but it is not a DNS server, and pointing Windows at an address
// nothing answers on makes every lookup wait out a timeout. Measured on the
// owner's machine: the broker's resolve gate failed after eight seconds once
// the address became Preferred, while the same gate had passed instantly
// moments before, when the adapter still had no usable address and Windows was
// still using the physical resolver. Leaving the adapter alone keeps that
// resolver: before capture its queries go out directly, and afterwards they
// enter the tun and the hijack forwards them, so nothing is lost.
func assignTunIPv4(name, cidr string) error {
	ip, mask, err := splitCIDR(cidr)
	if err != nil {
		return fmt.Errorf("win32=%d", 87)
	}
	if msg, err := netsh("interface", "ipv4", "set", "address", "name="+name, "source=static", "addr="+ip, "mask="+mask); err != nil {
		return fmt.Errorf("netsh address: %s", msg)
	}
	return nil
}

func netsh(args ...string) (string, error) {
	cmd := exec.Command("netsh", args...)
	out, err := cmd.CombinedOutput()
	text := strings.TrimSpace(string(out))
	if err != nil {
		return text, err
	}
	return text, nil
}

func splitCIDR(cidr string) (string, string, error) {
	ip, network, err := net.ParseCIDR(cidr)
	if err != nil {
		return "", "", err
	}
	ones, bits := network.Mask.Size()
	if bits != 32 || ones < 0 {
		return "", "", fmt.Errorf("not ipv4")
	}
	v4 := ip.To4()
	if v4 == nil {
		return "", "", fmt.Errorf("not ipv4")
	}
	return v4.String(), net.IP(network.Mask).String(), nil
}

func waitForBreak() {
	ch := make(chan os.Signal, 1)
	signal.Notify(ch, os.Interrupt)
	<-ch
	signal.Stop(ch)
}
