import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/data/windows_tunnel_protocol.dart';

void main() {
  test('frame round trip stays under the service limit', () {
    final hello = tunnelHello();
    final bytes = encodeTunnelFrame(hello);
    final buffer = TunnelFrameBuffer()..add(bytes)..add(bytes);
    expect(buffer.take(), jsonEncode(hello));
    expect(buffer.take(), jsonEncode(hello));
    expect(buffer.take(), isNull);
  });

  test('oversize frame is refused', () {
    expect(
      () => encodeTunnelFrame({'command': 'connect', 'uri': 'x' * 5000}),
      throwsFormatException,
    );
    final buffer = TunnelFrameBuffer()
      ..add([0x01, 0x10, 0x00, 0x00]);
    expect(buffer.take, throwsFormatException);
  });

  test('connect carries one line and hostnames only', () {
    final message = tunnelConnect(
      uri: 'hy2://secret@cdn.example:443',
      directDomains: ['lan.example', 'http://nope', '../x'],
    );
    expect(message['command'], 'connect');
    expect(message['protocol_version'], 2);
    expect(message.containsKey('outbounds'), isFalse);
    expect(message['direct_domains'], ['lan.example']);
    final event = TunnelStateEvent.parse(
      '{"event":"state","generation":4,"state":"connected","message":null,"code":null,"cleanup_verified":false}',
    );
    expect(event?.generation, 4);
    expect(event?.state, 'connected');
    expect(event?.message, isNull);
    expect(event?.cleanupVerified, isFalse);
  });

  test('idle without cleanup_verified is not a restored network', () {
    final missing = TunnelStateEvent.parse(
      '{"event":"state","generation":1,"state":"idle","message":null}',
    );
    expect(missing?.cleanupVerified, isNull);
    expect(tunnelEventIsDisconnectTerminal(missing!), isFalse);
    expect(tunnelCleanupSucceeded(missing), isFalse);
    final restored = TunnelStateEvent.parse(
      '{"event":"state","generation":1,"state":"idle","code":null,"message":null,"cleanup_verified":true}',
    );
    expect(tunnelCleanupSucceeded(restored!), isTrue);
    final failed = TunnelStateEvent.parse(
      '{"event":"state","generation":1,"state":"disconnecting","code":"cleanup_failed","message":"Сеть не восстановлена","cleanup_verified":false}',
    );
    expect(tunnelEventIsDisconnectTerminal(failed!), isTrue);
    expect(tunnelCleanupSucceeded(failed), isFalse);
  });

  test('disconnect echoes the service generation', () {
    expect(tunnelDisconnect(3)['generation'], 3);
    expect(tunnelDisconnect(3)['protocol_version'], 2);
  });

  test('pipe access matches the service DACL', () {
    expect(kTunnelPipeAccess, 0x00120003);
    expect(kTunnelPipeAccess & 0x80000000, 0);
    expect(kWindowsConnectWait, const Duration(seconds: 30));
  });
}
