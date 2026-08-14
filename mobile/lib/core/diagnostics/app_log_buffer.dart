import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// In-memory ring buffer for lightweight diagnostic logs (no PII).
///
/// Optional persist (~256 KB) so «Отправить отчёт» survives process kill.
class AppLogBuffer {
  AppLogBuffer._();

  static final AppLogBuffer instance = AppLogBuffer._();

  static const maxLines = 800;
  static const maxPersistBytes = 256 * 1024;

  final ListQueue<String> _lines = ListQueue<String>();
  File? _persistFile;
  Future<void>? _flushInFlight;

  /// Load existing lines from [file] and write subsequent appends there.
  Future<void> attachPersistFile(File file) async {
    _persistFile = file;
    try {
      if (await file.exists()) {
        final text = await file.readAsString();
        for (final line in text.split('\n')) {
          if (line.isEmpty) continue;
          _lines.addLast(line);
        }
        while (_lines.length > maxLines) {
          _lines.removeFirst();
        }
      }
    } catch (_) {
      // Corrupt / unreadable persist must not block startup.
    }
  }

  void info(String message) => _append('info', message);

  void warn(String message) => _append('warn', message);

  void _append(String level, String message) {
    final line =
        '${DateTime.now().toUtc().toIso8601String()} [$level] $message';
    _lines.addLast(line);
    while (_lines.length > maxLines) {
      _lines.removeFirst();
    }
    final file = _persistFile;
    if (file != null) {
      _flushInFlight = (_flushInFlight ?? Future<void>.value()).then((_) {
        return _writePersist(file);
      });
    }
  }

  Future<void> flushPersist() async {
    final file = _persistFile;
    if (file == null) return;
    await (_flushInFlight ?? _writePersist(file));
  }

  Future<void> _writePersist(File file) async {
    try {
      var body = formatRecentLog();
      var encoded = utf8.encode(body);
      if (encoded.length > maxPersistBytes) {
        final keep = <String>[];
        var used = 0;
        for (final line in _lines.toList().reversed) {
          final n = utf8.encode('$line\n').length;
          if (used + n > maxPersistBytes) break;
          keep.add(line);
          used += n;
        }
        body = keep.reversed.join('\n');
      }
      await file.writeAsString(body, flush: true);
    } catch (_) {
      // Disk full / sandbox — keep memory ring only.
    }
  }

  List<String> recentLines() => List.unmodifiable(_lines);

  String formatRecentLog() {
    if (_lines.isEmpty) return '(empty)';
    return _lines.join('\n');
  }

  void clear() {
    _lines.clear();
  }

  /// Tests: drop persist target so later cases stay isolated.
  @visibleForTesting
  void resetForTest() {
    _lines.clear();
    _persistFile = null;
    _flushInFlight = null;
  }
}
