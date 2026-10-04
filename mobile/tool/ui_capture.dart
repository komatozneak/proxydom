// Scratch UI capture harness. Not part of CI: lives in tool/, not test/.
//
//   cd mobile && flutter test tool/ui_capture.dart
//
// Renders the real screens at phone size and at window size, and writes PNGs to
// ../.scratch/ui/, so a design pass can be judged from the actual pixels
// instead of from code. Fonts are loaded from the asset bundle — the default
// test font would draw boxes and hide every type decision.
//
// Known: the run exits non-zero with "A Timer is still pending" — the screens
// keep 1s timers alive through singletons that outlive the tree. The PNGs are
// written before that check, so the output is good; ignore the exit code.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/core/widgets/proxydom_ground.dart';
import 'package:proxydom/features/home/presentation/home_screen.dart';
import 'package:proxydom/features/settings/presentation/settings_screen.dart';
import 'package:proxydom/features/shell/presentation/main_shell.dart';
import 'package:proxydom/features/vpn/data/subscription_label.dart';
import 'package:proxydom/features/vpn/presentation/server_instrument.dart';
import 'package:proxydom/features/vpn/presentation/server_instrument_parts.dart';
import 'package:proxydom/l10n/app_localizations.dart';

/// Logical 360x780 at DPR 3 — the same framing as the owner's device captures.
const Size _phone = Size(360, 780);
const double _phoneDpr = 3;

/// A resized window, not a phone in a frame. DPR 2 keeps the text crisp.
const Size _desktop = Size(1120, 780);
const double _desktopDpr = 2;

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

/// Puts a bare screen body the way the shell does: on the night ground, and on
/// Windows inside the rail.
Widget _frame(
  Widget child,
  BuildContext context, {
  required bool desktop,
  double glow = 0.75,
}) {
  final state = GroundGlow()
    ..houseRadius = desktop ? 200 : 160
    ..houseCenter = const Alignment(0, -0.1);
  state.set(glow);
  // The screen publishes the house geometry into this scope; without it the
  // orbit would be drawn around a guess instead of around the house.
  Widget content = GroundGlowScope(
    notifier: state,
    child: Scaffold(
      backgroundColor: Colors.transparent,
      body: ProxydomGround(state: state, child: child),
    ),
  );
  if (!desktop) return content;
  return Scaffold(
    backgroundColor: Colors.transparent,
    body: Row(
      children: [
        WindowsNavRail(selected: MainShell.homeIndex, onSelect: (_) {}),
        Expanded(child: content),
      ],
    ),
  );
}

Widget _app(
  Widget child, {
  required Brightness brightness,
  required bool desktop,
}) {
  return ProviderScope(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('ru'),
      home: Builder(builder: (context) => _frame(child, context, desktop: desktop)),
    ),
  );
}

Future<void> _capture(
  WidgetTester tester,
  String name,
  Widget child, {
  required Brightness brightness,
  bool desktop = false,
}) async {
  final size = desktop ? _desktop : _phone;
  final dpr = desktop ? _desktopDpr : _phoneDpr;
  tester.view
    ..physicalSize = size * dpr
    ..devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  if (desktop) {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  } else {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  }

  final boundaryKey = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: _app(child, brightness: brightness, desktop: desktop),
    ),
  );
  // Two frames: the first settles the tree, the second paints animations that
  // started on the first. Settle() would hang on the breathing house animation.
  // A few more let asynchronously decoded row assets (the QS tile glyph) land
  // before the shutter — one pump renders them as an empty chip.
  await tester.pump();
  // Image decoding is real async work: without a runAsync round trip the marks
  // are still blank when the shutter opens. Precache every asset the screens
  // draw, then let the tree settle again.
  await tester.runAsync(() async {
    final context = tester.element(find.byType(Navigator).first);
    for (final asset in const [
      'assets/icon/logo_mark_nav.png',
      'assets/icon/logo_mark_nav_light.png',
      'assets/icon/ic_launcher_monochrome.png',
      'assets/icon/nav_vpn_proxydom.png',
    ]) {
      await precacheImage(AssetImage(asset), context);
    }
  });
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }

  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  // Image encoding is real async work: inside a widget test it only completes
  // under runAsync, otherwise the next pumpWidget deadlocks on the pending one.
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    _outDir.createSync(recursive: true);
    File('${_outDir.path}/$name.png')
        .writeAsBytesSync(data!.buffer.asUint8List());
  });

  // HomeScreen keeps a 1s uptime timer and the house never stops breathing.
  // Unmount or the fake clock drains forever and the test times out.
  await tester.pumpWidget(const SizedBox.shrink());
  debugDefaultTargetPlatformOverride = null;
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

  testWidgets('windows home', (tester) async {
    await _capture(tester, 'windows-home', const HomeScreen(),
        brightness: Brightness.dark, desktop: true);
  });

  testWidgets('windows settings', (tester) async {
    await _capture(tester, 'windows-settings', const SettingsScreen(),
        brightness: Brightness.dark, desktop: true);
  });

  // The Servers tab reads a profile document off the device and refreshes it over
  // the network on boot, so it cannot be driven from a widget test. The card
  // itself can: this is the instrument as a person sees it, fed sample facts.
  testWidgets('server instrument', (tester) async {
    const nodes = [
      PoolServerLabel(
        title: 'Москва',
        subtitle: 'eu1.proxydom.su:443',
        tile: PoolTile.flag,
        flag: '🇷🇺',
      ),
      PoolServerLabel(
        title: 'Нидерланды',
        subtitle: 'nl3.proxydom.su:443',
        tile: PoolTile.flag,
        flag: '🇳🇱',
      ),
      PoolServerLabel(
        title: 'Игровой',
        subtitle: 'низкий пинг',
        tile: PoolTile.gaming,
        flag: '',
      ),
    ];
    await _capture(
      tester,
      'server-instrument',
      Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ProfileInstrument(
                title: 'Теремок',
                description: 'Значок справа ведёт в бота',
                facts: ['2aq93K0', '15 ГБ из 100 ГБ', 'обновлено 04.10'],
                selected: true,
                selectedNodeTitle: 'Москва',
                onSelect: _ignore,
                onNodeTap: _ignoreIndex,
                telegramLabel: 'Telegram',
                onTelegram: _ignore,
                onRefresh: _ignore,
                onShare: _ignore,
                onDelete: _ignore,
                nodes: [
                  for (final node in nodes)
                    NodeLine(
                      label: node,
                      endpoint: node.subtitle,
                      selected: node.title == 'РњРѕСЃРєРІР°',
                      onTap: _ignore,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      brightness: Brightness.dark,
      desktop: true,
    );
  });
}

void _ignore() {}

void _ignoreIndex(int index) {}


