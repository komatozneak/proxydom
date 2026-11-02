// Scratch: HomeScreen in every tunnel state, for judging the mascot in place.
//
//   cd mobile && flutter test tool/home_states_capture.dart
//
// Writes to ../.scratch/pixel-house/home/.
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
import 'package:proxydom/features/home/application/home_stats_provider.dart';
import 'package:proxydom/features/home/application/vpn_provider.dart';
import 'package:proxydom/features/home/application/vpn_status.dart';
import 'package:proxydom/features/home/presentation/home_screen.dart';
import 'package:proxydom/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ScriptedVpn extends VpnNotifier {
  _ScriptedVpn(this._initial);

  final VpnStatus _initial;

  @override
  VpnStatus build() => _initial;

  @override
  Future<void> syncFromNative() async {}

  @override
  Future<void> reconcileWithNative() async {}
}

final Map<String, VpnStatus> _statuses = {
  'off': const VpnDisconnected(),
  'connecting': const VpnConnecting(progress: 0.4),
  'on': VpnConnected(
    serverName: 'США',
    protocol: 'hysteria2',
    connectedSince: DateTime(2026, 11, 2, 12),
  ),
  'error': const VpnError(message: 'probe failed', code: 'probe_failed'),
};

final _out = Directory('../.scratch/pixel-house/home');

Future<void> _shoot(
  WidgetTester tester,
  String name,
  VpnStatus status,
  Brightness brightness,
  bool desktop, {
  Size? size,
}) async {
  final shot = size ?? (desktop ? const Size(826, 591) : const Size(360, 780));
  final dpr = desktop ? 2.0 : 3.0;
  tester.view
    ..physicalSize = shot * dpr
    ..devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  debugDefaultTargetPlatformOverride =
      desktop ? TargetPlatform.windows : TargetPlatform.android;

  final boundaryKey = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: ProviderScope(
        overrides: [
          vpnProvider.overrideWith(() => _ScriptedVpn(status)),
          windowsPingSourceProvider.overrideWithValue(
            () => Stream<int?>.value(null),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
          locale: const Locale('ru'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: const NightBackdrop(child: HomeScreen()),
        ),
      ),
    ),
  );
  for (var i = 0; i < 180; i++) {
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
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  setUpAll(() async {
    final manifest =
        json.decode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest) {
      final map = entry as Map<String, dynamic>;
      final loader = FontLoader(map['family'] as String);
      for (final font in (map['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  setUp(() {
    // This harness lives in tool/, not test/, so the analyzer reads the mock
    // setter as a test-only member. Seeding the store is the point: Home has
    // to be photographed with a profile, not with an empty screen.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in [
      'proxydom/vpn',
      'proxydom/vpn/status',
      'proxydom/vpn/session',
      'proxydom/vpn/traffic',
      'proxydom/vpn/ping',
      'proxydom/window_chrome',
    ]) {
      messenger.setMockMethodCallHandler(
          MethodChannel(name), (call) async => null);
    }
  });

  for (final brightness in Brightness.values) {
    for (final desktop in [true, false]) {
      for (final entry in _statuses.entries) {
        testWidgets(
          '${entry.key}-${brightness.name}-${desktop ? 'win' : 'phone'}',
          (tester) async {
            await _shoot(
              tester,
              '${entry.key}-${brightness.name}-${desktop ? 'win' : 'phone'}',
              entry.value,
              brightness,
              desktop,
            );
          },
        );
      }
    }
  }

  // The smallest window the app allows: the house must not squeeze the readout
  // out of the frame.
  for (final brightness in Brightness.values) {
    testWidgets('on-${brightness.name}-win-min', (tester) async {
      await _shoot(
        tester,
        'on-${brightness.name}-win-min',
        _statuses['on']!,
        brightness,
        true,
        size: const Size(720, 520),
      );
    });
  }
}
