import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/core/widgets/proxydom_mark.dart';

/// The mark is traced by `tool/build_logo_mark.py`, so the drawing itself is
/// not asserted here — that would only restate the SVG. What is asserted is the
/// part a test can actually protect: that the asset ships, that the constants the
/// lockup positions itself with still describe that file, and that the lockup
/// keeps doing the arithmetic it documents.
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

  test('the mark is sized by the viewBox it was traced into', () {
    // ProxyDomMark.aspect boxes the drawing by its height. If the tool ever
    // re-traces into a different viewBox, the mark is letterboxed and the lockup
    // no longer fills the band it was given, so this has to fail here rather
    // than in a screenshot.
    final svg = File(ProxyDomMark.asset).readAsStringSync();
    final viewBox = RegExp(r'viewBox="0 0 (\d+(?:\.\d+)?) (\d+(?:\.\d+)?)"')
        .firstMatch(svg);
    expect(viewBox, isNotNull, reason: 'the file must carry a viewBox');
    final width = double.parse(viewBox!.group(1)!);
    final height = double.parse(viewBox.group(2)!);
    expect(ProxyDomMark.aspect, closeTo(width / height, 0.0001));
  });

  test('the lockup fits the word to the letters inside the house', () {
    // The word is sized so its cap band and the DOM band are the same height:
    // DOM runs 97.62 units of a 279-unit drawing, Onest's caps are 0.753 em.
    const size = 40.0;
    const lockup = ProxyDomLockup(
      label: 'Прокси',
      ink: AppBrand.inkDark,
      size: size,
    );
    final capHeight = lockup.fittedWordSize * 0.753;
    const domHeight = size * 0.3499;
    expect(capHeight, closeTo(domHeight, 0.001));
    expect(capHeight, closeTo(14.0, 0.01));
  });

  test('the lockup drops the word onto DOM\'s line, not the other way round', () {
    const size = 40.0;
    const lockup = ProxyDomLockup(
      label: 'Прокси',
      ink: AppBrand.inkDark,
      size: size,
    );
    // DOM's centre is 9.33% of the house's height below the box middle; the
    // word's cap centre is 0.044 em above its own. The word moves down by both,
    // which is the only way the house can keep the full height of the band.
    final drop = size * (0.5933 - 0.5) + lockup.fittedWordSize * 0.044;
    expect(drop, closeTo(3.732 + 0.818, 0.002));
    expect(drop, greaterThan(0));

    // Where the two centres land once the word has dropped: the house's own DOM
    // centre. Anything else and the letters sit off the word's baseline.
    const wordBoxMiddle = size / 2;
    final capCentre = wordBoxMiddle + drop - lockup.fittedWordSize * 0.044;
    expect(capCentre, closeTo(size * 0.5933, 0.001));
  });

  test('the lockup keeps a word space, not a seam', () {
    const size = 40.0;
    const lockup = ProxyDomLockup(
      label: 'Прокси',
      ink: AppBrand.inkDark,
      size: size,
    );
    // The house's wall is where the word ends, so the gap has to read as space:
    // under 0.1 of the mark the last letter reads as touching the house.
    expect(lockup.gap, greaterThan(size * 0.1));
    expect(lockup.gap, lessThan(size * 0.2));
  });

  testWidgets('the caption lockup renders one row without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: AppBrand.groundDark,
          body: Center(
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

  testWidgets('the house fills the caption it is given', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: AppBrand.groundDark,
          body: Center(child: WindowCaptionProbe()),
        ),
      ),
    );
    await tester.pump();

    // A caption is a band, and the mark is asked to take all of it: the house
    // box and the mark box are the same height, with nothing letterboxed away.
    final mark = tester.getSize(
      find.descendant(
        of: find.byType(ProxyDomLockup),
        matching: find.byType(ProxyDomMark),
      ),
    );
    expect(mark.height, closeTo(40, 0.001));
    expect(mark.width, closeTo(40 * ProxyDomMark.aspect, 0.001));
  });
}

/// Keeps the test free of the MethodChannel that the real caption bar talks to.
class WindowCaptionProbe extends StatelessWidget {
  const WindowCaptionProbe({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProxyDomLockup(
      label: 'Прокси',
      ink: AppBrand.inkDark,
      size: 40,
    );
  }
}
