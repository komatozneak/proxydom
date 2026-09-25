import 'app_log_buffer.dart';

/// Explicit severity. The buffer does not infer it from the event text.
enum ProductLogLevel { error, warn, info, debug }

/// Structured product events for owner reports (no PII, no tokens).
class ProductLog {
  ProductLog._();

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
    final line = parts.join(' ');
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
    if (raw.length <= 500) return raw;
    return '${raw.substring(0, 497)}...';
  }
}
