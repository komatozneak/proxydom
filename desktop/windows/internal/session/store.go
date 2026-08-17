package session

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// File is persisted under %APPDATA%\TeremokConnect\session.json (Windows)
// or ~/.config/teremok-connect/session.json elsewhere.
type File struct {
	DeviceUUID   string `json:"device_uuid"`
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token,omitempty"`
	APISecret    string `json:"api_secret"`
	RecoveryCode string `json:"recovery_code,omitempty"`
}

func Dir() (string, error) {
	if app := os.Getenv("APPDATA"); app != "" {
		return filepath.Join(app, "TeremokConnect"), nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".config", "teremok-connect"), nil
}

func Path() (string, error) {
	dir, err := Dir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "session.json"), nil
}

func Load() (*File, error) {
	p, err := Path()
	if err != nil {
		return nil, err
	}
	raw, err := os.ReadFile(p)
	if err != nil {
		return nil, err
	}
	var f File
	if err := json.Unmarshal(raw, &f); err != nil {
		return nil, fmt.Errorf("session.json: %w", err)
	}
	if f.DeviceUUID == "" || f.APISecret == "" || f.AccessToken == "" {
		return nil, fmt.Errorf("session.json incomplete")
	}
	return &f, nil
}

func (f *File) Save() error {
	dir, err := Dir()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	p := filepath.Join(dir, "session.json")
	raw, err := json.MarshalIndent(f, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(p, raw, 0o600)
}
