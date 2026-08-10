import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/install_id_storage.dart';
import '../../auth/data/auth_api.dart';

/// Loads account device slots (`GET /devices?device_id=`).
final devicesListProvider =
    AsyncNotifierProvider<DevicesListNotifier, DeviceListResult>(
  DevicesListNotifier.new,
);

class DevicesListNotifier extends AsyncNotifier<DeviceListResult> {
  @override
  Future<DeviceListResult> build() => _fetch();

  Future<DeviceListResult> _fetch() async {
    final id = await InstallIdStorage.instance.getOrCreate();
    return AuthApi().listDevices(deviceUuid: id);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }
}
