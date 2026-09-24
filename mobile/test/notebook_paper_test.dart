import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/theme.dart';
import 'package:teremok_connect/core/widgets/notebook_paper.dart';

void main() {
  test('notebook sheet stays in the house family, not blue ink', () {
    expect(AppBrand.paperLight.r, greaterThan(AppBrand.paperLight.b));
    expect(AppBrand.paperDark.r, greaterThan(AppBrand.paperDark.b));
    expect(AppBrand.paperGrid.r, greaterThan(AppBrand.paperGrid.b));
    final lightSheet = AppBrand.paperLight.r +
        AppBrand.paperLight.g +
        AppBrand.paperLight.b;
    final lightGrid = AppBrand.paperGridLight.r +
        AppBrand.paperGridLight.g +
        AppBrand.paperGridLight.b;
    expect(lightGrid, lessThan(lightSheet));
    expect(AppBrand.paperMargin.r, greaterThan(AppBrand.paperMargin.g));
    expect(AppBrand.paperMargin.r, greaterThan(AppBrand.paperMargin.b));
  });

  testWidgets('notebook paper paints in both themes', (tester) async {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const NotebookPaper(child: SizedBox(width: 80, height: 80)),
        ),
      );
      expect(find.byType(NotebookPaper), findsOneWidget);
    }
  });
}
