//go:build !windows

package ui

import "fmt"

func RunTray(Callbacks) error {
	return fmt.Errorf("tray UI is Windows-only; use -headless")
}

func SetTip(string) {}
