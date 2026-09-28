import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/data/windows_tunnel_protocol.dart';

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

  test('disconnect echoes the broker generation', () {
    expect(tunnelDisconnect(3)['generation'], 3);
    expect(tunnelDisconnect(3)['protocol_version'], 3);
    expect(kWindowsConnectWait, const Duration(seconds: 45));
  });
}
