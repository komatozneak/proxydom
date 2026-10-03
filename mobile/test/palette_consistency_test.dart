import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/features/home/presentation/home_screen.dart';
import 'package:proxydom/l10n/app_localizations.dart';

const _screenSources = [
  'lib/features/home/presentation/home_screen.dart',
  'lib/features/settings/presentation/settings_screen.dart',
  'lib/features/vpn/presentation/hy2_import_screen.dart',
];

Widget _wrap(Widget child, {ThemeData? theme}) {
  return ProviderScope(
    child: MaterialApp(
      theme: theme ?? AppTheme.light,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('ru'),
      home: child,
    ),
  );
}

void main() {
  test('screen sources use theme tokens, no hardcoded Color(0xFF…)', () {
    for (final path in _screenSources) {
      final source = File(path).readAsStringSync();
      expect(
        source.contains(RegExp(r'Color\(0xFF')),
        isFalse,
        reason: '$path has hardcoded Color(0xFF…)',
      );
      expect(
        source.contains('Colors.teal'),
        isFalse,
        reason: '$path uses Colors.teal',
      );
      expect(
        source.contains('Colors.amber'),
        isFalse,
        reason: '$path uses Colors.amber',
      );
      expect(
        source.contains('Colors.red'),
        isFalse,
        reason: '$path uses Colors.red',
      );
      expect(
        source.contains('Colors.white'),
        isFalse,
        reason: '$path uses Colors.white',
      );
    }
  });

  testWidgets('home screen builds under AppTheme.light', (tester) async {
    await tester.pumpWidget(_wrap(const HomeScreen()));
    await tester.pump();
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
