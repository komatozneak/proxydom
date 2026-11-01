import 'package:flutter/material.dart';

import '../theme.dart';

/// What the Windows caption needs to know about the navigation pane.
///
/// The caption sits above the router and the pane inside it, so they are in
/// different trees. The pane's column runs to the top of the window — the
/// caption paints the same panel over the pane's width — and for that the two
/// must agree on how wide the pane is right now and what it is made of.
class WindowsPane {
  WindowsPane._();

  static const double width = 248;
  static const double compactWidth = 60;

  /// Below this the pane lays itself out folded, also while it animates; the
  /// caption shows the lockup only at or above it.
  static const double wideFrom = 160;
  static const Duration fold = Duration(milliseconds: 200);
  static const Curve foldCurve = Curves.easeOutCubic;

  /// The pane's target width, or null when no pane is on screen (onboarding,
  /// import): then the caption is the ground's, with no column in it.
  static final ValueNotifier<double?> currentWidth = ValueNotifier(null);

  /// Height of the window caption: the height of the Windows caption buttons,
  /// so the band is no taller than the controls in it.
  static const double captionHeight = 32;

  static Color panel(bool dark) =>
      dark ? AppBrand.surfaceRaisedDark : AppBrand.stoneLight;

  static BorderSide edge(bool dark) => BorderSide(
        color: (dark ? AppBrand.mossLight : AppBrand.inkLight)
            .withValues(alpha: dark ? 0.16 : 0.10),
      );
}
