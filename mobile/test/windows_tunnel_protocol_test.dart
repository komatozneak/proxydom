import 'dart:convert';
import 'dart:typed_data';

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
    expect(message.containsKey('outbounds'), isFalse);
    expect(message['direct_domains'], ['lan.example']);
    final event = TunnelStateEvent.parse(
      '{"event":"state","generation":4,"state":"connected","message":null}',
    );
    expect(event?.generation, 4);
    expect(event?.state, 'connected');
    expect(event?.message, isNull);
  });

  test('disconnect echoes the service generation', () {
    expect(tunnelDisconnect(3)['generation'], 3);
  });
}
