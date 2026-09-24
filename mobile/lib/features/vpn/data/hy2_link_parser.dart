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
  final sni = (uri.queryParameters['sni'] ?? '').trim();
  if (sni.isEmpty) {
    throw const FormatException('missing sni');
  }
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

/// True when [raw] is an http(s) subscription URL, not a Hy2 URI.
bool looksLikeSubscriptionUrl(String raw) {
  final text = raw.trim();
  final uri = Uri.tryParse(text);
  if (uri == null) return false;
  return uri.scheme == 'https' || uri.scheme == 'http';
}
