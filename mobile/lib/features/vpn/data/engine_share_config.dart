import 'dart:convert';

import 'share_link_parser.dart';

/// Local SOCKS port for the share engines. Not Hy2's :10808.
///
/// The v2ray core and the REALITY engine use the same port: StartShare stops
/// one before it starts the other, so one number is all the path watch and the
/// TUN pump ever need.
const shareSocksPort = 10809;

/// JSON for `hy2bind.StartShare`. Returns null for Hysteria2 or a link we
/// cannot describe. Callers must not log the result: it contains secrets.
///
/// Two share cores exist behind this one entry point:
///
/// * REALITY + VLESS, carried by the permissive engine in
///   `hy2bind/share_reality.go`. The document names itself with
///   `"engine":"reality"`.
/// * the v2ray-core family, which is the document the loader in
///   `hy2bind_engine_load.go` reads.
///
/// "Cannot describe" means neither engine can start the line. The v2ray
/// loader is strict about transport and security (see [_engineTransports] and
/// [_engineSecurities]); the REALITY engine currently carries TCP only.
/// Returning null keeps the failure explicit instead of handing over a
/// document the loader will reject.
String? buildShareSocksConfig(ParsedShareLink link) {
  if (link.isHysteria2) return null;
  if (isRealityLink(link)) return buildRealityConfig(link);
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

/// Whether [link] is a VLESS line with the REALITY security layer.
///
/// `security=reality` is the written form; a bare `pbk` (the server's public
/// key) is what some generators emit instead, and either one means the same
/// handshake.
bool isRealityLink(ParsedShareLink link) {
  if (link.scheme != 'vless') return false;
  final q = Uri.tryParse(link.raw)?.queryParameters;
  if (q == null) return false;
  return (q['security'] ?? '').trim().toLowerCase() == 'reality' ||
      (q['pbk'] ?? '').trim().isNotEmpty;
}

/// JSON for the permissive REALITY + VLESS engine.
///
/// The engine keeps the link's UUID, public key, short id and SNI in memory and
/// never writes them to a log. It has no Xray-core dependency: the handshake is
/// the client half of the public REALITY protocol, carried over uTLS.
String? buildRealityConfig(ParsedShareLink link) {
  final uri = Uri.tryParse(link.raw);
  if (uri == null) return null;
  final host = uri.host.trim();
  if (host.isEmpty || uri.userInfo.isEmpty) return null;
  final q = uri.queryParameters;
  final publicKey = (q['pbk'] ?? '').trim();
  if (publicKey.isEmpty) return null;
  final network = (q['type'] ?? q['net'] ?? 'tcp').trim().toLowerCase();
  // TCP only (`raw` is Xray's newer name for it). WebSocket and gRPC put
  // another framing layer above this stream; until that layer exists the line
  // stays inactive instead of failing after the TLS handshake.
  if (network.isNotEmpty && network != 'tcp' && network != 'raw') return null;
  final uuid = Uri.decodeComponent(uri.userInfo);
  if (uuid.isEmpty) return null;
  // A server's short ids are whole bytes, at most eight of them. Anything else
  // matches no server, so the line is inactive rather than a certain failure.
  final sid = (q['sid'] ?? '').trim();
  if (sid.length.isOdd || sid.length > 16 || !_hex.hasMatch(sid)) return null;
  final sni = (q['sni'] ?? q['peer'] ?? host).trim();
  final flow = (q['flow'] ?? '').trim();
  // XTLS Vision adds a second framing layer above VLESS, and a Vision user is
  // refused without it. The engine carries plain VLESS only.
  if (flow.isNotEmpty && flow != 'none') return null;
  // `allowInsecure` is not forwarded: the certificate check is what proves the
  // peer holds the node's key, so the engine always performs it.
  return jsonEncode({
    'engine': 'reality',
    'server': host,
    'port': uri.hasPort ? uri.port : 443,
    'uuid': uuid,
    'public_key': publicKey,
    'short_id': sid,
    'sni': sni,
    'fingerprint': (q['fp'] ?? '').trim(),
    'network': 'tcp',
    // `Uri` decodes `%2F` in the query, so the list arrives as the wire
    // spelling the engine can use directly.
    'alpn': _alpnList(q['alpn']),
    'socks_listen': '127.0.0.1:$shareSocksPort',
  });
}

final _hex = RegExp(r'^[0-9a-fA-F]*$');

Map<String, Object?>? _outbound(ParsedShareLink link) {
  switch (link.scheme) {
    case 'vless':
      return _vless(link);
    case 'vmess':
      return _vmess(link);
    case 'trojan':
      return _trojan(link);
    case 'ss':
      return _shadowsocks(link);
    case 'socks5':
      return _socks(link);
    default:
      return null;
  }
}

/// SOCKS5 is a bare outbound: no transport, no TLS, no stream settings.
///
/// A credential is optional — a server that takes none is dialled with
/// `noauth`, and the engine has no third mode. The password can be empty even
/// when a user is present, which is why both fields are written from the same
/// split rather than from a "has auth" test.
Map<String, Object?>? _socks(ParsedShareLink link) {
  final uri = Uri.parse(link.raw);
  final host = uri.host.trim();
  if (host.isEmpty) return null;
  final port = uri.hasPort ? uri.port : 1080;
  final server = <String, Object?>{
    'address': host,
    'port': port,
  };
  if (uri.userInfo.isNotEmpty) {
    final userinfo = Uri.decodeComponent(uri.userInfo);
    final colon = userinfo.indexOf(':');
    server['users'] = [
      {
        'user': colon < 0 ? userinfo : userinfo.substring(0, colon),
        'pass': colon < 0 ? '' : userinfo.substring(colon + 1),
      },
    ];
  }
  return {
    'protocol': 'socks',
    'settings': {
      'servers': [server],
    },
  };
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
      // VMess spells the skip-verify switch inside its JSON blob, not in a
      // query: `allowInsecure` is a boolean there, and `verify_cert: false` is
      // the other name clients write. Without it a node whose own key says so
      // could never be dialled against a self-signed endpoint.
      if (decoded['allowInsecure'] == true ||
          decoded['allowInsecure'] == 1 ||
          decoded['allowInsecure'] == '1' ||
          decoded['verify_cert'] == false)
        'allowInsecure': '1',
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

/// Transports `shareStreamConfig` expresses in `hy2bind_engine_load.go`.
///
/// Everything else — `quic`, `splithttp`/`xhttp`, or a name this core does not
/// register — is refused, because the loader answers `unsupported transport`
/// and the start fails after the UI has already offered the line as active.
const _engineTransports = {
  'tcp',
  'ws',
  'websocket',
  'kcp',
  'grpc',
  'httpupgrade',
};

/// Securities `shareStreamConfig` expresses in `hy2bind_engine_load.go`.
///
/// A REALITY line never reaches this table: [buildShareSocksConfig] hands it to
/// the REALITY engine first. `xtls` has no engine at all.
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
    // `raw` is Xray's newer name for the plain TCP stream.
    '' || 'raw' => 'tcp',
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
    final fingerprint = (q['fp'] ?? '').trim().toLowerCase();
    stream['tlsSettings'] = {
      'serverName': sni,
      // The link's own word. The Go loader owns the one table that maps share
      // names (`chrome`) to uTLS presets (`chrome_auto`) and drops a name it
      // does not know, on every platform; a second copy here could only drift.
      if (fingerprint.isNotEmpty) 'fingerprint': fingerprint,
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
  // gRPC carries its own path as a service name, and the core will not guess
  // one: a line without `serviceName` is dialable only against a server that
  // listens on the empty service, so the link's own word is what travels.
  if (normalized == 'grpc') {
    stream['grpcSettings'] = {
      if ((q['serviceName'] ?? '').isNotEmpty) 'serviceName': q['serviceName'],
      if (q['mode'] == 'multi') 'multiMode': true,
    };
  }
  if (normalized == 'httpupgrade') {
    stream['httpupgradeSettings'] = {
      'path': (q['path'] ?? '/').isEmpty ? '/' : q['path'],
      if ((q['host'] ?? '').isNotEmpty) 'host': q['host'],
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
