import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/auth/data/auth_api.dart';

void main() {
  test('DeviceListResult.fromJson parses slots and is_current', () {
    final result = DeviceListResult.fromJson({
      'active_count': 2,
      'max_devices': 5,
      'devices': [
        {
          'id': 1,
          'device_name': 'Pixel',
          'platform': 'android',
          'status': 'active',
          'created_at': '2026-01-01T00:00:00Z',
          'last_seen_at': '2026-08-10T09:00:00Z',
          'is_current': true,
          'seat_role': 'owner',
          'is_owner': true,
        },
        {
          'id': 2,
          'device_name': null,
          'platform': 'android',
          'status': 'active',
          'created_at': '2026-02-01T00:00:00Z',
          'is_current': false,
          'seat_role': 'member',
          'is_owner': false,
        },
      ],
    });

    expect(result.activeCount, 2);
    expect(result.maxDevices, 5);
    expect(result.devices, hasLength(2));
    expect(result.devices.first.isCurrent, isTrue);
    expect(result.devices.first.isOwner, isTrue);
    expect(result.devices.first.seatRole, 'owner');
    expect(result.devices.first.deviceName, 'Pixel');
    expect(result.devices.last.isCurrent, isFalse);
    expect(result.devices.last.isOwner, isFalse);
  });
}
