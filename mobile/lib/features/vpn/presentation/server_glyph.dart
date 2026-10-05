import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../data/subscription_label.dart';

/// The mark in front of every node.
///
/// It was an emoji on a flat square: the platform draws the flag, or a tofu
/// box where the platform has no emoji font, and the square behind it is a
/// colour swatch with no shape. The repo already ships country flags as SVG
/// (`assets/flags/*.svg`), so those are what a country node gets — the same
/// mark on every device, drawn by us. Emoji stays only as the fallback for a
/// label the app has no flag for.
class ServerGlyph extends StatelessWidget {
  const ServerGlyph({super.key, required this.label, this.size = 34});

  final PoolServerLabel label;
  final double size;

  /// Regional indicator pairs to an ISO-3166 code: 🇷🇺 is U+1F1F7 U+1F1FA,
  /// which is 26 letters each. Anything else is not a flag.
  static String? isoFromFlag(String flag) {
    if (flag.runes.length != 2) return null;
    final runes = flag.runes.toList();
    const base = 0x1F1E6;
    if (runes[0] < base || runes[0] > base + 25) return null;
    if (runes[1] < base || runes[1] > base + 25) return null;
    return '${String.fromCharCode(runes[0] - base + 97)}'
        '${String.fromCharCode(runes[1] - base + 97)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    switch (label.tile) {
      case PoolTile.youtube:
        // The one tile that is allowed to shout: YouTube is the reason a lot
        // of these profiles exist.
        return _Tile(
          size: size,
          fill: AppBrand.youtubePlay,
          radius: size * 0.28,
          child: AppIcon(
            AppIcons.play,
            size: _glyph(size, 15),
            color: AppBrand.mascotCream,
          ),
        );
      case PoolTile.gaming:
        return _Tile(
          size: size,
          fill: AppBrand.moss.withValues(alpha: 0.9),
          radius: size * 0.28,
          child: AppIcon(
            AppIcons.gamepad,
            size: _glyph(size, 18),
            color: AppBrand.mascotCream,
          ),
        );
      case PoolTile.flag:
        final iso = isoFromFlag(label.flag);
        if (iso == null) {
          return _Tile(
            size: size,
            fill: theme.colorScheme.onSurface.withValues(alpha: 0.07),
            radius: size * 0.28,
            child: AppIcon(
              AppIcons.globe,
              size: _glyph(size, 17),
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          );
        }
        // A flag on a dark night needs an edge, or it dissolves into the card.
        return Container(
          width: size,
          height: size * 0.72,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.18),
            ),
          ),
          child: SvgPicture.asset(
            'assets/flags/$iso.svg',
            fit: BoxFit.cover,
            placeholderBuilder: (_) => const SizedBox.shrink(),
          ),
        );
    }
  }
}

/// A country flag on its own, at any size.
///
/// The terminal head wants the flag big — it is the one thing on the home
/// screen that says *where* you are — and an emoji blown up to 30px is a
/// different picture on every platform, or a tofu box where the platform has
/// no emoji font. The repo ships the flags as SVG; this is how anything gets
/// one.
class FlagMark extends StatelessWidget {
  const FlagMark({super.key, required this.flag, this.width = 34});

  final String flag;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iso = ServerGlyph.isoFromFlag(flag);
    if (iso == null) {
      return Icon(
        AppIcons.globe,
        size: width * 0.6,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
      );
    }
    // A flag is 2:3. Drawing it in a square would stretch the cross on every
    // Nordic flag and the stripes on every other one.
    return Container(
      width: width,
      height: width * 0.66,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.18),
        ),
      ),
      child: SvgPicture.asset(
        'assets/flags/$iso.svg',
        fit: BoxFit.cover,
        placeholderBuilder: (_) => const SizedBox.shrink(),
      ),
    );
  }
}

/// Glyph inside a tile. List tiles stay at the size they were drawn for.
/// A head that asks for a tile twice as wide gets a glyph twice as wide too,
/// or the mark is an empty square with a speck in it.
double _glyph(double tile, double designed) {
  if (tile <= 40) return designed;
  return designed * tile / 38;
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.size,
    required this.fill,
    required this.radius,
    required this.child,
  });

  final double size;
  final Color fill;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}