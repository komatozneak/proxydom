package hy2bind

// Congestion-controller selection for Hysteria2.
//
// Brutal is a mode, not a controller. core/v2 turns Brutal on only after auth,
// and only when this client has declared a bandwidth (client/client.go:149-167).
// This task does not declare a bandwidth, so Brutal is never selected here.
// What this file selects is the fallback controller used when no rate applies.
//
// The values are deliberately restricted to what the engine accepts, because
// `Config.verifyAndFill` treats an unknown one as fatal:
//
//	c.CongestionConfig.Type, err = congestion.NormalizeType(...)
//	if err != nil { return errors.ConfigError{...} }   // config.go:78-81
//
// NormalizeType accepts only "", "bbr" and "reno" (internal/congestion/utils.go:18-27),
// and ParseProfile only "", "standard", "conservative", "aggressive"
// (internal/congestion/bbr/bbr_sender.go:119-127). Share links do not speak this
// vocabulary — Hiddify's `fm` blob writes `"congestion":"brutal"`, which is the
// mode, not a controller the client may name. Passing it through would turn a
// field we do not even use into a connection error, so it is read, recognised,
// and replaced with bbr rather than forwarded.

import (
	"fmt"
	"strings"
)

// congestionTypes are the controllers core/v2 will accept, mirroring
// NormalizeType. Empty is absent on purpose: an undeclared link leaves the
// engine default alone, which is already bbr, and spelling bbr here would put
// a congestion block on every catalog node that never sent `fm`.
var congestionTypes = map[string]string{
	"bbr":  "bbr",
	"reno": "reno",
}

// bbrProfiles mirror bbr.ParseProfile.
var bbrProfiles = map[string]string{
	"standard":     "standard",
	"conservative": "conservative",
	"aggressive":   "aggressive",
}

// congestionModes are values that name Brutal rather than a controller. They
// are not controllers and must not be forwarded. They are not junk either:
// the log should say the provider asked for a mode and the client applied bbr.
var congestionModes = map[string]bool{
	"brutal":     true,
	"bandwidth":  true,
	"bbr_brutal": true,
}

// congestionConfigFor resolves the declared controller into engine values.
//
// An empty declaration returns empty strings: the catalog path has no `fm`,
// and leaving CongestionConfig at its zero value is today's behaviour.
// An unrecognised controller falls back to bbr with a warning. Refusing the
// start would be worse than the field is worth: the node still connects, and
// every node behaved this way before the field was read at all.
func congestionConfigFor(cfg startConfig) (congestionType string, bbrProfile string, warnings []string) {
	rawType := strings.TrimSpace(cfg.Congestion)
	rawProfile := strings.TrimSpace(cfg.BBRProfile)
	if rawType == "" && rawProfile == "" {
		return "", "", nil
	}

	normalizedType := strings.ToLower(rawType)
	switch {
	case rawType == "":
		// A profile with no controller still selects BBR. The profile only
		// means anything for BBR, and an empty type would drop it.
		congestionType = "bbr"
	case congestionModes[normalizedType]:
		warnings = append(warnings, fmt.Sprintf(
			"congestion %q names a mode, not a controller; applying bbr",
			rawType))
		congestionType = "bbr"
	case congestionTypes[normalizedType] != "":
		congestionType = congestionTypes[normalizedType]
		if congestionType == "reno" {
			warnings = append(warnings, fmt.Sprintf(
				"congestion %q applied as reno", rawType))
		}
	default:
		warnings = append(warnings, fmt.Sprintf(
			"unsupported congestion %q, applying bbr", rawType))
		congestionType = "bbr"
	}

	// A profile only means anything for BBR. bbr.ParseProfile rejects an unknown
	// one, so an unreadable value is dropped rather than passed on.
	if resolved, ok := bbrProfiles[strings.ToLower(rawProfile)]; ok {
		bbrProfile = resolved
	} else if rawProfile != "" {
		warnings = append(warnings, fmt.Sprintf(
			"unsupported bbr profile %q, using the engine default", rawProfile))
	}
	if congestionType != "bbr" {
		// Reno ignores the profile; keeping it would only confuse the log.
		bbrProfile = ""
	}
	return congestionType, bbrProfile, warnings
}
