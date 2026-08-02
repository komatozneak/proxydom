import 'package:flutter_test/flutter_test.dart';

import 'package:teremok_connect/features/vpn/data/device_envelope.dart';

void main() {
  test('DeviceEnvelope query includes device_id and optional fields', () {
    const env = DeviceEnvelope(
      deviceId: 'abcd-1234-efgh-5678',
      deviceName: 'Pixel',
      platform: 'android',
    );
    final q = env.toQueryParameters();
    expect(q['device_id'], 'abcd-1234-efgh-5678');
    expect(q['device_name'], 'Pixel');
    expect(q['platform'], 'android');
  });

  test('DeviceEnvelope omits empty optional fields', () {
    const env = DeviceEnvelope(deviceId: 'abcd-1234-efgh-5678');
    final q = env.toQueryParameters();
    expect(q.keys, ['device_id']);
  });
}
