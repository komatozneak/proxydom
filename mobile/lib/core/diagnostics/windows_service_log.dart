import 'dart:io';

import 'tunnel_log_redact.dart';

/// One file the owner can send. Window text and the broker journal, secrets masked.
String windowsDebugReport(String windowLog, String serviceLog) {
  return redactTunnelLog(
    '=== window ===\n$windowLog\n=== service ===\n$serviceLog',
  );
}

String? _profilePath(String folder) {
  final profile = Platform.environment['USERPROFILE'];
  if (profile == null || profile.isEmpty) return null;
  return '$profile\\$folder\\proxydom-debug.txt';
}

/// Broker journal. Missing file is a line, not an exception: the report must still leave.
Future<String> readWindowsServiceLog() async {
  if (!Platform.isWindows) return 'not-windows';
  final root = Platform.environment['ProgramData'];
  final base = (root == null || root.isEmpty) ? r'C:\ProgramData' : root;
  final dir = '$base\\Proxy Dom\\logs';
  final parts = <String>[];
  for (final name in ['service.log.1', 'service.log']) {
    final file = File('$dir\\$name');
    parts.add('--- $name ---');
    try {
      if (!await file.exists()) {
        parts.add('missing');
        continue;
      }
      parts.add(await file.readAsString());
    } on IOException catch (error) {
      parts.add('unreadable $error');
    }
  }
  return parts.join('\n');
}

/// Visible folder. Downloads is where Telegram already saves files on this machine.
Future<String?> writeWindowsDebugFile(String text) async {
  if (!Platform.isWindows) return null;
  for (final folder in ['Downloads', 'Desktop']) {
    final path = _profilePath(folder);
    if (path == null) return null;
    final file = File(path);
    try {
      if (!await file.parent.exists()) continue;
      await file.writeAsString(text, flush: true);
      return file.path;
    } on IOException {
      continue;
    }
  }
  return null;
}

/// Outcome of a delete attempt: what went, and what refused.
class LogDeleteResult {
  const LogDeleteResult({this.deleted = const [], this.blocked = const []});

  final List<String> deleted;
  final List<String> blocked;

  bool get isComplete => blocked.isEmpty;
}

/// Paths the broker journal and the exported report live at.
List<String> windowsServiceLogPaths() {
  final root = Platform.environment['ProgramData'];
  final base = (root == null || root.isEmpty) ? r'C:\ProgramData' : root;
  return [
    '$base\\Proxy Dom\\logs\\service.log.1',
    '$base\\Proxy Dom\\logs\\service.log',
  ];
}

String _serviceLogDirName() => 'logs\\service.log';

/// Remove the broker journal and the exported report from disk.
///
/// «Удалить» in the log screen used to empty the window's own ring and stop
/// there, which is why an exported `proxydom-debug.txt` kept coming back and
/// old `service.log` entries kept accumulating across installs: these files
/// belong to a different process and a different lifetime.
///
/// A running broker holds `service.log` open for append without
/// FILE_SHARE_DELETE, so Windows refuses the delete. That is reported instead
/// of swallowed - a delete that silently did nothing is the bug this replaces.
Future<LogDeleteResult> deleteWindowsServiceLog() async {
  if (!Platform.isWindows) {
    return const LogDeleteResult();
  }
  final deleted = <String>[];
  final blocked = <String>[];
  final exported = <String>[
    for (final folder in ['Downloads', 'Desktop'])
      if (_profilePath(folder) case final path?) path,
  ];
  final targets = <String>[...windowsServiceLogPaths(), ...exported];
  for (final path in targets) {
    final file = File(path);
    try {
      if (!await file.exists()) continue;
      await file.delete();
      deleted.add(_displayName(path));
    } on FileSystemException {
      blocked.add(_displayName(path));
    }
  }
  return LogDeleteResult(deleted: deleted, blocked: blocked);
}

String _displayName(String path) {
  if (path.contains('Downloads') || path.contains('Desktop')) {
    return path.split('\\').last;
  }
  return _serviceLogDirName();
}
