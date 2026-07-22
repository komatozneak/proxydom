import 'dart:collection';

/// In-memory ring buffer for lightweight diagnostic logs (no PII).
class AppLogBuffer {
  AppLogBuffer._();

  static final AppLogBuffer instance = AppLogBuffer._();

  static const _maxLines = 200;

  final ListQueue<String> _lines = ListQueue<String>();

  void info(String message) => _append('info', message);

  void warn(String message) => _append('warn', message);

  void _append(String level, String message) {
    final line =
        '${DateTime.now().toUtc().toIso8601String()} [$level] $message';
    _lines.addLast(line);
    while (_lines.length > _maxLines) {
      _lines.removeFirst();
    }
  }

  List<String> recentLines() => List.unmodifiable(_lines);

  String formatRecentLog() {
    if (_lines.isEmpty) return '(empty)';
    return _lines.join('\n');
  }

  void clear() => _lines.clear();
}
