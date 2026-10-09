package hy2bind

// QUIC timers from a share link's `quicParams`.
//
// Only two of the four are readable from `fm`. The other receive-window fields
// exist in `client.QUICConfig` and Hysteria's own YAML, but they change memory
// behaviour rather than connectivity, and nothing in the plans asks for them, so
// they are left at the engine defaults.
//
// Both are validated by `Config.verifyAndFill`, and an out-of-range value is a
// ConfigError that fails the whole connection (client/config.go:66-75):
//
//	MaxIdleTimeout  must be between 4s and 120s
//	KeepAlivePeriod must be between 2s and 60s
//
// A provider writing `maxIdleTimeout: 1` would therefore kill a link that
// connects fine today. Values outside the range are clamped into it and warned
// about, because the alternative — forwarding them — converts a tuning hint into
// a dead node, and ignoring them silently would leave the operator guessing.
//
// `keepAlivePeriode22` in the foreign link is the provider's typo, but it is the
// key their whole fleet ships, so it is read alongside the correct spelling.

import (
	"fmt"
	"math"
	"strconv"
	"strings"
	"time"
)

// Bounds mirror client/config.go:66-75. Kept as durations so the intent is
// readable, and converted once at the comparison.
const (
	minMaxIdleTimeout  = 4 * time.Second
	maxMaxIdleTimeout  = 120 * time.Second
	minKeepAlivePeriod = 2 * time.Second
	maxKeepAlivePeriod = 60 * time.Second
)

// Seconds, because YAML and share links both express these in seconds. The
// arithmetic is bounded well inside float64's exact-integer range.
const secondsToDuration = float64(time.Second)

// quicTimer describes one timer: where it comes from, its accepted range, and
// what to call it in a warning.
type quicTimer struct {
	name string
	raw  string
	min  time.Duration
	max  time.Duration
	// zeroWhenNegative is unnecessary: both fields treat <= 0 as "unset", which
	// verifyAndFill then fills with the engine default.
}

// quicConfigFor resolves the two timers into engine values.
func quicConfigFor(cfg startConfig) (maxIdleTimeout, keepAlivePeriod time.Duration, warnings []string) {
	timers := []quicTimer{
		{"maxIdleTimeout", cfg.MaxIdleTimeout, minMaxIdleTimeout, maxMaxIdleTimeout},
		{"keepAlivePeriod", cfg.KeepAlivePeriod, minKeepAlivePeriod, maxKeepAlivePeriod},
	}
	resolved := make([]time.Duration, len(timers))
	for i, t := range timers {
		value, warning := resolveQUICTimer(t)
		resolved[i] = value
		if warning != "" {
			warnings = append(warnings, warning)
		}
	}
	return resolved[0], resolved[1], warnings
}

// resolveQUICTimer parses one timer, clamping out-of-range values into the range
// the engine will accept.
func resolveQUICTimer(t quicTimer) (time.Duration, string) {
	raw := strings.TrimSpace(t.raw)
	if raw == "" {
		return 0, ""
	}
	seconds, err := strconv.ParseFloat(raw, 64)
	if err != nil || math.IsNaN(seconds) || math.IsInf(seconds, 0) {
		return 0, fmt.Sprintf("unreadable %s %q, using the engine default", t.name, t.raw)
	}
	if seconds <= 0 {
		// "0" or a negative is how a provider says "leave it alone".
		return 0, ""
	}
	wanted := time.Duration(seconds * secondsToDuration)
	switch {
	case wanted < t.min:
		return t.min, fmt.Sprintf(
			"%s %q is below the %s minimum, clamped to %s", t.name, t.raw, t.min, t.min)
	case wanted > t.max:
		return t.max, fmt.Sprintf(
			"%s %q is above the %s maximum, clamped to %s", t.name, t.raw, t.max, t.max)
	default:
		return wanted, ""
	}
}
