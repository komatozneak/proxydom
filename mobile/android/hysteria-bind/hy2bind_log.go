package hy2bind

import (
	"encoding/json"
	"strings"

	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

// Android log priorities. Same numeric values as <android/log.h>.
const (
	androidLogDebug = 3
	androidLogInfo  = 4
	androidLogWarn  = 5
	androidLogError = 6
)

// tunnelLevel is the tun2socks zap threshold. Android init attaches a core
// that writes __android_log_write at this level. stderr stays ERROR in
// logcat, so JSON on stderr made every info line look fatal.
var tunnelLevel = zap.NewAtomicLevelAt(zapcore.InfoLevel)

func applyTunnelLogLevel(configJSON string) {
	var env struct {
		Level string `json:"teremokLogLevel"`
	}
	_ = json.Unmarshal([]byte(configJSON), &env)
	setTunnelLogLevel(env.Level)
}

func setTunnelLogLevel(raw string) {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "debug":
		tunnelLevel.SetLevel(zapcore.DebugLevel)
	case "warn":
		tunnelLevel.SetLevel(zapcore.WarnLevel)
	case "error":
		tunnelLevel.SetLevel(zapcore.ErrorLevel)
	case "off":
		tunnelLevel.SetLevel(zapcore.FatalLevel + 1)
	default:
		tunnelLevel.SetLevel(zapcore.InfoLevel)
	}
}

func androidLogPriority(level zapcore.Level) int {
	switch {
	case level >= zapcore.ErrorLevel:
		return androidLogError
	case level >= zapcore.WarnLevel:
		return androidLogWarn
	case level >= zapcore.InfoLevel:
		return androidLogInfo
	default:
		return androidLogDebug
	}
}
