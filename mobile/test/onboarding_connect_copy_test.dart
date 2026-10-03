import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/onboarding/presentation/onboarding_screen.dart';
import 'package:proxydom/features/vpn/presentation/vpn_platform_copy.dart';
import 'package:proxydom/l10n/app_localizations_en.dart';
import 'package:proxydom/l10n/app_localizations_ru.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('iOS onboarding connect copy has no Android', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(onboardingConnectBodyForPlatform(AppL10nEn()), isNot(contains('Android')));
    expect(onboardingConnectBodyForPlatform(AppL10nRu()), isNot(contains('Android')));
    expect(onboardingConnectBodyForPlatform(AppL10nEn()), contains('iPhone'));
    expect(onboardingConnectBodyForPlatform(AppL10nRu()), contains('iPhone'));
  });

  test('Android onboarding connect copy keeps Android VPN permission', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(onboardingConnectBodyForPlatform(AppL10nEn()), contains('Android'));
    expect(onboardingConnectBodyForPlatform(AppL10nRu()), contains('Android'));
    expect(onboardingConnectBodyForPlatform(AppL10nEn()), isNot(contains('iPhone')));
  });

  test('iOS Home and gate copy has no Android', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    for (final s in [
      ...visibleVpnGuidanceCopy(AppL10nEn()),
      ...visibleVpnGuidanceCopy(AppL10nRu()),
    ]) {
      expect(s.toLowerCase(), isNot(contains('android')));
    }
  });
}
