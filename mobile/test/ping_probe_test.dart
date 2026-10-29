import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/utils/format_utils.dart';
import 'package:proxydom/features/vpn/data/windows_ping_probe_io.dart';

void main() {
  group('formatPingMs', () {
    test('renders a dash for missing or implausible values', () {
      expect(formatPingMs(null, russian: true), '—');
      expect(formatPingMs(0, russian: true), '—');
      expect(formatPingMs(-1, russian: true), '—');
      expect(formatPingMs(5001, russian: true), '—');
    });

    test('keeps fast nodes and thousands separated for both locales', () {
      expect(formatPingMs(1, russian: true), '1 мс');
      expect(formatPingMs(44, russian: true), '44 мс');
      expect(formatPingMs(44, russian: false), '44 ms');
      expect(formatPingMs(1240, russian: true), '1\u00A0240 мс');
      expect(formatPingMs(1240, russian: false), '1,240 ms');
    });
  });

  group('probeWindowsTunnelRtt', () {
    test('reads a 204 status line from a raw HTTP server', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      });
      try {
        final ms = await probeWindowsTunnelRtt(
          host: InternetAddress.loopbackIPv4.address,
          port: server.port,
        );
        expect(ms, isNotNull);
        expect(ms, greaterThanOrEqualTo(1));
      } finally {
        await server.close(force: true);
      }
    });

    test('rejects a captive-portal status', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = HttpStatus.found;
        await request.response.close();
      });
      try {
        final ms = await probeWindowsTunnelRtt(
          host: InternetAddress.loopbackIPv4.address,
          port: server.port,
        );
        expect(ms, isNull);
      } finally {
        await server.close(force: true);
      }
    });
  });

  group('windowsPingStream', () {
    test('publishes a successful sample immediately', () async {
      final value = await windowsPingStream(
        probe: () async => 42,
        interval: const Duration(milliseconds: 1),
      ).first;
      expect(value, 42);
    });

    test('holds the old value through one miss, then accepts a sample',
        () async {
      final samples = <int?>[null, 44];
      final value = await windowsPingStream(
        probe: () async => samples.removeAt(0),
        interval: const Duration(milliseconds: 1),
      ).first;
      expect(value, 44);
    });

    test('clears after two consecutive misses', () async {
      final value = await windowsPingStream(
        probe: () async => null,
        interval: const Duration(milliseconds: 1),
      ).first;
      expect(value, isNull);
    });
  });
}
