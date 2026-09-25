import 'dart:convert';

import '../../../core/diagnostics/product_log.dart';
import 'share_link_parser.dart';

/// One connect attempt. [raw] credentials never enter the fields.
class ShareSessionLog {
  ShareSessionLog._();

  static int _seq = 0;

  static String nextSid() =>
      '${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}-${++_seq}';

  static void emit(
    String name, {
    required ProductLogLevel level,
    String? sid,
    Map<String, Object?> fields = const {},
    Map<String, Object?> extra = const {},
  }) {
    ProductLog.event(
      name,
      level: level,
      fields: {
        if (sid != null && sid.isNotEmpty) 'sid': sid,
        ...fields,
        ...extra,
      },
    );
  }

  /// Protocol facts safe to print. No password, URI, or key material.
  static Map<String, Object?> fieldsFor(ParsedShareLink link) {
    final endpoint = link.endpoint.split(':');
    final host = endpoint.first;
    final port = endpoint.length > 1 ? endpoint.last : '';
    final out = <String, Object?>{
      'scheme': link.scheme,
      'profile': link.name,
      'host': host,
      'port': port,
    };
    if (link.isHysteria2) {
      final profile = link.hy2!.profile;
      out['sni'] = profile.sni;
      out['insecure'] = profile.insecure;
      out['obfs'] = profile.obfs.isEmpty ? 'none' : profile.obfs;
      if (profile.obfsPassword.isNotEmpty) out['obfs_password'] = 'set';
      return out;
    }
    final q = _query(link.raw);
    if (link.scheme == 'vless' || link.scheme == 'trojan') {
      out['security'] = q['security'] ?? '';
      out['network'] = (q['type'] ?? q['net'] ?? 'tcp');
      out['sni'] = q['sni'] ?? '';
      if (q['security'] == 'reality') {
        out['fp'] = q['fp'] ?? '';
        out['pbk_len'] = (q['pbk'] ?? '').length;
        out['sid_len'] = (q['sid'] ?? '').length;
      }
      if (q['allowInsecure'] == '1' || q['insecure'] == '1') {
        out['allowInsecure'] = true;
      }
      final path = q['path'] ?? '';
      if (path.isNotEmpty) out['path'] = path;
      return out;
    }
    if (link.scheme == 'vmess') {
      final decoded = _vmess(link.raw);
      out['security'] = (decoded['tls'] ?? '').toString().isEmpty
          ? 'none'
          : decoded['tls'];
      out['network'] = (decoded['net'] ?? 'tcp').toString();
      return out;
    }
    if (link.scheme == 'ss') {
      out['method'] = _ssMethod(link.raw);
    }
    return out;
  }

  static Map<String, String> _query(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return const {};
    return uri.queryParameters;
  }

  static Map<String, Object?> _vmess(String raw) {
    final payload = raw.substring('vmess://'.length).split('#').first.trim();
    try {
      final normalized = payload.replaceAll('-', '+').replaceAll('_', '/');
      final pad = normalized.length % 4 == 0
          ? normalized
          : normalized.padRight(
              normalized.length + (4 - normalized.length % 4),
              '=',
            );
      final decoded = jsonDecode(utf8.decode(base64Decode(pad)));
      if (decoded is Map) {
        return {
          'tls': decoded['tls'] ?? '',
          'net': decoded['net'] ?? 'tcp',
        };
      }
    } on FormatException {
      return const {};
    }
    return const {};
  }

  static String _ssMethod(String raw) {
    final hash = raw.indexOf('#');
    final body = (hash < 0 ? raw : raw.substring(0, hash)).substring('ss://'.length);
    final user = body.split('@').first;
    try {
      final normalized = user.replaceAll('-', '+').replaceAll('_', '/');
      final pad = normalized.length % 4 == 0
          ? normalized
          : normalized.padRight(
              normalized.length + (4 - normalized.length % 4),
              '=',
            );
      final text = utf8.decode(base64Decode(pad));
      final colon = text.indexOf(':');
      if (colon > 0) return text.substring(0, colon);
    } on FormatException {
      return '';
    }
    return '';
  }
}
