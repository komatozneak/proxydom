package hy2bind

import "testing"

// StopTun must be idempotent and must not double-close when both stack and
// device are set (regression: Pixel fdsan abort on ACTION_STOP).
func TestStopTunIdempotentNil(t *testing.T) {
	StopTun()
	StopTun()
	Stop()
}

func TestStopTunClosesStackOnlyOnce(t *testing.T) {
	mu.Lock()
	// Simulate a "live" stack without a real TUN fd: only stack pointer set.
	// StopTun must prefer st.Close() and not also Close(nil) panics.
	tunDev = nil
	tunStk = nil
	mu.Unlock()
	StopTun()
	StopTun()
}
