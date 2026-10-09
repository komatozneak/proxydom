import 'dart:convert';

import 'share_link_parser.dart';

/// Local SOCKS port for the in-process VLESS engine (v2ray-core, MIT).
/// Not Hy2's :10808.
const shareSocksPort = 10809;

/// JSON for `hy2bind.StartShare`. Returns null for Hysteria2 or a link we
/// cannot describe. Callers must not log the result: it contains secrets.
///
/// "Cannot describe" means the loader would reject the document. The engine is
/// v2ray-core, which has no Reality engine and no `xhttp` dialer, and
/// `hy2bind_engine_load.go` is strict about both transport and security (see
/// [_engineTransports] and [_engineSecurities]). Returning null keeps the
/// failure explicit instead of handing over a document the loader will reject.
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
  final stream = _stream(q, network: network, security: security, sni: sni);
  if (stream == null) return null;
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
    'streamSettings': stream,
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
  final stream = _stream(q, network: network, security: security, sni: sni);
  if (stream == null) return null;
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
    'streamSettings': stream,
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
  final stream = _stream(
    {
      'path': '${decoded['path'] ?? ''}',
      'host': '${decoded['host'] ?? ''}',
    },
    network: network,
    security: security,
    sni: sni,
  );
  if (stream == null) return null;
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
    'streamSettings': stream,
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
  final stream = _stream(
    q,
    network: (q['type'] ?? q['net'] ?? 'tcp').trim(),
    security: 'none',
    sni: host,
  );
  if (stream == null) return null;
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
    'streamSettings': stream,
  };
}

/// Transports `engineTransport` expresses in `hy2bind_engine_load.go`.
///
/// Everything else — `grpc`, `quic`, `httpupgrade`, `xhttp`, `splithttp` — is
/// refused, because the loader answers `unsupported transport` and the start
/// fails after the UI has already offered the line as active.
const _engineTransports = {'tcp', 'ws', 'websocket', 'kcp'};

/// Securities `shareStreamConfig` expresses in `hy2bind_engine_load.go`.
///
/// `reality` and `xtls` are refused there, so they are refused here.
const _engineSecurities = {'none', 'tls'};

Map<String, Object?>? _stream(
  Map<String, String> q, {
  required String network,
  required String security,
  required String sni,
}) {
  // Share links are written by hand and by many generators, so `type=WS` and
  // `security=TLS` arrive here as often as the lowercase forms. Every other
  // reader folds case before comparing: the C++ broker through `lower_copy`,
  // the Go loader through `strings.ToLower`, and the `headerType` check a few
  // lines below. Comparing the raw word here made this the only side that
  // refused, and it refused on every platform at once — a node the engine can
  // dial shown as unsupported, which is the least useful answer available.
  final folded = network.trim().toLowerCase();
  final normalized = switch (folded) {
    '' => 'tcp',
    'mkcp' => 'kcp',
    _ => folded,
  };
  final foldedSecurity = security.trim().toLowerCase();
  final scheme = foldedSecurity.isEmpty ? 'none' : foldedSecurity;
  // Allowlists, not a blacklist: the loader's own sets are the authority, so a
  // transport or security it would reject must stay "not describable" here.
  if (!_engineTransports.contains(normalized)) return null;
  if (!_engineSecurities.contains(scheme)) return null;
  // `headerType` is read by no layer: the loader has no `tcpSettings` at all,
  // so TCP obfuscation cannot be expressed. Dropping it silently would dial
  // plain TCP at a server that expects obfuscation and surface a generic
  // failure; refusing is the honest answer. `headerType=none` means no
  // obfuscation and passes.
  final headerType = (q['headerType'] ?? '').trim().toLowerCase();
  if (headerType.isNotEmpty && headerType != 'none') return null;
  final stream = <String, Object?>{
    'network': normalized,
    'security': scheme,
  };
  if (scheme == 'tls') {
    final allowInsecure = q['allowInsecure'] == '1' || q['insecure'] == '1';
    // Uri has already percent-decoded the query, so `http%2F1.1` arrives as
    // `http/1.1`. A front that serves only http/1.1 rejects a WS upgrade
    // offered under h2; the link's own alpn is the only authority on that.
    final alpn = _alpnList(q['alpn']);
    final fingerprint = _fingerprint(q['fp']);
    stream['tlsSettings'] = {
      'serverName': sni,
      // Share links say `fp=chrome`. v2ray-core's uTLS map has no such name
      // (`unknown preset name`) and then the dial never starts. Translate the
      // short names to the presets that core actually has.
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (allowInsecure) 'allowInsecure': true,
      if (alpn.isNotEmpty) 'alpn': alpn,
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

/// Short `fp` values from share links, and the uTLS preset v2ray-core accepts.
///
/// Names already in the core map pass through. Anything else is omitted: the
/// loader treats a non-empty fingerprint as a uTLS imitate string, and an
/// unknown one fails the dial before TLS starts.
const _fingerprintAliases = <String, String>{
  'chrome': 'chrome_auto',
  'firefox': 'firefox_auto',
  'ios': 'ios_auto',
  'android': 'android_11_okhttp',
  'edge': 'edge_auto',
  'safari': 'safari_auto',
  '360': '360_auto',
  'qq': 'qq_auto',
  'random': 'randomized',
  'randomized': 'randomized',
  'randomizedalpn': 'randomizedalpn',
  'randomizednoalpn': 'randomizednoalpn',
  'firefox_auto': 'firefox_auto',
  'firefox_55': 'firefox_55',
  'firefox_56': 'firefox_56',
  'firefox_63': 'firefox_63',
  'firefox_65': 'firefox_65',
  'firefox_99': 'firefox_99',
  'firefox_102': 'firefox_102',
  'firefox_105': 'firefox_105',
  'chrome_auto': 'chrome_auto',
  'chrome_58': 'chrome_58',
  'chrome_62': 'chrome_62',
  'chrome_70': 'chrome_70',
  'chrome_72': 'chrome_72',
  'chrome_83': 'chrome_83',
  'chrome_87': 'chrome_87',
  'chrome_96': 'chrome_96',
  'chrome_100': 'chrome_100',
  'chrome_102': 'chrome_102',
  'ios_auto': 'ios_auto',
  'ios_11_1': 'ios_11_1',
  'ios_12_1': 'ios_12_1',
  'ios_13': 'ios_13',
  'ios_14': 'ios_14',
  'android_11_okhttp': 'android_11_okhttp',
  'edge_auto': 'edge_auto',
  'edge_85': 'edge_85',
  'edge_106': 'edge_106',
  'safari_auto': 'safari_auto',
  'safari_16_0': 'safari_16_0',
  '360_auto': '360_auto',
  '360_7_5': '360_7_5',
  '360_11_0': '360_11_0',
  'qq_auto': 'qq_auto',
  'qq_11_1': 'qq_11_1',
};

String? _fingerprint(String? raw) {
  final name = (raw ?? '').trim().toLowerCase();
  if (name.isEmpty) return null;
  return _fingerprintAliases[name];
}

/// `alpn=http/1.1` or `alpn=h2,http/1.1` → `['http/1.1']` / `['h2','http/1.1']`.
///
/// An empty value yields no ALPN, which leaves the engine's default in place.
List<String> _alpnList(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return const [];
  return text
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
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
