//go:build !android

package hy2bind

import "log"

// connLogf writes one line per connection. The Windows broker reads these
// lines from the engine's output to tell a tunnel that never received a packet
// from one that received it and could not dial, so off Android they always go
// out.
func connLogf(format string, args ...any) {
	log.Printf(format, args...)
}
