import 'dart:convert';
import 'dart:typed_data';

/// Named-pipe frame from ADR 030. The body is at most 4096 bytes.
const int kTunnelFrameMaxBody = 4096;

/// The service rejects older commands. Idle is authoritative only in version 2.
const int kTunnelProtocolVersion = 2;

/// Rights the service DACL grants Authenticated Users.
///
/// `GENERIC_READ | GENERIC_WRITE` asks for attribute and EA rights the pipe
/// does not grant, so CreateFile fails and Connect never reaches the service.
const int kTunnelPipeAccess = 0x0001 | 0x0002 | 0x00020000 | 0x00100000;

/// Adapter wait plus the service probe. The probe itself is limited to 7s.
const Duration kWindowsConnectWait = Duration(seconds: 30);

/// Restore is local route and adapter cleanup, not another internet probe.
const Duration kWindowsDisconnectWait = Duration(seconds: 15);

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
      'protocol_version': kTunnelProtocolVersion,
    };

Map<String, Object?> tunnelConnect({
  required String uri,
  required List<String> directDomains,
}) {
  return {
    'command': 'connect',
    'protocol_version': kTunnelProtocolVersion,
    'uri': uri,
    'direct_domains': [
      for (final domain in directDomains)
        if (tunnelDomainAllowed(domain)) domain,
    ],
  };
}

Map<String, Object?> tunnelDisconnect(int generation) => {
      'command': 'disconnect',
      'protocol_version': kTunnelProtocolVersion,
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
    required this.event,
    required this.generation,
    required this.state,
    this.code,
    this.message,
    this.cleanupVerified,
    this.accepted,
    this.command,
    this.seq = 0,
  });

  final String event;
  final int generation;
  final String state;
  final String? code;
  final String? message;
  final bool? cleanupVerified;
  final bool? accepted;
  final String? command;

  /// Local arrival order. The service does not send it.
  final int seq;

  TunnelStateEvent withSeq(int value) {
    return TunnelStateEvent(
      event: event,
      generation: generation,
      state: state,
      code: code,
      message: message,
      cleanupVerified: cleanupVerified,
      accepted: accepted,
      command: command,
      seq: value,
    );
  }

  static TunnelStateEvent? parse(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return null;
    final event = decoded['event'];
    if (event is! String) return null;
    final generation = decoded['generation'];
    final state = decoded['state'];
    final message = decoded['message'];
    final code = decoded['code'];
    final command = decoded['command'];
    return TunnelStateEvent(
      event: event,
      generation: generation is int ? generation : 0,
      state: state is String ? state : '',
      code: code is String ? code : null,
      message: message is String ? message : null,
      cleanupVerified: decoded['cleanup_verified'] is bool
          ? decoded['cleanup_verified'] as bool
          : null,
      accepted: decoded['accepted'] is bool ? decoded['accepted'] as bool : null,
      command: command is String ? command : null,
    );
  }
}

/// A connect attempt is finished only by the service generation it accepted.
bool tunnelEventIsConnectTerminal(TunnelStateEvent event, int generation) {
  if (event.event != 'state' || event.generation != generation) return false;
  if (event.state == 'connected' || event.state == 'idle') return true;
  return event.state == 'disconnecting' && event.code == 'cleanup_failed';
}

/// Disconnect is finished by a verified idle or an explicit cleanup failure.
///
/// An idle event that omits [TunnelStateEvent.cleanupVerified] is not proof
/// that the machine routes were restored.
bool tunnelEventIsDisconnectTerminal(TunnelStateEvent event) {
  if (event.event != 'state') return false;
  if (event.state == 'idle' && event.cleanupVerified == true) return true;
  return event.code == 'cleanup_failed';
}

bool tunnelCleanupSucceeded(TunnelStateEvent event) {
  return event.event == 'state' &&
      event.state == 'idle' &&
      event.cleanupVerified == true;
}
