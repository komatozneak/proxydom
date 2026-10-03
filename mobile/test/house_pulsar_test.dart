import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/core/widgets/house_pulsar.dart';

void main() {
  test('flame is brighter than the roof so the house edge stays visible', () {
    expect(AppBrand.flame.r, greaterThan(AppBrand.livingHouse.r));
  });

  testWidgets('house pulsar breathes from the center', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HousePulsar(diameter: 120)),
    );
    expect(find.byType(HousePulsar), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
