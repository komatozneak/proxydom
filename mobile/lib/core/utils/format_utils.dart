String formatGib(double gib, {bool russian = true}) {
  final raw = gib.toStringAsFixed(2);
  return russian ? raw.replaceAll('.', ',') : raw;
}

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

/// Formats a tunnel RTT for the compact Home metric.
///
/// A missing or out-of-range sample is an em dash, never `0 мс`: zero is not a
/// measured RTT, and the compact column must stay the same width.
String formatPingMs(int? ms, {required bool russian}) {
  if (ms == null || ms < 1 || ms > 5000) return '—';
  final unit = russian ? 'мс' : 'ms';
  if (ms >= 1000) {
    final thousands = ms ~/ 1000;
    final remainder = (ms % 1000).toString().padLeft(3, '0');
    final separator = russian ? '\u00A0' : ',';
    return '$thousands$separator$remainder $unit';
  }
  return '$ms $unit';
}

/// Relative age of last VPN status / traffic heartbeat for Home link cell.
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
