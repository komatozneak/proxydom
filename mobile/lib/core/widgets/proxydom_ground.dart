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

    // Parallax: the pointer on a window, a slow idle drift on a phone.
    final drive = state.pointerDriven
        ? state.pointer
        : Offset(
            math.sin(t * math.pi * 2 * 0.06),
            math.cos(t * math.pi * 2 * 0.045),
          );
    _pointer = Offset.lerp(_pointer, drive, 0.06)!;
    final p = _pointer;

    if (night) {
      // The yard, from inside the lit room: a pool of light on the floor, the
      // boards it falls across, and dust turning slowly inside the beam. No
      // fireflies, no orbit — the house is the only lamp, and a background that
      // draws its own attention is a background that eats the words on it.
      final floor = Offset(
        house.dx + p.dx * 18,
        // At the house's feet, not at the bottom of the window: light on a
        // floor starts where the thing casting it stands.
        size.height * 0.72 + p.dy * 10,
      );
      _lightPool(canvas, size, floor, lit);
      _boards(canvas, size, p * 22, lit);
      _dustInBeam(canvas, size, floor, p * 34, lit);
    }

    _bloom(canvas, house, size, night ? 0.16 + lit * 0.26 : 0.12 * lit);

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

  /// The pool of light the house throws on the floor: a wide, soft ellipse
  /// rather than a round glow, because light on a floor is an ellipse. It
  /// breathes with the charge — a lit house lights more of the yard.
  void _lightPool(Canvas canvas, Size size, Offset floor, double lit) {
    final w = size.width * 1.5;
    final h = size.height * 0.42;
    final breath = 1 + 0.04 * math.sin(clock.value * math.pi * 2 * 0.05);
    canvas.drawOval(
      Rect.fromCenter(center: floor, width: w * breath, height: h * breath),
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppBrand.mascotGold.withValues(alpha: 0.055 + lit * 0.05),
            AppBrand.mascotEmber.withValues(alpha: 0.030 + lit * 0.03),
            AppBrand.mascotEmber.withValues(alpha: 0.0),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(
          Rect.fromCenter(center: floor, width: w, height: h),
        ),
    );
  }

  /// Floorboards. Long shallow lines that spread as they come forward, so the
  /// parallax slides them like a floor under a moving camera. They fade into
  /// the night above, because a ruled line all the way to the top of the
  /// screen is a grid — the thing this background replaced.
  void _boards(Canvas canvas, Size size, Offset shift, double lit) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppBrand.inkMutedDark.withValues(alpha: 0.05 + lit * 0.015);
    final start = size.height * 0.46;
    for (var i = 0; i < 12; i++) {
      final f = i / 12;
      // Perspective: spacing grows towards the viewer.
      final y = start + (size.height - start) * math.pow(f, 1.7).toDouble();
      // Nearer boards sit a little brighter: the floor catches more light near
      // the viewer than at the far end.
      final depth = 0.35 + f * 0.65;
      final slide = shift.dx * (1 + f * 2.4);
      canvas.drawLine(
        Offset(-30 + slide, y),
        Offset(size.width + 30 + slide * 1.15, y),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = paint.color.withValues(alpha: paint.color.a * depth),
      );
    }
    // Fog: the far end of the floor dissolves into the night, so no line ever
    // reaches the words at the top of the screen.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppBrand.groundDark,
            AppBrand.groundDark.withValues(alpha: 0.92),
            AppBrand.groundDark.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.40, 0.58],
        ).createShader(
          Rect.fromLTRB(0, size.height * 0.30, size.width, size.height * 0.60),
        ),
    );
  }

  /// Dust turning in the beam. It only exists where the light is, which is why
  /// it never becomes noise: away from the pool there is nothing to see.
  void _dustInBeam(
    Canvas canvas,
    Size size,
    Offset floor,
    Offset shift,
    double lit,
  ) {
    final rng = math.Random(seed + 11);
    final w = size.width * 0.72;
    final h = size.height * 0.34;
    for (var i = 0; i < 11; i++) {
      final fx = rng.nextDouble();
      final rise = (clock.value * (0.02 + rng.nextDouble() * 0.03)) % 1.0;
      // Dust rises through the beam and starts again at the floor.
      final fy = (1 - rise + rng.nextDouble() * 0.1) % 1.0;
      final wobble = math.sin(clock.value * math.pi * 2 * 0.08 + i) * 12;
      final at = Offset(
        floor.dx + (fx - 0.5) * w + wobble + shift.dx * 10,
        floor.dy - fy * h + shift.dy * 6,
      );
      // Falls off towards the edge of the beam, like real dust does.
      final edge = 1 - ((fx - 0.5) * 2).abs().clamp(0.0, 1.0);
      final a = (0.03 + rng.nextDouble() * 0.04) * (0.5 + edge * 0.5) *
          (0.7 + lit * 0.3);
      canvas.drawCircle(
        at,
        0.9 + rng.nextDouble() * 1.1,
        Paint()..color = AppBrand.mascotGoldLit.withValues(alpha: a),
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