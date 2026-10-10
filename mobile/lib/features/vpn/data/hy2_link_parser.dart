import 'dart:convert';

import 'hysteria_profile.dart';

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
  final query = uri.queryParameters;
  // Official URI scheme: omitted sni means the TLS name is the host.
  final queriedSni = (_queryValue(query, 'sni') ?? '').trim();
  final sni = queriedSni.isEmpty ? host : queriedSni;
  final insecure = _queryValue(query, 'insecure') == '1' ||
      _queryValue(query, 'allowInsecure') == '1';
  final obfs = (_queryValue(query, 'obfs') ?? '').trim();
  final obfsPassword = _queryValue(query, 'obfs-password') ?? '';
  final quic = hy2QuicFromQuery(query);
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
      congestion: quic.congestion,
      bbrProfile: quic.bbrProfile,
      maxIdleTimeout: quic.maxIdleTimeout,
      keepAlivePeriod: quic.keepAlivePeriod,
      fmDeclared: quic.declared,
    ),
  );
}

/// Congestion name and QUIC timers a link declares, as written.
///
/// Values are forwarded verbatim. `hy2bind` clamps the timers and narrows the
/// controller (`hy2bind_quic_timers.go`, `hy2bind_congestion.go`), because an
/// out-of-range timer or an unknown controller is a fatal ConfigError in
/// core/v2. Bandwidth figures inside `fm` are named in [Hy2QuicDecl.declared]
/// and are not copied onto the profile.
///
/// Nested `quicParams` wins over a flat query key. `keepAlivePeriode22` is the
/// provider's typo, and it is the key their fleet ships.
Hy2QuicDecl hy2QuicFromQuery(Map<String, String> q) {
  final fm = _fmQuicParams(_queryValue(q, 'fm'));
  final values = fm?.values ?? const <String, String>{};
  return Hy2QuicDecl(
    congestion: _firstDeclared([
          values['congestion'],
          _queryValue(q, 'congestion'),
        ]) ??
        '',
    bbrProfile: _firstDeclared([
          values['bbrprofile'],
          _queryValue(q, 'bbrprofile'),
        ]) ??
        '',
    maxIdleTimeout: _firstDeclared([
          values['maxidletimeout'],
          _queryValue(q, 'maxidletimeout'),
        ]) ??
        '',
    keepAlivePeriod: _firstDeclared([
          values['keepaliveperiode22'],
          values['keepaliveperiod'],
          _queryValue(q, 'keepaliveperiode22'),
          _queryValue(q, 'keepaliveperiod'),
        ]) ??
        '',
    declared: _joinDeclared(fm?.declared ?? '', _flatDeclared(q)),
  );
}

/// What a link declared. Empty strings mean the link did not say.
class Hy2QuicDecl {
  const Hy2QuicDecl({
    required this.congestion,
    required this.bbrProfile,
    required this.maxIdleTimeout,
    required this.keepAlivePeriod,
    required this.declared,
  });

  final String congestion;
  final String bbrProfile;
  final String maxIdleTimeout;
  final String keepAlivePeriod;

  /// Field names only, comma-separated. Never the values.
  final String declared;
}

class _FmQuic {
  const _FmQuic({required this.values, required this.declared});

  /// Normalized key → scalar text. Numbers are rendered without interpolation.
  final Map<String, String> values;

  /// `quicParams.originalKey` names, in document order.
  final String declared;
}

/// `quicParams` from the link's `fm` blob. Null when absent or unreadable.
///
/// A broken `fm` is ignored. The rest of the link still parses: a timer hint
/// must not turn a working node into a parse error.
_FmQuic? _fmQuicParams(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  String? wrapper;
  Object? quic;
  for (final entry in decoded.entries) {
    if (_queryKey('${entry.key}') != 'quicparams') continue;
    wrapper = '${entry.key}';
    quic = entry.value;
    break;
  }
  if (wrapper == null || quic is! Map) return null;
  final values = <String, String>{};
  final names = <String>[];
  for (final entry in quic.entries) {
    final scalar = _fmScalar(entry.value);
    if (scalar == null) continue;
    final key = '${entry.key}';
    names.add('$wrapper.$key');
    values[_queryKey(key)] = scalar;
  }
  return _FmQuic(values: values, declared: names.join(','));
}

/// JSON number or string. Maps and lists are not timer values.
String? _fmScalar(Object? value) {
  if (value is int) return value.toString();
  if (value is double) {
    if (value.isNaN || value.isInfinite) return null;
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }
  if (value is String) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
  return null;
}

/// The first non-blank value, trimmed.
String? _firstDeclared(List<String?> values) {
  for (final value in values) {
    final text = (value ?? '').trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

String _joinDeclared(String nested, String flat) {
  if (nested.isEmpty) return flat;
  if (flat.isEmpty) return nested;
  return '$nested,$flat';
}

/// Flat query keys this reader understands, under their original spelling.
///
/// `fm` itself is the container and is not listed. Bandwidth names are listed
/// so the log shows they were present; their values are not copied.
String _flatDeclared(Map<String, String> q) {
  const recognized = <String>{
    'congestion',
    'bbrprofile',
    'maxidletimeout',
    'keepaliveperiod',
    'keepaliveperiode22',
    'brutalup',
    'brutaldown',
  };
  final names = <String>[];
  for (final entry in q.entries) {
    final key = _queryKey(entry.key);
    if (key == 'fm' || !recognized.contains(key)) continue;
    if (entry.value.trim().isEmpty) continue;
    names.add(entry.key);
  }
  return names.join(',');
}

/// Query value for [key], matched without case, `_`, or `-`.
///
/// `maxIdleTimeout`, `max_idle_timeout` and `max-idle-timeout` are one key.
/// Looking up only the spelling we happened to write would drop the value for
/// every other provider.
String? _queryValue(Map<String, String> q, String key) {
  final direct = q[key];
  if (direct != null) return direct;
  final wanted = _queryKey(key);
  for (final entry in q.entries) {
    if (_queryKey(entry.key) == wanted) return entry.value;
  }
  return null;
}

String _queryKey(String key) =>
    key.toLowerCase().replaceAll('_', '').replaceAll('-', '');

/// Percent-decoded remark. `Uri.fragment` leaves `%D0…` in the string.
String decodeUserFacingToken(String raw) {
  final text = raw.trim();
  if (!text.contains('%')) return text;
  try {
    return Uri.decodeComponent(text);
  } on ArgumentError {
    return text;
  }
}

/// Fragment after `#`, decoded once.
String decodedShareFragment(String raw) {
  final hash = raw.indexOf('#');
  if (hash < 0 || hash + 1 >= raw.length) return '';
  return decodeUserFacingToken(raw.substring(hash + 1));
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
/// Throws [FormatException] `subscription` when a custom-scheme deeplink does
/// not contain an http(s) address. No request is made.
SubscriptionDocumentTarget? subscriptionDocumentTarget(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final lower = text.toLowerCase();
  if (lower.startsWith('https://') || lower.startsWith('http://')) {
    return _webTarget(text);
  }
  if (lower.startsWith('happ://') ||
      lower.startsWith('proxydom://') ||
      lower.startsWith('teremok://')) {
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
    r'^(?:proxydom|teremok|happ)://(?:add|import)/(https?://.*)$',
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
      : normalized.padRight(
          normalized.length + (4 - normalized.length % 4), '=');
  try {
    return utf8.decode(base64Decode(pad));
  } on FormatException {
    return null;
  }
}
