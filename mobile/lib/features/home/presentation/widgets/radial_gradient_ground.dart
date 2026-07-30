import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/connect_button.dart';

/// Soft radial «ground» behind Signal Nest — atmospheric fill, not a second glow.
///
/// Container is fixed 400×400 (not Positioned.fill) so color ends ~200dp from center.
class RadialGradientGround extends StatelessWidget {
  const RadialGradientGround({
    super.key,
    required this.state,
    required this.child,
  });

  final TreeState state;
  final Widget child;

  static const double _box = 400;

  Color _centerColor(Brightness brightness) {
    final darkFactor = brightness == Brightness.dark ? 0.7 : 1.0;
    final (Color base, double alpha) = switch (state) {
      TreeState.disconnected => (AppBrand.livingHouse, 0.08),
      TreeState.connecting => (AppBrand.connectingAura, 0.12),
      TreeState.connected => (AppBrand.success, 0.10),
      TreeState.error => (AppBrand.error, 0.06),
    };
    return base.withValues(alpha: alpha * darkFactor);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final center = _centerColor(brightness);

    return SizedBox(
      width: _box,
      height: _box,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: ExcludeSemantics(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
                width: _box,
                height: _box,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [center, center.withValues(alpha: 0)],
                    radius: 0.71,
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
