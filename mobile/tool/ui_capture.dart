// Scratch UI capture harness. Not part of CI: lives in tool/, not test/.
//
//   cd mobile && flutter test tool/ui_capture.dart
//
// Renders the real screens at phone size and writes PNGs to ../.scratch/ui/,
// so a design pass can be judged from the actual pixels instead of from code.
// Fonts are loaded from the asset bundle — the default test font would draw
// boxes and hide every type decision.
//
// Known: the run exits non-zero with "A Timer is still pending" — the screens
// keep 1s timers alive through singletons that outlive the tree. The PNGs are
// written before that check, so the output is good; ignore the exit code.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/core/widgets/notebook_paper.dart';
import 'package:proxydom/features/home/presentation/home_screen.dart';
import 'package:proxydom/features/settings/presentation/settings_screen.dart';
import 'package:proxydom/l10n/app_localizations.dart';

/// Logical 360x780 at DPR 3 — the same framing as the owner's device captures.
const Size _logical = Size(360, 780);
const double _dpr = 3;

final _outDir = Directory('../.scratch/ui');

Future<void> _loadFonts() async {
  final manifest =
      json.decode(await rootBundle.loadString('FontManifest.json')) as List;
  final wanted = <String, List<String>>{};
  for (final entry in manifest) {
    final map = entry as Map<String, dynamic>;
    final family = map['family'] as String;
    final fonts = (map['fonts'] as List).cast<Map<String, dynamic>>();
    wanted.putIfAbsent(family, () => []).addAll(
          fonts.map((font) => font['asset'] as String),
        );
  }
  for (final family in wanted.keys) {
    final loader = FontLoader(family);
    for (final asset in wanted[family]!) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }
}

Widget _app(Widget child, {required Brightness brightness}) {
  return ProviderScope(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('ru'),
      // The screens are bare bodies — MainShell puts them on paper + grid.
      // Reproduce that here, otherwise the capture is a white void.
      home: Builder(
        builder: (context) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          return Scaffold(
            backgroundColor: dark ? AppBrand.paperDark : AppBrand.paperLight,
            body: NotebookPaper(child: child),
          );
        },
      ),
    ),
  );
}

Future<void> _capture(
  WidgetTester tester,
  String name,
  Widget child, {
  required Brightness brightness,
  Size size = _logical,
}) async {
  tester.view
    ..physicalSize = size * _dpr
    ..devicePixelRatio = _dpr;
  addTearDown(tester.view.reset);

  final boundaryKey = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: _app(child, brightness: brightness),
    ),
  );
  // Two frames: the first settles the tree, the second paints animations that
  // started on the first. Settle() would hang on the breathing house animation.
  // A few more let asynchronously decoded row assets (the QS tile glyph) land
  // before the shutter — one pump renders them as an empty chip.
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }

  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  // Image encoding is real async work: inside a widget test it only completes
  // under runAsync, otherwise the next pumpWidget deadlocks on the pending one.
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    _outDir.createSync(recursive: true);
    File('${_outDir.path}/$name.png')
        .writeAsBytesSync(data!.buffer.asUint8List());
  });

  // HomeScreen keeps a 1s uptime timer and the house never stops breathing.
  // Unmount or the fake clock drains forever and the test times out.
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  setUpAll(_loadFonts);

  setUp(() {
    // The screens talk to the native side on boot. Stub every channel so the
    // harness sees no MissingPluginException and stays quiet.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in [
      'proxydom/vpn',
      'proxydom/vpn/status',
      'proxydom/vpn/session',
      'proxydom/vpn/traffic',
      'proxydom/vpn/ping',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (call) async => null,
      );
    }
  });

  testWidgets('home dark', (tester) async {
    await _capture(tester, 'home-dark', const HomeScreen(),
        brightness: Brightness.dark);
  });

  testWidgets('home light', (tester) async {
    await _capture(tester, 'home-light', const HomeScreen(),
        brightness: Brightness.light);
  });

  testWidgets('settings dark', (tester) async {
    await _capture(tester, 'settings-dark', const SettingsScreen(),
        brightness: Brightness.dark);
  });

  testWidgets('settings light', (tester) async {
    await _capture(tester, 'settings-light', const SettingsScreen(),
        brightness: Brightness.light);
  });
}
