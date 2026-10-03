import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('router only exposes the local utility', () {
    final src = File('lib/core/router.dart').readAsStringSync();
    final paths = RegExp(r"path: '([^']+)'")
        .allMatches(src)
        .map((m) => m.group(1)!)
        .toList();
    const allowed = {
      '/onboarding',
      '/import',
      '/scan',
      '/locations',
      '/home',
      '/settings',
      'logs',
      'no-vpn',
      // Redirects into the no-VPN screen. They do not open a catalog.
      'split-tunnel',
      'modes',
    };
    expect(paths.toSet().difference(allowed), isEmpty, reason: '$paths');
  });
}
