import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// How lit the yard is, and where the house stands. The shell paints the
/// ground; the screen on top writes these numbers. One owner, three values —
/// and the painter reads the geometry every frame, so a screen may publish it
/// during layout without asking the shell to rebuild.
class GroundGlow extends ChangeNotifier {
  double _value = 0.30;

  double get value => _value;

  /// The house's half-size. The orbit is measured against it, so the chain of
  /// light clears the roof instead of running underneath it.
  double houseRadius = 150;

  /// Where the house sits on screen.
  Alignment houseCenter = Alignment.center;

  void set(double next) {
    final clamped = next.clamp(0.0, 1.0);
    if ((clamped - _value).abs() < 0.001) return;
    _value = clamped;
    notifyListeners();
  }
}

class GroundGlowScope extends InheritedNotifier<GroundGlow> {
  const GroundGlowScope({
    super.key,
    required GroundGlow super.notifier,
    required super.child,
  });

  static GroundGlow? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<GroundGlowScope>()
      ?.notifier;
}

/// The night the house stands in.
///
/// The app used to sit on a school-notebook grid. This is the Proxy Dom
/// version: a cold night, a warm bloom where the house stands, fireflies
/// drifting over the ground, and — while the house is lit — a chain of light
/// going round it.
///
/// One painter, one always-running ticker. The fireflies and the orbit read the
/// clock from the ticker; the lit level eases toward [glow] on every frame, so
/// a caller only ever sets a number and the transition is smooth.
class ProxydomGround extends StatefulWidget {
  const ProxydomGround({
    super.key,
    required this.child,
    required this.state,
    this.fireflies,
    this.seed = 7,
  });

  final Widget child;

  /// Lit level plus where the house stands. The screen that owns the house
  /// writes into it.
  final GroundGlow state;

  /// Drifting lights. Defaults to fewer on a phone: they are decoration.
  final int? fireflies;

  /// Same page, same fireflies — the ground must not reshuffle on rebuild.
  final int seed;

  @override
  State<ProxydomGround> createState() => _ProxydomGroundState();
}

class _ProxydomGroundState extends State<ProxydomGround>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 30),
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
        painter: _GroundPainter(
          repaint: _clock,
          clock: _clock,
          state: widget.state,
          fireflies: widget.fireflies ?? (dark ? 26 : 10),
          seed: widget.seed,
          night: dark,
        ),
        isComplex: true,
        willChange: true,
        child: widget.child,
      ),
    );
  }
}

class _GroundPainter extends CustomPainter {
  _GroundPainter({
    required Listenable repaint,
    required this.clock,
    required this.state,
    required this.fireflies,
    required this.seed,
    required this.night,
  })  : _lit = state.value,
        super(repaint: repaint);

  final AnimationController clock;

  /// Read every frame: the home publishes the lit level and the house geometry
  /// into it, and the ground follows without a rebuild.
  final GroundGlow state;

  /// Eased toward the target on every frame, so the yard never snaps on.
  double _lit;

  final int fireflies;
  final int seed;
  final bool night;

  static const double _ease = 0.045;

  @override
  void paint(Canvas canvas, Size size) {
    _lit += (state.value - _lit) * _ease;
    final lit = _lit.clamp(0.0, 1.0);
    final t = clock.value;
    final houseCenter = state.houseCenter;
    final houseRadius = state.houseRadius;

    // The night itself: deep at the edges, a shade warmer under the house.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: night
              ? const [AppBrand.groundDark, AppBrand.groundDeep]
              : const [AppBrand.paperLight, AppBrand.surfaceElevatedLight],
          stops: const [0, 1],
        ).createShader(Offset.zero & size),
    );

    final house = Offset(
      size.width * (0.5 + houseCenter.x),
      size.height * (0.5 + houseCenter.y),
    );

    _bloom(canvas, house, size, night ? 0.55 + lit * 0.45 : 0.35 * lit);
    if (!night) return;

    // Fireflies. Each drifts on its own loop and blinks on its own phase, so
    // the field never pulses in unison and never looks like a grid.
    final rng = math.Random(seed);
    for (var i = 0; i < fireflies; i++) {
      final fx = rng.nextDouble();
      final fy = rng.nextDouble();
      final phase = rng.nextDouble() * math.pi * 2;
      final speed = 0.5 + rng.nextDouble() * 1.4;
      final drift = 0.012 + rng.nextDouble() * 0.028;
      final radius = 0.9 + rng.nextDouble() * 1.8;
      final warm = rng.nextDouble();

      final dx = math.sin(phase + t * math.pi * 2 * speed) * drift;
      final dy =
          math.cos(phase * 1.7 + t * math.pi * 2 * speed * 0.7) * drift * 0.55;
      final blink = 0.45 + 0.55 * (0.5 + 0.5 * math.sin(phase * 2.3 + t * 3));
      // Lit, the fireflies step forward: the whole yard wakes up.
      final alpha = (0.14 + warm * 0.28) * blink * (0.75 + lit * 0.55);

      final p = Offset(
        (fx + dx) * size.width,
        // Keep them low over the ground rather than filling the sky.
        (0.25 + fy * 0.7 + dy) * size.height,
      );
      canvas.drawCircle(
        p,
        radius * 3.6,
        Paint()
          ..color = AppBrand.firefly.withValues(alpha: alpha * 0.20)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(
        p,
        radius,
        Paint()..color = AppBrand.firefly.withValues(alpha: alpha),
      );
    }

    // The chain going round the orbit — the хоровод. Six lights on a ring,
    // each a little behind the one before it, so it reads as a dance and not
    // as a loading spinner.
    if (lit > 0.03) {
      // Clearly outside the roof: [houseRadius] is the house's half-size, and
      // an orbit tucked under it would never be seen.
      final orbit = math.max(houseRadius * 1.06, size.shortestSide * 0.24) +
          lit * 12;
      final spin = t * math.pi * 2 * 1.1;
      // The path itself, faint: six dots alone read as more fireflies, the
      // ring is what makes it a round dance.
      canvas.drawCircle(
        house,
        orbit,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = AppBrand.mascotGoldLit.withValues(alpha: lit * 0.16),
      );
      for (var i = 0; i < 6; i++) {
        final a = spin + i * (math.pi * 2 / 6);
        final wobble = 1 + 0.05 * math.sin(a * 2 + i);
        final p = house + Offset(math.cos(a), math.sin(a)) * orbit * wobble;
        final trail = (0.42 + lit * 0.52 - i * 0.06).clamp(0.0, 1.0);
        canvas.drawCircle(
          p,
          11,
          Paint()
            ..color = AppBrand.mascotGoldLit.withValues(alpha: trail * 0.34)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
        );
        canvas.drawCircle(
          p,
          3.4,
          Paint()..color = AppBrand.mascotGoldLit.withValues(alpha: trail),
        );
      }
    }

    // Vignette: the yard falls away at the edges so the house owns the centre.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.95,
          colors: [
            AppBrand.groundDeep.withValues(alpha: 0.0),
            AppBrand.groundDeep.withValues(alpha: 0.50 + lit * 0.18),
          ],
          stops: const [0.55, 1.0],
        ).createShader(Offset.zero & size),
    );
  }

  void _bloom(Canvas canvas, Offset center, Size size, double strength) {
    if (strength <= 0.001) return;
    final radius = size.shortestSide * (0.34 + strength * 0.22);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppBrand.mascotGold.withValues(alpha: 0.17 * strength),
            AppBrand.mascotEmber.withValues(alpha: 0.07 * strength),
            AppBrand.mascotEmber.withValues(alpha: 0.0),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(covariant _GroundPainter old) =>
      old.fireflies != fireflies ||
      old.seed != seed ||
      old.state != state ||
      old.night != night;
}