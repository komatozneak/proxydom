import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/widgets/house_pulsar.dart';

void main() {
  testWidgets('house pulsar breathes from the center', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HousePulsar(diameter: 120)),
    );
    expect(find.byType(HousePulsar), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
