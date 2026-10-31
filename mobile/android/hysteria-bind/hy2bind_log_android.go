//go:build android

package hy2bind

/*
#cgo LDFLAGS: -llog

#include <android/log.h>
#include <stdlib.h>
*/
import "C"

import (
	"unsafe"

	t2log "github.com/xjasonlyu/tun2socks/v2/log"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

// cGoLogTag lives for the process. mobileinit uses the same tag for stderr.
var cGoLogTag = C.CString("GoLog")

func init() {
	core := androidLogCore{enabler: tunnelLevel}
	t2log.SetLogger(zap.New(core, zap.AddCaller()))
}

type androidLogCore struct {
	enabler zapcore.LevelEnabler
}

func (c androidLogCore) Enabled(level zapcore.Level) bool {
	return c.enabler.Enabled(level)
}

func (c androidLogCore) With([]zapcore.Field) zapcore.Core { return c }

func (c androidLogCore) Check(ent zapcore.Entry, ce *zapcore.CheckedEntry) *zapcore.CheckedEntry {
	if c.Enabled(ent.Level) {
		return ce.AddCore(ent, c)
	}
	return ce
}

func (c androidLogCore) Write(ent zapcore.Entry, _ []zapcore.Field) error {
	// zap fills in the caller after Check, so the per-connection demotion can
	// only be judged here, where the file the line came from is known.
	level := tunnelEntryLevel(ent)
	if !c.Enabled(level) {
		return nil
	}
	msg := ent.Message
	if ent.Caller.Defined {
		msg = ent.Caller.TrimmedPath() + " " + msg
	}
	writeAndroidLog(androidLogPriority(level), msg)
	return nil
}

func (c androidLogCore) Sync() error { return nil }

func writeAndroidLog(priority int, msg string) {
	if len(msg) > 900 {
		msg = msg[:900]
	}
	cmsg := C.CString(msg)
	C.__android_log_write(C.int(priority), cGoLogTag, cmsg)
	C.free(unsafe.Pointer(cmsg))
}
