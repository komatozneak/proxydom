import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/vpn/data/vpn_controller.dart';

void main() {
  group('parsePingEventMs', () {
    test('parses plausible delayMs', () {
      expect(parsePingEventMs({'delayMs': 44}), 44);
      expect(parsePingEventMs({'delayMs': 30}), 30);
      expect(parsePingEventMs(245), 245);
    });

    test('null delayMs clears stale RTT', () {
      expect(parsePingEventMs({'delayMs': null}), isNull);
    });

    test('rejects out of range', () {
      expect(parsePingEventMs({'delayMs': 5}), isNull);
      expect(parsePingEventMs({'delayMs': 9000}), isNull);
    });
  });
}
