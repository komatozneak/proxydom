import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:teremok_connect/core/theme.dart';
import 'package:teremok_connect/features/settings/presentation/seat_invite_code_dialog.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

Widget _app(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('ru'),
    localizationsDelegates: AppL10n.localizationsDelegates,
    supportedLocales: AppL10n.supportedLocales,
    home: child,
  );
}

void main() {
  testWidgets('SeatInviteCodeDialog renders code, QR and buttons', (tester) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => const SeatInviteCodeDialog(code: 'AB12CD'),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('AB1-2CD'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Скопировать'), findsOneWidget);
    expect(find.text('Отмена'), findsOneWidget);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(find.byType(SeatInviteCodeDialog), findsNothing);
  });
}
