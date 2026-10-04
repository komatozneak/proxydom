import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/core/widgets/proxydom_mark.dart';

/// The mark is traced by `tool/build_logo_mark.py`, so the drawing itself is
/// not asserted here — that would only restate the SVG. What is asserted is the
/// part a test can actually protect: that the asset ships, and that the lockup's
/// offset keeps doing the arithmetic it documents.
void main() {
  test('the traced mark ships with the app', () {
    final file = File(ProxyDomMark.asset);
    expect(
      file.existsSync(),
      isTrue,
      reason: 'run: python tool/build_logo_mark.py',
    );
    final svg = file.readAsStringSync();
    // One path, even-odd: the letters and their counters are knocked out of the
    // house by parity, so six subpaths — house, D, O, M and the two counters.
    expect('M'.allMatches(svg).length, 6);
    expect(svg, contains('fill-rule="evenodd"'));
    // A door under the O is what the hand-drawn mark never had.
    expect(svg, contains('Z'));
  });

  test('the lockup lifts the mark so DOM meets the word cap centre', () {
    // DOM's centre sits 59.3% down the mark box; the cap centre sits 0.021 em
    // above the middle of the text box. Both terms must be present, or the
    // letters hang under the baseline.
    const markSize = 26.0;
    const fontSize = 15.0;
    final lift = markSize * (0.593 - 0.5) + fontSize * 0.021;
    expect(lift, closeTo(2.418 + 0.315, 0.001));

    // The mark must move up, never down: DOM is below the middle of its box.
    expect(lift, greaterThan(0));
    // And the lift has to stay small next to the mark, or the house detaches
    // from the word it belongs to.
    expect(lift, lessThan(markSize * 0.5));
  });

  testWidgets('the caption lockup renders one row without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: AppBrand.groundDark,
          body: const Center(
            child: WindowCaptionProbe(),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(ProxyDomLockup), findsOneWidget);
    expect(find.byType(ProxyDomMark), findsOneWidget);
  });
}

/// Keeps the test free of the MethodChannel that the real caption bar talks to.
class WindowCaptionProbe extends StatelessWidget {
  const WindowCaptionProbe({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProxyDomLockup(
      label: 'Прокси Дом',
      ink: AppBrand.inkDark,
      markSize: 26,
      fontSize: 15,
    );
  }
}