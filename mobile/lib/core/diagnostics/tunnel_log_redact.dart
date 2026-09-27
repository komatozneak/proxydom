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
  r'(hysteria2|hy2|vless)://[^@\s/]+@',
  caseSensitive: false,
);

/// Copy and export use the same mask as the buffer. Already-masked text is stable.
String redactTunnelLog(String text) {
  final secrets = text.replaceAllMapped(_shareSecret, (match) {
    return '${match.group(1)}://***@';
  });
  return maskTunnelIpv4(secrets);
}
