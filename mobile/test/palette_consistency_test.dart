import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/theme.dart';
import 'package:teremok_connect/features/auth/presentation/login_screen.dart';
import 'package:teremok_connect/features/auth/presentation/verify_screen.dart';
import 'package:teremok_connect/features/home/presentation/home_screen.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

const _screenSources = [
  'lib/features/auth/presentation/login_screen.dart',
  'lib/features/auth/presentation/verify_screen.dart',
  'lib/features/home/presentation/home_screen.dart',
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

  testWidgets('login screen builds under AppTheme.light', (tester) async {
    await tester.pumpWidget(_wrap(const LoginScreen()));
    await tester.pump();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
  });

  testWidgets('verify screen builds under AppTheme.dark', (tester) async {
    await tester.pumpWidget(
      _wrap(const VerifyScreen(phone: '+79991234567'), theme: AppTheme.dark),
    );
    await tester.pump();
    expect(find.byType(VerifyScreen), findsOneWidget);
  });

  testWidgets('home screen builds under AppTheme.light', (tester) async {
    await tester.pumpWidget(_wrap(const HomeScreen()));
    await tester.pump();
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
