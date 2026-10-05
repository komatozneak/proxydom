// The home head: the node is the large centred reading, and the state sits
// on the traffic label at the left instead of floating in the middle.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/features/vpn/data/subscription_label.dart';
import 'package:proxydom/core/widgets/app_icon.dart';
import 'package:proxydom/features/vpn/presentation/free_client_chrome.dart';
import 'package:proxydom/features/vpn/presentation/server_glyph.dart';
import 'package:proxydom/l10n/app_localizations.dart';

void main() {
  testWidgets('the mark is doubled and the status sits on the traffic label',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    tester.view
      ..physicalSize = const Size(800, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('ru'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: const Scaffold(
          body: ConnectionTerminal(
            status: 'Не подключено',
            serverName: 'Игровой',
            serverSubtitle: 'низкий пинг',
            tile: PoolTile.gaming,
            accent: AppBrand.inkMutedDark,
            trafficLabel: '22 ГБ',
            uptime: '00:01:02',
          ),
        ),
      ),
    );
    await tester.pump();

    final name = tester.widget<Text>(find.text('ИГРОВОЙ'));
    expect(name.style?.fontSize, 42);
    expect(name.maxLines, 1);
    expect(
      tester.widget<ServerGlyph>(find.byType(ServerGlyph)).size,
      76,
    );
    expect(tester.widget<AppIcon>(find.byType(AppIcon)).size, 36);

    final nameBox = tester.getRect(find.text('ИГРОВОЙ'));
    final note = tester.getRect(find.text('низкий пинг'));
    final status = tester.getRect(find.text('НЕ ПОДКЛЮЧЕНО'));
    final traffic = tester.getRect(find.text('ТРАФИК'));
    final clock = tester.getRect(find.text('00:01:02'));
    final head = tester.getRect(find.byType(ConnectionTerminal));

    expect(note.top, greaterThan(nameBox.bottom - 1));
    expect(note.center.dx, closeTo(head.center.dx, 8));
    // The lamp leads the word, so the word starts just right of «ТРАФИК».
    expect(status.left - traffic.left, inInclusiveRange(0, 28));
    expect(status.bottom, lessThan(traffic.top));
    expect(traffic.top - status.bottom, lessThan(24));
    expect(clock.left, greaterThan(status.right));
    expect(clock.center.dx, greaterThan(head.center.dx));

    debugDefaultTargetPlatformOverride = null;
  });
}
