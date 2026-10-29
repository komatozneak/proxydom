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
import 'package:proxydom/core/widgets/window_caption_bar.dart';
import 'package:proxydom/features/home/presentation/home_screen.dart';
import 'package:proxydom/features/settings/presentation/settings_screen.dart';
import 'package:proxydom/features/shell/presentation/main_shell.dart';
import 'package:proxydom/features/vpn/data/profile_manifest.dart';
import 'package:proxydom/features/vpn/data/subscription_label.dart';
import 'package:proxydom/features/vpn/data/subscription_traffic.dart';
import 'package:proxydom/features/vpn/presentation/locations_screen.dart';
import 'package:proxydom/features/vpn/presentation/server_instrument.dart';
import 'package:proxydom/features/vpn/presentation/server_instrument_parts.dart';
import 'package:proxydom/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Logical 360x780 at DPR 3 — the same framing as the owner's device captures.
const Size _phone = Size(360, 780);
const double _phoneDpr = 3;

/// A resized window, not a phone in a frame. DPR 2 keeps the text crisp.
/// 826x591 is the size windows/runner/main.cpp opens the app at — the captures
/// have to be shot at the frame the owner actually looks at.
const Size _desktop = Size(826, 591);
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
/// Windows inside the caption and the rail.
///
/// The ground goes behind the whole window, caption included — that is what
/// MainShell does, and without it the caption is shot on an empty white band
/// instead of on the night.
Widget _frame(
  Widget child,
  BuildContext context, {
  required bool desktop,
  required Brightness brightness,
  double glow = 0.75,
}) {
  final state = GroundGlow()
    ..houseRadius = desktop ? 200 : 160
    ..houseCenter = const Alignment(0, -0.1);
  state.set(glow);
  Widget page = Scaffold(backgroundColor: Colors.transparent, body: child);
  if (desktop) {
    page = Column(
      children: [
        WindowCaptionBar(
          label: 'Прокси',
          ink: brightness == Brightness.dark
              ? AppBrand.inkDark
              : AppBrand.inkLight,
        ),
        Expanded(
          child: Row(
            children: [
              WindowsNavRail(selected: MainShell.homeIndex, onSelect: (_) {}),
              Expanded(child: page),
            ],
          ),
        ),
      ],
    );
  }
  // The screen publishes the house geometry into this scope; without it the
  // orbit would be drawn around a guess instead of around the house.
  return GroundGlowScope(
    notifier: state,
    child: Scaffold(
      backgroundColor: Colors.transparent,
      body: ProxydomGround(state: state, child: page),
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
      home: Builder(
          builder: (context) => _frame(
                child,
                context,
                desktop: desktop,
                brightness: brightness,
              )),
    ),
  );
}

Future<void> _capture(
  WidgetTester tester,
  String name,
  Widget child, {
  required Brightness brightness,
  bool desktop = false,
  int settlePumps = 4,
  Size? size,
}) async {
  final shot = size ?? (desktop ? _desktop : _phone);
  final dpr = desktop ? _desktopDpr : _phoneDpr;
  tester.view
    ..physicalSize = shot * dpr
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
  for (var i = 0; i < settlePumps; i++) {
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
      // The window caption asks the runner whether the window is maximized and
      // where its buttons are. Without a stub it throws out of the build.
      'proxydom/window_chrome',
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

  // The caption is the one band of the window that is only ever seen at its own
  // size, so it is photographed on its own: the lockup is judged by how the
  // house sits against the top and bottom of the frame, and against the line of
  // the word beside it — neither of which a full-screen shot shows at a size
  // where the difference is visible.
  testWidgets('windows caption', (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('proxydom/window_chrome'),
      (call) async => null,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(
          const MethodChannel('proxydom/window_chrome'),
          null,
        ));
    await _capture(
      tester,
      'windows-caption',
      const Align(
        alignment: Alignment.topCenter,
        child: WindowCaptionBar(label: 'Прокси', ink: AppBrand.inkDark),
      ),
      brightness: Brightness.dark,
      desktop: true,
      size: const Size(1120, 40),
    );
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
                title: 'Мой профиль',
                description: 'Поддержка и обновления',
                facts: const [
                  (text: '15 ГБ из 100 ГБ', accent: true),
                ],
                parsedTraffic: const SubscriptionTraffic(
                  upload: 60 * 1000 * 1000 * 1000,
                  download: 25 * 1000 * 1000 * 1000,
                  total: 100 * 1000 * 1000 * 1000,
                ),
                manifestTraffic: const ProfileTraffic(
                  upload: 60 * 1000 * 1000 * 1000,
                  download: 25 * 1000 * 1000 * 1000,
                  total: 100 * 1000 * 1000 * 1000,
                ),
                planName: '100 GB',
                trafficUpdatedAt: DateTime.utc(2026, 10, 29, 9),
                updated: 'обновлено 29.10',
                selected: true,
                selectedNodeTitle: 'Москва',
                onNodeTap: _ignoreIndex,
                telegramLabel: 'Поддержка',
                onTelegram: _ignore,
                onRefresh: _ignore,
                onShare: _ignore,
                onDelete: _ignore,
                nodes: [
                  for (final node in nodes)
                    NodeLine(
                      label: node,
                      endpoint: node.subtitle,
                      selected: node.title == 'Москва',
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

  // The Servers tab itself. It reads its profiles out of the store on boot, so
  // it is seeded through the same key the app writes and then captured as the
  // real screen: this tab was the last one still built on its own numbers, and
  // a page is judged from pixels, not from a widget tree.
  //
  // Phone only. A window keeps its documents in a file under LOCALAPPDATA, so a
  // seeded store does not reach it — and a harness has no business writing into
  // the real app data of the machine it runs on. The window measure is covered
  // by page_gutter_test, which measures the heading against the shared gutter.
  testWidgets('servers light', (tester) async {
    _seedSavedProfile();
    await _capture(
      tester,
      'servers-light',
      const LocationsScreen(),
      brightness: Brightness.light,
      settlePumps: 10,
    );
  });

  testWidgets('servers dark', (tester) async {
    _seedSavedProfile();
    await _capture(
      tester,
      'servers-dark',
      const LocationsScreen(),
      brightness: Brightness.dark,
      settlePumps: 10,
    );
  });
}

/// One saved profile, in the store's own key and the app's own shape.
String _savedLine(String name) => 'hysteria2://pw@eu1.proxydom.su:443'
    '?sni=eu1.proxydom.su&insecure=1#$name';

void _seedSavedProfile() {
  // This harness lives in tool/, not test/, so the analyzer reads the mock
  // setter as a test-only member. Seeding the store is the whole reason the
  // Servers tab can be photographed here at all.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({
    'hy2_import_v1': jsonEncode({
      'catalogs': [
        {
          'id': 'profile',
          'title': 'Мой профиль',
          'url': 'https://panel.example.test/profile',
          'trafficMeta':
              'upload=5000000000; download=2500000000; total=20000000000',
          'lastUpdated': '2026-10-04T12:22:09Z',
          'announce': 'Поддержка и обновления',
          'supportUrl': 'https://t.me/example',
          'manifest': {
            'version': 1,
            'displayName': 'Мой профиль',
            'planName': '20 GB',
            'traffic': {
              'upload': 5000000000,
              'download': 2500000000,
              'total': 20000000000,
              'updatedAt': '2026-10-29T09:00:00Z',
            },
          },
          'lines': [
            _savedLine('YouTube · без рекламы'),
            _savedLine('Индия · дешёвые подписки'),
            _savedLine('Игровой · низкий пинг'),
            _savedLine('США · нейросети'),
          ],
        },
      ],
      'selected': 0,
    }),
  });
}

void _ignore() {}

void _ignoreIndex(int index) {}
