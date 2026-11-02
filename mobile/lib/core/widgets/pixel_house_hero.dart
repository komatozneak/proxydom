import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../theme.dart';
import 'connect_button.dart';
import 'pixel_house.dart';

/// One ring of the firefly circle.
@immutable
class PixelHouseRing {
  const PixelHouseRing({
    required this.count,
    required this.rx,
    required this.ry,
    required this.direction,
    required this.speed,
    required this.speedConnecting,
    required this.colors,
  });

  final int count;

  /// Radii as a fraction of the grid: a flat ellipse, so the circle reads as
  /// lying on the ground around the house rather than standing up behind it.
  final double rx;
  final double ry;

  /// 1 or -1: the two rings turn against each other.
  final int direction;
  final double speed;
  final double speedConnecting;
  final List<Color> colors;
}

/// Two rings, against each other, so the lights look like a round dance and
/// not like planets on one rail.
///
/// The radii are larger than the house's half-width and taller than its walls:
/// the house is wide, and a circle tucked inside its silhouette read as dust
/// at the edges instead of a circle. The outer ring reaches past the roof and
/// under the door, so the dance is visible on both halves.
const List<PixelHouseRing> kPixelHouseRings = [
  PixelHouseRing(
    count: 10,
    rx: 0.44,
    ry: 0.27,
    direction: 1,
    speed: 0.30,
    speedConnecting: 0.62,
    colors: [AppBrand.firefly, AppBrand.mascotGoldLit],
  ),
  PixelHouseRing(
    count: 8,
    rx: 0.49,
    ry: 0.42,
    direction: -1,
    speed: 0.18,
    speedConnecting: 0.42,
    colors: [AppBrand.mascotGoldLit, AppBrand.mossLight],
  ),
];

/// What the house is doing. One-to-one with [TreeState], kept apart so the
/// motion model does not have to know about the tunnel.
enum PixelHouseMood { off, connecting, on, error }

/// Everything that moves, as numbers.
///
/// The painter only reads it; the widget only ticks it. Kept public and free
/// of `BuildContext` so the behaviour — the lights go out when the tunnel
/// drops, the gold rises from the door — is testable without pumping a frame.
class PixelHouseMotion {
  PixelHouseMotion(PixelHouseMood mood) : _mood = mood {
    _snap();
  }

  PixelHouseMood _mood;
  PixelHouseMood get mood => _mood;

  /// Seconds of animation. Stops while reduce motion is on.
  double t = 0;

  /// Seconds since the last state change.
  double moodT = 0;

  /// How much of the house is gold: 0 rested, 1 burning.
  double gold = 0;

  /// How lit the fireflies are.
  double lights = 0;

  /// How lit the glow is, before the breath multiplies it.
  double glow = 0;

  /// How lit the door is.
  double door = 0;

  /// How wrong things are: dims the house and makes the lights fall.
  double err = 0;

  /// One lonely firefly, for the resting house.
  double lone = 0;

  /// The glow after the breath: what the painter draws.
  double lit = 0;

  /// The breath of the pixel glow, in whole cells.
  int breathOff = 0;

  double blinkT = 0;
  double press = 0;
  double flash = 0;

  String pose = 'base';
  int lift = 0;

  final List<double> phase = [0, 0];
  final List<double> speed = [0, 0];

  final List<PixelHousePuff> puffs = [];
  double _zClock = 0;
  bool _zBig = false;

  static const Set<PixelHouseMood> _awake = {
    PixelHouseMood.on,
    PixelHouseMood.connecting,
  };

  void _snap() {
    gold = _mood == PixelHouseMood.on
        ? 1
        : _mood == PixelHouseMood.connecting
            ? 0.6
            : 0;
    lights = _awake.contains(_mood) ? 1 : 0;
    glow = lights;
    err = _mood == PixelHouseMood.error ? 1 : 0;
    lone = _mood == PixelHouseMood.off ? 1 : 0;
    door = _mood == PixelHouseMood.on ? 1 : 0;
    lit = glow;
  }

  void setMood(PixelHouseMood next) {
    if (next == _mood) return;
    _mood = next;
    moodT = 0;
    blinkT = 0.14;
  }

  /// A finger landed: the house is pushed in and the door flashes, whatever
  /// the tunnel does next.
  void tap() {
    press = 0.13;
    flash = 0.3;
  }

  void update(double dt, {bool reduced = false}) {
    if (dt <= 0) return;
    moodT += dt;
    if (!reduced) t += dt;
    final time = reduced ? 1.15 : t;
    final on = _mood == PixelHouseMood.on;
    final connecting = _mood == PixelHouseMood.connecting;
    final off = _mood == PixelHouseMood.off;
    final error = _mood == PixelHouseMood.error;

    final goldTarget = on
        ? 1.0
        : connecting
            ? 0.5 + 0.32 * (0.5 + 0.5 * math.sin(2 * math.pi * time / 1.4))
            : 0.0;
    final lightsTarget = (on || connecting) ? 1.0 : 0.0;
    final doorTarget = on
        ? 1.0
        : connecting
            ? ((math.sin(time * 9) + 0.6 * math.sin(time * 5.3)) > 0
                ? 1.0
                : 0.35)
            : 0.0;

    if (reduced) {
      gold = goldTarget;
      lights = lightsTarget;
      glow = lightsTarget;
      err = error ? 1.0 : 0.0;
      lone = off ? 1.0 : 0.0;
      door = doorTarget;
    } else {
      gold = _approach(gold, goldTarget, (goldTarget > gold ? 0.9 : 1.4) * dt);
      lights = _approach(
          lights, lightsTarget, (lightsTarget > lights ? 0.75 : 1.0) * dt);
      glow = _approach(glow, lightsTarget, 1.6 * dt);
      err = _approach(err, error ? 1.0 : 0.0, (error ? 1.1 : 3.0) * dt);
      lone = _approach(lone, off ? 1.0 : 0.0, 0.5 * dt);
      door = _approach(door, doorTarget, 6 * dt);
    }

    for (var k = 0; k < kPixelHouseRings.length; k++) {
      final ring = kPixelHouseRings[k];
      final target = on
          ? ring.speed
          : connecting
              ? ring.speedConnecting
              : off
                  ? 0.08
                  : 0.0;
      speed[k] = _approach(speed[k], target, 0.6 * dt);
      if (!reduced) phase[k] += ring.direction * speed[k] * dt;
    }

    final breath = on
        ? 0.82 + 0.18 * math.sin(2 * math.pi * time / 2.8)
        : connecting
            ? 0.55 + 0.45 * (0.5 + 0.5 * math.sin(2 * math.pi * time / 1.4))
            : 1.0;
    lit = glow * breath;
    breathOff = on
        ? roundHalfUp(1.1 * math.sin(2 * math.pi * time / 2.8))
        : connecting
            ? roundHalfUp(1.6 * math.sin(2 * math.pi * time / 1.4))
            : 0;

    blinkT = math.max(0, blinkT - dt);
    press = math.max(0, press - dt);
    flash = math.max(0, flash - dt);

    // Squash and stretch on the grid: whole rows, never a scale transform, so
    // the cells never land on half a pixel.
    final hop = math.sin(2 * math.pi * time / 1.4);
    final falling = math.cos(2 * math.pi * time / 1.4) < 0;
    var nextPose = 'base';
    var nextLift = 0;
    if (!reduced) {
      if (connecting) {
        nextLift = roundHalfUp(2 * math.max(0, hop));
        nextPose = hop > 0.25
            ? 'tall'
            : (hop > -0.3 && falling)
                ? 'wide'
                : 'base';
      } else if (on) {
        final k = time % 6;
        if (k < 0.12) {
          nextPose = 'wide';
        } else if (k < 0.34) {
          nextPose = 'tall';
          nextLift = 1;
        } else if (k < 0.46) {
          nextPose = 'wide';
        } else {
          nextPose = math.sin(2 * math.pi * time / 2.8) > 0.6 ? 'tall' : 'base';
        }
      } else if (off) {
        nextPose = math.sin(2 * math.pi * time / 3.6) > 0.55 ? 'tall' : 'base';
      } else if (error) {
        nextPose = 'wide';
      }
    } else if (error) {
      nextPose = 'wide';
    }
    if (press > 0) {
      nextPose = 'wide';
      nextLift = 0;
    }
    pose = nextPose;
    lift = nextLift;

    if (reduced) {
      puffs.clear();
      return;
    }
    // Asleep: a small `z`, then a big one, floating up inside the face.
    _zClock += dt;
    if (off && _zClock > 1.05) {
      _zClock = 0;
      _zBig = !_zBig;
      puffs.add(PixelHousePuff(big: _zBig));
    }
    for (final puff in puffs) {
      puff.age += dt;
    }
    puffs.removeWhere((puff) => puff.age >= 3.4 || !off);
  }

  /// Which eye mask to draw, and where the pupils look.
  ({String mask, int look}) eyes(double time) {
    if (blinkT > 0) return (mask: 'blink', look: 0);
    switch (_mood) {
      case PixelHouseMood.on:
        return (mask: 'happy', look: 0);
      case PixelHouseMood.off:
        return (mask: 'sleep', look: 0);
      case PixelHouseMood.error:
        return (mask: 'err', look: 0);
      case PixelHouseMood.connecting:
        if ((time % 2.3) < 0.13) return (mask: 'blink', look: 0);
        final look = (math.sin(time * 1.9) * 1.6).round().clamp(-1, 1);
        return (mask: 'open', look: look);
    }
  }
}

/// The `z` rising out of a sleeping house.
class PixelHousePuff {
  PixelHousePuff({required this.big});

  final bool big;
  double age = 0;
}

double _approach(double value, double target, double step) {
  if (value < target) return math.min(target, value + step);
  return math.max(target, value - step);
}

double _q4(double alpha) => (alpha.clamp(0.0, 1.0) * 4).round() / 4;

const List<String> _lightSizes = ['dot1', 'dot2', 'plus3', 'gem4', 'star5'];

/// The approved look's firefly: a plus with a short fading trail.
const String _lightShape = 'plus3';
const int _trailLength = 2;
const List<double> _trailAlpha = [0.55, 0.32, 0.18, 0.1, 0.05];

const Map<String, List<String>> _lightShapes = {
  'dot1': ['c'],
  'dot2': ['ca', 'aa'],
  'plus3': ['.a.', 'aca', '.a.'],
  'gem4': ['.aa.', 'acca', 'acca', '.aa.'],
  'star5': ['..a..', '.aca.', 'acCca', '.aca.', '..a..'],
};

const List<String> _smallZ = ['###', '..#', '.#.', '###'];
const List<String> _bigZ = ['####', '...#', '..#.', '.#..', '####'];

/// The connect button: a house of cells with a firefly circle around it.
///
/// The whole hero is one grid. The house, the glow, the lights and the sleeping
/// `z` are all placed on it and painted at an integer number of device pixels
/// per cell, so nothing is ever resampled. The one soft layer is the radial
/// haze behind the house, which is air, not an object.
class PixelHouseHero extends StatefulWidget {
  const PixelHouseHero({
    super.key,
    required this.state,
    this.onTap,
    this.size = 300,
  });

  final TreeState state;
  final VoidCallback? onTap;

  /// Side of the square the hero is drawn in. The house fills about three
  /// quarters of it; the rest is the light circle.
  final double size;

  @override
  State<PixelHouseHero> createState() => _PixelHouseHeroState();
}

class _PixelHouseHeroState extends State<PixelHouseHero>
    with SingleTickerProviderStateMixin {
  late final PixelHouse _house;
  late final Map<String, PixelHouse> _poses;
  late final PixelHouseMotion _motion;
  late final Ticker _ticker;
  final _Clock _clock = _Clock();
  Duration _last = Duration.zero;
  bool _reduced = false;
  bool _running = false;

  static const PixelHouseSpec _spec = PixelHouseSpec.organic;

  @override
  void initState() {
    super.initState();
    _house = buildPixelHouse(_spec);
    _poses = {
      'base': _house,
      'tall': buildPixelHouse(_spec, poseDh: 1, poseDw: -2, withEffects: false),
      'wide': buildPixelHouse(_spec, poseDh: -1, poseDw: 2, withEffects: false),
    };
    _motion = PixelHouseMotion(_moodFor(widget.state));
    _ticker = createTicker(_tick);
  }

  PixelHouseMood _moodFor(TreeState state) => switch (state) {
        TreeState.disconnected => PixelHouseMood.off,
        TreeState.connecting => PixelHouseMood.connecting,
        TreeState.connected => PixelHouseMood.on,
        TreeState.error => PixelHouseMood.error,
      };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final changed = reduced != _reduced;
    _reduced = reduced;
    if (changed) {
      _motion.update(0.016, reduced: _reduced);
      _clock.tick();
    }
    _syncTicker();
  }

  void _syncTicker() {
    final shouldRun = !_reduced;
    if (shouldRun && !_running) {
      _last = Duration.zero;
      _ticker.start();
      _running = true;
    } else if (!shouldRun && _running) {
      _ticker.stop();
      _running = false;
    }
  }

  void _tick(Duration elapsed) {
    final dt =
        _last == Duration.zero ? 0.016 : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    // A muted ticker resumes with a jump; a long frame must not teleport the
    // dance, so the step is capped.
    _motion.update(math.min(dt, 0.05), reduced: false);
    _clock.tick();
  }

  @override
  void didUpdateWidget(covariant PixelHouseHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _motion.setMood(_moodFor(widget.state));
      _clock.tick();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  void _handleTap() {
    _motion.tap();
    _clock.tick();
    HapticFeedback.lightImpact();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final goldInk = PixelHouseInk.gold(_spec);
    final fadedInk = PixelHouseInk.faded(_spec, dark: dark);
    return Semantics(
      button: true,
      label: AppL10n.of(context).appTitle,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _PixelHousePainter(
              motion: _motion,
              house: _house,
              poses: _poses,
              spec: _spec,
              goldInk: goldInk,
              fadedInk: fadedInk,
              dark: dark,
              // A paper house on paper, a night house on the night: the haze
              // needs to know which one it is sitting on.
              haze: theme.brightness == Brightness.dark ? 1.35 : 1.0,
              devicePixelRatio: dpr,
              repaint: _clock,
            ),
          ),
        ),
      ),
    );
  }
}

class _Clock extends ChangeNotifier {
  void tick() => notifyListeners();
}

class _PixelHousePainter extends CustomPainter {
  _PixelHousePainter({
    required this.motion,
    required this.house,
    required this.poses,
    required this.spec,
    required this.goldInk,
    required this.fadedInk,
    required this.dark,
    required this.haze,
    required this.devicePixelRatio,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final PixelHouseMotion motion;
  final PixelHouse house;
  final Map<String, PixelHouse> poses;
  final PixelHouseSpec spec;
  final PixelHouseInk goldInk;
  final PixelHouseInk fadedInk;
  final bool dark;
  final double haze;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final n = spec.n;
    final dpr = devicePixelRatio;
    // The cell is a whole number of device pixels, and the grid is centred on
    // a whole pixel too: a half-pixel origin is what makes pixel art look
    // dirty on a phone.
    final cellPx = math.max(1.0, (size.width * dpr / n).floorToDouble());
    final cell = cellPx / dpr;
    final grid = cell * n;
    final left = ((size.width - grid) / 2 * dpr).roundToDouble() / dpr;
    final top = ((size.height - grid) / 2 * dpr).roundToDouble() / dpr;

    Rect at(int x, int y, [int w = 1, int h = 1]) =>
        Rect.fromLTWH(left + x * cell, top + y * cell, w * cell, h * cell);
    void put(Path path, int x, int y) => path.addRect(at(x, y));

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final time = motion.t;
    final glow = motion.lit;

    // 1. The haze. The only layer off the grid: it has to read as air on a
    // paper background, and a stepped one would read as a sticker.
    if (glow > 0.01) {
      final center = Offset(left + house.gx * cell, top + house.gy * cell);
      final radius = n * cell * 0.52;
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              AppBrand.flame.withValues(alpha: 0.20 * glow * haze),
              AppBrand.mascotGold.withValues(alpha: 0.10 * glow * haze),
              AppBrand.mascotGold.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(rect),
      );
    }

    // 2. The pixel glow: stepped bands hugging the silhouette, dithered so the
    // edge of the light is a pattern of cells and not a gradient.
    if (glow > 0.02) {
      final bands = [Path(), Path(), Path()];
      final colors = [
        AppBrand.mascotGoldLit.withValues(alpha: 0.45),
        AppBrand.firefly.withValues(alpha: 0.30),
        AppBrand.flame.withValues(alpha: 0.18),
      ];
      final density = [0.5, 0.25, 0.09];
      final aura = house.aura;
      for (var i = 0; i < aura.length; i += 4) {
        final distance = aura[i + 2] - motion.breathOff;
        final band = distance <= 1.5
            ? 0
            : distance <= 3.5
                ? 1
                : distance <= 6
                    ? 2
                    : -1;
        if (band < 0) continue;
        if (aura[i + 3] < density[band] * glow) {
          put(bands[band], aura[i].toInt(), aura[i + 1].toInt());
        }
      }
      for (var k = 0; k < bands.length; k++) {
        canvas.drawPath(
          bands[k],
          Paint()
            ..color = colors[k]
            ..isAntiAlias = false,
        );
      }
    }

    final doorLit = math.max(motion.door, motion.flash > 0 ? 1.0 : 0.0);

    // 3. The light the door throws on the ground. It does not hop with the
    // house: a floor is where the house stands.
    if (doorLit > 0.05) {
      final spill = Path();
      final rows = [
        (1, 0.5),
        (2, 0.25),
        (3, motion.flash > 0 ? 0.15 : 0.0),
      ];
      for (final (dy, density) in rows) {
        final y = house.door.bottom + dy;
        final half = house.door.width / 2 + dy;
        for (var k = 0; k < half; k++) {
          for (final x in [house.door.left - k, house.door.right + k]) {
            if (!_inside(x, y)) continue;
            if (pixelBayer(x, y) < density * doorLit) put(spill, x, y);
          }
        }
      }
      canvas.drawPath(
        spill,
        Paint()
          ..color = AppBrand.firefly.withValues(alpha: 0.85)
          ..isAntiAlias = false,
      );
    }

    final lights = _lights(time);
    _drawLights(canvas, lights, time: time, front: false, at: at);

    // 4. The house: gold rises row by row from the door while it connects.
    final pose = poses[motion.pose] ?? house;
    final span = pose.bottom - pose.topRow + 1;
    final litStart = pose.bottom - roundHalfUp(motion.gold * span) + 1;
    final lift = -motion.lift;
    final housePaths = <Color, Path>{};
    final cells = pose.cells;
    for (var i = 0; i < cells.length; i += 3) {
      final x = cells[i];
      final y = cells[i + 1];
      final part = PixelHousePart.values[cells[i + 2]];
      final isLit = y >= litStart;
      var color = (isLit ? goldInk : fadedInk).of(part);
      if (isLit &&
          y == litStart &&
          motion.gold < 0.999 &&
          (part == PixelHousePart.body ||
              part == PixelHousePart.lit ||
              part == PixelHousePart.shade)) {
        color = AppBrand.firefly;
      }
      if (part == PixelHousePart.door && doorLit > 0.05) {
        color = motion.flash > 0
            ? AppBrand.lightSource
            : doorLit > 0.6
                ? AppBrand.mascotCream
                : Color.lerp(fadedInk.door, AppBrand.mascotCream, doorLit)!;
      }
      (housePaths[color] ??= Path()).addRect(at(x, y + lift));
    }
    final houseAlpha = motion.err > 0.5 ? 1 - 0.38 * motion.err : 1.0;
    for (final entry in housePaths.entries) {
      canvas.drawPath(
        entry.value,
        Paint()
          ..color = entry.key.withValues(alpha: entry.key.a * houseAlpha)
          ..isAntiAlias = false,
      );
    }

    // 5. The sleeping `z` and the eyes, in one pass on top of the house.
    final face = pose.face;
    final eyePaths = <Color, Path>{};
    for (final puff in motion.puffs) {
      final shape = puff.big ? _bigZ : _smallZ;
      final x = face.right +
          face.offset -
          2 -
          roundHalfUp(puff.age * 1.3) +
          roundHalfUp(math.sin(puff.age * 2.4) * 1.2);
      final y = face.base - 3 - shape.length - roundHalfUp(puff.age * 2.6);
      final alpha = puff.age < 0.2
          ? 0.45
          : puff.age < 1.8
              ? 0.95
              : puff.age < 2.6
                  ? 0.6
                  : 0.3;
      for (var dy = 0; dy < shape.length; dy++) {
        for (var dx = 0; dx < shape[dy].length; dx++) {
          if (shape[dy][dx] != '#') continue;
          final px = x + dx;
          final py = y + dy;
          if (px < 0 || py < 0 || px >= n || py >= n) continue;
          if (pose.faceMask[py * n + px] != 1) continue;
          (eyePaths[fadedInk.eye.withValues(alpha: alpha)] ??= Path())
              .addRect(at(px, py + lift));
        }
      }
    }

    final eyes = motion.eyes(time);
    final mask = pixelEyeMask(spec.eyeSet, eyes.mask);
    final scale = face.scale.round();
    final maskWidth = mask.first.length * scale;
    final maskHeight = mask.length * scale;
    for (final side in const [-1, 1]) {
      var rows = mask;
      if (eyes.mask == 'err' && side == 1) {
        rows = mask.map((row) => row.split('').reversed.join()).toList();
      }
      if (eyes.mask == 'open' && eyes.look != 0) {
        rows = mask
            .map((row) => eyes.look > 0
                ? '.${row.substring(0, row.length - 1)}'
                : '${row.substring(1)}.')
            .toList();
      }
      final x0 = side > 0
          ? face.right + face.offset - maskWidth ~/ 2
          : face.left - face.offset + maskWidth ~/ 2 - maskWidth + 1;
      final y0 = face.base - maskHeight + 1;
      for (var ry = 0; ry < rows.length; ry++) {
        for (var rx = 0; rx < rows[ry].length; rx++) {
          if (rows[ry][rx] != '#') continue;
          for (var a = 0; a < scale; a++) {
            for (var b = 0; b < scale; b++) {
              final y = y0 + ry * scale + a;
              final color = y >= litStart ? goldInk.eye : fadedInk.eye;
              (eyePaths[color] ??= Path())
                  .addRect(at(x0 + rx * scale + b, y + lift));
            }
          }
        }
      }
      // A pupil, or the open eye is a blank white bean. It runs a cell left and
      // right while the tunnel comes up — the one bit of face acting the
      // connecting state gets.
      if (eyes.mask == 'open') {
        final pupil = (litStart <= y0 + 2 * scale ? goldInk : fadedInk).face;
        for (var a = 0; a < 2 * scale; a++) {
          for (var b = 0; b < 2 * scale; b++) {
            (eyePaths[pupil] ??= Path()).addRect(
              at(x0 + (3 + eyes.look) * scale + b, y0 + 2 * scale + a + lift),
            );
          }
        }
      }
    }
    for (final entry in eyePaths.entries) {
      canvas.drawPath(
        entry.value,
        Paint()
          ..color = entry.key.withValues(alpha: entry.key.a * houseAlpha)
          ..isAntiAlias = false,
      );
    }

    _drawLights(
      canvas,
      lights,
      time: time,
      front: true,
      at: at,
    );

    canvas.restore();
  }

  bool _inside(int x, int y) => x >= 0 && y >= 0 && x < spec.n && y < spec.n;

  void _drawLights(
    Canvas canvas,
    List<_Light> lights, {
    required double time,
    required bool front,
    required Rect Function(int x, int y, [int w, int h]) at,
  }) {
    final want = _lightSizes.indexOf(_lightShape);
    for (final light in lights) {
      if (light.front != front) continue;
      final alpha = _q4(light.alpha);
      if (alpha <= 0) continue;
      final depth = light.z > 0.3
          ? 4
          : light.z > -0.35
              ? 2
              : 1;
      final shape = _lightShapes[
          light.lone ? 'dot1' : _lightSizes[math.min(want, depth)]]!;
      final core = Color.lerp(
        light.color,
        AppBrand.mascotCream,
        dark ? 0.6 : 0.75,
      )!;
      final cells = <Color, Path>{};

      void add(Color color, double a, int x, int y) {
        if (!_inside(x, y)) return;
        final quantized = _q4(a);
        if (quantized <= 0) return;
        (cells[color.withValues(alpha: quantized)] ??= Path())
            .addRect(at(x, y));
      }

      void shapeAt(int x, int y) {
        final origin = shape.length ~/ 2;
        for (var dy = 0; dy < shape.length; dy++) {
          for (var dx = 0; dx < shape[dy].length; dx++) {
            final ch = shape[dy][dx];
            if (ch == '.') continue;
            add(
              ch == 'c'
                  ? core
                  : ch == 'C'
                      ? AppBrand.lightSource
                      : light.color,
              alpha,
              x + dx - origin,
              y + dy - origin,
            );
          }
        }
      }

      if (light.lone) {
        for (var j = 3; j >= 1; j--) {
          final point = light.at!(time - j * 0.3);
          add(
            light.color,
            [0.12, 0.25, 0.45][j - 1] * alpha / 0.5,
            point.$1.round(),
            point.$2.round(),
          );
        }
        final point = light.at!(time);
        shapeAt(point.$1.round(), point.$2.round());
      } else {
        List<int> position(double theta) {
          final x = (house.rcx + light.rx * math.cos(theta)).round();
          final y =
              (house.rcy + light.ry * math.sin(theta) + light.fall).round();
          return [x, y];
        }

        final dTheta = 1.5 / math.max(light.rx, 1);
        for (var j = _trailLength; j >= 1; j--) {
          final trail = position(light.theta - light.direction * j * dTheta);
          add(
            light.color,
            _trailAlpha[j - 1] * alpha,
            trail[0],
            trail[1],
          );
        }
        final point = position(light.theta);
        shapeAt(point[0], point[1] - light.hop);
      }

      for (final entry in cells.entries) {
        canvas.drawPath(
          entry.value,
          Paint()
            ..color = entry.key
            ..isAntiAlias = false,
        );
      }
    }
  }

  /// The lights, placed on the same ellipse every frame.
  List<_Light> _lights(double time) {
    final out = <_Light>[];
    if (motion.lights > 0.01) {
      for (var k = 0; k < kPixelHouseRings.length; k++) {
        final ring = kPixelHouseRings[k];
        final spiral = 1 - motion.lights;
        final rx = ring.rx * spec.n * (1 + spiral * 0.9);
        final ry = ring.ry * spec.n * (1 + spiral * 0.9);
        for (var i = 0; i < ring.count; i++) {
          final theta = motion.phase[k] +
              i * 2 * math.pi / ring.count +
              ring.direction * spiral * 2.4;
          final hop = (motion.lights > 0.9 &&
                  motion.err < 0.1 &&
                  math.sin(time * 5.5 - theta * 2 * ring.direction) > 0.55)
              ? 1
              : 0;
          var alpha = motion.lights * (1 - motion.err);
          alpha *= math.sin(time * 3.1 + i * 1.7 + k) > -0.7 ? 1 : 0.6;
          final z = math.sin(theta);
          alpha *= 0.5 + 0.5 * (z + 1) / 2;
          out.add(
            _Light(
              theta: theta,
              rx: rx,
              ry: ry,
              hop: hop,
              fall: motion.err * motion.err * spec.n * 0.35,
              front: z > 0,
              z: z,
              alpha: alpha,
              color: ring.colors[i % ring.colors.length],
              direction: ring.direction,
            ),
          );
        }
      }
    }
    if (motion.lone > 0.01) {
      out.add(
        _Light(
          lone: true,
          at: (tt) => (
            house.rcx + spec.n * 0.36 * math.sin(tt * 0.23),
            house.rcy - spec.n * 0.05 + spec.n * 0.16 * math.sin(tt * 0.37 + 1),
          ),
          alpha: 0.5 * motion.lone,
          color: AppBrand.firefly,
          front: true,
        ),
      );
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _PixelHousePainter old) =>
      old.motion != motion ||
      old.goldInk != goldInk ||
      old.fadedInk != fadedInk ||
      old.devicePixelRatio != devicePixelRatio ||
      old.haze != haze;
}

class _Light {
  _Light({
    required this.alpha,
    required this.color,
    required this.front,
    this.theta = 0,
    this.rx = 0,
    this.ry = 0,
    this.hop = 0,
    this.fall = 0,
    this.z = 0,
    this.direction = 1,
    this.lone = false,
    this.at,
  });

  final double alpha;
  final Color color;
  final bool front;
  final double theta;
  final double rx;
  final double ry;
  final int hop;
  final double fall;
  final double z;
  final int direction;
  final bool lone;
  final (double, double) Function(double time)? at;
}
