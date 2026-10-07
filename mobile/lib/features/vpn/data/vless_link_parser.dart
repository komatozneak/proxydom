import 'vpn_config.dart';

/// Parsed `vless://` URI fields (Marzban / Reality).
class ParsedVlessLink {
  const ParsedVlessLink({
    required this.uuid,
    required this.host,
    required this.port,
    required this.transport,
    required this.flow,
    required this.security,
    required this.publicKey,
    required this.shortId,
    required this.serverName,
    required this.fingerprint,
    required this.spiderX,
    required this.name,
    this.path,
    this.mode,
  });

  final String uuid;
  final String host;
  final int port;
  final String transport;
  final String? flow;
  final String? security;
  final String? publicKey;
  final String? shortId;
  final String? serverName;
  final String fingerprint;
  final String spiderX;
  final String? name;
  final String? path;
  final String? mode;
}

/// Parse a Marzban `vless://uuid@host:port?…#name` link.
///
/// Mirrors [backend/app/services/vless_parser.py] — no env Reality fallbacks.
ParsedVlessLink parseVlessLink(String link) {
  final trimmed = link.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('empty vless link');
  }
  final uri = Uri.parse(trimmed);
  if (uri.scheme != 'vless') {
    throw FormatException('unsupported scheme: ${uri.scheme}');
  }
  final uuid = Uri.decodeComponent(uri.userInfo);
  if (uuid.isEmpty) {
    throw const FormatException('missing uuid in vless link');
  }
  final host = uri.host;
  if (host.isEmpty) {
    throw const FormatException('missing host in vless link');
  }
  final port = uri.hasPort ? uri.port : 443;
  final params = uri.queryParameters;
  final flow = params['flow'];
  final path = params['path'];
  final mode = params['mode'];
  return ParsedVlessLink(
    uuid: uuid,
    host: host,
    port: port,
    transport: params['type']?.isNotEmpty == true ? params['type']! : 'tcp',
    flow: (flow == null || flow.isEmpty) ? null : flow,
    security: params['security'],
    publicKey: params['pbk'],
    shortId: params['sid'],
    serverName: params['sni'],
    fingerprint:
        params['fp']?.isNotEmpty == true ? params['fp']! : 'chrome',
    spiderX: params['spx'] ?? '',
    name: uri.hasFragment ? Uri.decodeComponent(uri.fragment) : null,
    path: (path == null || path.isEmpty) ? null : path,
    mode: (mode == null || mode.isEmpty) ? null : mode,
  );
}

/// Optional Reality fills when Marzban ships blank ``sid=`` / ``pbk=``.
class RealityFallback {
  const RealityFallback({
    this.publicKey,
    this.shortId,
    this.serverName,
  });

  final String? publicKey;
  final String? shortId;
  final String? serverName;
}

String? _firstNonEmpty(String? primary, String? fallback) {
  final a = primary?.trim();
  if (a != null && a.isNotEmpty) return a;
  final b = fallback?.trim();
  if (b != null && b.isNotEmpty) return b;
  return null;
}

/// Build a single [EngineCandidate] from a VLESS URI (legacy `/vpn/config` fallback).
EngineCandidate engineCandidateFromVlessLink(
  String link, {
  String? id,
  String? label,
  RealityFallback? realityFallback,
}) {
  final parsed = parseVlessLink(link);
  if (parsed.security != 'reality') {
    throw FormatException(
      'unsupported VLESS security for xray_profile: ${parsed.security}',
    );
  }
  final publicKey = _firstNonEmpty(
    parsed.publicKey,
    realityFallback?.publicKey,
  );
  final shortId = _firstNonEmpty(parsed.shortId, realityFallback?.shortId);
  final serverName = _firstNonEmpty(
    parsed.serverName,
    realityFallback?.serverName,
  );
  final missing = <String>[
    if (publicKey == null) 'pbk',
    if (shortId == null) 'sid',
    if (serverName == null) 'sni',
  ];
  if (missing.isNotEmpty) {
    throw FormatException(
      'missing Reality fields for xray_profile fallback: ${missing.join(', ')}',
    );
  }
  final host = parsed.host;
  return EngineCandidate(
    id: id ?? host,
    label: label ?? parsed.name ?? host,
    host: host,
    port: parsed.port,
    protocol: 'vless',
    uuid: parsed.uuid,
    flow: parsed.flow,
    transport: parsed.transport,
    security: 'reality',
    serverName: serverName!,
    publicKey: publicKey!,
    shortId: shortId!,
    fingerprint: parsed.fingerprint,
    spiderX: parsed.spiderX,
    path: parsed.path,
    mode: parsed.mode,
  );
}

/// Pick `selected_link` or the first `vless://` entry from [links].
String? pickVlessLink({
  String? selectedLink,
  List<String> links = const [],
}) {
  final selected = selectedLink?.trim();
  if (selected != null && selected.startsWith('vless://')) {
    return selected;
  }
  for (final link in links) {
    final trimmed = link.trim();
    if (trimmed.startsWith('vless://')) return trimmed;
  }
  return null;
}
