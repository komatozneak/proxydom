import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The round dance around the house.
///
/// It used to live in the background, which is why the yard felt busy: an
/// ornament that belongs to the button was painted behind the whole screen, so
/// it never read as part of anything. Here it is a child of the house, drawn
/// only while the house burns, and it is the one place in the app where
/// something is allowed to move fast.
///
/// Six lights chasing each other around the roof, plus a thread for the path.
class HouseOrbit extends StatefulWidget {
  const HouseOrbit({
    super.key,
    required this.burning,
    this.lights = 6,
  });

  /// 0 while the house rests — nothing is drawn at all. 1 while it burns.
  final double burning;

  final int lights;

  @override
  State<HouseOrbit> createState() => _HouseOrbitState();
}

class _HouseOrbitState extends State<HouseOrbit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _OrbitPainter(
          repaint: _clock,
          clock: _clock,
          burning: widget.burning,
          lights: widget.lights,
          night: dark,
        ),
        isComplex: true,
        willChange: true,
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
    required Listenable repaint,
    required this.clock,
    required this.burning,
    required this.lights,
    required this.night,
  }) : _lit = burning,
       super(repaint: repaint);

  final AnimationController clock;
  final double burning;
  final int lights;
  final bool night;

  /// Eased, so lighting the house does not snap the dance into place.
  double _lit;

  @override
  void paint(Canvas canvas, Size size) {
    _lit += (burning - _lit) * 0.08;
    final lit = _lit.clamp(0.0, 1.0);
    if (!night || lit < 0.02) return;

    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.40 + lit * 6;
    final spin = clock.value * math.pi * 2 * 1.35;

    // The path, thin: six dots alone read as confetti.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = AppBrand.mascotGoldLit.withValues(alpha: lit * 0.14),
    );

    for (var i = 0; i < lights; i++) {
      final a = spin + i * (math.pi * 2 / lights);
      final wobble = 1 + 0.05 * math.sin(a * 2 + i);
      final at = center + Offset(math.cos(a), math.sin(a)) * radius * wobble;
      // Each light a step behind the one before it: a chase, not a spinner.
      final trail = (0.35 + lit * 0.55 - i * 0.05).clamp(0.0, 1.0);
      canvas.drawCircle(
        at,
        9,
        Paint()
          ..color = AppBrand.mascotGoldLit.withValues(alpha: trail * 0.30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
      canvas.drawCircle(
        at,
        3,
        Paint()..color = AppBrand.mascotGoldLit.withValues(alpha: trail),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter old) =>
      old.lights != lights || old.night != night || old.burning != burning;
}