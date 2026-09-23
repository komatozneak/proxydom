import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Honey flame from the middle of the house, only while the tunnel is coming up.
class HousePulsar extends StatefulWidget {
  const HousePulsar({super.key, required this.diameter});

  /// Diameter of the house box. The glow starts inside it.
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
        final canvas = widget.diameter * 1.42;
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
              color: AppBrand.flame,
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

  /// Outer first. Scales are fractions of the house radius, starting inside it.
  static const List<(double scale, double alpha, double phase)> _rings = [
    (1.28, 0.03, 0),
    (1.0, 0.05, 1.05),
    (0.78, 0.08, 2.1),
    (0.58, 0.11, 3.15),
    (0.38, 0.15, 4.2),
    (0.18, 0.20, 5.25),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final base = diameter / 2;
    final reach = base * 1.28;
    final turn = t * math.pi * 2;
    final breathe = 1 + 0.035 * math.sin(turn);
    canvas.drawCircle(
      center,
      reach * breathe,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.26),
            color.withValues(alpha: 0.10),
            color.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.42, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: reach)),
    );
    for (final ring in _rings) {
      final pulse = 1 + 0.04 * math.sin(turn + ring.$3);
      canvas.drawCircle(
        center,
        base * ring.$1 * pulse,
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
