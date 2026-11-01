import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  test('the word in the wing is cut as tall as DOM', () {
    // The word and DOM are one line of type: Onest's caps are 0.753 em, DOM
    // runs 97.62 units of a 279-unit drawing.
    const size = 40.0;
    const lockup = ProxyDomLockup(
      label: 'Прокси',
      ink: AppBrand.inkDark,
      size: size,
    );
    final capHeight = lockup.fittedWordSize * 0.753;
    expect(capHeight, closeTo(size * 97.62 / 279, 0.001));
  });

  testWidgets('the wing joins the house without reaching into the D', (
    tester,
  ) async {
    late LockupGeometry geo;
    const lockup = ProxyDomLockup(
      label: 'Прокси',
      ink: AppBrand.inkDark,
      size: 40,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            geo = lockup.geometry(context);
            return const SizedBox();
          },
        ),
      ),
    );

    // The house's left wall is at x 30 under the eave and the D starts at 36:
    // the wing has to end between them to make one silhouette and keep the D.
    expect(geo.wingRight, greaterThan(geo.house(30, 0).dx));
    expect(geo.wingRight, lessThan(geo.house(36, 0).dx));

    // The word sits inside the wing, clear of both its ends and its roof.
    expect(geo.wordRect.left, greaterThan(0));
    expect(geo.wordRect.right, lessThan(geo.wingRight));
    expect(geo.wordRect.top, greaterThanOrEqualTo(geo.wingTop));
    expect(geo.wordRect.bottom, lessThanOrEqualTo(40));
    // Same air at the wing's end as between the word and the D.
    expect(
      geo.wordRect.left,
      closeTo(geo.house(36, 0).dx - geo.wordRect.right, 0.001),
    );
  });

  testWidgets('the lockup is as wide as the wing and the house together', (
    tester,
  ) async {
    late LockupGeometry geo;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: Builder(
            builder: (context) {
              const lockup = ProxyDomLockup(
                label: 'Proxy',
                ink: AppBrand.inkDark,
                size: 40,
              );
              geo = lockup.geometry(context);
              return lockup;
            },
          ),
        ),
      ),
    );
    final box = tester.getSize(find.byType(ProxyDomLockup));
    expect(box.height, 40);
    expect(box.width, closeTo(geo.width, 0.001));
    expect(geo.width, closeTo(geo.houseLeft + 40 * ProxyDomMark.aspect, 0.001));
    // The word is set in capitals whatever the label's case.
    expect(geo.word, 'PROXY');
  });

  testWidgets('the word is a hole in the wing and the door is lit', (
    tester,
  ) async {
    const ground = AppBrand.groundDark;
    const ink = AppBrand.inkDark;
    const door = AppBrand.mascotGoldLit;
    const size = 120.0;
    final key = GlobalKey();
    late LockupGeometry geo;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: ground,
          body: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: ground,
                child: Builder(
                  builder: (context) {
                    const lockup = ProxyDomLockup(
                      label: 'Proxy',
                      ink: ink,
                      door: door,
                      size: size,
                    );
                    geo = lockup.geometry(context);
                    return lockup;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final pixels = await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData();
      return (image.width, data!);
    });
    final (width, data) = pixels!;
    Color at(Offset p) {
      final i = (p.dy.round() * width + p.dx.round()) * 4;
      return Color.fromARGB(
        data.getUint8(i + 3),
        data.getUint8(i),
        data.getUint8(i + 1),
        data.getUint8(i + 2),
      );
    }

    void expectColor(Offset p, Color want, String reason) {
      final got = at(p);
      expect(
        (got.r - want.r).abs() +
            (got.g - want.g).abs() +
            (got.b - want.b).abs(),
        lessThan(0.06),
        reason: '$reason at $p: got $got',
      );
    }

    final word = geo.wordRect;
    final band =
        geo.house(0, (ProxyDomLockup.domTop + ProxyDomLockup.domBottom) / 2).dy;
    // The wing before the word is solid.
    expectColor(Offset(word.left / 2, band), ink, 'the wing');
    // Inside the first letter the ground shows through: cut, not painted over.
    // (The test font draws Latin glyphs as solid boxes, so a box's middle
    // would be ink if the word were painted rather than cut.)
    expectColor(
      Offset(word.left + geo.style.fontSize! * 0.3, band),
      ground,
      'the word',
    );
    // Light in the doorway, under the O.
    expectColor(geo.house(148, 265), door, 'the door');
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
