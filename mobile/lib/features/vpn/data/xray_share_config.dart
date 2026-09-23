import 'dart:convert';

import 'share_link_parser.dart';

/// Local SOCKS port for an in-process Xray core (MPL-2.0). Not Hy2's :10808.
const xraySocksPort = 10809;

/// JSON for `hy2bind.StartShare`. Returns null for Hysteria2 or a link we
/// cannot describe. Callers must not log the result: it contains secrets.
String? buildXraySocksConfig(ParsedShareLink link) {
  if (link.isHysteria2) return null;
  final outbound = _outbound(link);
  if (outbound == null) return null;
  return jsonEncode({
    'inbounds': [
      {
        'listen': '127.0.0.1',
        'port': xraySocksPort,
        'protocol': 'socks',
        'settings': {'udp': true, 'auth': 'noauth'},
      },
    ],
    'outbounds': [outbound],
  });
}

Map<String, Object?>? _outbound(ParsedShareLink link) {
  switch (link.scheme) {
    case 'vless':
      return _vlessOrTrojan(link, protocol: 'vless');
    case 'trojan':
      return _vlessOrTrojan(link, protocol: 'trojan');
    case 'vmess':
      return _vmess(link);
    case 'ss':
      return _shadowsocks(link);
    default:
      return null;
  }
}

Map<String, Object?>? _vlessOrTrojan(
  ParsedShareLink link, {
  required String protocol,
}) {
  final uri = Uri.parse(link.raw);
  final host = uri.host.trim();
  if (host.isEmpty || uri.userInfo.isEmpty) return null;
  final user = Uri.decodeComponent(uri.userInfo);
  final port = uri.hasPort ? uri.port : 443;
  final q = uri.queryParameters;
  final network = (q['type'] ?? q['net'] ?? 'tcp').trim();
  final security = (q['security'] ?? 'tls').trim();
  final sni = (q['sni'] ?? q['peer'] ?? host).trim();
  final flow = (q['flow'] ?? '').trim();
  final userMap = <String, Object?>{
    if (protocol == 'vless') 'id': user,
    if (protocol == 'vless') 'encryption': q['encryption'] ?? 'none',
    if (protocol == 'trojan') 'password': user,
    if (flow.isNotEmpty) 'flow': flow,
  };
  return {
    'protocol': protocol,
    'settings': {
      'vnext': [
        {
          'address': host,
          'port': port,
          'users': [userMap],
        },
      ],
    },
    'streamSettings': _stream(q, network: network, security: security, sni: sni),
  };
}

Map<String, Object?>? _vmess(ParsedShareLink link) {
  final payload = link.raw.substring('vmess://'.length).split('#').first.trim();
  final jsonText = _b64(payload);
  if (jsonText == null) return null;
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map) return null;
  final host = '${decoded['add'] ?? ''}'.trim();
  final id = '${decoded['id'] ?? ''}'.trim();
  if (host.isEmpty || id.isEmpty) return null;
  final port = int.tryParse('${decoded['port'] ?? ''}') ?? 443;
  final network = '${decoded['net'] ?? 'tcp'}'.trim();
  final tls = '${decoded['tls'] ?? ''}'.trim();
  final security = tls.isEmpty ? 'none' : tls;
  final sni = '${decoded['sni'] ?? decoded['host'] ?? host}'.trim();
  return {
    'protocol': 'vmess',
    'settings': {
      'vnext': [
        {
          'address': host,
          'port': port,
          'users': [
            {'id': id, 'security': '${decoded['scy'] ?? 'auto'}'},
          ],
        },
      ],
    },
    'streamSettings': _stream(
      {
        'path': '${decoded['path'] ?? ''}',
        'host': '${decoded['host'] ?? ''}',
      },
      network: network,
      security: security,
      sni: sni,
    ),
  };
}

Map<String, Object?>? _shadowsocks(ParsedShareLink link) {
  final hash = link.raw.indexOf('#');
  final body = (hash < 0 ? link.raw : link.raw.substring(0, hash))
      .substring('ss://'.length);
  String method;
  String password;
  String host;
  int port;
  if (body.contains('@')) {
    final uri = Uri.parse(link.raw);
    final user = _b64(uri.userInfo) ?? Uri.decodeComponent(uri.userInfo);
    final colon = user.indexOf(':');
    if (colon <= 0 || uri.host.isEmpty) return null;
    method = user.substring(0, colon);
    password = user.substring(colon + 1);
    host = uri.host;
    port = uri.hasPort ? uri.port : 8388;
  } else {
    final decoded = _b64(body);
    if (decoded == null || !decoded.contains('@')) return null;
    final at = decoded.lastIndexOf('@');
    final user = decoded.substring(0, at);
    final hostPort = decoded.substring(at + 1);
    final colon = user.indexOf(':');
    final hp = hostPort.split(':');
    if (colon <= 0 || hp.length < 2) return null;
    method = user.substring(0, colon);
    password = user.substring(colon + 1);
    host = hp.first;
    port = int.tryParse(hp[1]) ?? 8388;
  }
  return {
    'protocol': 'shadowsocks',
    'settings': {
      'servers': [
        {
          'address': host,
          'port': port,
          'method': method,
          'password': password,
        },
      ],
    },
  };
}

Map<String, Object?> _stream(
  Map<String, String> q, {
  required String network,
  required String security,
  required String sni,
}) {
  final stream = <String, Object?>{
    'network': network.isEmpty ? 'tcp' : network,
    'security': security.isEmpty ? 'none' : security,
  };
  if (security == 'tls') {
    stream['tlsSettings'] = {
      'serverName': sni,
      if ((q['fp'] ?? '').isNotEmpty) 'fingerprint': q['fp'],
    };
  } else if (security == 'reality') {
    stream['realitySettings'] = {
      'serverName': sni,
      'publicKey': q['pbk'] ?? '',
      'shortId': q['sid'] ?? '',
      'fingerprint': (q['fp'] ?? '').isEmpty ? 'chrome' : q['fp'],
    };
  }
  if (network == 'ws') {
    stream['wsSettings'] = {
      'path': (q['path'] ?? '/').isEmpty ? '/' : q['path'],
      if ((q['host'] ?? '').isNotEmpty) 'headers': {'Host': q['host']},
    };
  }
  return stream;
}

String? _b64(String payload) {
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
