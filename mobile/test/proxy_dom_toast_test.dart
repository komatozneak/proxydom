// An alert is drawn the way the platform it is on expects to be drawn.
//
// It was a Material SnackBar on every platform: a slab the full width of the
// page, hanging off the bottom edge, with a shadow. That is the phone's answer.
// A window has a corner, a pointer and a person who can see the whole page at
// once, so the same words belong in the corner on a narrow plate — and the
// corner plate has a way to be sent away.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/core/toasts/proxy_dom_toast.dart';
import 'package:proxydom/core/toasts/proxy_dom_toast_host.dart';
import 'package:proxydom/core/widgets/app_action_button.dart';

const _window = Size(1160, 820);
const _phone = Size(360, 780);
const _dpr = 3.0;

Finder get _plate => find.byKey(kProxyDomToastPlate);

Future<void> _pump(WidgetTester tester, {required bool desktop}) async {
  tester.view
    ..physicalSize = desktop ? _window : _phone * _dpr
    ..devicePixelRatio = desktop ? 1 : _dpr;
  addTearDown(tester.view.reset);
  debugDefaultTargetPlatformOverride =
      desktop ? TargetPlatform.windows : TargetPlatform.android;

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const ProxyDomToastHost(
        child: Scaffold(body: SizedBox.expand()),
      ),
    ),
  );
  await tester.pump();
}

/// Let the alert finish its life inside the test. A toast that outlives the
/// test is a pending timer, and a pending timer is a red suite.
Future<void> _letItGo(WidgetTester tester) async {
  await tester.pump(kProxyDomToastDuration);
  await tester.pump(const Duration(milliseconds: 250));
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  testWidgets('a window puts the alert in its corner', (tester) async {
    await _pump(tester, desktop: true);

    showProxyDomToast('Обновлено: 5', bottomInset: 76);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final plate = tester.getRect(_plate);
    // The corner, on its own measure: the same alert full width across a
    // 1160px window is the phone's slab with more of it, and it lies over the
    // keys of the page it is answering.
    expect(plate.width, lessThanOrEqualTo(kToastCornerWidth));
    expect(plate.right, closeTo(_window.width - kToastCornerInset, 1));
    // And above the bar the page reserved for itself.
    expect(_window.height - plate.bottom, closeTo(kToastCornerInset + 76, 2));
    await _letItGo(tester);
  });

  testWidgets('a phone puts the alert along its bottom edge', (tester) async {
    await _pump(tester, desktop: false);

    showProxyDomToast('Обновлено: 5');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final plate = tester.getRect(_plate);
    expect(plate.width, closeTo(_phone.width - 32, 1));
    expect(plate.left, closeTo(16, 1));
    await _letItGo(tester);
  });

  testWidgets('a window gives the alert a way out; a phone does not', (
    tester,
  ) async {
    await _pump(tester, desktop: true);
    showProxyDomToast('Обновлено: 5');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    // A pointer invites a way out of a thing that is only in the way.
    expect(find.byType(AppRingButton), findsOneWidget);
    await _letItGo(tester);

    await _pump(tester, desktop: false);
    showProxyDomToast('Обновлено: 5');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    // A thumb has no reason to close what it just asked for.
    expect(find.byType(AppRingButton), findsNothing);
    await _letItGo(tester);
  });

  testWidgets('the alert leaves on its own, and the next one replaces it', (
    tester,
  ) async {
    await _pump(tester, desktop: true);

    showProxyDomToast('Первое');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Первое'), findsOneWidget);

    // A second alert is the second alert, not a queue to read through.
    showProxyDomToast('Второе');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Первое'), findsNothing);
    expect(find.text('Второе'), findsOneWidget);

    await _letItGo(tester);
    expect(find.text('Второе'), findsNothing);
  });

  testWidgets('the alert belongs to the window, not to the page', (
    tester,
  ) async {
    // It wraps the navigator rather than living inside a screen, so it stays up
    // when the tab that raised it is gone.
    await _pump(tester, desktop: true);
    showProxyDomToast('Обновлено: 5');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(ProxyDomToasts.instance.current?.message, 'Обновлено: 5');
    expect(ProxyDomToasts.instance.current?.tone, ToastTone.info);
    await _letItGo(tester);
  });
}