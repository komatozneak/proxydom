import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proxydom/features/settings/presentation/settings_screen.dart';
import 'package:proxydom/l10n/app_localizations.dart';

Widget _settingsApp() {
  return const ProviderScope(
    child: MaterialApp(
      locale: Locale('ru'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: SettingsScreen(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Recovery after a drop is engine behaviour (Android VpnService, iOS Packet
  // Tunnel) or Windows service restart — never a user setting, so no platform
  // ships the row and a stored value from an older build must not bring it back.
  for (final platform in const [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
  ]) {
    testWidgets('${platform.name} Settings has no auto-reconnect row',
        (tester) async {
      SharedPreferences.setMockInitialValues({'auto_reconnect_enabled': true});
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.pumpWidget(_settingsApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Авто-переподключение'), findsNothing);
      expect(find.text('Быстрое переподключение при обрыве'), findsNothing);
      // The binding checks its invariants before tearDown, so reset here.
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
