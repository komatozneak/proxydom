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

  /// Parallax driver, normalised to −1…1. On desktop the shell writes the
  /// pointer here; on a phone it stays zero and the painter drifts on its own
  /// clock instead.
  Offset pointer = Offset.zero;

  bool pointerDriven = false;

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
    this.seed = 7,
  });

  final Widget child;

  /// Lit level, house geometry and the parallax pointer. The screen that owns
  /// the house writes into it.
  final GroundGlow state;

  /// Same page, same yard — the ground must not reshuffle on rebuild.
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

    // The night itself. Everything that follows lives under 8% luminance except
    // the house's own halo: a background that competes with the words on top of
    // it is not a background.
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

    // Parallax: the pointer on a window, a slow idle drift on a phone. Three
    // layers, each moving faster than the one behind it, so the yard has depth
    // without a single bright point in the middle of the screen.
    final drive = state.pointerDriven
        ? state.pointer
        : Offset(
            math.sin(t * math.pi * 2 * 0.06),
            math.cos(t * math.pi * 2 * 0.045),
          );
    _pointer = Offset.lerp(_pointer, drive, 0.06)!;
    final p = _pointer;

    if (night) {
      _horizonHaze(canvas, size, p * 6, lit);
      _ridge(canvas, size, p * 14, lit);
      _motes(canvas, size, p * 26, lit);
    }

    _bloom(canvas, house, size, night ? 0.18 + lit * 0.30 : 0.12 * lit);

    // The orbit stays, but it belongs to the house, not to the wallpaper:
    // a thread of light while the house burns.
    if (night && lit > 0.03) {
      final orbit =
          math.max(houseRadius * 1.06, size.shortestSide * 0.24) + lit * 12;
      final spin = t * math.pi * 2 * 1.1;
      canvas.drawCircle(
        house,
        orbit,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = AppBrand.mascotGoldLit.withValues(alpha: lit * 0.10),
      );
      for (var i = 0; i < 6; i++) {
        final a = spin + i * (math.pi * 2 / 6);
        final wobble = 1 + 0.05 * math.sin(a * 2 + i);
        final at = house + Offset(math.cos(a), math.sin(a)) * orbit * wobble;
        final trail = (0.16 + lit * 0.34 - i * 0.022).clamp(0.0, 1.0);
        canvas.drawCircle(
          at,
          9,
          Paint()
            ..color = AppBrand.mascotGoldLit.withValues(alpha: trail * 0.30)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
        );
        canvas.drawCircle(
          at,
          2.6,
          Paint()..color = AppBrand.mascotGoldLit.withValues(alpha: trail),
        );
      }
    }

    if (!night) return;

    // The column of air the words stand in: a soft dark wash down the middle,
    // so type keeps its contrast whatever the yard is doing behind it.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.72,
          colors: [
            AppBrand.groundDeep.withValues(alpha: 0.34),
            AppBrand.groundDeep.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(Offset.zero & size),
    );

    // Vignette: the yard falls away at the edges.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.95,
          colors: [
            AppBrand.groundDeep.withValues(alpha: 0.0),
            AppBrand.groundDeep.withValues(alpha: 0.62),
          ],
          stops: const [0.45, 1.0],
        ).createShader(Offset.zero & size),
    );
  }

  /// Slowed-down pointer, so the layers glide instead of snapping.
  Offset _pointer = Offset.zero;

  /// Layer 1 — the warm haze sitting on the horizon.
  void _horizonHaze(Canvas canvas, Size size, Offset shift, double lit) {
    final band = size.height * 0.30;
    final top = size.height * 0.72 + shift.dy - band;
    final rect = Rect.fromLTWH(0, top, size.width, band);
    canvas.drawRect(
      Rect.fromLTRB(-40 + shift.dx, top, size.width + 40, top + band),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppBrand.mascotEmber.withValues(alpha: 0),
            AppBrand.mascotEmber.withValues(alpha: 0.035 + lit * 0.02),
            AppBrand.mascotEmber.withValues(alpha: 0),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );
  }

  /// Layer 2 — the ridge behind the yard: one slow curve, no detail.
  void _ridge(Canvas canvas, Size size, Offset shift, double lit) {
    final base = size.height * 0.80 + shift.dy;
    final path = Path()..moveTo(-20, size.height);
    path.lineTo(-20, base);
    for (var i = 0; i <= 8; i++) {
      final f = i / 8;
      final x = -20 + f * (size.width + 40) + shift.dx * (1 + f);
      final y = base - math.sin(f * math.pi * 1.6 + seed) * size.height * 0.045;
      path.lineTo(x, y);
    }
    path
      ..lineTo(size.width + 20, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppBrand.groundDark.withValues(alpha: 0.55 + lit * 0.05),
            AppBrand.groundDeep.withValues(alpha: 0.85),
          ],
        ).createShader(Rect.fromLTRB(0, base - 60, size.width, size.height)),
    );
  }

  /// Layer 3 — dust in the near air. Barely there, and never in the middle.
  void _motes(Canvas canvas, Size size, Offset shift, double lit) {
    final rng = math.Random(seed + 11);
    for (var i = 0; i < 9; i++) {
      final fx = rng.nextDouble();
      final fy = rng.nextDouble();
      final phase = rng.nextDouble() * math.pi * 2;
      final x = (fx + shift.dx * (0.6 + fx)) * size.width +
          math.sin(phase + clock.value * math.pi * 2 * 0.05) * 10;
      final y = (0.12 + fy * 0.82) * size.height +
          math.cos(phase * 1.3 + clock.value * math.pi * 2 * 0.04) * 8 +
          shift.dy * (0.4 + fy);
      final a = (0.05 + rng.nextDouble() * 0.03) * (0.7 + lit * 0.3);
      canvas.drawCircle(
        Offset(x, y),
        1.1 + rng.nextDouble() * 1.2,
        Paint()..color = AppBrand.firefly.withValues(alpha: a),
      );
    }
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
      old.seed != seed || old.state != state || old.night != night;
}