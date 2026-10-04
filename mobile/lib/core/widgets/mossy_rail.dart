import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The rail as mossy stone.
///
/// It was a flat rectangle a shade off the page — furniture that says nothing.
/// This is the same rail with weather on it: a dark forest night, damp stone
/// under it, moss creeping along the bottom edge. Everything is painted from
/// one seeded field so the stone is the same stone on every frame — a
/// background that reshuffles under the cursor is noise, and noise is exactly
/// what this rail must not be.
class MossyRail extends StatelessWidget {
  const MossyRail({super.key, required this.child, this.light = false});

  final Widget child;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MossyStonePainter(light: light),
      child: child,
    );
  }
}

class _MossyStonePainter extends CustomPainter {
  _MossyStonePainter({required this.light});

  final bool light;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    if (!light) {
      // A forest night: black-green at the top, damper stone below.
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppBrand.forestDark, AppBrand.forestDeep],
          ).createShader(rect),
      );
      _damp(canvas, size);
      _moss(canvas, size);
    } else {
      canvas.drawRect(rect, Paint()..color = AppBrand.stoneLight);
      _damp(canvas, size);
      _moss(canvas, size, light: true);
    }

    // The lit lip along the top, and the seam down the right: a stone slab has
    // an edge, and an edge is what separates furniture from page.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            (light ? AppBrand.inkLight : AppBrand.lightSource)
                .withValues(alpha: light ? 0.10 : 0.07),
            AppBrand.lightSource.withValues(alpha: 0.0),
          ],
          stops: const [0, 0.18],
        ).createShader(rect),
    );
    canvas.drawLine(
      Offset(size.width - 0.5, 0),
      Offset(size.width - 0.5, size.height),
      Paint()
        ..strokeWidth = 1
        ..color = (light ? AppBrand.inkLight : AppBrand.mossLight)
                .withValues(alpha: light ? 0.14 : 0.18),
    );
  }

  /// Damp patches: a few large, soft, slow spots of darker stone. Few and big
  /// on purpose — small ones read as dirt on the screen.
  void _damp(Canvas canvas, Size size) {
    final rng = math.Random(41);
    for (var i = 0; i < 5; i++) {
      final center = Offset(
        rng.nextDouble() * size.width,
        size.height * (0.2 + rng.nextDouble() * 0.7),
      );
      final radius = size.width * (0.45 + rng.nextDouble() * 0.55);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              (light ? AppBrand.stoneShade : AppBrand.forestShade)
                  .withValues(alpha: light ? 0.16 : 0.5),
              (light ? AppBrand.stoneShade : AppBrand.forestShade)
                  .withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  /// Moss along the bottom, where water sits.
  void _moss(Canvas canvas, Size size, {bool light = false}) {
    final top = size.height * 0.58;
    final path = Path()..moveTo(0, size.height);
    path.lineTo(0, top + size.height * 0.10);
    for (var i = 0; i <= 6; i++) {
      final f = i / 6;
      final x = f * size.width;
      final y = top +
          math.sin(f * math.pi * 2.1 + 1.3) * size.height * 0.045 +
          f * size.height * 0.10;
      path.lineTo(x, y);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            (light ? AppBrand.mossLight : AppBrand.moss)
                .withValues(alpha: light ? 0.10 : 0.0),
            (light ? AppBrand.mossLight : AppBrand.moss)
                .withValues(alpha: light ? 0.22 : 0.16),
          ],
        ).createShader(Rect.fromLTRB(0, top, size.width, size.height)),
    );
  }

  @override
  bool shouldRepaint(covariant _MossyStonePainter old) => old.light != light;
}

/// The phone's counterpart of [MossyRail]: the same stone, lying flat.
///
/// A bottom bar used to be a rule and nothing else — a gold hairline over a
/// transparent box, which is the phone's version of saying "there is a bar
/// here". This is the slab the rail is cut from, turned on its side: the damp
/// stone, the lit lip along its top edge where the screen light falls, and
/// moss along that same top edge, because that is the face a thumb touches and
/// water sits on the face that points up.
class MossySlab extends StatelessWidget {
  const MossySlab({super.key, required this.child, this.light = false});

  final Widget child;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SlabPainter(light: light),
      child: child,
    );
  }
}

class _SlabPainter extends CustomPainter {
  const _SlabPainter({required this.light});

  final bool light;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: light
              ? [AppBrand.stoneLight, AppBrand.stoneShade.withValues(alpha: 0.5)]
              : [AppBrand.forestDark, AppBrand.forestDeep],
        ).createShader(rect),
    );

    // The lit lip: light comes from above, so it lands on the top edge and dies
    // within a fifth of the way down.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            (light ? AppBrand.inkLight : AppBrand.lightSource)
                .withValues(alpha: light ? 0.10 : 0.08),
            Colors.transparent,
          ],
          stops: const [0, 0.20],
        ).createShader(rect),
    );

    // Moss creeping along the top edge in uneven tufts — one seeded field, so
    // the same tufts every frame.
    final rng = math.Random(97);
    final path = Path()..moveTo(0, 0);
    for (var i = 0; i <= 14; i++) {
      final f = i / 14;
      final x = f * size.width;
      final y = math.sin(f * math.pi * 3.2) * 1.6 +
          (rng.nextDouble() - 0.5) * 2.2;
      path.lineTo(x, math.max(0, y));
    }
    path
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = (light ? AppBrand.moss : AppBrand.mossLight)
            .withValues(alpha: light ? 0.18 : 0.12),
    );

    // The seam under the lip, where the slab meets the night.
    canvas.drawLine(
      Offset(0, 0.5),
      Offset(size.width, 0.5),
      Paint()
        ..strokeWidth = 1
        ..color = (light ? AppBrand.moss : AppBrand.mossLight)
            .withValues(alpha: light ? 0.22 : 0.16),
    );
  }

  @override
  bool shouldRepaint(covariant _SlabPainter old) => old.light != light;
}

/// The edge of a moss patch, for the rail's selected item: the same green the
/// moss is painted with, so the selection belongs to the stone.
class MossEdge extends StatelessWidget {
  const MossEdge({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 8),
        ],
      ),
    );
  }
}