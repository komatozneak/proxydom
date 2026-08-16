// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/theme.dart';
import 'package:teremok_connect/features/auth/data/restore_device_choice.dart';
import 'package:teremok_connect/features/auth/presentation/restore_device_slot_dialog.dart';
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
  test('parses needs_device_slot devices from poll and 409 bodies', () {
    final fromPoll = RestoreDeviceChoice.listFromResponse({
      'status': 'needs_device_slot',
      'devices': [
        {'id': 7, 'name': 'Pixel 8', 'last_seen': null, 'is_owner': true},
      ],
    });
    expect(fromPoll.single.id, 7);
    expect(fromPoll.single.name, 'Pixel 8');
    expect(fromPoll.single.isOwner, isTrue);

    final from409 = RestoreDeviceChoice.listFromResponse({
      'detail': {
        'error': {'code': 'needs_device_slot'},
        'devices': [
          {'id': 3, 'name': 'Android', 'is_owner': false},
        ],
      },
    });
    expect(from409.single.id, 3);
    expect(from409.single.isOwner, isFalse);
  });

  testWidgets('picker lists device names and owner label', (tester) async {
    RestoreDeviceChoice? picked;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                picked = await RestoreDeviceSlotDialog.show(
                  context,
                  devices: const [
                    RestoreDeviceChoice(
                      id: 1,
                      name: 'Pixel 8',
                      isOwner: true,
                    ),
                    RestoreDeviceChoice(
                      id: 2,
                      name: 'Android',
                      isOwner: false,
                    ),
                  ],
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
    expect(find.text('Лимит устройств'), findsOneWidget);
    expect(find.text('Pixel 8'), findsOneWidget);
    expect(find.text('Владелец'), findsOneWidget);
    expect(find.text('Android'), findsOneWidget);

    await tester.tap(find.text('Android'));
    await tester.pumpAndSettle();
    expect(picked?.id, 2);
  });
}
