//go:build windows

package proc

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"

	"golang.org/x/sys/windows"
)

const createNoWindow = 0x08000000

type windowsStarter struct{}

func NewStarter() Starter { return windowsStarter{} }

func (windowsStarter) Start(opts StartOpts) (Handle, error) {
	exe := opts.HysteriaPath
	if exe == "" {
		exe = filepath.Join(opts.WorkDir, "hysteria.exe")
	}
	if _, err := os.Stat(exe); err != nil {
		return nil, fmt.Errorf("hysteria.exe: %w", err)
	}
	if _, err := os.Stat(opts.ConfigPath); err != nil {
		return nil, fmt.Errorf("config: %w", err)
	}
	// Explicit `client` subcommand (hysteria app/v2.6.2). YAML with `server:` is client mode.
	logPath := filepath.Join(opts.WorkDir, "hysteria.log")
	if opts.Elevated {
		script, err := writeElevatedRunner(opts.WorkDir, exe, opts.ConfigPath, logPath)
		if err != nil {
			return nil, err
		}
		if err := shellRunAs(script, "", opts.WorkDir); err != nil {
			return nil, err
		}
		return elevatedHandle{}, nil
	}
	cmd := exec.Command(exe, "client", "-c", opts.ConfigPath)
	cmd.Dir = opts.WorkDir
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: createNoWindow}
	logFile, err := os.Create(logPath)
	if err != nil {
		return nil, err
	}
	cmd.Stdout = logFile
	cmd.Stderr = logFile
	if err := cmd.Start(); err != nil {
		_ = logFile.Close()
		return nil, err
	}
	return &userHandle{cmd: cmd, log: logFile}, nil
}

type userHandle struct {
	cmd *exec.Cmd
	log *os.File
}

func (h *userHandle) Stop() error {
	if h.cmd != nil && h.cmd.Process != nil {
		_ = h.cmd.Process.Kill()
		_, _ = h.cmd.Process.Wait()
	}
	if h.log != nil {
		_ = h.log.Close()
	}
	return nil
}

type elevatedHandle struct{}

func (elevatedHandle) Stop() error {
	// Unelevated host cannot OpenProcess an elevated hysteria. Re-run taskkill
	// via UAC (same pattern as start).
	sysRoot := os.Getenv("SystemRoot")
	if sysRoot == "" {
		sysRoot = `C:\Windows`
	}
	taskkill := filepath.Join(sysRoot, "System32", "taskkill.exe")
	return shellRunAs(taskkill, "/F /IM hysteria.exe", "")
}

func writeElevatedRunner(workDir, exe, configPath, logPath string) (string, error) {
	script := filepath.Join(workDir, "run-hy2.cmd")
	body := fmt.Sprintf("@echo off\r\n\"%s\" client -c \"%s\" -l debug > \"%s\" 2>&1\r\n", exe, configPath, logPath)
	if err := os.WriteFile(script, []byte(body), 0o700); err != nil {
		return "", err
	}
	return script, nil
}

func shellRunAs(file, params, dir string) error {
	verb, err := windows.UTF16PtrFromString("runas")
	if err != nil {
		return err
	}
	f, err := windows.UTF16PtrFromString(file)
	if err != nil {
		return err
	}
	p, err := windows.UTF16PtrFromString(params)
	if err != nil {
		return err
	}
	var d *uint16
	if dir != "" {
		d, err = windows.UTF16PtrFromString(dir)
		if err != nil {
			return err
		}
	}
	return windows.ShellExecute(0, verb, f, p, d, int32(windows.SW_HIDE))
}
