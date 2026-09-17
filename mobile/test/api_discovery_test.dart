import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/api_discovery.dart';

void main() {
  test('probeTimeout stays at 2s (LaunchScreen must not wait 8s)', () {
    expect(ApiDiscovery.probeTimeout, const Duration(seconds: 2));
  });
}
