package hy2bind

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/komatozneak/proxydom/hy2bind/internal/aarstamp"
)

// aarPath is the built archive, relative to this package. It is gitignored:
// build-aar.sh produces it, and CI builds it before the jobs that link it.
const aarPath = "../app/libs/hysteria-client.aar"

// Gradle links libs/hysteria-client.aar and not this source, so editing the
// package and building an APK without rerunning build-aar.sh ships the old
// engine silently. #317 was exactly that mistake: the package gained
// maybeHop, startFlowAPI, setHijackDNS, setUDPDirect, setExtraForceSuffixes and
// seven startConfig fields, the archive was not rebuilt, and CI stayed green
// because the Go tests test the source while the Android tests linked the
// stale archive.
//
// On a fresh checkout there is no archive and there is nothing to compare, so
// this skips. build-sideload.ps1 runs the same check through aarstamp verify,
// where an absent archive is an error rather than a skip.
func TestLocalAARMatchesTheSource(t *testing.T) {
	if _, err := os.Stat(aarPath); os.IsNotExist(err) {
		t.Skipf("%s is not built; build-aar.sh produces it", aarPath)
	}
	if err := aarstamp.Verify(".", aarPath); err != nil {
		t.Fatalf("%v", err)
	}
}

// The guard is only worth having if it can tell a fresh archive from a stale
// one, so this pins the properties it rests on.
func TestTheStampTracksTheSource(t *testing.T) {
	dir := t.TempDir()
	for _, name := range []string{"a.go", "go.mod", "go.sum"} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte("package p\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	before, err := aarstamp.SourceHash(dir)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "a.go"), []byte("package p\n\nvar x = 1\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	after, err := aarstamp.SourceHash(dir)
	if err != nil {
		t.Fatal(err)
	}
	if before == after {
		t.Fatal("a content change left the hash alone, so the guard cannot see a stale archive")
	}

	// A test file never reaches the archive, so it must not move the hash
	// either: a test-only change should not demand a rebuild.
	if err := os.WriteFile(filepath.Join(dir, "a_test.go"), []byte("package p\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	withTest, err := aarstamp.SourceHash(dir)
	if err != nil {
		t.Fatal(err)
	}
	if withTest != after {
		t.Fatal("a test file moved the hash, so a test-only change would demand a rebuild")
	}

	// Line endings are a checkout artefact, not a source change. Without this
	// the guard would fail on every Windows checkout and pass on Linux.
	if err := os.WriteFile(filepath.Join(dir, "a.go"), []byte(strings.ReplaceAll("package p\n\nvar x = 1\n", "\n", "\r\n")), 0o644); err != nil {
		t.Fatal(err)
	}
	crlf, err := aarstamp.SourceHash(dir)
	if err != nil {
		t.Fatal(err)
	}
	if crlf != after {
		t.Fatal("line endings moved the hash, so the guard would fail on a Windows checkout")
	}
}

// Verify is what build-sideload.ps1 runs, so its refusals are the ones that
// stop a stale production APK. Exercise each of them.
func TestVerifyRefusesAStaleOrMissingArchive(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "a.go"), []byte("package p\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "go.mod"), []byte("module p\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "go.sum"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	aar := filepath.Join(dir, "out.aar")

	if err := aarstamp.Verify(dir, aar); err == nil {
		t.Fatal("a missing archive passed verification")
	}

	if err := os.WriteFile(aar, []byte("not a real archive"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := aarstamp.Verify(dir, aar); err == nil {
		t.Fatal("an archive with no sidecar passed verification")
	}

	if _, err := aarstamp.Write(dir, aar); err != nil {
		t.Fatal(err)
	}
	if err := aarstamp.Verify(dir, aar); err != nil {
		t.Fatalf("a freshly stamped archive failed verification: %v", err)
	}

	// The failure this exists for.
	if err := os.WriteFile(filepath.Join(dir, "a.go"), []byte("package p\n\nvar y = 2\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	err := aarstamp.Verify(dir, aar)
	if err == nil {
		t.Fatal("an archive built from older source passed verification")
	}
	if !strings.Contains(err.Error(), "predates") {
		t.Fatalf("the refusal does not say what is wrong: %v", err)
	}
}
