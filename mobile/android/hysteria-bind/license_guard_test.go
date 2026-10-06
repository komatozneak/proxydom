package hy2bind

import (
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strings"
	"testing"
)

// knownViolations lists copyleft modules that are still in the build graph.
// Each entry names the task that removes it. An entry MUST be deleted by that
// task; while it is present the check warns instead of failing so that CI stays
// green during the migration. Re-adding a module after its entry was deleted
// fails the build — that is the point.
var knownViolations = map[string]string{
	"github.com/sagernet/sing": "removed by docs/ops/engine-migration/03-mobile-engine-swap.md",
}

// reviewedLicense is a license a person has read because the markers could not
// classify it (no license file at the module root, or unusual wording).
type reviewedLicense struct {
	spdx   string
	reason string
}

// reviewedLicenses may only name an allowed SPDX id, and it never overrides a
// forbidden license or an additional restriction found in the module's files.
var reviewedLicenses = map[string]reviewedLicense{}

// licenseGuardTargets are the builds that ship hy2bind (ADR 036). gomobile
// links its own bind runtime next to the package, so those packages are
// walked as well: they end up in the AAR and the xcframework.
var licenseGuardTargets = []struct {
	goos, goarch string
	packages     []string
}{
	{"android", "arm64", []string{"./...", "golang.org/x/mobile/bind/java", "golang.org/x/mobile/bind/seq"}},
	{"ios", "arm64", []string{"./...", "golang.org/x/mobile/bind/objc", "golang.org/x/mobile/bind/seq"}},
}

var allowedLicenses = map[string]bool{
	"MIT": true, "BSD-2-Clause": true, "BSD-3-Clause": true, "ISC": true, "0BSD": true,
	"Apache-2.0": true, "MPL-2.0": true, "Zlib": true, "Unlicense": true, "CC0-1.0": true,
}

type licenseRule struct {
	class   string
	markers []string // all must occur in the normalised text
}

// disallowedRules are checked in order and the first match names the file.
// AGPL and LGPL texts quote the GPL, so they come before it.
var disallowedRules = []licenseRule{
	{"AGPL", []string{"gnu affero general public license"}},
	{"LGPL", []string{"gnu lesser general public license"}},
	{"LGPL", []string{"gnu library general public license"}},
	{"GPL-3.0", []string{"gnu general public license", "version 3"}},
	{"GPL-2.0", []string{"gnu general public license", "version 2"}},
	{"GPL", []string{"gnu general public license"}},
	{"SSPL", []string{"server side public license"}},
	{"BUSL", []string{"business source license"}},
	{"CC-BY-NC", []string{"attribution-noncommercial"}},
	{"BSD-4-Clause", []string{"all advertising materials mentioning features or use of this software"}},
}

var allowedRules = []licenseRule{
	{"MPL-2.0", []string{"mozilla public license version 2.0"}},
	{"MPL-2.0", []string{"mozilla public license, v. 2.0"}},
	{"Apache-2.0", []string{"apache license", "version 2.0"}},
	{"MIT", []string{"permission is hereby granted, free of charge"}},
	{"BSD", []string{"redistribution and use in source and binary forms"}},
	{"ISC", []string{"permission to use, copy, modify, and/or distribute this software"}},
	{"Zlib", []string{"altered source versions must be plainly marked as such"}},
	{"Unlicense", []string{"this is free and unencumbered software released into the public domain"}},
	{"CC0-1.0", []string{"cc0 1.0 universal"}},
}

// restrictionMarkers are terms layered on top of a license. Their presence
// fails the module even when the base license is allowed (ADR 036 §1).
var restrictionMarkers = []string{
	"no derivative work may use the name",
	"non-commercial",
	"noncommercial",
	"field of use",
	"field-of-use",
	"commons clause",
}

// mplSecondaryLicenses is the MPL-2.0 definition that names the GNU licenses.
// It is not a grant of GPL, so it is cut before the GNU markers are matched.
const mplSecondaryLicenses = `"secondary license" means either the gnu general public license, ` +
	`version 2.0, the gnu lesser general public license, version 2.1, the gnu affero ` +
	`general public license, version 3.0, or any later versions of those licenses.`

var licenseFilePrefixes = []string{"LICENSE", "LICENCE", "COPYING", "NOTICE", "UNLICENSE"}

type guardModule struct {
	path, version, dir string
}

type licenseFile struct {
	name, text string
}

type licenseClassification struct {
	allowed      []string
	disallowed   []string
	restrictions []string
}

func normaliseLicense(text string) string {
	text = strings.NewReplacer("\u2018", "'", "\u2019", "'", "\u201c", `"`, "\u201d", `"`).Replace(text)
	return strings.Join(strings.Fields(strings.ToLower(text)), " ")
}

func matchesAll(text string, markers []string) bool {
	for _, m := range markers {
		if !strings.Contains(text, m) {
			return false
		}
	}
	return true
}

func classifyLicense(text string) licenseClassification {
	var c licenseClassification
	norm := normaliseLicense(text)
	for _, m := range restrictionMarkers {
		if strings.Contains(norm, m) {
			c.restrictions = append(c.restrictions, m)
		}
	}
	gnu := norm
	if strings.Contains(norm, "mozilla public license") {
		gnu = strings.ReplaceAll(gnu, mplSecondaryLicenses, "")
	}
	for _, r := range disallowedRules {
		if matchesAll(gnu, r.markers) {
			c.disallowed = append(c.disallowed, r.class)
			break
		}
	}
	seen := map[string]bool{}
	for _, r := range allowedRules {
		if !matchesAll(norm, r.markers) {
			continue
		}
		class := r.class
		switch class {
		case "BSD":
			class = "BSD-2-Clause"
			if strings.Contains(norm, "to endorse or promote products derived from this software") {
				class = "BSD-3-Clause"
			}
		case "ISC":
			if !strings.Contains(norm, "provided that the above copyright notice") {
				class = "0BSD"
			}
		}
		if !seen[class] {
			seen[class] = true
			c.allowed = append(c.allowed, class)
		}
	}
	return c
}

// judgeModule returns the license classes found in the module's files and the
// reasons the module may not ship. No reasons means the module is allowed.
func judgeModule(path string, files []licenseFile) (classes, problems []string) {
	found := map[string]bool{}
	for _, f := range files {
		c := classifyLicense(f.text)
		for _, class := range c.disallowed {
			found[class] = true
			problems = append(problems, fmt.Sprintf("forbidden license %s in %s", class, f.name))
		}
		for _, m := range c.restrictions {
			problems = append(problems, fmt.Sprintf("additional restriction %q in %s", m, f.name))
		}
		for _, class := range c.allowed {
			found[class] = true
		}
	}
	allowedFound := false
	for class := range found {
		classes = append(classes, class)
		if allowedLicenses[class] {
			allowedFound = true
		}
	}
	sort.Strings(classes)
	if allowedFound || len(problems) > 0 {
		return classes, problems
	}
	if r, ok := reviewedLicenses[path]; ok {
		if !allowedLicenses[r.spdx] {
			return classes, []string{fmt.Sprintf("reviewedLicenses names %s, which ADR 036 does not allow", r.spdx)}
		}
		return []string{r.spdx}, nil
	}
	if len(files) == 0 {
		return classes, []string{"no LICENSE, COPYING or NOTICE file at the module root; " +
			"read the license and add the module to reviewedLicenses with a reason"}
	}
	return classes, []string{"license not recognised; read it and add the module to " +
		"reviewedLicenses with a reason"}
}

func readLicenseFiles(dir string) ([]licenseFile, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var files []licenseFile
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		upper := strings.ToUpper(e.Name())
		for _, prefix := range licenseFilePrefixes {
			if !strings.HasPrefix(upper, prefix) {
				continue
			}
			raw, err := os.ReadFile(dir + string(os.PathSeparator) + e.Name())
			if err != nil {
				return nil, err
			}
			files = append(files, licenseFile{name: e.Name(), text: string(raw)})
			break
		}
	}
	return files, nil
}

// shippedModules walks every target in licenseGuardTargets and returns the
// union of non-main modules, keyed by module path.
func shippedModules(t *testing.T) map[string]guardModule {
	t.Helper()
	// The test cache does not see go list; reading these makes a go.mod or
	// go.sum edit invalidate a cached pass.
	for _, name := range []string{"go.mod", "go.sum"} {
		if _, err := os.ReadFile(name); err != nil {
			t.Fatalf("read %s: %v", name, err)
		}
	}
	const format = `{{with .Module}}{{if not .Main}}{{.Path}}|` +
		`{{if .Replace}}{{.Replace.Version}}{{else}}{{.Version}}{{end}}|{{.Dir}}{{end}}{{end}}`
	modules := map[string]guardModule{}
	for _, target := range licenseGuardTargets {
		args := append([]string{"list", "-deps", "-f", format}, target.packages...)
		cmd := exec.Command("go", args...)
		cmd.Env = append(os.Environ(), "GOOS="+target.goos, "GOARCH="+target.goarch, "CGO_ENABLED=1")
		cmd.Stderr = os.Stderr
		out, err := cmd.Output()
		if err != nil {
			t.Fatalf("go list for %s/%s: %v", target.goos, target.goarch, err)
		}
		for _, line := range strings.Split(string(out), "\n") {
			if line = strings.TrimSpace(line); line == "" {
				continue
			}
			parts := strings.SplitN(line, "|", 3)
			if len(parts) != 3 || parts[2] == "" {
				t.Fatalf("go list for %s/%s: no module directory in %q; run go mod download",
					target.goos, target.goarch, line)
			}
			modules[parts[0]] = guardModule{path: parts[0], version: parts[1], dir: parts[2]}
		}
	}
	if len(modules) == 0 {
		t.Fatal("go list returned no modules; the guard would pass on nothing")
	}
	return modules
}

func sortedModulePaths(modules map[string]guardModule) []string {
	paths := make([]string, 0, len(modules))
	for p := range modules {
		paths = append(paths, p)
	}
	sort.Strings(paths)
	return paths
}

// TestLicenseGuard fails when a module that ships inside hy2bind carries a
// forbidden or unrecognised license, or a restriction on top of its license.
func TestLicenseGuard(t *testing.T) {
	modules := shippedModules(t)
	for _, path := range sortedModulePaths(modules) {
		m := modules[path]
		files, err := readLicenseFiles(m.dir)
		if err != nil {
			t.Errorf("%s %s: %v", m.path, m.version, err)
			continue
		}
		classes, problems := judgeModule(m.path, files)
		task, known := knownViolations[m.path]
		switch {
		case len(problems) == 0 && known:
			t.Errorf("%s %s is in knownViolations but no longer violates (%s); delete the entry",
				m.path, m.version, strings.Join(classes, " AND "))
		case len(problems) == 0:
		case known:
			msg := fmt.Sprintf("KNOWN VIOLATION %s %s: %s; %s",
				m.path, m.version, strings.Join(problems, "; "), task)
			t.Log("WARNING " + msg)
			if os.Getenv("GITHUB_ACTIONS") == "true" {
				fmt.Printf("::warning title=License guard::%s\n", msg)
			}
		default:
			for _, p := range problems {
				t.Errorf("%s %s: %s", m.path, m.version, p)
			}
		}
	}
	for path, task := range knownViolations {
		if _, ok := modules[path]; !ok {
			t.Errorf("knownViolations lists %s, which is no longer in the build graph; "+
				"delete the entry (%s)", path, task)
		}
	}
}

func TestLicenseClassifier(t *testing.T) {
	cases := []struct {
		name         string
		text         string
		classes      []string
		wantProblems bool
	}{
		{
			name: "gpl3 notice",
			text: "Copyright (C) 2022 by nekohasekai\n\nThis program is free software: you can " +
				"redistribute it and/or modify\nit under the terms of the GNU General Public " +
				"License as published by\nthe Free Software Foundation, either version 3 of the License.",
			classes:      []string{"GPL-3.0"},
			wantProblems: true,
		},
		{
			name: "gpl3 full text heading",
			text: "                    GNU GENERAL PUBLIC LICENSE\n                       " +
				"Version 3, 29 June 2007",
			classes:      []string{"GPL-3.0"},
			wantProblems: true,
		},
		{
			name:         "lgpl quotes the gpl",
			text:         "GNU LESSER GENERAL PUBLIC LICENSE Version 3 ... the GNU General Public License",
			classes:      []string{"LGPL"},
			wantProblems: true,
		},
		{
			name:         "agpl quotes the gpl",
			text:         "GNU AFFERO GENERAL PUBLIC LICENSE Version 3 ... GNU General Public License",
			classes:      []string{"AGPL"},
			wantProblems: true,
		},
		{
			name: "mpl names the gnu licenses as secondary",
			text: "Mozilla Public License Version 2.0\n==================================\n" +
				"1.12. \"Secondary License\"\n    means either the GNU General Public License, " +
				"Version 2.0, the GNU Lesser\n    General Public License, Version 2.1, the GNU " +
				"Affero General Public\n    License, Version 3.0, or any later versions of " +
				"those licenses.",
			classes: []string{"MPL-2.0"},
		},
		{
			name: "mpl with a gpl grant beyond the definition",
			text: "Mozilla Public License Version 2.0 ... This program is also free software " +
				"under the GNU General Public License as published by the Free Software " +
				"Foundation, either version 3 of the License.",
			classes:      []string{"GPL-3.0", "MPL-2.0"},
			wantProblems: true,
		},
		{
			name: "sing-box name clause on top of the gpl",
			text: "GNU General Public License version 3 ... In addition, no derivative work " +
				"may use the name or imply association with this application without prior consent.",
			classes:      []string{"GPL-3.0"},
			wantProblems: true,
		},
		{
			name:         "mit with a non-commercial rider",
			text:         "Permission is hereby granted, free of charge, ... for non-commercial use only.",
			classes:      []string{"MIT"},
			wantProblems: true,
		},
		{
			name:    "mit with curly quotes",
			text:    "Permission is hereby granted, free of charge, to any person obtaining a copy of this software (the \u201cSoftware\u201d)",
			classes: []string{"MIT"},
		},
		{
			name: "bsd 3 clause",
			text: "Redistribution and use in source and binary forms, with or without " +
				"modification, are permitted ... Neither the name of Google Inc. nor the names " +
				"of its contributors may be used to endorse or promote products derived from " +
				"this software without specific prior written permission.",
			classes: []string{"BSD-3-Clause"},
		},
		{
			name: "bsd 2 clause",
			text: "Redistribution and use in source and binary forms, with or without " +
				"modification, are permitted provided that the following conditions are met:",
			classes: []string{"BSD-2-Clause"},
		},
		{
			name:    "isc",
			text:    "Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.",
			classes: []string{"ISC"},
		},
		{
			name:    "apache notice",
			text:    "Licensed under the Apache License, Version 2.0 (the \"License\");",
			classes: []string{"Apache-2.0"},
		},
		{
			name:         "unknown wording",
			text:         "All rights reserved. Ask us first.",
			wantProblems: true,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			classes, problems := judgeModule("example.test/"+tc.name, []licenseFile{{name: "LICENSE", text: tc.text}})
			if strings.Join(classes, ",") != strings.Join(tc.classes, ",") {
				t.Errorf("classes = %v, want %v", classes, tc.classes)
			}
			if got := len(problems) > 0; got != tc.wantProblems {
				t.Errorf("problems = %v, want problems: %v", problems, tc.wantProblems)
			}
		})
	}
}

func TestLicenseGuardRejectsMissingLicenseFile(t *testing.T) {
	_, problems := judgeModule("example.test/bare", nil)
	if len(problems) == 0 {
		t.Fatal("a module without a license file must not pass")
	}
}
