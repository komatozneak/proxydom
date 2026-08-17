package session

import (
	"path/filepath"
	"testing"
)

func TestSaveLoadRoundTrip(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	in := &File{
		DeviceUUID:   "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
		AccessToken:  "access",
		RefreshToken: "refresh",
		APISecret:    "secret",
		RecoveryCode: "recover",
	}
	if err := in.Save(); err != nil {
		t.Fatal(err)
	}
	out, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if out.DeviceUUID != in.DeviceUUID || out.APISecret != in.APISecret {
		t.Fatalf("round-trip: %+v", out)
	}
	p, err := Path()
	if err != nil {
		t.Fatal(err)
	}
	if filepath.Base(p) != "session.json" {
		t.Fatalf("path: %s", p)
	}
}

func TestLoadIncomplete(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	if err := (&File{DeviceUUID: "only-id"}).Save(); err != nil {
		t.Fatal(err)
	}
	if _, err := Load(); err == nil {
		t.Fatal("expected incomplete session error")
	}
}
