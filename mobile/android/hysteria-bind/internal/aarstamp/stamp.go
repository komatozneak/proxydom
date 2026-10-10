// Package aarstamp ties a hysteria-client.aar back to the hy2bind source it was
// built from.
//
// The archive is a build product: CI builds it before the jobs that need it,
// and mobile/android/build-sideload.ps1 builds a production APK from whatever
// archive is on disk. That second path is what this guards. Gradle links
// libs/hysteria-client.aar and not the Go source, so editing hy2bind and
// building a sideload APK without rerunning build-aar.sh ships the old engine
// silently. #317 was exactly that mistake.
//
// "Rebuild and compare bytes" is not the guard: a byte comparison needs the
// exact toolchain of whoever built the archive. So build-aar.sh writes a hash
// of the source into a sidecar next to the archive, and both the Go test and
// build-sideload.ps1 compare that hash to the source.
//
// The sidecar lives beside the archive rather than inside it so that nothing
// has to rewrite the zip. Both files are written by the same script run and are
// gitignored, so they cannot drift from each other in normal use.
package aarstamp

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// SidecarSuffix is appended to the archive path.
const SidecarSuffix = ".source-hash"

// SidecarPath returns the stamp path for an archive.
func SidecarPath(aarPath string) string {
	return aarPath + SidecarSuffix
}

// SourceFiles lists the package files that reach the archive, sorted.
//
// Only the top-level package is hashed, because only it is linked into the
// archive: cmd/proxydom-engine is a separate main package that is never
// imported by hy2bind. Test files are excluded for the same reason.
func SourceFiles(pkgDir string) ([]string, error) {
	entries, err := os.ReadDir(pkgDir)
	if err != nil {
		return nil, err
	}
	var names []string
	for _, e := range entries {
		name := e.Name()
		if e.IsDir() || !strings.HasSuffix(name, ".go") {
			continue
		}
		if strings.HasSuffix(name, "_test.go") {
			continue
		}
		names = append(names, name)
	}
	names = append(names, "go.mod", "go.sum")
	sort.Strings(names)
	return names, nil
}

// SourceHash hashes the name and the content of every file that reaches the
// archive. Line endings are normalised so a Windows checkout and a Linux one
// hash the same source to the same value.
func SourceHash(pkgDir string) (string, error) {
	names, err := SourceFiles(pkgDir)
	if err != nil {
		return "", err
	}
	digest := sha256.New()
	for _, name := range names {
		body, err := os.ReadFile(filepath.Join(pkgDir, name))
		if err != nil {
			return "", err
		}
		body = []byte(strings.ReplaceAll(string(body), "\r\n", "\n"))
		sum := sha256.Sum256(body)
		digest.Write([]byte(name))
		digest.Write([]byte{0})
		digest.Write(sum[:])
	}
	return hex.EncodeToString(digest.Sum(nil)), nil
}

// Write records the source hash beside the archive and returns it.
func Write(pkgDir, aarPath string) (string, error) {
	hash, err := SourceHash(pkgDir)
	if err != nil {
		return "", err
	}
	if err := os.WriteFile(SidecarPath(aarPath), []byte(hash+"\n"), 0o644); err != nil {
		return "", err
	}
	return hash, nil
}

// Read returns the recorded hash, or "" when there is no sidecar.
func Read(aarPath string) (string, error) {
	body, err := os.ReadFile(SidecarPath(aarPath))
	if os.IsNotExist(err) {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(body)), nil
}

// Verify reports whether the archive on disk was built from the current source.
// A missing archive or sidecar is an error: build-aar.sh writes both, so their
// absence means the caller skipped it.
func Verify(pkgDir, aarPath string) error {
	if _, err := os.Stat(aarPath); err != nil {
		return fmt.Errorf("%s is missing: run mobile/android/hysteria-bind/build-aar.sh", aarPath)
	}
	want, err := SourceHash(pkgDir)
	if err != nil {
		return err
	}
	have, err := Read(aarPath)
	if err != nil {
		return err
	}
	if have == "" {
		return fmt.Errorf("%s has no %s: run build-aar.sh", aarPath, SidecarSuffix)
	}
	if have != want {
		return fmt.Errorf("the archive predates the source:\n  source  %s\n  archive %s\nrun build-aar.sh", want, have)
	}
	return nil
}
