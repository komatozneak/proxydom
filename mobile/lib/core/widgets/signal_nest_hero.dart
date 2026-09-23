import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'connect_button.dart';

/// Living House connect button — upright glyph + symmetrical nest (ref layout).
///
/// Reference: 8 sparks — 4 moss (inner) + 4 mustard (outer), one pair per
/// quadrant, mirrored H/V. Hub behind house → fly out → shared orbit.
///
/// | State | House | Network |
/// |---|---|---|
/// | disconnected | still, house only | hidden |
/// | connecting | soft seamless hop | nest emerges + orbits |
/// | connected | barely breathes | same nest, calmer |
/// | error | frozen + grey | hidden |
class SignalNestHero extends StatefulWidget {
  const SignalNestHero({
    super.key,
    required this.state,
    this.onTap,
    this.size = 280,
  });

  final TreeState state;
  final VoidCallback? onTap;
  final double size;

  @override
  State<SignalNestHero> createState() => _SignalNestHeroState();
}

class _SignalNestHeroState extends State<SignalNestHero>
    with TickerProviderStateMixin {
  static const _houseAsset = 'assets/brand/connect/s1-flat-launcher.png';

  late final AnimationController _clock;
  late final AnimationController _emerge;
  final Stopwatch _sw = Stopwatch();

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _emerge = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _sw.start();
    _configureMotion(widget.state, animateEmerge: false);
  }

  void _configureMotion(TreeState state, {required bool animateEmerge}) {
    if (!_clock.isAnimating) {
      _clock
        ..duration = const Duration(seconds: 1)
        ..repeat();
    }

    switch (state) {
      case TreeState.disconnected:
        if (animateEmerge) {
          _emerge.reverse();
        } else {
          _emerge.value = 0;
        }
      case TreeState.connecting:
        if (animateEmerge) {
          _emerge.forward(from: _emerge.value);
        } else {
          _emerge.value = 1;
        }
      case TreeState.connected:
        if (_emerge.value < 1) {
          _emerge.forward();
        } else {
          _emerge.value = 1;
        }
      case TreeState.error:
        if (animateEmerge) {
          _emerge.reverse();
        } else {
          _emerge.value = 0;
        }
    }
  }

  @override
  void didUpdateWidget(covariant SignalNestHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _configureMotion(widget.state, animateEmerge: true);
    }
  }

  Future<void> _onTap() async {
    HapticFeedback.lightImpact();
    widget.onTap?.call();
  }

  double get _tSec => _sw.elapsedMilliseconds / 1000.0;

  static ({double sx, double sy, double dy}) _slimeHop(
      double tSec, double amp) {
    final a = amp.clamp(0.0, 1.0);
    final wave = math.sin(tSec * math.pi * 2 / 1.4);
    final lift = math.max(0.0, wave);
    final ground = math.max(0.0, -wave);
    return (
      sx: 1.0 - 0.06 * a * lift + 0.08 * a * ground,
      sy: 1.0 + 0.09 * a * lift - 0.10 * a * ground,
      dy: -lift * lift * (11.0 * a),
    );
  }

  ({double sx, double sy, double dy}) _housePose() {
    final t = _tSec;
    switch (widget.state) {
      case TreeState.disconnected:
        final p = 1.0 + 0.005 * (0.5 + 0.5 * math.sin(t * math.pi * 2 / 3.6));
        return (sx: p, sy: p, dy: 0);
      case TreeState.connecting:
        return _slimeHop(t, 0.45);
      case TreeState.connected:
        final p = 1.0 + 0.010 * (0.5 + 0.5 * math.sin(t * math.pi * 2 / 2.8));
        return (sx: p, sy: p, dy: 0);
      case TreeState.error:
        final p = 1.0 + 0.005 * (0.5 + 0.5 * math.sin(t * math.pi * 2 / 3.6));
        return (sx: p, sy: p, dy: 0);
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _emerge.dispose();
    _sw.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glyph = widget.size * 0.85;
    final showNet = widget.state == TreeState.connecting ||
        widget.state == TreeState.connected;
    final isError = widget.state == TreeState.error;

    return Semantics(
      button: true,
      label: 'Teremok connect',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: Listenable.merge([_clock, _emerge]),
            builder: (context, _) {
              final pose = _housePose();
              Widget house = Image.asset(
                _houseAsset,
                width: glyph,
                height: glyph,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => CustomPaint(
                  size: Size.square(glyph),
                  painter: SignalNestPainter(
                    state: widget.state,
                    emitProgress: 0,
                  ),
                ),
              );

              if (isError) {
                house = ColorFiltered(
                  colorFilter: const ColorFilter.matrix(<double>[
                    0.2126,
                    0.7152,
                    0.0722,
                    0,
                    0,
                    0.2126,
                    0.7152,
                    0.0722,
                    0,
                    0,
                    0.2126,
                    0.7152,
                    0.0722,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0.92,
                    0,
                  ]),
                  child: house,
                );
              }

              return Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  if (showNet && _emerge.value > 0.01)
                    CustomPaint(
                      size: Size.square(widget.size),
                      painter: _RefSymNetPainter(
                        tSec: _tSec,
                        emerge: Curves.easeOutCubic.transform(_emerge.value),
                        energetic: widget.state == TreeState.connecting,
                      ),
                    ),
                  Transform.translate(
                    offset: Offset(0, pose.dy),
                    child: Transform(
                      alignment: Alignment.bottomCenter,
                      transform: Matrix4.diagonal3Values(pose.sx, pose.sy, 1),
                      child: house,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Reference nest: 8 sparks on a shared circle (not a square).
///
/// Hub behind house → soft radial spokes → sparks on one orbit.
/// No chord polygons (those read as a square). Soft oval guide only.
class _RefSymNetPainter extends CustomPainter {
  _RefSymNetPainter({
    required this.tSec,
    required this.emerge,
    required this.energetic,
  });

  final double tSec;
  final double emerge;
  final bool energetic;

  static const int sparkCount = 8;
  static const Color _moss = Color(0xFF7A9B6A);
  static const Color _mustard = Color(0xFFC78F29);
  static const Color _honey = Color(0xFFE8A838);

  @override
  void paint(Canvas canvas, Size size) {
    if (emerge < 0.01) return;

    final hub = Offset(size.width * 0.5, size.height * 0.52);
    final orbitR = size.width * 0.47;
    final ellipseY = 0.90;

    // Rigid-body spin — seamless, keeps equal spacing.
    final spin = tSec * (energetic ? 0.50 : 0.30);
    final pulse = 1.0 + 0.035 * math.sin(tSec * math.pi * 2 / 2.4);
    final r = orbitR * emerge * pulse;

    final nodes = <Offset>[];
    for (var i = 0; i < sparkCount; i++) {
      // Even 45° slots — circle, not diamond corners.
      final ang = -math.pi / 2 + (i / sparkCount) * math.pi * 2 + spin;
      nodes.add(Offset(
        hub.dx + math.cos(ang) * r,
        hub.dy + math.sin(ang) * r * ellipseY,
      ));
    }

    // Hub behind house.
    final hubGlow = 0.6 + 0.4 * (0.5 + 0.5 * math.sin(tSec * 2.2));
    canvas.drawCircle(
      hub,
      size.width * 0.020 * hubGlow,
      Paint()
        ..color = _mustard.withValues(alpha: 0.40 * emerge * hubGlow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
        ..isAntiAlias = true,
    );
    canvas.drawCircle(
      hub,
      size.width * 0.010,
      Paint()
        ..color = _honey.withValues(alpha: 0.88 * emerge)
        ..isAntiAlias = true,
    );

    // Soft circular orbit track (oval) — never a polygon of chords.
    canvas.drawOval(
      Rect.fromCenter(
        center: hub,
        width: r * 2,
        height: r * 2 * ellipseY,
      ),
      Paint()
        ..color = AppBrand.livingHouse.withValues(
          alpha: (energetic ? 0.14 : 0.08) * emerge,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.0055
        ..isAntiAlias = true,
    );

    // Radial spokes hub→spark only (no neighbor edges = no square).
    for (var i = 0; i < sparkCount; i++) {
      final p = nodes[i];
      final color = i.isEven ? _moss : _mustard;
      canvas.drawLine(
        hub,
        p,
        Paint()
          ..color = color.withValues(alpha: (energetic ? 0.20 : 0.11) * emerge)
          ..strokeWidth = size.width * 0.0055
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );

      final phase =
          tSec * (energetic ? 1.55 : 0.95) + i * (math.pi * 2 / sparkCount);
      final t = 0.5 + 0.5 * math.sin(phase);
      final bead = Offset.lerp(hub, p, t)!;
      final glow = math.sin(t * math.pi);
      canvas.drawCircle(
        bead,
        size.width * 0.009 * (0.55 + 0.45 * glow),
        Paint()
          ..color = color.withValues(alpha: (0.22 + 0.48 * glow) * emerge)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6)
          ..isAntiAlias = true,
      );
    }

    for (var i = 0; i < sparkCount; i++) {
      final color = i.isEven ? _moss : _mustard;
      final flicker = 0.74 +
          0.26 *
              (0.5 +
                  0.5 *
                      math.sin(
                        tSec * 2.0 + i * (math.pi * 2 / sparkCount),
                      ));
      final sr = size.width * (energetic ? 0.028 : 0.025) * flicker;
      canvas.drawCircle(
        nodes[i],
        sr,
        Paint()
          ..color = color.withValues(
            alpha: (energetic ? 0.92 : 0.78) * emerge * flicker,
          )
          ..isAntiAlias = true,
      );
      canvas.drawCircle(
        nodes[i],
        sr * 0.30,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.50 * emerge * flicker)
          ..isAntiAlias = true,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RefSymNetPainter oldDelegate) =>
      oldDelegate.tSec != tSec ||
      oldDelegate.emerge != emerge ||
      oldDelegate.energetic != energetic;
}
