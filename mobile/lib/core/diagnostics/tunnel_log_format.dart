/// Millisecond UTC stamp shared by the Dart buffer and the Android ring.
String tunnelLogStamp([DateTime? time]) {
  final utc = (time ?? DateTime.now()).toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final ms = utc.millisecond.toString().padLeft(3, '0');
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${two(utc.month)}-${two(utc.day)}T'
      '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}.'
      '${ms}Z';
}

/// Source token from the event name: `doc.fetch` → `doc`.
String tunnelLogSource(String message) {
  final token = message.trim().split(RegExp(r'\s+')).first;
  final dot = token.indexOf('.');
  if (dot <= 0) return 'app';
  return token.substring(0, dot);
}

final _stamp = RegExp(
  r'^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z)',
);

final _epochMs = RegExp(r'^(\d{13})(?:\s|$)');

/// ISO stamp, or a leading epoch-millis line from an older native ring.
DateTime? tunnelLogTime(String line) {
  final match = _stamp.firstMatch(line);
  if (match != null) return DateTime.tryParse(match.group(1)!);
  final epoch = _epochMs.firstMatch(line);
  if (epoch == null) return null;
  final ms = int.tryParse(epoch.group(1)!);
  if (ms == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}
