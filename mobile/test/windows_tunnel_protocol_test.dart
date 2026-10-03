import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/vpn/data/windows_tunnel_protocol.dart';

void main() {
  test('controller contract is protocol v3 newline JSON', () {
    final hello = tunnelHello();
    expect(hello['protocol_version'], 3);
    expect(jsonEncode(hello).contains('\n'), isFalse);
  });

  test('connect carries one share line and hostnames only', () {
    final message = tunnelConnect(
      uri: 'hy2://secret@cdn.example:443',
      directDomains: ['lan.example', 'http://nope', '../x'],
    );
    expect(message['command'], 'connect');
    expect(message['protocol_version'], 3);
    expect(message.containsKey('outbounds'), isFalse);
    expect(message['direct_domains'], ['lan.example']);
  });

  test('connect carries the udp bypass and the force-proxy hosts', () {
    final message = tunnelConnect(
      uri: 'hy2://secret@cdn.example:443',
      directDomains: ['steamserver.net'],
      forceProxyDomains: ['youtube.com', 'bad host'],
      udpDirect: true,
    );
    expect(message['force_proxy_domains'], ['youtube.com']);
    expect(message['udp_direct'], 1);

    final off = tunnelConnect(
      uri: 'hy2://secret@cdn.example:443',
      directDomains: const [],
    );
    expect(off['force_proxy_domains'], isEmpty);
    expect(off['udp_direct'], 0);
  });

  test('state parser preserves authoritative broker fields', () {
    final event = TunnelStateEvent.parse(
      '{"event":"state","generation":4,"state":"connected",'
      '"message":null,"code":null,"cleanup_verified":false}',
    );
    expect(event?.generation, 4);
    expect(event?.state, 'connected');
    expect(event?.message, isNull);
    expect(event?.cleanupVerified, isFalse);
    expect(TunnelStateEvent.parse('not-json'), isNull);
  });

  test('idle without cleanup_verified is not restored', () {
    final missing = TunnelStateEvent.parse(
      '{"event":"state","generation":1,"state":"idle","message":null}',
    );
    expect(missing?.cleanupVerified, isNull);
    expect(tunnelEventIsDisconnectTerminal(missing!), isFalse);
    expect(tunnelCleanupSucceeded(missing), isFalse);

    final restored = TunnelStateEvent.parse(
      '{"event":"state","generation":1,"state":"idle","code":null,'
      '"message":null,"cleanup_verified":true}',
    );
    expect(tunnelCleanupSucceeded(restored!), isTrue);

    final failed = TunnelStateEvent.parse(
      '{"event":"state","generation":1,"state":"disconnecting",'
      '"code":"cleanup_failed","message":"Сеть не восстановлена",'
      '"cleanup_verified":false}',
    );
    expect(tunnelEventIsDisconnectTerminal(failed!), isTrue);
    expect(tunnelCleanupSucceeded(failed), isFalse);
  });

  test('tun_ready is not Connected and connect_begin needs an ack', () {
    final ready = TunnelStateEvent.parse(
      '{"event":"tun_ready","generation":4,"state":"connecting",'
      '"cleanup_verified":false}',
    )!;
    expect(tunnelEventIsConnectTerminal(ready, 4), isFalse);
    final ack = TunnelStateEvent.parse(
      '{"event":"ack","command":"connect","accepted":true,"generation":4,'
      '"code":null,"message":null}',
    )!;
    expect(windowsConnectBeginAllowed(ack), isTrue);
    final refused = TunnelStateEvent.parse(
      '{"event":"state","generation":0,"state":"idle",'
      '"code":"broker_unavailable","cleanup_verified":true}',
    )!;
    expect(windowsConnectBeginAllowed(refused), isFalse);
    final rejected = TunnelStateEvent.parse(
      '{"event":"client_error","generation":0,"state":"",'
      '"code":"direct_domains","message":"Команда подключения не передана",'
      '"cleanup_verified":true}',
    )!;
    expect(tunnelEventIsClientReject(rejected), isTrue);
    expect(tunnelEventIsConnectTerminal(rejected, 0), isFalse);
  });

  test('connect terminal must match accepted generation', () {
    final stale = TunnelStateEvent.parse(
      '{"event":"state","generation":2,"state":"connected",'
      '"cleanup_verified":false}',
    )!;
    final current = TunnelStateEvent.parse(
      '{"event":"state","generation":3,"state":"idle",'
      '"code":"foreign_tunnel","cleanup_verified":true}',
    )!;
    expect(tunnelEventIsConnectTerminal(stale, 3), isFalse);
    expect(tunnelEventIsConnectTerminal(current, 3), isTrue);
  });

  test('broker captions are not the generic connection error', () {
    const generic = 'Ошибка подключения';
    expect(
      windowsGateCaption(
        'foreign_tunnel',
        'Обнаружен сторонний туннель: Happ',
        generic,
      ),
      kWindowsForeignTunnelCaption,
    );
    expect(
      windowsGateCaption('foreign_tunnel', kWindowsForeignTunnelCaption, generic)
          .contains('Happ'),
      isFalse,
    );
    expect(
      windowsGateCaption('foreign_tunnel', kWindowsForeignTunnelCaption, generic)
          .contains('happ'),
      isFalse,
    );
    expect(
      windowsGateCaption(
        'key_probe_failed',
        'Ключ не принят сервером или узел недоступен',
        generic,
      ),
      'Ключ не принят сервером или узел недоступен',
    );
    expect(
      windowsGateCaption(
        'resolve_failed',
        'Не удалось определить адрес сервера',
        generic,
      ),
      'Не удалось определить адрес сервера',
    );
    expect(
      windowsGateCaption('connecting_timeout', '', generic),
      kWindowsConnectingTimeoutCaption,
    );
    expect(
      windowsGateCaption('core_exited', '', generic),
      'Сбой локальной службы туннеля',
    );
    expect(
      windowsGateCaption('tun_init_timeout', '', generic),
      'Сбой сетевого адаптера туннеля',
    );
    expect(
      windowsGateCaption('auth_rejected', 'таймаут', generic),
      'Ключ не принят сервером',
    );
    expect(
      windowsGateCaption('invalid_profile', '', generic),
      'Неверный порт сервера',
    );
    expect(
      windowsGateCaption('egress_timeout', '', generic),
      'Узел недоступен',
    );
    expect(
      windowsGateCaption(
        'egress_failed',
        'Не удалось подтвердить доступность узла. Попробуйте другой сервер',
        generic,
      ),
      'Не удалось подтвердить доступность узла. Попробуйте другой сервер',
    );
    expect(
      windowsGateCaption('route_failed', 'Сбой применения маршрутов', generic),
      'Сбой применения маршрутов',
    );
    expect(
      windowsGateCaption(
        'broker_unavailable',
        'Служба Прокси Дом недоступна. Переустановите приложение',
        generic,
      ),
      'Служба Прокси Дом недоступна. Переустановите приложение',
    );
    expect(windowsGateCaption('something_else', 'служба', generic), generic);
  });

  test('disconnect echoes the broker generation', () {
    expect(tunnelDisconnect(3)['generation'], 3);
    expect(tunnelDisconnect(3)['protocol_version'], 3);
    expect(kWindowsConnectWait, const Duration(seconds: 45));
  });
}
