import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/busy/busy_overlay.dart';
import 'package:proxydom/core/busy/busy_overlay_host.dart';
import 'package:proxydom/core/theme.dart';

Widget _hostApp() {
  return ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: Stack(
          children: [
            Center(child: Text('underlay')),
            BusyOverlayHost(),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('idle host stays mounted without BackdropFilter or spinner',
      (tester) async {
    await tester.pumpWidget(_hostApp());
    expect(find.byType(BusyOverlayHost), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('underlay'), findsOneWidget);
  });

  testWidgets('run shows working then success then idle without unmount',
      (tester) async {
    await tester.pumpWidget(_hostApp());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(BusyOverlayHost)),
    );

    final future = container.read(busyOverlayProvider.notifier).run(
          () async {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            return 42;
          },
          workingTitle: 'Меняем локацию…',
          workingBody: 'Подключаем выбранный сервер',
          successTitle: 'Готово',
          successHold: const Duration(milliseconds: 50),
        );

    await tester.pump();
    expect(find.text('Меняем локацию…'), findsOneWidget);
    expect(find.text('Подключаем выбранный сервер'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);

    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.text('Готово'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(); // post-frame idle
    await tester.pump(const Duration(milliseconds: 40));
    final value = await future;
    expect(value, 42);
    expect(container.read(busyOverlayProvider).phase, BusyPhase.idle);
    expect(find.byType(BusyOverlayHost), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('Готово'), findsNothing);
  });

  testWidgets('run failure shows fail title then idles and rethrows',
      (tester) async {
    await tester.pumpWidget(_hostApp());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(BusyOverlayHost)),
    );

    Object? caught;
    final future = () async {
      try {
        await container.read(busyOverlayProvider.notifier).run(
              () async {
                throw StateError('boom');
              },
              workingTitle: 'Working',
              failedTitle: 'Не удалось сменить локацию',
              failedHold: const Duration(milliseconds: 40),
            );
      } catch (e) {
        caught = e;
      }
    }();

    await tester.pump();
    await tester.pump();
    expect(find.text('Не удалось сменить локацию'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await future;
    expect(caught, isA<StateError>());
    expect(container.read(busyOverlayProvider).phase, BusyPhase.idle);
  });

  testWidgets('showDialog above host does not throw dependents assertion',
      (tester) async {
    await tester.pumpWidget(_hostApp());
    final ctx = tester.element(find.byType(BusyOverlayHost));
    showDialog<void>(
      context: ctx,
      useRootNavigator: true,
      builder: (dCtx) => AlertDialog(
        title: const Text('seat'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx, rootNavigator: true).pop(),
            child: const Text('ok'),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('seat'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('ok'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('seat'), findsNothing);
    expect(find.byType(BusyOverlayHost), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
