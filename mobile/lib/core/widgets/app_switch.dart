import 'package:flutter/material.dart';

import '../theme.dart';

/// The house switch.
///
/// Material's [Switch] is the loudest object in a settings list: a saturated
/// pill that outranks the row title it belongs to. This one is the same size
/// but built like the rest of the app — a sunk track, a lit top edge when on,
/// and a thumb with a key shadow so it reads as a physical part.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;

  final ValueChanged<bool>? onChanged;

  static const double _trackW = 48;
  static const double _trackH = 30;
  static const double _thumb = 24;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final enabled = onChanged != null;

    final onTrack =
        dark ? AppBrand.switchTrackOnDark : AppBrand.switchTrackOnLight;
    // On the night, surfaceSunkDark is almost the card itself: off switches
    // became floating white dots with no track. Use the rimmed dark track.
    final offTrack =
        dark ? AppBrand.switchTrackOffDark : AppBrand.switchTrackOffLight;
    final trackTop = value
        ? Color.lerp(onTrack, AppBrand.lightSource, dark ? 0.12 : 0.10)!
        : Color.lerp(offTrack, AppBrand.lightSource, 0.10)!;
    final trackFloor = value
        ? onTrack
        : dark
            ? AppBrand.surfaceVariantDark
            : Color.lerp(offTrack, AppBrand.shadeSource, 0.18)!;
    final border = dark
        ? AppBrand.lightSource.withValues(alpha: value ? 0.10 : 0.08)
        : AppBrand.shadeSource.withValues(alpha: value ? 0.10 : 0.24);
    final thumb =
        value && dark ? AppBrand.switchThumbOnDark : AppBrand.surfaceElevatedLight;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Semantics(
        toggled: value,
        enabled: enabled,
        child: GestureDetector(
          onTap: enabled ? () => onChanged!(!value) : null,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppBrand.motionReveal,
            curve: AppBrand.motionRevealCurve,
            width: _trackW,
            height: _trackH,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_trackH / 2),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [trackTop, trackFloor],
                stops: const [0.0, 0.6],
              ),
              border: Border.all(color: border),
              boxShadow: value
                  ? [
                      BoxShadow(
                        color: onTrack.withValues(alpha: 0.35),
                        blurRadius: 10,
                        spreadRadius: -3,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: AnimatedAlign(
              duration: AppBrand.motionReveal,
              curve: AppBrand.motionRevealCurve,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: _thumb,
                height: _thumb,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: thumb,
                  boxShadow: [
                    BoxShadow(
                      color: AppBrand.shadeSource.withValues(alpha: 0.32),
                      blurRadius: 4,
                      spreadRadius: -1,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
