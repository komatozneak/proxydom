import 'app_log_buffer.dart';

/// Explicit severity. The buffer does not infer it from the event text.
enum ProductLogLevel { error, warn, info, debug }

/// Structured product events for owner reports (no PII, no tokens).
///
/// The contract a reader can rely on:
///
/// ```text
/// <event name> key=value key="value with spaces" [key=value …]
/// ```
///
/// * the event name is stable, lowercase and dot-separated — `vpn.connect_fail`,
///   never «не подключилось». It is what you grep and count by;
/// * the part before the first dot is the source, and it is what the log screen
///   filters on (`[vpn]`, `[net]`, `[hy2]`, `[core]`, `[doc]`, `[ui]`);
/// * values with whitespace are quoted, so `key=a b` is one value and not two;
/// * a null field is omitted, never rendered as `key=null` — absent and
///   unknown are different facts and the log should not invent one of them.
class ProductLog {
  ProductLog._();

  /// Whole-line cap. One fat value must not push the connect timeline out of
  /// the 800-line ring and make the report unreadable.
  static const int maxLineChars = 2000;

  static void event(
    String name, {
    required ProductLogLevel level,
    Map<String, Object?> fields = const {},
  }) {
    final parts = <String>[name];
    for (final entry in fields.entries) {
      final value = entry.value;
      if (value == null) continue;
      parts.add('${entry.key}=${_fmt(value)}');
    }
    final line = _clip(parts.join(' '));
    switch (level) {
      case ProductLogLevel.error:
        AppLogBuffer.instance.error(line);
      case ProductLogLevel.warn:
        AppLogBuffer.instance.warn(line);
      case ProductLogLevel.debug:
        AppLogBuffer.instance.debug(line);
      case ProductLogLevel.info:
        AppLogBuffer.instance.info(line);
    }
  }

  static String _fmt(Object value) {
    final raw = value.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    final body = _clip(raw, max: 500);
    // Quoting keeps `key=` from absorbing the next field. A value that already
    // lost its quotes must not be able to fake a field boundary on the way out.
    final needsQuote = body.isEmpty ||
        body.contains(' ') ||
        body.contains('"') ||
        body.contains('=');
    if (!needsQuote) return body;
    return '"${body.replaceAll('"', "'")}"';
  }

  static String _clip(String text, {int max = maxLineChars}) {
    if (text.length <= max) return text;
    return '${text.substring(0, max - 3)}...';
  }
}