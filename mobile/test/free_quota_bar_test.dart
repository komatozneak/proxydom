import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/theme.dart';
import 'package:teremok_connect/core/utils/format_utils.dart';
import 'package:teremok_connect/features/home/data/free_quota_meter.dart';
import 'package:teremok_connect/features/home/presentation/widgets/free_quota_bar.dart';
import 'package:teremok_connect/features/settings/data/subscription_status.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

int _argb(Color c) {
  try {
    // ignore: avoid_dynamic_calls
    return (c as dynamic).toARGB32() as int;
  } catch (_) {
    // ignore: deprecated_member_use
    return c.value;
  }
}

double _rgbDistance(Color a, Color b) {
  int ch(Color c, int shift) => (_argb(c) >> shift) & 0xFF;
  final dr = ch(a, 16) - ch(b, 16);
  final dg = ch(a, 8) - ch(b, 8);
  final db = ch(a, 0) - ch(b, 0);
  return (dr * dr + dg * dg + db * db) / (255.0 * 255.0 * 3.0);
}

void main() {
  test('quota remaining fraction uses remaining/limit', () {
    const s = SubscriptionStatus(
      quotaBytesUsed: 1 << 30,
      quotaBytesLimit: 1 << 31,
      quotaBytesRemaining: 1 << 30,
    );
    expect(s.quotaRemainingFraction, closeTo(0.5, 0.001));
    expect(s.showsMeteredQuotaBar, isTrue);
  });

  test('premium / alpha hide the metered bar', () {
    expect(
      const SubscriptionStatus(
        quotaUnlimited: true,
        quotaBytesLimit: 100,
      ).showsMeteredQuotaBar,
      isFalse,
    );
    expect(
      const SubscriptionStatus(
        isAlpha: true,
        quotaBytesLimit: 100,
      ).showsMeteredQuotaBar,
      isFalse,
    );
  });

  test('exhausted at remaining 0', () {
    const s = SubscriptionStatus(
      quotaBytesUsed: 100,
      quotaBytesLimit: 100,
      quotaBytesRemaining: 0,
    );
    expect(s.quotaExhausted, isTrue);
    expect(s.quotaRemainingFraction, 0);
  });

  test('HP colour is green at full, mustard mid, red low, grey empty', () {
    expect(_argb(freeQuotaBarColor(1)), _argb(AppBrand.quotaHealthy));
    expect(_argb(freeQuotaBarColor(0.5)), _argb(AppBrand.quotaCaution));
    expect(_argb(freeQuotaBarColor(0)), _argb(AppBrand.quotaDepleted));
    expect(
        _argb(freeQuotaBarColor(0.01)), isNot(_argb(AppBrand.quotaDepleted)));
  });

  test('HP colour moves smoothly while draining 4.2 GiB (no hard steps)', () {
    Color? prev;
    for (var i = 100; i >= 1; i--) {
      final c = freeQuotaBarColor(i / 100);
      if (prev != null) {
        expect(
          _rgbDistance(prev, c),
          lessThan(0.02),
          reason: 'jump at remaining=${i / 100}',
        );
      }
      prev = c;
    }
  });

  test('formatGib uses comma in Russian', () {
    expect(formatGib(4.2, russian: true), '4,20');
    expect(formatGib(4.2, russian: false), '4.20');
  });

  testWidgets('exhausted bar shows Трафик закончился', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(
          body: FreeQuotaBar(
            remainingFraction: 0,
            title: 'Остаток трафика',
            amountLabel: '0,00 / 4,20 ГБ',
            exhaustedLabel: 'Трафик закончился',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Трафик закончился'), findsOneWidget);
    expect(find.text('Остаток трафика'), findsOneWidget);
  });
}
