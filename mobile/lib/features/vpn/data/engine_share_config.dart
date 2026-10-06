import 'dart:convert';

import 'share_link_parser.dart';

/// Local SOCKS port for the in-process VLESS core. Not Hy2's :10808.
const shareSocksPort = 10809;

/// JSON for `hy2bind.StartShare`. The Go loader turns this document into
/// v2ray-core protobuf. It is not the full v2ray JSON schema: that loader
/// also compiles WireGuard. Returns null for Hysteria2 or a link we cannot
/// describe. Callers must not log the result: it contains secrets.
///
/// `network` stays the share-link short name (`ws`, `kcp`). The loader maps
/// those onto the names v2ray-core registers (`websocket`, `mkcp`).
String? buildShareSocksConfig(ParsedShareLink link) {
  if (link.isHysteria2) return null;
  final outbound = _outbound(link);
  if (outbound == null) return null;
  outbound['tag'] = 'proxy';
  return jsonEncode({
    'log': {'loglevel': 'warning'},
    'inbounds': [
      {
        'listen': '127.0.0.1',
        'port': shareSocksPort,
        'protocol': 'socks',
        'settings': {'udp': true, 'auth': 'noauth'},
        'tag': 'socks-in',
      },
    ],
    'outbounds': [
      outbound,
      {'protocol': 'freedom', 'tag': 'direct'},
    ],
    'routing': {
      'domainStrategy': 'AsIs',
      'rules': [
        {
          'type': 'field',
          'ip': [
            '10.0.0.0/8',
            '172.16.0.0/12',
            '192.168.0.0/16',
            '127.0.0.0/8',
          ],
          'outboundTag': 'direct',
        },
      ],
    },
  });
}

Map<String, Object?>? _outbound(ParsedShareLink link) {
  switch (link.scheme) {
    case 'vless':
      return _vless(link);
    case 'trojan':
      return _trojan(link);
    case 'vmess':
      return _vmess(link);
    case 'ss':
      return _shadowsocks(link);
    default:
      return null;
  }
}

Map<String, Object?>? _vless(ParsedShareLink link) {
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
  return {
    'protocol': 'vless',
    'settings': {
      'vnext': [
        {
          'address': host,
          'port': port,
          'users': [
            {
              'id': user,
              'encryption': q['encryption'] ?? 'none',
              if (flow.isNotEmpty) 'flow': flow,
            },
          ],
        },
      ],
    },
    'streamSettings':
        _stream(q, network: network, security: security, sni: sni),
  };
}

Map<String, Object?>? _trojan(ParsedShareLink link) {
  final uri = Uri.parse(link.raw);
  final host = uri.host.trim();
  if (host.isEmpty || uri.userInfo.isEmpty) return null;
  final password = Uri.decodeComponent(uri.userInfo);
  final port = uri.hasPort ? uri.port : 443;
  final q = uri.queryParameters;
  final network = (q['type'] ?? q['net'] ?? 'tcp').trim();
  final security = (q['security'] ?? 'tls').trim();
  final sni = (q['sni'] ?? q['peer'] ?? host).trim();
  return {
    'protocol': 'trojan',
    'settings': {
      'servers': [
        {
          'address': host,
          'port': port,
          'password': password,
        },
      ],
    },
    'streamSettings':
        _stream(q, network: network, security: security, sni: sni),
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
  final uri = Uri.tryParse(link.raw.split('#').first);
  final q = uri?.queryParameters ?? const <String, String>{};
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
    'streamSettings': _stream(
      q,
      network: (q['type'] ?? q['net'] ?? 'tcp').trim(),
      security: 'none',
      sni: host,
    ),
  };
}

Map<String, Object?> _stream(
  Map<String, String> q, {
  required String network,
  required String security,
  required String sni,
}) {
  final normalized = switch (network) {
    '' => 'tcp',
    'mkcp' => 'kcp',
    _ => network,
  };
  final stream = <String, Object?>{
    'network': normalized,
    'security': security.isEmpty ? 'none' : security,
  };
  if (security == 'tls') {
    final allowInsecure = q['allowInsecure'] == '1' || q['insecure'] == '1';
    final alpn = (q['alpn'] ?? '')
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    stream['tlsSettings'] = {
      'serverName': sni,
      if ((q['fp'] ?? '').isNotEmpty) 'fingerprint': q['fp'],
      if (allowInsecure) 'allowInsecure': true,
      if (alpn.isNotEmpty) 'alpn': alpn,
    };
  } else if (security == 'reality') {
    stream['realitySettings'] = {
      'serverName': sni,
      'publicKey': q['pbk'] ?? '',
      'shortId': q['sid'] ?? '',
      'fingerprint': (q['fp'] ?? '').isEmpty ? 'chrome' : q['fp'],
    };
  }
  if (normalized == 'ws') {
    stream['wsSettings'] = {
      'path': (q['path'] ?? '/').isEmpty ? '/' : q['path'],
      if ((q['host'] ?? '').isNotEmpty) 'headers': {'Host': q['host']},
    };
  }
  if (normalized == 'kcp') {
    final seed = (q['seed'] ?? q['path'] ?? '').trim();
    if (seed.isNotEmpty && seed != '/') {
      stream['kcpSettings'] = {'seed': seed};
    }
  }
  return stream;
}

String? _b64(String payload) {
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
