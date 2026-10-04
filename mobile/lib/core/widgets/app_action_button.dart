import 'package:flutter/material.dart';

import '../theme.dart';
import 'app_icon.dart';
import 'interaction.dart';

/// The house key.
///
/// Material's [FilledButton] is one flat fill: no lit top edge, no shadow, no
/// press travel — which is why a row of them reads as cheap plastic at any
/// size. This is a milled key instead:
///
/// * the top face is a step lighter than the sides,
/// * a rim runs along the bottom edge so the key has thickness,
/// * pressing drops it 1px and collapses the shadow, then releases.
///
/// [color] is a role colour from [AppBrand] (moss for paste, amber for QR); the
/// key mixes its own light from it. The label is always charcoal on top, which
/// is why the roles are chosen light.
class AppActionButton extends StatefulWidget {
  const AppActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.onPressed,
    this.height = 56,
    this.expand = true,
    this.tooltip,
    this.iconSize = 19,
  });

  final IconData icon;

  final String label;

  /// Role colour. Mixed by the key, never used raw.
  final Color color;

  final VoidCallback? onPressed;

  final double height;

  final bool expand;

  final String? tooltip;

  final double iconSize;

  @override
  State<AppActionButton> createState() => _AppActionButtonState();
}

class _AppActionButtonState extends State<AppActionButton> {
  bool _down = false;

  /// Keyboard focus has to live somewhere; without a node there is nothing to
  /// traverse with Tab on a desktop.
  final FocusNode _focus = FocusNode(debugLabel: 'AppActionButton');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _setDown(bool value) {
    if (_down == value || !mounted) return;
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final enabled = widget.onPressed != null;

    final base = enabled
        ? widget.color
        : dark
            ? AppBrand.surfaceSunkDark
            : AppBrand.honeySurface;
    final ink =
        enabled ? AppBrand.inkLight : theme.colorScheme.onSurfaceVariant;
    final radius = BorderRadius.circular(widget.height / 2);

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: SizedBox(
        height: widget.height,
        width: widget.expand ? double.infinity : null,
        child: HoverBuilder(
          onTap: widget.onPressed,
          focusNode: _focus,
          onKeyActivate: widget.onPressed,
          builder: (context, hovered) {
            // Hover lifts the key the way a pointer would expect it to: a
            // shade lighter and a longer shadow, not a Material tint.
            final lit = _down ? 0.0 : (hovered ? 0.07 : 0.0);
            // On paper the same gold reads as brown. The night gives a mid-tone
            // gold its own light — it sits on black and looks lit — while on
            // cream there is nothing for it to be brighter than, and #C88F27
            // turns into mud with a dark label on it. Waxing it towards the
            // light is what makes the key look like a key in daylight.
            final lift = dark ? lit : lit + 0.24;
            final face = _down
                ? Color.lerp(base, AppBrand.shadeSource, 0.16)!
                : Color.lerp(
                    base,
                    AppBrand.lightSource,
                    (dark ? 0.10 : 0.16) + lift,
                  )!;
            final floor = _down
                ? Color.lerp(base, AppBrand.shadeSource, 0.30)!
                : Color.lerp(
                    base,
                    // The floor is most of what the eye sees — the gradient
                    // hands it everything below 62% — so lifting only the face
                    // left a bright top on a brown box. On paper the shade goes
                    // in the other direction.
                    dark ? AppBrand.shadeSource : AppBrand.lightSource,
                    dark ? (hovered ? 0.04 : 0.08) : 0.12,
                  )!;
            final rim = Color.lerp(
              base,
              dark ? AppBrand.shadeSource : AppBrand.lightSource,
              dark ? (enabled ? 0.45 : 0.2) : 0.28,
            )!;

            Widget key = AnimatedContainer(
              duration: AppBrand.motionPress,
              curve: AppBrand.motionPressCurve,
              transform: Matrix4.translationValues(0, _down ? 1.5 : 0, 0),
              decoration: BoxDecoration(
                borderRadius: radius,
                // The rim is part of the same box as the face: a separate
                // overlay decor detached from the key when press moved it.
                border: Border.all(color: rim.withValues(alpha: 0.55)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [face, floor],
                  stops: const [0.0, 0.62],
                ),
                boxShadow: enabled
                    ? [
                        BoxShadow(
                          // The key's own colour underneath it is a shadow the
                          // way a bruise is a shadow. On the night that reads
                          // as weight; on cream it read as dirt under a key, so
                          // daylight gets a soft neutral instead.
                          color: dark
                              ? Color.lerp(
                                  base,
                                  AppBrand.shadeSource,
                                  0.55,
                                )!
                              : AppBrand.shadeSource.withValues(alpha: 0.16),
                          blurRadius: _down ? 4 : (hovered ? 20 : 14),
                          spreadRadius: -2,
                          offset: Offset(0, _down ? 1 : (hovered ? 9 : 6)),
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: widget.onPressed,
                    onTapDown: enabled ? (_) => _setDown(true) : null,
                    onTapUp: enabled ? (_) => _setDown(false) : null,
                    onTapCancel: enabled ? () => _setDown(false) : null,
                    splashColor: AppBrand.lightSource.withValues(alpha: 0.14),
                    highlightColor: AppBrand.lightSource.withValues(alpha: 0.06),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: widget.expand
                            ? MainAxisSize.max
                            : MainAxisSize.min,
                        children: [
                          AppIcon(widget.icon, size: widget.iconSize, color: ink),
                          const SizedBox(width: 8),
                          // Scale down instead of ellipsising: a key that reads
                          // "Вста…" is worse than one with a smaller label.
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                widget.label,
                                maxLines: 1,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: ink,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );

            return widget.tooltip == null
                ? key
                : Tooltip(message: widget.tooltip!, child: key);
          },
        ),
      ),
    );
  }
}

/// A quiet round control: ring, no slab.
///
/// Used where the action is secondary (reload). A solid circle in a saturated
/// role colour shouts louder than the primary key next to it; a ring with the
/// same hue keeps the accent and gives the eye back to the primary action.
class AppRingButton extends StatefulWidget {
  const AppRingButton({
    super.key,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.tooltip,
    this.size = 44,
    this.iconSize = 20,
  });

  final IconData icon;

  final Color color;

  final VoidCallback? onPressed;

  final String? tooltip;

  final double size;

  final double iconSize;

  @override
  State<AppRingButton> createState() => _AppRingButtonState();
}

class _AppRingButtonState extends State<AppRingButton> {
  bool _down = false;

  final FocusNode _focus = FocusNode(debugLabel: 'AppRingButton');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ring =
        Color.lerp(widget.color, AppBrand.lightSource, dark ? 0.15 : 0)!;

    return Semantics(
      button: true,
      label: widget.tooltip,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: HoverBuilder(
          onTap: widget.onPressed,
          focusNode: _focus,
          onKeyActivate: widget.onPressed,
          builder: (context, hovered) {
            final fill = _down
                ? (dark ? 0.26 : 0.20)
                : hovered
                    ? (dark ? 0.22 : 0.18)
                    : (dark ? 0.12 : 0.10);
            final button = AnimatedContainer(
              duration: AppBrand.motionPress,
              curve: AppBrand.motionPressCurve,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: fill),
                border: Border.all(
                  color: ring.withValues(
                    alpha: dark ? (hovered ? 1.0 : 0.85) : 0.95,
                  ),
                  width: hovered ? 2 : 1.6,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: dark ? 0.22 : 0.18),
                    blurRadius: hovered ? 14 : 10,
                    spreadRadius: -4,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Material(
                type: MaterialType.transparency,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: widget.onPressed,
                  onTapDown: (_) => setState(() => _down = true),
                  onTapUp: (_) => setState(() => _down = false),
                  onTapCancel: () => setState(() => _down = false),
                  child: Center(
                    child: AppIcon(
                      widget.icon,
                      size: widget.iconSize,
                      color: ring,
                    ),
                  ),
                ),
              ),
            );

            return widget.tooltip == null
                ? button
                : Tooltip(message: widget.tooltip!, child: button);
          },
        ),
      ),
    );
  }
}
