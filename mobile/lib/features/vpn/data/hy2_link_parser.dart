import 'dart:convert';

import 'vpn_config.dart';

/// One pasted Hysteria2 server.
class ParsedHy2Link {
  const ParsedHy2Link({required this.name, required this.profile});

  final String name;
  final HysteriaProfile profile;
}

/// Parse `hysteria2://` or `hy2://` userpass links.
///
/// Userinfo is decoded by [Uri], so `%2B` stays a plus and is not a space.
ParsedHy2Link parseHy2Link(String raw) {
  var text = raw.trim();
  if (text.startsWith('hy2://')) {
    text = 'hysteria2://${text.substring('hy2://'.length)}';
  }
  if (!text.startsWith('hysteria2://')) {
    throw const FormatException('unsupported scheme');
  }
  final uri = Uri.parse(text);
  if (uri.scheme != 'hysteria2') {
    throw FormatException('unsupported scheme: ${uri.scheme}');
  }
  final host = uri.host.trim();
  if (host.isEmpty) {
    throw const FormatException('missing host');
  }
  final userInfo = uri.userInfo;
  if (userInfo.isEmpty) {
    throw const FormatException('missing auth');
  }
  final colon = userInfo.indexOf(':');
  final username = colon < 0
      ? Uri.decodeComponent(userInfo)
      : Uri.decodeComponent(userInfo.substring(0, colon));
  final password =
      colon < 0 ? '' : Uri.decodeComponent(userInfo.substring(colon + 1));
  final auth = password.isEmpty ? username : '$username:$password';
  final port = uri.hasPort ? uri.port : 443;
  // Official URI scheme: omitted sni means the TLS name is the host.
  final queriedSni = (uri.queryParameters['sni'] ?? '').trim();
  final sni = queriedSni.isEmpty ? host : queriedSni;
  final insecure = uri.queryParameters['insecure'] == '1' ||
      uri.queryParameters['allowInsecure'] == '1';
  final obfs = (uri.queryParameters['obfs'] ?? '').trim();
  final obfsPassword = uri.queryParameters['obfs-password'] ?? '';
  final title = shareServerTitle(decodedShareFragment(text), host);
  return ParsedHy2Link(
    name: title,
    profile: HysteriaProfile(
      schemaVersion: 1,
      nodeId: host,
      server: '$host:$port',
      auth: auth,
      username: username,
      sni: sni,
      socksListen: '127.0.0.1:10808',
      insecure: insecure,
      obfs: obfs,
      obfsPassword: obfsPassword,
    ),
  );
}

/// Fragment after `#`, decoded once. `Uri.fragment` leaves `%D0…` on this scheme.
String decodedShareFragment(String raw) {
  final hash = raw.indexOf('#');
  if (hash < 0 || hash + 1 >= raw.length) return '';
  final tail = raw.substring(hash + 1).trim();
  try {
    return Uri.decodeComponent(tail);
  } on ArgumentError {
    return tail;
  }
}

/// Title before ` · `. Falls back to [fallback] when the remark is empty.
String shareServerTitle(String remark, String fallback) {
  const sep = ' · ';
  final at = remark.indexOf(sep);
  final title = (at < 0 ? remark : remark.substring(0, at)).trim();
  return title.isEmpty ? fallback : title;
}

/// Newline-separated subscription body, or one bare URI.
List<ParsedHy2Link> parseHy2Subscription(String body) {
  final out = <ParsedHy2Link>[];
  for (final line in body.split(RegExp(r'\r?\n'))) {
    final text = line.trim();
    if (text.isEmpty || text.startsWith('#')) continue;
    if (text.startsWith('hysteria2://') || text.startsWith('hy2://')) {
      out.add(parseHy2Link(text));
    }
  }
  return out;
}

/// Web document the user pasted. [url] has no fragment; [title] is `#name`.
class SubscriptionDocumentTarget {
  const SubscriptionDocumentTarget({required this.url, this.title});

  final String url;
  final String? title;
}

/// One http(s) document, or null when [raw] is share lines.
///
/// Throws [FormatException] `subscription` when a Happ/Teremok deeplink does
/// not contain an http(s) address. No request is made.
SubscriptionDocumentTarget? subscriptionDocumentTarget(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final lower = text.toLowerCase();
  if (lower.startsWith('https://') || lower.startsWith('http://')) {
    return _webTarget(text);
  }
  if (lower.startsWith('happ://') || lower.startsWith('teremok://')) {
    return _deeplinkTarget(text);
  }
  return null;
}

/// True when [raw] is an http(s) subscription document, not a share line.
bool looksLikeSubscriptionUrl(String raw) {
  try {
    return subscriptionDocumentTarget(raw) != null;
  } on FormatException {
    return false;
  }
}

SubscriptionDocumentTarget _webTarget(String text) {
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) {
    throw const FormatException('subscription');
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') {
    throw const FormatException('subscription');
  }
  final title = _fragmentTitle(uri);
  var url = uri.replace(fragment: '').toString();
  if (url.endsWith('#')) url = url.substring(0, url.length - 1);
  return SubscriptionDocumentTarget(
    url: url,
    title: title,
  );
}

SubscriptionDocumentTarget _deeplinkTarget(String text) {
  final nested = RegExp(
    r'^(?:teremok|happ)://(?:add|import)/(https?://.*)$',
    caseSensitive: false,
  ).firstMatch(text);
  if (nested != null) {
    return _requireWeb(nested.group(1)!);
  }
  final uri = Uri.tryParse(text);
  if (uri == null) throw const FormatException('subscription');
  final fromQuery = uri.queryParameters['url'];
  if (fromQuery != null && fromQuery.trim().isNotEmpty) {
    return _requireWeb(fromQuery.trim());
  }
  final host = uri.host.toLowerCase();
  if (host == 'sub') {
    var payload = uri.path;
    if (payload.startsWith('/')) payload = payload.substring(1);
    final decoded = _utf8Base64(payload);
    if (decoded == null) throw const FormatException('subscription');
    return _requireWeb(decoded.trim());
  }
  final marker = text.indexOf('://');
  final payload = marker < 0 ? '' : text.substring(marker + 3);
  final decoded = _utf8Base64(payload);
  final decodedLower = decoded?.trim().toLowerCase() ?? '';
  if (decoded != null &&
      (decodedLower.startsWith('https://') ||
          decodedLower.startsWith('http://'))) {
    return _requireWeb(decoded.trim());
  }
  throw const FormatException('subscription');
}

SubscriptionDocumentTarget _requireWeb(String text) {
  final lower = text.toLowerCase();
  if (!lower.startsWith('https://') && !lower.startsWith('http://')) {
    throw const FormatException('subscription');
  }
  return _webTarget(text);
}

String? _fragmentTitle(Uri uri) {
  final raw = uri.fragment.trim();
  if (raw.isEmpty) return null;
  try {
    final decoded = Uri.decodeComponent(raw).trim();
    return decoded.isEmpty ? null : decoded;
  } on ArgumentError {
    return raw;
  }
}

String? _utf8Base64(String payload) {
  final normalized = payload.replaceAll('-', '+').replaceAll('_', '/');
  final pad = normalized.length % 4 == 0
      ? normalized
      : normalized.padRight(normalized.length + (4 - normalized.length % 4), '=');
  try {
    return utf8.decode(base64Decode(pad));
  } on FormatException {
    return null;
  }
}
