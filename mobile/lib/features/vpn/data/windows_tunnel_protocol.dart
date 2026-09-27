import 'dart:convert';
import 'dart:typed_data';

/// Named-pipe frame from ADR 029. The body is at most 4096 bytes.
const int kTunnelFrameMaxBody = 4096;

Uint8List encodeTunnelFrame(Map<String, Object?> message) {
  final body = utf8.encode(jsonEncode(message));
  if (body.length > kTunnelFrameMaxBody) {
    throw const FormatException('frame');
  }
  final out = Uint8List(4 + body.length);
  final n = body.length;
  out[0] = n & 0xff;
  out[1] = (n >> 8) & 0xff;
  out[2] = (n >> 16) & 0xff;
  out[3] = (n >> 24) & 0xff;
  out.setRange(4, out.length, body);
  return out;
}

/// Pulls complete frames out of a byte stream.
class TunnelFrameBuffer {
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  void add(List<int> chunk) => _bytes.add(chunk);

  /// The next JSON body, or null when more bytes are required.
  ///
  /// Throws [FormatException] when the length prefix is over the limit.
  String? take() {
    final data = _bytes.toBytes();
    if (data.length < 4) return null;
    final n = data[0] | (data[1] << 8) | (data[2] << 16) | (data[3] << 24);
    if (n > kTunnelFrameMaxBody) {
      throw const FormatException('frame');
    }
    if (data.length < 4 + n) return null;
    final json = utf8.decode(data.sublist(4, 4 + n));
    _bytes.clear();
    if (data.length > 4 + n) {
      _bytes.add(data.sublist(4 + n));
    }
    return json;
  }
}

Map<String, Object?> tunnelHello() => const {
      'command': 'hello',
      'protocol_version': 1,
    };

Map<String, Object?> tunnelConnect({
  required String uri,
  required List<String> directDomains,
}) {
  return {
    'command': 'connect',
    'uri': uri,
    'direct_domains': [
      for (final domain in directDomains)
        if (tunnelDomainAllowed(domain)) domain,
    ],
  };
}

Map<String, Object?> tunnelDisconnect(int generation) => {
      'command': 'disconnect',
      'generation': generation,
    };

bool tunnelDomainAllowed(String host) {
  if (host.isEmpty || host.length > 253) return false;
  if (host.startsWith('.') || host.endsWith('.') || host.contains('..')) {
    return false;
  }
  return RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(host);
}

class TunnelStateEvent {
  const TunnelStateEvent({
    required this.generation,
    required this.state,
    this.message,
  });

  final int generation;
  final String state;
  final String? message;

  static TunnelStateEvent? parse(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return null;
    if (decoded['event'] != 'state') return null;
    final state = decoded['state'];
    if (state is! String) return null;
    final generation = decoded['generation'];
    final message = decoded['message'];
    return TunnelStateEvent(
      generation: generation is int ? generation : 0,
      state: state,
      message: message is String ? message : null,
    );
  }
}
