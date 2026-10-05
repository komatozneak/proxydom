// The tabs share one gutter.
//
// They did not: the Servers heading reserved 44px for a leading button that no
// longer exists, Settings started at 20 and Home at 24. Switching tabs slid the
// page sideways under the eye. The numbers are measured, not eyeballed —
// getTopLeft on the heading's own Text.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/features/settings/presentation/settings_screen.dart';
import 'package:proxydom/features/vpn/presentation/locations_screen.dart';
import 'package:proxydom/l10n/app_localizations.dart';

const Size _phone = Size(360, 780);
const double _dpr = 3;
/// The size windows/runner/main.cpp opens the app at: a tab has to hold its
/// measure in the window the owner actually looks at.
const Size _window = Size(826, 591);
const double _windowDpr = 2;

/// Renders a tab and returns the left edge of the given text.
Future<double> _headingLeft(
  WidgetTester tester,
  Widget screen,
  String text, {
  TargetPlatform platform = TargetPlatform.android,
}) async {
  final wide = platform == TargetPlatform.windows;
  tester.view
    ..physicalSize = (wide ? _window : _phone) * (wide ? _windowDpr : _dpr)
    ..devicePixelRatio = wide ? _windowDpr : _dpr;
  addTearDown(tester.view.reset);
  // Reset inline, not in a tearDown: the binding asserts foundation debug vars
  // are unset before tearDowns run, so deferring it fails the test.
  debugDefaultTargetPlatformOverride = platform;
  try {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('ru'),
          home: screen,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final found = find.text(text);
    expect(found, findsWidgets, reason: 'the heading "$text" should be on screen');
    return tester.getRect(found.first).left;
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  test('the gutter is one value per size, not three', () {
    expect(AppBrand.pageGutter, 24);
    expect(AppBrand.pageGutterWide, 32);
    expect(AppBrand.pageGutterWide, greaterThan(AppBrand.pageGutter));
  });

  testWidgets('Сервера and Настройки headings start on the same line',
      (tester) async {
    // The servers heading used to sit 24px to the right of this one.
    final servers = await _headingLeft(tester, const LocationsScreen(), 'Сервера');
    expect(servers, AppBrand.pageGutter);

    final settings =
        await _headingLeft(tester, const SettingsScreen(), 'Настройки');
    expect(settings, AppBrand.pageGutter);
    expect(servers, settings);
  });

  testWidgets('in a window the Servers heading uses the wide gutter',
      (tester) async {
    // Only Servers is compared here. On a window Settings and Home are centred
    // measures (maxWidth 780 and 1080), so their headings sit in the middle of
    // the window on purpose and are not on any left gutter; the wide value is
    // the inner padding of that measure there.
    final servers = await _headingLeft(
      tester,
      const LocationsScreen(),
      'Сервера',
      platform: TargetPlatform.windows,
    );
    expect(servers, AppBrand.pageGutterWide);

    // The tab's VPN status poll retries up to five times with growing delays
    // (~3s). Fake time has to be advanced past it or the binding fails the test
    // for a pending timer, which has nothing to do with the gutter.
    await tester.pump(const Duration(seconds: 4));
  });
}
