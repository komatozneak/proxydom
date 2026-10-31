package hy2bind

import (
	"crypto/sha256"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

var updateNotices = flag.Bool("update-notices", false,
	"rewrite THIRD-PARTY-NOTICES.md from the shipped dependency graph")

// noticesPath is a Flutter asset, so one file reaches the APK, the IPA and the
// Windows window's flutter_assets; build-msi.ps1 also copies it next to the
// executables.
const noticesPath = "../../assets/legal/THIRD-PARTY-NOTICES.md"

var copyrightLine = regexp.MustCompile(`(?i)^(copyright\b\s*(\(c\)|©|\d{4}|by\b)|(\(c\)|©)\s*\d{4})`)

type noticeEntry struct {
	name, version string
	classes       []string
	files         []licenseFile
}

func copyrightLines(files []licenseFile) []string {
	var out []string
	seen := map[string]bool{}
	for _, f := range files {
		for _, line := range strings.Split(f.text, "\n") {
			line = strings.Join(strings.Fields(line), " ")
			if !copyrightLine.MatchString(line) || seen[line] {
				continue
			}
			seen[line] = true
			out = append(out, line)
		}
	}
	return out
}

func cleanLicenseText(text string) string {
	lines := strings.Split(strings.ReplaceAll(text, "\r\n", "\n"), "\n")
	for i, l := range lines {
		lines[i] = strings.TrimRight(l, " \t\r")
	}
	return strings.Trim(strings.Join(lines, "\n"), "\n")
}

func codeFence(text string) string {
	longest, run := 0, 0
	for _, r := range text {
		if r == '`' {
			run++
			if run > longest {
				longest = run
			}
		} else {
			run = 0
		}
	}
	if longest < 3 {
		return "```"
	}
	return strings.Repeat("`", longest+1)
}

func renderNotices(entries []noticeEntry) string {
	var b strings.Builder
	b.WriteString(`# Third-party notices

Прокси Дом (Proxy Dom) links the Go engine ` + "`hy2bind`" + ` into the Android and iOS
applications. The modules below are compiled into that engine. Each is listed with its
version, license and copyright notice; the full license texts follow. ` + "`std`" + ` is the Go
standard library and runtime, which every Go binary contains.

Dart and Flutter packages are attributed separately: Flutter writes their licenses into
the application bundle (` + "`NOTICES`" + `).

This file is generated from the dependency graph. Do not edit it by hand. To refresh it,
run in ` + "`mobile/android/hysteria-bind`" + `:

    go test -run TestThirdPartyNotices -update-notices .

## Modules

| Module | Version | License | Copyright |
|---|---|---|---|
`)
	cell := strings.NewReplacer("|", `\|`).Replace
	for _, e := range entries {
		version := e.version
		if version == "" {
			version = "—"
		}
		copyright := strings.Join(copyrightLines(e.files), "<br>")
		if copyright == "" {
			copyright = "see license text"
		}
		fmt.Fprintf(&b, "| `%s` | %s | %s | %s |\n",
			e.name, version, strings.Join(e.classes, " AND "), cell(copyright))
	}

	type textGroup struct {
		text  string
		users []string
	}
	var groups []*textGroup
	byHash := map[[32]byte]*textGroup{}
	for _, e := range entries {
		for _, f := range e.files {
			text := cleanLicenseText(f.text)
			key := sha256.Sum256([]byte(text))
			g, ok := byHash[key]
			if !ok {
				g = &textGroup{text: text}
				byHash[key] = g
				groups = append(groups, g)
			}
			g.users = append(g.users, "`"+e.name+"/"+f.name+"`")
		}
	}
	hasMPL := false
	for _, e := range entries {
		for _, class := range e.classes {
			if class == "MPL-2.0" {
				hasMPL = true
			}
		}
	}
	if hasMPL {
		b.WriteString(`
## MPL-2.0 components

Modules marked MPL-2.0 are used unmodified. The source of each such module is
available from its upstream repository at the version pinned in ` + "`go.mod`" + `.
MPL-2.0 applies to those files only; it does not cover Proxy Dom's own source.
`)
	}
	b.WriteString("\n## License texts\n")
	for _, g := range groups {
		fmt.Fprintf(&b, "\n### %s\n\n", g.users[0])
		if len(g.users) > 1 {
			fmt.Fprintf(&b, "The same text applies to %s.\n\n", strings.Join(g.users[1:], ", "))
		}
		fence := codeFence(g.text)
		fmt.Fprintf(&b, "%stext\n%s\n%s\n", fence, g.text, fence)
	}
	return b.String()
}

func goStdlibEntry(t *testing.T) noticeEntry {
	t.Helper()
	out, err := exec.Command("go", "env", "GOROOT").Output()
	if err != nil {
		t.Fatalf("go env GOROOT: %v", err)
	}
	raw, err := os.ReadFile(filepath.Join(strings.TrimSpace(string(out)), "LICENSE"))
	if err != nil {
		t.Fatalf("read the Go license: %v", err)
	}
	files := []licenseFile{{name: "LICENSE", text: string(raw)}}
	classes, problems := judgeModule("std", files)
	if len(problems) > 0 {
		t.Fatalf("Go standard library license: %v", problems)
	}
	return noticeEntry{name: "std", classes: classes, files: files}
}

// TestThirdPartyNotices keeps the shipped notices in step with the graph the
// license guard walks: a module added without regenerating the file fails.
func TestThirdPartyNotices(t *testing.T) {
	modules := shippedModules(t)
	entries := []noticeEntry{goStdlibEntry(t)}
	for _, path := range sortedModulePaths(modules) {
		m := modules[path]
		files, err := readLicenseFiles(m.dir)
		if err != nil {
			t.Fatalf("%s: %v", m.path, err)
		}
		classes, _ := judgeModule(m.path, files)
		entries = append(entries, noticeEntry{name: m.path, version: m.version, classes: classes, files: files})
	}
	want := renderNotices(entries)

	if *updateNotices {
		if err := os.MkdirAll(filepath.Dir(noticesPath), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(noticesPath, []byte(want), 0o644); err != nil {
			t.Fatal(err)
		}
		t.Logf("wrote %s (%d modules)", noticesPath, len(entries))
		return
	}
	got, err := os.ReadFile(noticesPath)
	if err != nil {
		t.Fatalf("read %s: %v; run go test -run TestThirdPartyNotices -update-notices .", noticesPath, err)
	}
	if strings.ReplaceAll(string(got), "\r\n", "\n") != want {
		t.Errorf("%s does not match the dependency graph; run "+
			"go test -run TestThirdPartyNotices -update-notices . and commit the result", noticesPath)
	}
}
