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

	v2core "github.com/v2fly/v2ray-core/v5"
	clog "github.com/v2fly/v2ray-core/v5/common/log"
)

// Two windows, about 8 MiB together. A minute of SOCKS packet lines is
// ~1100 rows and would erase the connect timeline, so those lines never land.
var coreWindowBytes = 4 << 20

var (
	coreMu    sync.Mutex
	coreDir   string
	coreLevel = "info"
	coreToErr bool
)

// coreSecret matches the credential-shaped fields the core may echo back.
var coreSecret = regexp.MustCompile(`(?i)\b(auth|token|password|secret|authorization)\s*[=:]\s*\S+`)

// coreUUID matches a user id in any position. It is a credential: on Android
// the core log goes to a file the app owns, but on Windows these lines reach
// the broker's service log, which is a file the owner sends around.
var coreUUID = regexp.MustCompile(`(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b`)

// CoreLogToStderr routes core decisions to stderr when no log directory is
// configured. Android always injects one (CoreLog.kt) and reads the file back;
// Windows has neither a logcat nor an injected directory, so without this the
// core's own explanation of a failed dial is written nowhere at all. The broker
// already reads this process's stderr into the service journal, so that is the
// one channel that reaches the person debugging it.
func CoreLogToStderr(on bool) {
	coreMu.Lock()
	coreToErr = on
	coreMu.Unlock()
}

// prepareCoreLog reads the directory and level Kotlin injects beside the
// share document. Empty dir means the handler stays quiet.
func prepareCoreLog(configJSON string) {
	var env struct {
		Dir   string `json:"proxydomLogDir"`
		Level string `json:"proxydomLogLevel"`
	}
	_ = json.Unmarshal([]byte(configJSON), &env)
	coreMu.Lock()
	coreDir = strings.TrimSpace(env.Dir)
	coreLevel = normalizeCoreLevel(env.Level)
	level := coreLevel
	coreMu.Unlock()
	setTunnelLogLevel(level)
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

// bindCoreLogHandler replaces the core log handler. That handler is the only
// process-wide one and would either write every Info line or none.
func bindCoreLogHandler() {
	clog.RegisterHandler(coreLogHandler{})
}

func noteShareCore() {
	appendCoreLine("info", "core.vless dns=system socks="+ShareSocksAddr())
	appendCoreLine("info", "core.vless started version="+v2core.Version())
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
	return "core.vless"
}

func redactCoreSecrets(text string) string {
	text = coreSecret.ReplaceAllString(text, "$1=***")
	return coreUUID.ReplaceAllString(text, "***")
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
	case strings.Contains(text, "V2Ray "):
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
	if !severityAllows(coreLevel, level) {
		return
	}
	if coreDir == "" {
		// No directory means the platform has not asked for a file. On Windows
		// the process's stderr is the journal, so speak there instead of
		// dropping the line: a silent core is what makes a live failure
		// undiagnosable.
		if coreToErr {
			fmt.Fprintln(os.Stderr, "core."+level+" "+message)
		}
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
	_, _ = file.WriteString("[PROXYDOM] Previous log window expired or reached the 8 MiB limit.\n")
}
