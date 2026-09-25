/// How much of the tunnel log is recorded, and which pool the screen shows.
enum TunnelLogLevel {
  off,
  error,
  warn,
  info,
  debug;

  /// Recording threshold: info keeps errors and warnings, debug keeps all.
  bool allows(String lineLevel) {
    if (this == TunnelLogLevel.off) return false;
    return _rank(lineLevel) <= index;
  }

  /// One pool. Debug is the verbose view and shows every recorded line.
  /// Off still shows lines already in the buffer.
  bool showsLine(String lineLevel) {
    if (this == TunnelLogLevel.off || this == TunnelLogLevel.debug) {
      return true;
    }
    return lineLevel == name;
  }

  /// Picking Errors or Warnings must not stop recording the other pools.
  TunnelLogLevel get recordingLevel => switch (this) {
        TunnelLogLevel.off => TunnelLogLevel.off,
        TunnelLogLevel.debug => TunnelLogLevel.debug,
        _ => TunnelLogLevel.info,
      };

  static int _rank(String lineLevel) => switch (lineLevel) {
        'error' => TunnelLogLevel.error.index,
        'warn' => TunnelLogLevel.warn.index,
        'debug' => TunnelLogLevel.debug.index,
        _ => TunnelLogLevel.info.index,
      };

  static TunnelLogLevel fromStorage(String? raw) => switch (raw) {
        'off' => TunnelLogLevel.off,
        'error' => TunnelLogLevel.error,
        'warn' => TunnelLogLevel.warn,
        'debug' => TunnelLogLevel.debug,
        _ => TunnelLogLevel.info,
      };
}
