import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('free-client copy does not sell access or name the bot', () {
    const paths = [
      'lib/features/vpn/presentation/free_client_chrome.dart',
      'lib/features/onboarding/presentation/onboarding_screen.dart',
      'lib/l10n/app_ru.arb',
    ];
    final banned = ['Premium', 'Platega', 'тариф', 'бот Теремка'];
    for (final path in paths) {
      final text = File(path).readAsStringSync();
      if (path.endsWith('app_ru.arb')) {
        final start = text.indexOf('"freeAdd"');
        expect(start, greaterThan(0));
        final slice = text.substring(start);
        for (final word in banned) {
          expect(slice.contains(word), isFalse, reason: '$path has $word');
        }
        continue;
      }
      for (final word in banned) {
        expect(text.contains(word), isFalse, reason: '$path has $word');
      }
    }
  });
}
