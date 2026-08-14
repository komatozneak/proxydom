import 'app_log_buffer.dart';

/// Structured product events for owner reports (no PII, no tokens).
class ProductLog {
  ProductLog._();

  static void event(String name, [Map<String, Object?> fields = const {}]) {
    final parts = <String>[name];
    for (final entry in fields.entries) {
      final value = entry.value;
      if (value == null) continue;
      parts.add('${entry.key}=${_fmt(value)}');
    }
    AppLogBuffer.instance.info(parts.join(' '));
  }

  static String _fmt(Object value) {
    final raw = value.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (raw.length <= 120) return raw;
    return '${raw.substring(0, 117)}...';
  }
}
