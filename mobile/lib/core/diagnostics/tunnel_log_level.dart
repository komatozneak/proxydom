/// How much of the tunnel log is recorded.
enum TunnelLogLevel {
  off,
  error,
  warn,
  info,
  debug;

  bool allows(String lineLevel) {
    if (this == TunnelLogLevel.off) return false;
    return _rank(lineLevel) <= index;
  }

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
