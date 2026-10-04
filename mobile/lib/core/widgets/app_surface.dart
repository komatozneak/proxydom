import 'package:flutter/material.dart';

import '../theme.dart';

/// A plate that catches light.
///
/// The app used to draw every card as `one fill + a 1px outline`. A single
/// fill with a hairline has no light source and no distance from the page, so
/// the screens read flat no matter how good the colours are. This is the one
/// surface cards, panels and rows should be built from:
///
/// * the first stretch of the plate carries the lit edge that separates it
///   from the sheet,
/// * the floor is a step darker than the top,
/// * a key shadow drops it onto the page.
///
/// Everything derives from [AppBrand] — no widget names a colour.
class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.radius = AppBrand.radiusCard,
    this.padding,
    this.elevated = true,
    this.tint,
    this.clip = false,
  });

  final Widget child;

  final double radius;

  final EdgeInsetsGeometry? padding;

  /// The key shadow. Off for things already flush with the page (nav sheets,
  /// wells) where a shadow would only muddy the edge.
  final bool elevated;

  /// Overrides the plate colour; the light is still derived from it.
  final Color? tint;

  /// Clip children to the plate (cards with dividers, lists, menus).
  final bool clip;

  /// Light and shadow for the current brightness.
  static ({Color top, Color floor, Color edge, Color shadow, Color rim}) _light(
      BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) {
      return (
        top: AppBrand.surfaceRaisedDark,
        floor: AppBrand.surfaceRaisedDark,
        edge: AppBrand.edgeDark,
        shadow: AppBrand.shadowKeyDark,
        rim: AppBrand.shadeSource,
      );
    }
    return (
      top: AppBrand.surfaceElevatedLight,
      floor: AppBrand.surfaceElevatedLight,
      edge: AppBrand.edgeLight,
      shadow: AppBrand.shadowKeyLight,
      rim: AppBrand.shadeSource,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final l = _light(context);
    final base = tint ?? l.top;

    // One light source for the whole app: a highlight from above, a floor a
    // touch under it, and the hairline that catches the eye last.
    final lit = Color.lerp(base, AppBrand.lightSource, dark ? 0.07 : 0.0)!;
    final sunk = Color.lerp(base, AppBrand.shadeSource, dark ? 0.22 : 0.03)!;
    final edge = Color.lerp(l.edge, base, dark ? 0.35 : 0.0)!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [lit, base, sunk],
          stops: const [0.0, 0.08, 1.0],
        ),
        border: Border.all(color: edge, width: 1),
        boxShadow: elevated
            ? [
                // The plate itself.
                BoxShadow(
                  color: l.shadow,
                  blurRadius: 22,
                  spreadRadius: -6,
                  offset: const Offset(0, 10),
                ),
                // The lit lip along the top edge, 1px, inside the shape.
                BoxShadow(
                  color: Color.lerp(
                    AppBrand.lightSource,
                    AppBrand.shadeSource,
                    dark ? 0.72 : 0.86,
                  )!,
                  blurRadius: 0,
                  spreadRadius: -1,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: clip
            ? ClipRRect(
                borderRadius: BorderRadius.circular(radius - 1),
                child: child,
              )
            : child,
      ),
    );
  }
}
