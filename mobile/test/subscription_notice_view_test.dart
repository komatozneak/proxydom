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
}
