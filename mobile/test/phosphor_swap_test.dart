import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/core/widgets/app_icon.dart';

void main() {
  testWidgets('AppIcon uses Phosphor static icons under AppTheme',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: AppIcon(AppIcons.shield, size: 32),
        ),
      ),
    );
    expect(find.byType(AppIcon), findsOneWidget);
  });

  test('AppIcons expose static IconData (tree-shake friendly)', () {
    expect(AppIcons.shield, isA<IconData>());
    expect(AppIcons.power, isA<IconData>());
    expect(AppIcons.servers, isA<IconData>());
  });
}
