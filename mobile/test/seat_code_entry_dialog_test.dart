import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/theme.dart';
import 'package:teremok_connect/features/auth/data/seat_outcome.dart';
import 'package:teremok_connect/features/settings/presentation/seat_code_entry_dialog.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

Widget _app(Widget home) {
  return MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('ru'),
    localizationsDelegates: AppL10n.localizationsDelegates,
    supportedLocales: AppL10n.supportedLocales,
    home: home,
  );
}

void main() {
  testWidgets('SeatCodeEntryDialog submit returns trimmed code without TEC dispose',
      (tester) async {
    String? result;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  useRootNavigator: true,
                  builder: (_) => const SeatCodeEntryDialog(),
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

    await tester.enterText(find.byType(TextField), ' ab12cd ');
    await tester.tap(find.widgetWithText(FilledButton, 'Войти в группу'));
    await tester.pumpAndSettle();

    // Extra frames: IME/focus teardown must not trip disposed TEC.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(result, 'ab12cd');
  });

  testWidgets('SeatCodeEntryDialog cancel returns null without TEC dispose',
      (tester) async {
    var completed = false;
    String? result = 'sentinel';
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  useRootNavigator: true,
                  builder: (_) => const SeatCodeEntryDialog(),
                );
                completed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'XYZ');
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(completed, isTrue);
    expect(result, isNull);
  });

  test('parseApiDetail reads string and nested error', () {
    expect(parseApiDetail({'detail': 'Seat code not found'}), 'Seat code not found');
    expect(
      parseApiDetail({
        'detail': {
          'error': {
            'code': 'device_limit_reached',
            'message': 'Maximum 5 devices reached',
          },
        },
      }),
      'Maximum 5 devices reached',
    );
    expect(parseApiDetail(null), isNull);
  });

  test('detailLooksLikeOwnSeatCode', () {
    expect(
      detailLooksLikeOwnSeatCode(
        'Cannot accept your own seat code',
        errorCode: 'own_seat_code',
      ),
      isTrue,
    );
    expect(detailLooksLikeOwnSeatCode(null, errorCode: 'own_seat_code'), isTrue);
    expect(detailLooksLikeOwnSeatCode('Seat code not found'), isFalse);
  });

  test('parseApiErrorCode reads nested own_seat_code', () {
    expect(
      parseApiErrorCode({
        'detail': {
          'error': {'code': 'own_seat_code', 'message': 'Cannot accept your own seat code'},
        },
      }),
      'own_seat_code',
    );
  });
}
