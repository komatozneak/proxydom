import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Three house-colored discs, larger toward the outside, breathing in place.
class HousePulsar extends StatefulWidget {
  const HousePulsar({super.key, required this.diameter});

  /// Diameter of the innermost disc, matching the house box.
  final double diameter;

  @override
  State<HousePulsar> createState() => _HousePulsarState();
}

class _HousePulsarState extends State<HousePulsar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tick;

  @override
  void initState() {
    super.initState();
    _tick = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _tick,
      builder: (context, _) {
        final canvas = widget.diameter * 1.46;
        return OverflowBox(
          alignment: Alignment.center,
          minWidth: canvas,
          maxWidth: canvas,
          minHeight: canvas,
          maxHeight: canvas,
          child: CustomPaint(
            size: Size.square(canvas),
            painter: _PulsarPainter(
              t: _tick.value,
              diameter: widget.diameter,
              color: AppBrand.livingHouse,
            ),
          ),
        );
      },
    );
  }
}

class _PulsarPainter extends CustomPainter {
  const _PulsarPainter({
    required this.t,
    required this.diameter,
    required this.color,
  });

  final double t;
  final double diameter;
  final Color color;

  /// Outer first so the denser inner disc sits on top.
  static const List<(double scale, double alpha, double phase)> _rings = [
    (1.32, 0.07, 0),
    (1.14, 0.13, 2.1),
    (1.0, 0.22, 4.2),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final base = diameter / 2;
    final turn = t * math.pi * 2;
    for (final ring in _rings) {
      final breathe = 1 + 0.045 * math.sin(turn + ring.$3);
      canvas.drawCircle(
        center,
        base * ring.$1 * breathe,
        Paint()..color = color.withValues(alpha: ring.$2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PulsarPainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.diameter != diameter ||
        oldDelegate.color != color;
  }
}
