package hy2bind

import (
	"archive/zip"
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/komatozneak/proxydom/hy2bind/internal/aarstamp"
)

// aarPath is the committed archive, relative to this package.
const aarPath = "../app/libs/hysteria-client.aar"

// The archive is a committed build product, and nothing rebuilt it
// automatically: #317 changed this package, the archive stayed behind, and CI
// stayed green because these Go tests test the source while the Android tests
// link the stale archive. These two checks close that: the first fails when the
// package changed and the archive was not rebuilt, the second fails when the
// stamp was rewritten without rebuilding.
//
// They are deliberately separate. Editing aar_stamp.go by hand passes the
// second check but fails the first; rerunning only `aarstamp write` passes the
// first but fails the second. Only build-aar.sh, which stamps and then binds,
// passes both.
func TestAARStampMatchesTheSource(t *testing.T) {
	want, err := aarstamp.SourceHash(".")
	if err != nil {
		t.Fatal(err)
	}
	have, err := aarstamp.CurrentStamp(".")
	if err != nil {
		t.Fatal(err)
	}
	if have == "" {
		t.Fatalf("no stamp in %s: run mobile/android/hysteria-bind/build-aar.sh", aarstamp.StampFile)
	}
	if have != want {
		t.Fatalf("the package changed since the archive was built:\n  source %s\n  stamp  %s\nrebuild with build-aar.sh", want, have)
	}
}

func TestCommittedAARCarriesTheStamp(t *testing.T) {
	stamp, err := aarstamp.CurrentStamp(".")
	if err != nil {
		t.Fatal(err)
	}
	if stamp == "" {
		t.Fatalf("no stamp in %s: run build-aar.sh", aarstamp.StampFile)
	}

	zr, err := zip.OpenReader(filepath.FromSlash(aarPath))
	if err != nil {
		t.Fatalf("the committed archive is missing or unreadable: %v", err)
	}
	defer zr.Close()

	// arm64 is the ABI the phone builds for. Checking one is enough: all four
	// are produced by the same bind from the same source.
	const entry = "jni/arm64-v8a/libhyjni.so"
	var found bool
	for _, f := range zr.File {
		if f.Name != entry {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			t.Fatal(err)
		}
		var buf bytes.Buffer
		if _, err := buf.ReadFrom(rc); err != nil {
			rc.Close()
			t.Fatal(err)
		}
		rc.Close()
		body := buf.Bytes()
		if !bytes.Contains(body, []byte(stamp)) {
			t.Fatalf("%s does not carry the stamp %s: the archive was not rebuilt after the source changed", entry, stamp)
		}
		found = true
		break
	}
	if !found {
		t.Fatalf("%s has no %s", aarPath, entry)
	}
}

// A stale archive is the failure this guards, so the guard has to be able to
// tell a rebuilt archive from a hand-edited stamp. This pins the one property
// that makes it work: the stamp is a hash of the package source, not a
// free-form string, so it changes when the source changes.
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

	// Line endings are a checkout artefact, not a source change.
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
