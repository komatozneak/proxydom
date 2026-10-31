package hy2bind

import (
	"testing"

	"go.uber.org/zap/zapcore"
)

func TestPerConnectionTunnelLinesAreDebug(t *testing.T) {
	at := func(level zapcore.Level, file string) zapcore.Entry {
		return zapcore.Entry{Level: level, Caller: zapcore.EntryCaller{Defined: true, File: file}}
	}
	cases := []struct {
		entry zapcore.Entry
		want  zapcore.Level
	}{
		// One line per connection, with its destination: trace detail.
		{at(zapcore.InfoLevel, "/go/pkg/mod/github.com/xjasonlyu/tun2socks/v2@v2.7.0/tunnel/tcp.go"), zapcore.DebugLevel},
		{at(zapcore.InfoLevel, "/go/pkg/mod/github.com/xjasonlyu/tun2socks/v2@v2.7.0/tunnel/udp.go"), zapcore.DebugLevel},
		// A warning from the same file is still a warning.
		{at(zapcore.WarnLevel, "/go/pkg/mod/github.com/xjasonlyu/tun2socks/v2@v2.7.0/tunnel/tcp.go"), zapcore.WarnLevel},
		// Any other record keeps its level.
		{at(zapcore.InfoLevel, "/go/pkg/mod/github.com/xjasonlyu/tun2socks/v2@v2.7.0/core/stack.go"), zapcore.InfoLevel},
		{zapcore.Entry{Level: zapcore.InfoLevel}, zapcore.InfoLevel},
	}
	for _, tc := range cases {
		if got := tunnelEntryLevel(tc.entry); got != tc.want {
			t.Fatalf("%s at %s: got %s, want %s", tc.entry.Caller.File, tc.entry.Level, got, tc.want)
		}
	}
}
