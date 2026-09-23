import 'dart:convert';

import 'hy2_link_parser.dart';

/// One pasted server. [raw] stays on device and must not be logged.
class ParsedShareLink {
  const ParsedShareLink({
    required this.scheme,
    required this.name,
    required this.endpoint,
    required this.raw,
    this.hy2,
  });

  /// `hysteria2`, `vless`, `vmess`, `trojan`, or `ss`.
  final String scheme;
  final String name;

  /// `host:port` for the list. Not a secret.
  final String endpoint;
  final String raw;
  final ParsedHy2Link? hy2;

  bool get isHysteria2 => hy2 != null;
}

const _schemes = <String>[
  'hysteria2://',
  'hy2://',
  'vless://',
  'vmess://',
  'trojan://',
  'ss://',
];

bool isShareLinkLine(String raw) {
  final text = raw.trim().toLowerCase();
  for (final scheme in _schemes) {
    if (text.startsWith(scheme)) return true;
  }
  return false;
}

/// Newline list, one URI, or a base64 blob of those lines.
List<ParsedShareLink> parseShareSubscription(String body) {
  final decoded = _decodeSubscriptionBody(body);
  final out = <ParsedShareLink>[];
  for (final line in decoded.split(RegExp(r'\r?\n'))) {
    final text = line.trim();
    if (text.isEmpty || text.startsWith('#')) continue;
    if (!isShareLinkLine(text)) continue;
    try {
      out.add(parseShareLink(text));
    } on FormatException {
      continue;
    }
  }
  return out;
}

ParsedShareLink parseShareLink(String raw) {
  final text = raw.trim();
  final lower = text.toLowerCase();
  if (lower.startsWith('hysteria2://') || lower.startsWith('hy2://')) {
    final hy2 = parseHy2Link(text);
    return ParsedShareLink(
      scheme: 'hysteria2',
      name: hy2.name,
      endpoint: hy2.profile.server,
      raw: text,
      hy2: hy2,
    );
  }
  if (lower.startsWith('vless://')) return _parseUserHost('vless', text);
  if (lower.startsWith('trojan://')) return _parseUserHost('trojan', text);
  if (lower.startsWith('vmess://')) return _parseVmess(text);
  if (lower.startsWith('ss://')) return _parseSs(text);
  throw const FormatException('unsupported scheme');
}

ParsedShareLink _parseUserHost(String scheme, String text) {
  final uri = Uri.parse(text);
  final host = uri.host.trim();
  if (host.isEmpty) throw const FormatException('missing host');
  final port = uri.hasPort ? uri.port : 443;
  final fragment = uri.fragment.trim();
  return ParsedShareLink(
    scheme: scheme,
    name: fragment.isEmpty ? host : fragment,
    endpoint: '$host:$port',
    raw: text,
  );
}

ParsedShareLink _parseVmess(String text) {
  final payload = text.substring('vmess://'.length).split('#').first.trim();
  final jsonText = _decodeUtf8Base64(payload);
  if (jsonText == null) throw const FormatException('vmess');
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map) throw const FormatException('vmess');
  final host = '${decoded['add'] ?? ''}'.trim();
  if (host.isEmpty) throw const FormatException('vmess host');
  final port = int.tryParse('${decoded['port'] ?? ''}') ?? 443;
  final name = '${decoded['ps'] ?? ''}'.trim();
  return ParsedShareLink(
    scheme: 'vmess',
    name: name.isEmpty ? host : name,
    endpoint: '$host:$port',
    raw: text,
  );
}

ParsedShareLink _parseSs(String text) {
  final hash = text.indexOf('#');
  final body = (hash < 0 ? text : text.substring(0, hash)).substring('ss://'.length);
  if (body.contains('@')) {
    final uri = Uri.parse(text);
    final port = uri.hasPort ? uri.port : 8388;
    final fragment = uri.fragment.trim();
    return ParsedShareLink(
      scheme: 'ss',
      name: fragment.isEmpty ? uri.host : fragment,
      endpoint: '${uri.host}:$port',
      raw: text,
    );
  }
  final payload = text.substring('ss://'.length).split('#').first.trim();
  final decoded = _decodeUtf8Base64(payload);
  if (decoded == null || !decoded.contains('@')) {
    throw const FormatException('ss');
  }
  final at = decoded.lastIndexOf('@');
  final hostPort = decoded.substring(at + 1).trim();
  if (!hostPort.contains(':')) throw const FormatException('ss host');
  final name = Uri.parse(text).fragment.trim();
  final host = hostPort.split(':').first;
  return ParsedShareLink(
    scheme: 'ss',
    name: name.isEmpty ? host : name,
    endpoint: hostPort,
    raw: text,
  );
}

String _decodeSubscriptionBody(String body) {
  final text = body.trim();
  if (text.contains('://')) return text;
  return _decodeUtf8Base64(text.replaceAll(RegExp(r'\s+'), '')) ?? text;
}

String? _decodeUtf8Base64(String payload) {
  final normalized = payload.replaceAll('-', '+').replaceAll('_', '/');
  final pad = normalized.length % 4 == 0
      ? normalized
      : normalized.padRight(normalized.length + (4 - normalized.length % 4), '=');
  try {
    final bytes = base64Decode(pad);
    final text = utf8.decode(bytes);
    if (text.isEmpty) return null;
    return text;
  } on FormatException {
    return null;
  }
}
