import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/onboarding/presentation/onboarding_screen.dart';
import 'package:teremok_connect/l10n/app_localizations_en.dart';
import 'package:teremok_connect/l10n/app_localizations_ru.dart';

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
}
