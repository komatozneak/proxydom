import 'dart:convert';

/// Broker v3 commands are newline-delimited JSON between Flutter and the
/// native controller. The controller owns the framed Windows named pipe.
const int kTunnelProtocolVersion = 3;

/// Includes the no-route key probe, TUN readiness, and bound egress proof.
const Duration kWindowsConnectWait = Duration(seconds: 45);

/// Shown for any foreign full tunnel. The adapter name stays in the service log.
const String kWindowsForeignTunnelCaption = 'Обнаружен активный туннель';

/// The window's wait ended before the accepted generation published a result.
const String kWindowsConnectingTimeoutCaption =
    'Служба не завершила этап подключения';

/// Broker codes that replace the generic connection error on the home screen.
bool windowsBrokerOwnsCaption(String? code) {
  switch (code) {
    case 'foreign_tunnel':
    case 'key_probe_failed':
    case 'resolve_failed':
    case 'connecting_timeout':
    case 'route_failed':
    case 'core_start_failed':
    case 'core_exited':
    case 'tun_not_ready':
    case 'tun_init_timeout':
    case 'egress_failed':
    case 'egress_timeout':
    case 'auth_rejected':
    case 'invalid_profile':
    case 'cleanup_failed':
    case 'busy':
    case 'broker_unavailable':
    case 'windows_notice':
      return true;
    default:
      return false;
  }
}

/// Human line for a broker code. Unknown codes keep [fallback].
String windowsGateCaption(String? code, String? message, String fallback) {
  if (code == 'foreign_tunnel') return kWindowsForeignTunnelCaption;
  if (code == 'connecting_timeout') return kWindowsConnectingTimeoutCaption;
  if (code == 'core_exited' || code == 'core_start_failed') {
    return 'Сбой локальной службы туннеля';
  }
  if (code == 'tun_init_timeout') return 'Сбой сетевого адаптера туннеля';
  if (code == 'auth_rejected') return 'Ключ не принят сервером';
  if (code == 'invalid_profile') return 'Неверный порт сервера';
  if (code == 'egress_timeout') return 'Узел недоступен';
  if (code == 'resolve_failed') return 'Не удалось определить адрес сервера';
  if (code == 'route_failed') {
    final text = message?.trim() ?? '';
    if (text.isNotEmpty) return text;
    return 'Сбой сетевого стека';
  }
  if (windowsBrokerOwnsCaption(code)) {
    final text = message?.trim() ?? '';
    if (text.isNotEmpty) return text;
  }
  return fallback;
}

/// Restore is verified locally and never waits for an internet request.
const Duration kWindowsDisconnectWait = Duration(seconds: 15);

Map<String, Object?> tunnelHello() => const {
      'command': 'hello',
      'protocol_version': kTunnelProtocolVersion,
    };

Map<String, Object?> tunnelConnect({
  required String uri,
  required List<String> directDomains,
  List<String> forceProxyDomains = const [],
  bool udpDirect = false,
}) {
  return {
    'command': 'connect',
    'protocol_version': kTunnelProtocolVersion,
    'uri': uri,
    'direct_domains': [
      for (final domain in directDomains)
        if (tunnelDomainAllowed(domain)) domain,
    ],
    'force_proxy_domains': [
      for (final domain in forceProxyDomains)
        if (tunnelDomainAllowed(domain)) domain,
    ],
    'udp_direct': udpDirect ? 1 : 0,
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

/// Broker ack is the only signal that a generation exists.
bool windowsConnectBeginAllowed(TunnelStateEvent ack) {
  return ack.event == 'ack' &&
      ack.command == 'connect' &&
      ack.accepted == true &&
      ack.generation > 0;
}

/// A rejected payload must end the wait. It is not a missing broker.
bool tunnelEventIsClientReject(TunnelStateEvent event) {
  final code = event.code;
  return event.event == 'client_error' &&
      code != null &&
      code.isNotEmpty &&
      code != 'broker_unavailable';
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
