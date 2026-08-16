import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/jwt_interceptor.dart';
import 'package:teremok_connect/features/auth/application/auth_provider.dart';
import 'package:teremok_connect/features/auth/application/auth_state.dart';

import 'helpers/secure_storage_mock.dart';

/// Skips the network register in build() so the logout decision is isolated.
class _UnauthedNotifier extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthStateUnauthenticated();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    mockSecureStorage();
  });

  test('logout path: unauthenticated(autoRegister: false) never re-registers',
      () async {
    final container = ProviderContainer(
      overrides: [authProvider.overrideWith(_UnauthedNotifier.new)],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.future);

    await container
        .read(authProvider.notifier)
        .unauthenticated(autoRegister: false);

    // A silent re-register would end in BootstrapFailed (no network in tests)
    // or Authenticated — never a clean Unauthenticated.
    expect(
      container.read(authProvider).valueOrNull,
      isA<AuthStateUnauthenticated>(),
    );
  });

  test('SessionExpiredGate exposes expiry and device-revoked hooks', () {
    expect(SessionExpiredGate.onExpired, isNull);
    expect(SessionExpiredGate.onDeviceRevoked, isNull);
    SessionExpiredGate.onExpired = () async {};
    SessionExpiredGate.onDeviceRevoked = () async {};
    expect(SessionExpiredGate.onExpired, isNotNull);
    expect(SessionExpiredGate.onDeviceRevoked, isNotNull);
    SessionExpiredGate.onExpired = null;
    SessionExpiredGate.onDeviceRevoked = null;
  });
}
