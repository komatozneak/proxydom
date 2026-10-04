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

/// The yard on its own, for a route that lives outside the shell.
///
/// A pushed screen — import, QR, onboarding — has no shell above it, so
/// nothing paints behind its cards. In the dark theme that reads as "night",
/// which is why it went unnoticed; in the light theme it left dark ink on a
/// black window, and the title of the screen could not be read at all. This
/// gives such a screen the same ground the shell has, with the house out of
/// frame: no glow to publish, so the painter draws the quiet yard.
class NightBackdrop extends StatefulWidget {
  const NightBackdrop({super.key, required this.child, this.seed = 7});

  final Widget child;
  final int seed;

  @override
  State<NightBackdrop> createState() => _NightBackdropState();
}

class _NightBackdropState extends State<NightBackdrop> {
  final GroundGlow _glow = GroundGlow();

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GroundGlowScope(
      notifier: _glow,
      child: ProxydomGround(
        state: _glow,
        seed: widget.seed,
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
    required this.night,  })  : _lit = state.value,
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
      // The yard, seen from inside a lit room: a pool of light on the ground and
      // two banks of slow mist crossing it. Nothing is drawn that has an edge —
      // a line, a board or a dot at this scale is noise behind the words, and
      // noise is what the words must not fight.
      final floor = Offset(
        house.dx + p.dx * 18,
        size.height * 0.72 + p.dy * 10,
      );
      _lightPool(canvas, size, floor, lit);
      _mist(canvas, size, p * 26, lit, clock.value, seed);
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

  /// Two banks of mist crossing the yard, and nothing else.
  ///
  /// The boards and the dust were detail: at this scale a line is a line and a
  /// dot is a dot, and behind a screen full of words they are noise. Mist has
  /// no edge, so it moves without ever being something to read.
  void _mist(
    Canvas canvas,
    Size size,
    Offset shift,
    double lit,
    double t,
    int seedField,
  ) {
    for (var bank = 0; bank < 2; bank++) {
      // Each bank takes a minute and a half to cross, in opposite directions.
      final dir = bank.isEven ? 1.0 : -1.0;
      final phase = (t * 0.11 * dir + bank * 0.5 + seedField * 0.13) % 1.0;
      final x = -0.3 + phase * 1.6 + shift.dx * (0.6 + bank * 0.5);
      final y = size.height * (0.42 + bank * 0.22) + shift.dy * 8;
      final w = size.width * (0.95 + bank * 0.35);
      final h = size.height * (0.30 + bank * 0.12);
      // Fades in at one edge and out at the other: a bank crossing the screen
      // would be a wipe, not weather.
      final a = math.sin(phase * math.pi).abs() * (0.030 + lit * 0.016);
      canvas.save();
      canvas.translate(x * size.width, y);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: w,
          height: h,
        ),
        Paint()
          ..shader = RadialGradient(
            colors: [
              AppBrand.forestShade.withValues(alpha: a),
              AppBrand.mascotEmber.withValues(alpha: a * 0.5),
              AppBrand.forestShade.withValues(alpha: 0.0),
            ],
            stops: const [0, 0.5, 1],
          ).createShader(
            Rect.fromCenter(center: Offset.zero, width: w, height: h),
          ),
      );
      canvas.restore();
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
