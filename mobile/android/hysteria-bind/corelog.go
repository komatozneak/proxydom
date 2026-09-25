package hy2bind

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"

	clog "github.com/xtls/xray-core/common/log"
	xcore "github.com/xtls/xray-core/core"
)

// Two windows, about 8 MiB together. A minute of SOCKS packet lines is
// ~1100 rows and would erase the connect timeline, so those lines never land.
var coreWindowBytes = 4 << 20

var (
	coreMu    sync.Mutex
	coreDir   string
	coreLevel = "info"
)

var coreSecret = regexp.MustCompile(`(?i)\b(auth|token|password|secret|authorization)\s*[=:]\s*\S+`)

// prepareCoreLog reads the directory and level Kotlin injects beside the
// share document. Empty dir means the handler stays quiet.
func prepareCoreLog(configJSON string) {
	var env struct {
		Dir   string `json:"teremokLogDir"`
		Level string `json:"teremokLogLevel"`
	}
	_ = json.Unmarshal([]byte(configJSON), &env)
	coreMu.Lock()
	coreDir = strings.TrimSpace(env.Dir)
	coreLevel = normalizeCoreLevel(env.Level)
	coreMu.Unlock()
}

func normalizeCoreLevel(raw string) string {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "off", "error", "warn", "info", "debug":
		return strings.ToLower(strings.TrimSpace(raw))
	default:
		return "info"
	}
}

func coreLevelSnapshot() string {
	coreMu.Lock()
	defer coreMu.Unlock()
	if coreLevel == "" {
		return "info"
	}
	return coreLevel
}

// bindCoreLogHandler replaces Xray's log.Instance. That instance is the only
// process-wide handler and would either write every Info line or none.
func bindCoreLogHandler() {
	clog.RegisterHandler(coreLogHandler{})
}

func noteShareCore() {
	appendCoreLine("info", "core.xray dns=system socks="+shareSocks)
	appendCoreLine("info", "core.xray started version="+xcore.Version())
}

type coreLogHandler struct{}

func (coreLogHandler) Handle(msg clog.Message) {
	level := coreLevelSnapshot()
	severity := clog.Severity_Info
	text := ""
	switch m := msg.(type) {
	case *clog.GeneralMessage:
		severity = m.Severity
		text = fmt.Sprint(m.Content)
	default:
		text = msg.String()
	}
	text = redactCoreSecrets(text)
	if !keepCoreRecord(level, severity, text) {
		return
	}
	appendCoreLine(coreLineLevel(severity), coreTag(text)+" "+text)
}

func coreLineLevel(severity clog.Severity) string {
	switch severity {
	case clog.Severity_Error:
		return "error"
	case clog.Severity_Warning:
		return "warn"
	case clog.Severity_Debug:
		return "debug"
	default:
		return "info"
	}
}

func coreTag(text string) string {
	lower := strings.ToLower(text)
	if strings.Contains(lower, "app/dns") ||
		strings.Contains(lower, "querying dns") ||
		strings.Contains(lower, "got answer") ||
		strings.Contains(lower, "will use dns") {
		return "core.dns"
	}
	return "core.xray"
}

func redactCoreSecrets(text string) string {
	return coreSecret.ReplaceAllString(text, "$1=***")
}

func keepCoreRecord(level string, severity clog.Severity, text string) bool {
	if level == "off" || isCoreNoise(text) {
		return false
	}
	if isCoreFailure(text) {
		return true
	}
	switch level {
	case "error":
		return severity == clog.Severity_Error
	case "warn":
		return severity == clog.Severity_Error || severity == clog.Severity_Warning
	case "debug":
		return true
	default:
		if isCoreDebugExtra(text) {
			return false
		}
		return isCoreDecision(text) ||
			severity == clog.Severity_Warning ||
			severity == clog.Severity_Error
	}
}

func isCoreNoise(text string) bool {
	switch {
	case strings.Contains(text, "send packet"):
	case strings.Contains(text, "writing back"):
	case strings.Contains(text, "dispatch request"):
	case strings.Contains(text, "create new counter"):
	case strings.Contains(text, "establishing new connection"):
	case strings.Contains(text, "client UDP connection"):
	case strings.Contains(text, "TCP Connect request"):
	case strings.Contains(text, "accepted tcp:"):
	case strings.Contains(text, "accepted udp:"):
	default:
		return false
	}
	return true
}

func isCoreDecision(text string) bool {
	switch {
	case strings.Contains(text, "sniffed domain"):
	case strings.Contains(text, "taking detour"):
	case strings.Contains(text, "default route"):
	case strings.Contains(text, "tunneling request"):
	case strings.Contains(text, "querying DNS"):
	case strings.Contains(text, "got answer"):
	case strings.Contains(text, "listening TCP"):
	case strings.Contains(text, "Logger started"):
	case strings.Contains(text, "Xray "):
	default:
		return false
	}
	return true
}

func isCoreDebugExtra(text string) bool {
	return strings.Contains(text, "will use DNS") || strings.Contains(text, "ECHAccepted")
}

func isCoreFailure(text string) bool {
	lower := strings.ToLower(text)
	return strings.Contains(lower, "failed") ||
		strings.Contains(lower, " error") ||
		strings.HasPrefix(lower, "error")
}

func severityAllows(selected, line string) bool {
	if selected == "off" {
		return false
	}
	return coreRank(line) <= coreRank(selected)
}

func coreRank(level string) int {
	switch level {
	case "off":
		return 0
	case "error":
		return 1
	case "warn":
		return 2
	case "debug":
		return 4
	default:
		return 3
	}
}

func appendCoreLine(level, message string) {
	coreMu.Lock()
	defer coreMu.Unlock()
	if coreDir == "" || !severityAllows(coreLevel, level) {
		return
	}
	if err := os.MkdirAll(coreDir, 0o700); err != nil {
		return
	}
	path := filepath.Join(coreDir, "core.log")
	if info, err := os.Stat(path); err == nil && info.Size() >= int64(coreWindowBytes) {
		rotateCoreLocked(path)
	}
	file, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return
	}
	defer file.Close()
	line := time.Now().Format("2006-01-02 15:04:05.000") + " [" + level + "] " + message + "\n"
	_, _ = file.WriteString(line)
}

func rotateCoreLocked(path string) {
	prev := filepath.Join(coreDir, "core.1.log")
	_ = os.Remove(prev)
	if err := os.Rename(path, prev); err != nil {
		return
	}
	file, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
	if err != nil {
		return
	}
	defer file.Close()
	_, _ = file.WriteString("[TEREMOK] Previous log window expired or reached the 8 MiB limit.\n")
}
