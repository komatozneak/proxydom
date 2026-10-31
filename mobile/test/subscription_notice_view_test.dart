import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/features/vpn/presentation/subscription_notice_view.dart';

void main() {
  testWidgets(
      'the description sits in a frame with the paper plane on the right',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SubscriptionNoticeView(
            text:
                'Для перехода в бота нажмите на значок правее\n🔑 sdc91quy Active',
            planeUrl: 'https://t.me/company_net_support',
            frame: true,
          ),
        ),
      ),
    );

    expect(find.textContaining('значок правее'), findsOneWidget);
    expect(find.textContaining('sdc91quy Active'), findsOneWidget);
    expect(find.byKey(kSubscriptionNoticeFrameKey), findsOneWidget);
    expect(find.byKey(kSubscriptionNoticePlaneKey), findsOneWidget);
    expect(find.byTooltip('Telegram'), findsOneWidget);

    final frame = tester.getRect(find.byKey(kSubscriptionNoticeFrameKey));
    final plane = tester.getRect(find.byKey(kSubscriptionNoticePlaneKey));
    expect(plane.left, greaterThan(frame.right - 8));
  });

  testWidgets(
      'without a frame the text has no border and a site link is not a plane',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SubscriptionNoticeView(
            text: 'Только текст',
            planeUrl: 'https://example.com/help',
            frame: false,
          ),
        ),
      ),
    );
    expect(find.byKey(kSubscriptionNoticeFrameKey), findsNothing);
    expect(find.byTooltip('Link'), findsOneWidget);
    expect(find.text('Только текст'), findsOneWidget);
  });

  testWidgets('the card can draw the plane itself, outside this frame',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SubscriptionNoticeView(
            text: 'Значок справа ведёт в бота',
            planeUrl: 'https://t.me/company_net_support',
            frame: true,
            showPlane: false,
          ),
        ),
      ),
    );
    expect(find.byKey(kSubscriptionNoticeFrameKey), findsOneWidget);
    expect(find.byKey(kSubscriptionNoticePlaneKey), findsNothing);
  });

  testWidgets('the plane, refresh, and trash sit above the description',
      (tester) async {
    const surface = Color(0xFFFFFFFF);
    final trash = catalogTrashFill(surface, dark: false);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: CatalogProfileChrome(
            title: const Text('CompanyNet'),
            share: const Icon(Icons.share),
            refresh: const Icon(Icons.refresh),
            plane: const Icon(Icons.send),
            trash: const Icon(Icons.delete),
            band: AppBrand.noticeBand,
            trashFill: trash,
            seamColor: AppBrand.lineLight,
            notice: const SubscriptionNoticeView(
              text: 'Значок справа ведёт в бота',
              planeUrl: null,
              frame: false,
              showPlane: false,
            ),
          ),
        ),
      ),
    );

    final share = tester.getRect(find.byKey(kCatalogShareSlotKey));
    final plane = tester.getRect(find.byKey(kCatalogPlaneSlotKey));
    final refresh = tester.getRect(find.byKey(kCatalogRefreshSlotKey));
    final trashBox = tester.getRect(find.byKey(kCatalogTrashFillKey));
    final notice = tester.getRect(find.text('Значок справа ведёт в бота'));

    expect(share.center.dy, closeTo(refresh.center.dy, 1));
    expect(share.right, lessThanOrEqualTo(refresh.left + 0.5));
    expect(plane.center.dx, closeTo(refresh.center.dx, 1));
    expect(plane.top, greaterThanOrEqualTo(refresh.bottom - 0.5));
    expect(refresh.right, lessThanOrEqualTo(trashBox.left + 0.5));
    expect(notice.top, greaterThanOrEqualTo(trashBox.bottom - 0.5));
    expect(notice.right, lessThanOrEqualTo(plane.left + 0.5));
    expect(find.byKey(kSubscriptionNoticeFrameKey), findsNothing);

    final band = tester.getRect(find.byKey(kCatalogRefreshBandKey));
    expect(band.bottom, closeTo(refresh.bottom, 1));
    expect(band.top, closeTo(refresh.top, 1));
    expect(
      tester.widget<ColoredBox>(find.byKey(kCatalogRefreshBandKey)).color,
      AppBrand.noticeBand,
    );
    expect(
      tester.widget<ColoredBox>(find.byKey(kCatalogTrashFillKey)).color,
      AppBrand.paperMargin,
    );
    expect(find.byIcon(Icons.share), findsOneWidget);
  });
}
