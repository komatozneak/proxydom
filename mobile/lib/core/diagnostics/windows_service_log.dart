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
