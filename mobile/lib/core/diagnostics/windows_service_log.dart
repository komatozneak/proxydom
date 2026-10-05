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

/// Paths the broker journal lives at. Kept for the report reader; the delete
/// goes through the broker, because this process has no rights on the files.
List<String> windowsServiceLogPaths() {
  final root = Platform.environment['ProgramData'];
  final base = (root == null || root.isEmpty) ? r'C:\ProgramData' : root;
  return [
    '$base\\Proxy Dom\\logs\\service.log.1',
    '$base\\Proxy Dom\\logs\\service.log',
  ];
}

/// Remove the exported report from Downloads or Desktop.
///
/// The broker journal is NOT deleted here, and no amount of stopping the tunnel
/// would help. Two facts, both found by hand on the machine:
///
/// - the files sit under Program Data, where the interactive user holds
///   `Write` but not `Delete`, so the attempt failed on the ACL;
/// - the service opens `service.log` only for the microseconds it takes to
///   append one line and closes it again, so no handle was ever the blocker.
///
/// Telling the user to stop the tunnel was therefore advice that could not
/// work. `WindowsTunnel.clearServiceLog()` asks the service — which owns the
/// files and runs as SYSTEM — to delete its own journal.
Future<LogDeleteResult> deleteWindowsServiceLog() async {
  if (!Platform.isWindows) {
    return const LogDeleteResult();
  }
  final deleted = <String>[];
  final blocked = <String>[];
  for (final folder in ['Downloads', 'Desktop']) {
    final path = _profilePath(folder);
    if (path == null || path.isEmpty) continue;
    final file = File(path);
    try {
      if (!await file.exists()) continue;
      await file.delete();
      deleted.add(file.uri.pathSegments.last);
    } on FileSystemException {
      blocked.add(file.uri.pathSegments.last);
    }
  }
  return LogDeleteResult(deleted: deleted, blocked: blocked);
}
