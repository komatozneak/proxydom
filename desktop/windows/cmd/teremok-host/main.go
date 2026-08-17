package main

import (
	"crypto/rand"
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/komatozneak/teremok-connect/desktop/windows/internal/api"
	"github.com/komatozneak/teremok-connect/desktop/windows/internal/hy2config"
	"github.com/komatozneak/teremok-connect/desktop/windows/internal/proc"
	"github.com/komatozneak/teremok-connect/desktop/windows/internal/prove"
	"github.com/komatozneak/teremok-connect/desktop/windows/internal/session"
	"github.com/komatozneak/teremok-connect/desktop/windows/internal/ui"
)

func main() {
	log.SetFlags(log.LstdFlags | log.Lmsgprefix)
	log.SetPrefix("teremok-host: ")
	if err := run(); err != nil {
		log.Printf("%v", err)
		os.Exit(1)
	}
}

func run() error {
	origin := flag.String("origin", api.DefaultOrigin, "control-plane origin (scheme+host+port)")
	binDir := flag.String("bin-dir", "", "directory with hysteria.exe + wintun.dll (default: exe dir)")
	mode := flag.String("mode", "socks", "socks (no UAC) or tun (Wintun, UAC)")
	nodeID := flag.String("node", "", "optional catalog node_id")
	headless := flag.Bool("headless", false, "no tray; connect then wait for Ctrl+C")
	once := flag.Bool("once", false, "connect, optional prove, disconnect, exit (implies -headless)")
	doProve := flag.Bool("prove", false, "HTTPS GET via local SOCKS after connect")
	proveURL := flag.String("prove-url", "https://ifconfig.me/ip", "URL for -prove")
	flag.Parse()
	if *once {
		*headless = true
	}

	m := hy2config.Mode(strings.ToLower(strings.TrimSpace(*mode)))
	if m != hy2config.ModeSOCKS && m != hy2config.ModeTUN {
		return fmt.Errorf("mode must be socks or tun")
	}
	workDir, err := resolveBinDir(*binDir)
	if err != nil {
		return err
	}
	host := newHost(*origin, workDir, *nodeID, *proveURL)
	if err := host.ensureSession(); err != nil {
		return err
	}

	if *headless {
		if err := host.connect(m, *doProve); err != nil {
			return err
		}
		if *once {
			log.Printf("connected mode=%s; -once disconnecting", m)
			return host.disconnect()
		}
		log.Printf("connected mode=%s; Ctrl+C to stop", m)
		waitSignal()
		return host.disconnect()
	}

	host.mu.Lock()
	host.wantProve = *doProve
	host.mu.Unlock()
	log.Printf("tray ready; right-click the icon. bins=%s", workDir)
	return ui.RunTray(ui.Callbacks{
		OnConnectSOCKS: func() { host.logErr(host.connect(hy2config.ModeSOCKS, host.wantProve)) },
		OnConnectTUN:   func() { host.logErr(host.connect(hy2config.ModeTUN, host.wantProve)) },
		OnDisconnect:   func() { host.logErr(host.disconnect()) },
		OnQuit: func() {
			_ = host.disconnect()
		},
	})
}

type host struct {
	origin    string
	workDir   string
	nodeID    string
	proveURL  string
	wantProve bool
	client    *api.Client
	starter   proc.Starter
	mu        sync.Mutex
	child     proc.Handle
}

func newHost(origin, workDir, nodeID, proveURL string) *host {
	return &host{
		origin:   origin,
		workDir:  workDir,
		nodeID:   nodeID,
		proveURL: proveURL,
		client:   api.NewClient(origin),
		starter:  proc.NewStarter(),
	}
}

func (h *host) logErr(err error) {
	if err != nil {
		log.Printf("%v", err)
		ui.SetTip("Teremok: " + err.Error())
	}
}

func (h *host) ensureSession() error {
	name, _ := os.Hostname()
	if name == "" {
		name = "Windows"
	}
	if saved, err := session.Load(); err == nil {
		h.client.DeviceUUID = saved.DeviceUUID
		h.client.Access = saved.AccessToken
		h.client.Refresh = saved.RefreshToken
		h.client.APISecret = saved.APISecret
		log.Printf("session loaded device=%s", saved.DeviceUUID[:8])
		return nil
	}
	id, err := newUUIDv4()
	if err != nil {
		return err
	}
	recovery, err := h.client.Register(id, name)
	if err != nil {
		return err
	}
	file := &session.File{
		DeviceUUID:   id,
		AccessToken:  h.client.Access,
		RefreshToken: h.client.Refresh,
		APISecret:    h.client.APISecret,
		RecoveryCode: recovery,
	}
	if err := file.Save(); err != nil {
		return err
	}
	log.Printf("registered device=%s (recovery saved in %%APPDATA%%\\TeremokConnect)", id[:8])
	return nil
}

func (h *host) connect(mode hy2config.Mode, doProve bool) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.child != nil {
		_ = h.child.Stop()
		h.child = nil
	}
	name, _ := os.Hostname()
	cfg, err := h.client.Connect(h.nodeID, name)
	if err != nil {
		return err
	}
	yamlPath := filepath.Join(h.workDir, "hysteria.yaml")
	if err := hy2config.WriteFile(yamlPath, hy2config.Options{
		Profile:  cfg.HysteriaProfile,
		NodeHost: cfg.NodeHost,
		Mode:     mode,
	}); err != nil {
		return err
	}
	hy := filepath.Join(h.workDir, "hysteria.exe")
	handle, err := h.starter.Start(proc.StartOpts{
		HysteriaPath: hy,
		ConfigPath:   yamlPath,
		WorkDir:      h.workDir,
		Elevated:     mode == hy2config.ModeTUN,
	})
	if err != nil {
		return err
	}
	h.child = handle
	listen := cfg.HysteriaProfile.SocksListen
	if listen == "" {
		listen = "127.0.0.1:10808"
	}
	ui.SetTip("Teremok: connecting " + string(mode))
	log.Printf("hysteria started mode=%s node=%s socks=%s", mode, cfg.HysteriaProfile.NodeID, listen)
	if doProve {
		if err := waitSOCKS(listen, 20*time.Second); err != nil {
			return err
		}
		ip, err := prove.ViaSOCKS5(listen, h.proveURL, 25*time.Second)
		if err != nil {
			return fmt.Errorf("socks prove: %w", err)
		}
		log.Printf("prove egress=%s expected_host=%s", ip, cfg.NodeHost)
		ui.SetTip("Teremok: " + ip)
	} else {
		ui.SetTip("Teremok: " + string(mode) + " " + cfg.HysteriaProfile.NodeID)
	}
	return nil
}

func (h *host) disconnect() error {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.child == nil {
		return nil
	}
	err := h.child.Stop()
	h.child = nil
	ui.SetTip("Teremok: disconnected")
	log.Printf("disconnected")
	return err
}

func waitSOCKS(addr string, d time.Duration) error {
	deadline := time.Now().Add(d)
	var last error
	for time.Now().Before(deadline) {
		c, err := net.DialTimeout("tcp", addr, time.Second)
		if err == nil {
			_ = c.Close()
			return nil
		}
		last = err
		time.Sleep(400 * time.Millisecond)
	}
	return fmt.Errorf("socks %s not up: %v", addr, last)
}

func resolveBinDir(flagDir string) (string, error) {
	if strings.TrimSpace(flagDir) != "" {
		return filepath.Abs(flagDir)
	}
	exe, err := os.Executable()
	if err != nil {
		return os.Getwd()
	}
	return filepath.Abs(filepath.Dir(exe))
}

func waitSignal() {
	ch := make(chan os.Signal, 1)
	signal.Notify(ch, os.Interrupt, syscall.SIGTERM)
	<-ch
}

func newUUIDv4() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:]), nil
}
