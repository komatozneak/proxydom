import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/core/widgets/app_icon.dart';
import 'package:proxydom/core/widgets/location_flag_icon.dart';
import 'package:proxydom/l10n/app_localizations.dart';

void main() {
  test('locationFlagKey maps emoji and product tiles', () {
    expect(locationFlagKey('🇺🇸'), 'us');
    expect(locationFlagKey('🇱🇻'), 'lv');
    expect(locationFlagKey('🇮🇳'), 'in');
    expect(locationFlagKey('🇳🇱'), 'nl');
    expect(locationFlagKey('🇩🇪'), 'de');
    expect(locationFlagKey('🎮'), 'gaming');
    expect(locationFlagKey('👑'), 'youtube');
    expect(locationFlagKey('🌐'), 'lv');
  });

  testWidgets('LocationFlagIcon paints SVG, not emoji text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('ru'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: const Scaffold(
          body: LocationFlagIcon(flag: '🇺🇸', size: 48),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(LocationFlagIcon), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('🇺🇸'), findsNothing);
  });

  testWidgets('YouTube and gaming tiles are colored icons, not SVG',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('ru'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: const Scaffold(
          body: Row(
            children: [
              LocationFlagIcon(flag: 'youtube', size: 48),
              LocationFlagIcon(flag: 'gaming', size: 48),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(LocationFlagIcon), findsNWidgets(2));
    expect(find.byType(SvgPicture), findsNothing);
    expect(find.byType(AppIcon), findsNWidgets(2));
  });
}
