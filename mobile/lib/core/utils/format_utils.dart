/// Speed / latency formatters for Home compact metrics.
String formatBytesPerSec(int bytesPerSec, {bool russian = true}) {
  if (bytesPerSec <= 0) {
    return russian ? '0 Б/с' : '0 B/s';
  }
  const kib = 1024.0;
  const mib = kib * 1024.0;
  if (bytesPerSec >= mib) {
    final v = bytesPerSec / mib;
    return russian
        ? '${v.toStringAsFixed(1)} МБ/с'
        : '${v.toStringAsFixed(1)} MiB/s';
  }
  if (bytesPerSec >= kib) {
    final v = bytesPerSec / kib;
    final digits = v >= 100 ? 0 : 1;
    return russian
        ? '${v.toStringAsFixed(digits)} КБ/с'
        : '${v.toStringAsFixed(digits)} KiB/s';
  }
  return russian ? '$bytesPerSec Б/с' : '$bytesPerSec B/s';
}

/// Returns null when ping should be hidden (not ready / invalid).
/// Kept for a future verified native urlTest spike — Home no longer polls it.
String? formatPingMs(int? ms, {bool russian = true}) {
  if (ms == null || ms <= 0) return null;
  if (ms > 9999) return russian ? '>9 с' : '>9s';
  return russian ? '$ms мс' : '$ms ms';
}

/// Relative age of last libbox status / traffic heartbeat for Home link cell.
String formatLinkAge(DateTime? lastSeenAt, {required bool russian}) {
  if (lastSeenAt == null) return russian ? 'сейчас' : 'just now';
  final sec = DateTime.now().difference(lastSeenAt).inSeconds;
  if (sec < 5) return russian ? 'сейчас' : 'just now';
  if (sec < 60) {
    return russian ? '$sec с назад' : '${sec}s ago';
  }
  final min = sec ~/ 60;
  if (min < 60) {
    return russian ? '$min мин назад' : '${min}m ago';
  }
  final h = min ~/ 60;
  return russian ? '$h ч назад' : '${h}h ago';
}
