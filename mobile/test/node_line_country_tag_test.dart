import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/features/vpn/data/share_link_parser.dart';
import 'package:proxydom/features/vpn/data/subscription_label.dart';
import 'package:proxydom/features/vpn/presentation/server_instrument_parts.dart';

void main() {
  testWidgets('a line tagged DE shows the flag, not the code', (tester) async {
    final link = parseShareLink(
      'hysteria2://user:pass@31.59.193.35:443/?sni=example.test'
      '#${Uri.encodeComponent('DE DoDoVPN | Hysteria')}',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: NodeLine(
            label: labelForShareLink(link),
            endpoint: link.endpoint,
            selected: false,
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('DE DoDoVPN | Hysteria'), findsNothing);
    expect(find.text('DoDoVPN | Hysteria'), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
  });
}
