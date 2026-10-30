/// Redaction for anything that leaves the process: the on-disk ring, the log
/// screen, the clipboard export and the shared report all go through here.
///
/// Two rules keep this safe:
/// * it is **idempotent** — re-redacting an already-masked string is a no-op,
///   so a line can be masked on write and again on export without turning
///   `***` into garbage;
/// * it is **not** a parser. It matches the shapes this app actually writes,
///   not the whole URI grammar, because a wrong guess at the grammar is worse
///   than a missing field.
library;

final _ipv4 = RegExp(
  r'\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b',
);

/// Node address as `45.91.***.***`. Domain names stay, including the document host.
String maskTunnelIpv4(String text) {
  return text.replaceAllMapped(_ipv4, (match) {
    final parts = match.group(0)!.split('.');
    return '${parts[0]}.${parts[1]}.***.***';
  });
}

final _shareSecret = RegExp(
  r'(hysteria2|hy2|vless|trojan|ss|vmess|socks5|socks)://[^@\s/]+@',
  caseSensitive: false,
);

/// Keys whose value is a credential in every shape this app logs.
///
/// `user`/`username` are here for the same reason as on Android: a Hysteria2
/// share link with no `:password` puts the *password* in the userinfo part, so
/// `user=…` is a secret, not a label.
final _keyValueSecret = RegExp(
  r'\b(auth|token|password|passwd|secret|authorization|hysteriaAuth|'
  r'obfs-password|obfs_password|api_key|apikey|user|username|login)'
  r'(=|:\s*)\s*("?)[^\s",}]+\3',
  caseSensitive: false,
);

final _bearer = RegExp(r'\bBearer\s+\S+');

/// Copy and export use the same mask as the buffer. Already-masked text is stable.
String redactTunnelLog(String text) {
  final withShareMasked = text.replaceAllMapped(_shareSecret, (match) {
    return '${match.group(1)}://***@';
  });
  final withKeysMasked = withShareMasked.replaceAllMapped(
    _keyValueSecret,
    (match) => '${match.group(1)}${match.group(2)}***',
  );
  final withBearerMasked = withKeysMasked.replaceAll(_bearer, 'Bearer ***');
  return maskTunnelIpv4(withBearerMasked);
}