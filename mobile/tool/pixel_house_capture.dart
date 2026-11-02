// Scratch capture for the pixel-house hero. Not part of CI: lives in tool/.
//
//   cd mobile && flutter test tool/pixel_house_capture.dart
//
// Writes one PNG per state and theme to ../.scratch/pixel-house/frames/, plus
// a 1x strip at device scale so the cell grid can be judged without the
// screenshot being resampled.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/core/widgets/connect_button.dart';
import 'package:proxydom/core/widgets/pixel_house_hero.dart';
import 'package:proxydom/l10n/app_localizations.dart';

const List<TreeState> _states = [
  TreeState.disconnected,
  TreeState.connecting,
  TreeState.connected,
  TreeState.error,
];

const Map<TreeState, String> _names = {
  TreeState.disconnected: 'off',
  TreeState.connecting: 'connecting',
  TreeState.connected: 'on',
  TreeState.error: 'error',
};

final _out = Directory('../.scratch/pixel-house/frames');

Future<void> _shoot(
  WidgetTester tester,
  String name,
  TreeState state,
  Brightness brightness, {
  double scale = 1,
  double box = 300,
  bool reduced = false,
}) async {
  final boundaryKey = GlobalKey();
  final dpr = tester.view.devicePixelRatio;
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      locale: const Locale('ru'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(box * scale + 80, box * scale + 80),
          devicePixelRatio: dpr,
          disableAnimations: reduced,
        ),
        child: Scaffold(
          backgroundColor: brightness == Brightness.dark
              ? AppBrand.groundDark
              : AppBrand.paperLight,
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: PixelHouseHero(
                state: state,
                size: box * scale,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 220; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    _out.createSync(recursive: true);
    File('${_out.path}/$name.png').writeAsBytesSync(
      data!.buffer.asUint8List(),
    );
  });
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  for (final brightness in Brightness.values) {
    for (final state in _states) {
      testWidgets('${_names[state]}-${brightness.name}', (tester) async {
        tester.view
          ..physicalSize = const Size(760, 760)
          ..devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await _shoot(
          tester,
          '${_names[state]}-${brightness.name}',
          state,
          brightness,
        );
      });
    }
  }

  // 1:1 device pixels, no downscale in the preview: the cell edges are the point.
  testWidgets('on-crisp', (tester) async {
    tester.view
      ..physicalSize = const Size(760, 760)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _shoot(tester, 'on-1x', TreeState.connected, Brightness.light);
  });

  testWidgets('reduced-motion', (tester) async {
    tester.view
      ..physicalSize = const Size(760, 760)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await _shoot(
      tester,
      'on-reduced',
      TreeState.connected,
      Brightness.light,
      reduced: true,
    );
  });
}
