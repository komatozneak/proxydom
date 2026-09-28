import 'dart:convert';

/// Broker v3 commands are newline-delimited JSON between Flutter and the
/// native controller. The controller owns the framed Windows named pipe.
const int kTunnelProtocolVersion = 3;

/// Includes the no-route key probe, TUN readiness, and bound egress proof.
const Duration kWindowsConnectWait = Duration(seconds: 45);

/// Restore is verified locally and never waits for an internet request.
const Duration kWindowsDisconnectWait = Duration(seconds: 15);

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

  /// Local arrival order. The broker does not send it.
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
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return null;
    }
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
      accepted:
          decoded['accepted'] is bool ? decoded['accepted'] as bool : null,
      command: command is String ? command : null,
    );
  }
}

bool tunnelEventIsConnectTerminal(TunnelStateEvent event, int generation) {
  if (event.event != 'state' || event.generation != generation) return false;
  if (event.state == 'connected' || event.state == 'idle') return true;
  return event.state == 'disconnecting' && event.code == 'cleanup_failed';
}

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
