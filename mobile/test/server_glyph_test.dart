import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/core/widgets/app_icon.dart';
import 'package:proxydom/features/vpn/data/subscription_label.dart';
import 'package:proxydom/features/vpn/presentation/server_glyph.dart';

Widget _glyph(String flag) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: ServerGlyph(
        label: PoolServerLabel(
          title: 'DoDoVPN',
          subtitle: '',
          tile: PoolTile.flag,
          flag: flag,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a country is an SVG flag, not a globe', (tester) async {
    await tester.pumpWidget(_glyph('🇩🇪'));
    await tester.pump();

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byType(AppIcon), findsNothing);

    // The label may carry the ISO key instead of the emoji.
    await tester.pumpWidget(_glyph('nl'));
    await tester.pump();

    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('no country value keeps the globe', (tester) async {
    await tester.pumpWidget(_glyph(''));
    await tester.pump();

    expect(find.byType(SvgPicture), findsNothing);
    expect(find.byType(AppIcon), findsOneWidget);
  });
}
