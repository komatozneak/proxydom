import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/install_id_storage.dart';
import '../../auth/data/auth_api.dart';
import '../../session/application/session_projections.dart';
import '../../session/application/session_provider.dart';

/// Loads account device slots from the session snapshot when present.
final devicesListProvider =
    AsyncNotifierProvider<DevicesListNotifier, DeviceListResult>(
  DevicesListNotifier.new,
);

class DevicesListNotifier extends AsyncNotifier<DeviceListResult> {
  @override
  Future<DeviceListResult> build() async {
    final session = ref.watch(sessionProvider).valueOrNull;
    if (session != null) {
      return devicesFromSession(session);
    }
    return _fetch();
  }

  Future<DeviceListResult> _fetch() async {
    final id = await InstallIdStorage.instance.getOrCreate();
    return AuthApi().listDevices(deviceUuid: id);
  }

  Future<void> refresh() async {
    await ref.read(sessionProvider.notifier).refresh();
    final session = ref.read(sessionProvider).valueOrNull;
    if (session != null) {
      state = AsyncData(devicesFromSession(session));
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }
}
