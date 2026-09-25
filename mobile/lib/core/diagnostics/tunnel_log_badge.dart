/// The `[info]` / `[error]` token in one tunnel-log line.
class TunnelLogBadge {
  const TunnelLogBadge({
    required this.before,
    required this.label,
    required this.after,
  });

  final String before;

  /// `error`, `warn`, `info`, or `debug`.
  final String label;
  final String after;
}

final _levelToken = RegExp(
  r'\[(error|warn|warning|info|debug)\]',
  caseSensitive: false,
);

/// First level token. The rest of the line stays plain text.
TunnelLogBadge? tunnelLogBadge(String line) {
  final match = _levelToken.firstMatch(line);
  if (match == null) return null;
  final raw = match.group(1)!.toLowerCase();
  return TunnelLogBadge(
    before: line.substring(0, match.start),
    label: raw == 'warning' ? 'warn' : raw,
    after: line.substring(match.end),
  );
}
