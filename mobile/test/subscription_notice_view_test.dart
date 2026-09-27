import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/theme.dart';
import 'package:teremok_connect/features/vpn/presentation/subscription_notice_view.dart';

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
            planeUrl: 'https://t.me/vpn_teremok_bot',
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
            planeUrl: 'https://t.me/vpn_teremok_bot',
            frame: true,
            showPlane: false,
          ),
        ),
      ),
    );
    expect(find.byKey(kSubscriptionNoticeFrameKey), findsOneWidget);
    expect(find.byKey(kSubscriptionNoticePlaneKey), findsNothing);
  });

  testWidgets('refresh and the Telegram plane share the sky band',
      (tester) async {
    const surface = Color(0xFFFFFFFF);
    final trash = catalogTrashFill(surface, dark: false);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: CatalogProfileChrome(
            title: const Text('Teremok'),
            share: const Icon(Icons.share),
            refresh: const Icon(Icons.refresh),
            plane: const Icon(Icons.send),
            trash: const Icon(Icons.delete),
            band: AppBrand.noticeBand,
            trashFill: trash,
            seamColor: AppBrand.lineLight,
            notice: const Text('Значок справа ведёт в бота'),
          ),
        ),
      ),
    );

    final refresh = tester.getRect(find.byKey(kCatalogRefreshSlotKey));
    final plane = tester.getRect(find.byKey(kCatalogPlaneSlotKey));
    expect(plane.top, closeTo(refresh.bottom, 0.5));
    expect(plane.left, closeTo(refresh.left, 0.5));
    expect(plane.width, refresh.width);

    final stamp = tester.getRect(find.byKey(kCatalogRefreshBandKey));
    expect(stamp.bottom, greaterThan(plane.bottom + 4));
    expect(stamp.left, closeTo(plane.left, 0.5));
    expect(stamp.right, closeTo(plane.right, 0.5));
    expect(
      tester.widget<CatalogStampBand>(find.byKey(kCatalogRefreshBandKey)).color,
      AppBrand.noticeBand,
    );
    expect(
      CatalogStampBand.dropFor(catalogActionExtent),
      closeTo(
        (catalogActionExtent - 1) / (catalogStampDiamonds + 1),
        0.01,
      ),
    );
    expect(
      tester.widget<ColoredBox>(find.byKey(kCatalogTrashFillKey)).color,
      trash,
    );
    expect(
      find.ancestor(
        of: find.byIcon(Icons.share),
        matching: find.byKey(kCatalogRefreshBandKey),
      ),
      findsNothing,
    );
    expect(trash.r, greaterThan(trash.g));
    expect(trash.g, greaterThan(trash.b));
    expect(trash.r, greaterThan(AppBrand.paperMargin.r));
  });
}
