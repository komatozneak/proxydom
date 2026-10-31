//go:build android

package hy2bind

import (
	"log"

	"go.uber.org/zap/zapcore"
)

// connLogf writes one line per connection. On Android nothing reads these
// lines but a person with adb, and at every page load they put each
// destination address into the system log, so they follow the level the user
// picked in the log screen: debug shows them, info and above do not.
func connLogf(format string, args ...any) {
	if !tunnelLevel.Enabled(zapcore.DebugLevel) {
		return
	}
	log.Printf(format, args...)
}
