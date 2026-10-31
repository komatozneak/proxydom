import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// ============================================================================
/// PROXY DOM CONNECT BUTTON — Signal Nest (CustomPainter)
/// ============================================================================
/// Real motion, painted in code (no animation runtime):
///   1. Idle — muted nest, soft slow pulse
///   2. Tap — house squash, then arcs emit 1→2→3
///   3. Connected — all arcs on, calm faster pulse
///
/// [SignalNestHero] draws the home screen's nest with the same painter.
/// ============================================================================

enum TreeState { disconnected, connecting, connected, error }

class OakTreeButton extends StatefulWidget {
  final TreeState state;
  final VoidCallback? onTap;
  final double size;

  const OakTreeButton({
    super.key,
    required this.state,
    this.onTap,
    this.size = 200,
  });

  @override
  State<OakTreeButton> createState() => _OakTreeButtonState();
}

class _OakTreeButtonState extends State<OakTreeButton>
    with TickerProviderStateMixin {
  late AnimationController _pulse;
  late AnimationController _emit;
  late AnimationController _tap;
  late AnimationController _slime;
  late Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this);
    _pulseScale = const AlwaysStoppedAnimation(1.0);
    _emit = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _tap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    // Minecraft-slime ASMR hop (no spin) — matches SignalNestHero.
    _slime = AnimationController.unbounded(vsync: this);
    _configure(widget.state);
  }

  @override
  void didUpdateWidget(covariant OakTreeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _configure(widget.state);
    }
  }

  void _configure(TreeState state) {
    _slime.stop();
    _slime.value = 0;
    _tap.stop();
    _tap.value = 0;

    switch (state) {
      case TreeState.disconnected:
        _emit.stop();
        _emit.value = 0;
        _pulse.duration = const Duration(milliseconds: 3600);
        _pulseScale = Tween<double>(begin: 1.0, end: 1.006).animate(
          CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
        );
        _pulse.repeat(reverse: true);
      case TreeState.connecting:
        _pulse.stop();
        _pulse.value = 0;
        _pulseScale = const AlwaysStoppedAnimation(1.0);
        _emit
          ..duration = const Duration(milliseconds: 1800)
          ..value = 0
          ..repeat();
        _slime.repeat(
          min: 0,
          max: 1,
          period: const Duration(milliseconds: 1180),
        );
      case TreeState.connected:
        _emit.stop();
        _emit.value = 1;
        _pulse.duration = const Duration(milliseconds: 2800);
        _pulseScale = Tween<double>(begin: 1.0, end: 1.012).animate(
          CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
        );
        _pulse.repeat(reverse: true);
      case TreeState.error:
        _emit.stop();
        _emit.value = 0;
        _pulse.stop();
        _pulse.value = 0;
        _pulseScale = const AlwaysStoppedAnimation(1.0);
    }
  }

  /// Minecraft-slime hop — connecting only. No rotation.
  static ({double sx, double sy, double dy}) _slimePose(double t, double amp) {
    final a = amp.clamp(0.0, 1.0);
    if (a <= 0 || t <= 0) return (sx: 1.0, sy: 1.0, dy: 0.0);

    late final double sx;
    late final double sy;
    late final double hop;

    if (t < 0.14) {
      final u = Curves.easeIn.transform(t / 0.14);
      sx = 1.0 + 0.08 * a * u;
      sy = 1.0 - 0.10 * a * u;
      hop = 0;
    } else if (t < 0.42) {
      final u = Curves.easeOutCubic.transform((t - 0.14) / 0.28);
      sx = (1.0 + 0.08 * a) - 0.14 * a * u;
      sy = (1.0 - 0.10 * a) + 0.18 * a * u;
      hop = math.sin(u * math.pi / 2) * (11.0 * a);
    } else if (t < 0.68) {
      final u = (t - 0.42) / 0.26;
      final rise = math.sin((1.0 - u) * math.pi / 2);
      sx = 1.0 - 0.06 * a + 0.03 * a * u;
      sy = 1.0 + 0.08 * a - 0.05 * a * u;
      hop = rise * (11.0 * a);
    } else if (t < 0.82) {
      final u = Curves.easeOut.transform((t - 0.68) / 0.14);
      sx = 1.0 + 0.10 * a * u;
      sy = 1.0 - 0.12 * a * u;
      hop = 0;
    } else {
      final u = Curves.easeOut.transform((t - 0.82) / 0.18);
      sx = 1.0 + 0.10 * a * (1.0 - u);
      sy = 1.0 - 0.12 * a * (1.0 - u);
      hop = 0;
    }
    return (sx: sx, sy: sy, dy: -hop);
  }

  ({double sx, double sy, double dy}) _pose() {
    switch (widget.state) {
      case TreeState.disconnected:
      case TreeState.connected:
      case TreeState.error:
        final p = _pulseScale.value;
        return (sx: p, sy: p, dy: 0);
      case TreeState.connecting:
        return _slimePose(_slime.value % 1.0, 0.55);
    }
  }

  Future<void> _handleTap() async {
    if (widget.state == TreeState.connecting) return;
    HapticFeedback.lightImpact();
    widget.onTap?.call();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _emit.dispose();
    _tap.dispose();
    _slime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isError = widget.state == TreeState.error;
    return Semantics(
      button: true,
      enabled: widget.onTap != null || widget.state != TreeState.connecting,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.state == TreeState.connecting ? null : _handleTap,
        child: AnimatedBuilder(
          animation: Listenable.merge([_pulse, _emit, _slime]),
          builder: (context, _) {
            final pose = _pose();
            final honey = Theme.of(context).colorScheme.tertiary;
            final fill = switch (widget.state) {
              TreeState.connected =>
                AppBrand.mossWithOpacity(isDark ? 0.18 : 0.10),
              TreeState.connecting =>
                AppBrand.oakWithOpacity(isDark ? 0.22 : 0.08),
              TreeState.disconnected =>
                AppBrand.oakWithOpacity(isDark ? 0.22 : 0.08),
              TreeState.error => AppBrand.oakWithOpacity(isDark ? 0.12 : 0.06),
            };
            final border = switch (widget.state) {
              TreeState.connected => AppBrand.mossWithOpacity(0.40),
              TreeState.connecting => honey.withValues(alpha: 0.55),
              TreeState.disconnected => AppBrand.oakWithOpacity(0.22),
              TreeState.error => AppBrand.oakWithOpacity(0.18),
            };
            Widget body = DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fill,
                border: Border.all(
                  color: border,
                  width: widget.state == TreeState.connecting ? 2 : 1.5,
                ),
              ),
              child: Center(
                child: CustomPaint(
                  size: Size.square(widget.size * 0.72),
                  painter: SignalNestPainter(
                    state: widget.state,
                    emitProgress: _emit.value,
                  ),
                ),
              ),
            );
            if (isError) {
              body = ColorFiltered(
                colorFilter: const ColorFilter.matrix(<double>[
                  0.2126, 0.7152, 0.0722, 0, 0,
                  0.2126, 0.7152, 0.0722, 0, 0,
                  0.2126, 0.7152, 0.0722, 0, 0,
                  0, 0, 0, 0.92, 0,
                ]),
                child: body,
              );
            }
            return SizedBox(
              width: widget.size,
              height: widget.size,
              child: Center(
                child: Transform.translate(
                  offset: Offset(0, pose.dy),
                  child: Transform(
                    alignment: Alignment.bottomCenter,
                    transform: Matrix4.diagonal3Values(pose.sx, pose.sy, 1),
                    child: body,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// House + 3 enveloping arcs (open at bottom). Animated via [emitProgress].
class SignalNestPainter extends CustomPainter {
  SignalNestPainter({
    required this.state,
    required this.emitProgress,
  });

  final TreeState state;
  final double emitProgress;

  // Mustard Living House + moss nest — never teal/cyan (v1/v2 leak).
  static const Color houseLive = AppBrand.livingHouse;
  static const Color arcLive = AppBrand.secondary;
  static const Color houseIdle = AppBrand.livingHouse;
  static const Color arcIdle = AppBrand.primaryContainer;

  @override
  void paint(Canvas canvas, Size size) {
    final grey = state == TreeState.error;
    final live = state == TreeState.connecting || state == TreeState.connected;
    final houseColor = grey
        ? const Color(0xFF8A8680)
        : (live ? houseLive : houseIdle);
    final arcColor = grey
        ? const Color(0xFF6E6A64)
        : (live ? arcLive : arcIdle);

    final cx = size.width * 0.50;
    final cy = size.height * 0.54;
    final houseH = size.height * 0.52;
    final houseW = size.width * 0.44;

    _drawHouse(canvas, Offset(cx, cy), houseW, houseH, houseColor);

    final opacities = _arcOpacities();
    for (var i = 0; i < 3; i++) {
      final o = opacities[i];
      if (o <= 0.01) continue;
      // Slight grow as arc appears (emit feel).
      final grow = 0.92 + 0.08 * o;
      _drawEnvelopingArc(
        canvas,
        center: Offset(cx, cy + houseH * 0.06),
        radius: houseW * (0.78 + i * 0.32) * grow,
        strokeWidth: size.width * (0.055 - i * 0.004),
        color: arcColor.withValues(alpha: o),
      );
    }
  }

  List<double> _arcOpacities() {
    switch (state) {
      case TreeState.disconnected:
        // Quiet nest — no orbit motion (emit frozen at 0).
        return const [0.55, 0.40, 0.28];
      case TreeState.error:
        return const [0.25, 0.18, 0.12];
      case TreeState.connected:
        return const [1.0, 1.0, 1.0];
      case TreeState.connecting:
        final t = emitProgress;
        return [
          _cascade(t, start: 0.00),
          _cascade(t, start: 0.20),
          _cascade(t, start: 0.40),
        ];
    }
  }

  /// Inner→outer appear, hold, soft fade, loop.
  static double _cascade(double t, {required double start}) {
    const rise = 0.18;
    const hold = 0.42;
    var local = t - start;
    if (local < 0) local += 1.0;
    local %= 1.0;
    if (local < rise) return Curves.easeOut.transform(local / rise);
    if (local < rise + hold) return 1.0;
    final fadeT = (local - rise - hold) / (1.0 - rise - hold);
    return (1.0 - Curves.easeIn.transform(fadeT.clamp(0.0, 1.0)))
        .clamp(0.0, 1.0);
  }

  void _drawHouse(
    Canvas canvas,
    Offset center,
    double w,
    double h,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final left = center.dx - w / 2;
    final right = center.dx + w / 2;
    final top = center.dy - h / 2;
    final bottom = center.dy + h / 2;
    final wallTop = top + h * 0.38;
    final r = w * 0.10;

    final path = Path()
      ..moveTo(center.dx, top + h * 0.04)
      ..quadraticBezierTo(
        right - r * 0.2,
        wallTop - h * 0.02,
        right,
        wallTop + r * 0.3,
      )
      ..lineTo(right, bottom - r)
      ..quadraticBezierTo(right, bottom, right - r, bottom)
      ..lineTo(left + r, bottom)
      ..quadraticBezierTo(left, bottom, left, bottom - r)
      ..lineTo(left, wallTop + r * 0.3)
      ..quadraticBezierTo(
        left + r * 0.2,
        wallTop - h * 0.02,
        center.dx,
        top + h * 0.04,
      )
      ..close();
    canvas.drawPath(path, paint);

    final doorPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;
    final doorW = w * 0.22;
    final doorH = h * 0.28;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center.dx, bottom - doorH * 0.55),
          width: doorW,
          height: doorH,
        ),
        Radius.circular(doorW * 0.45),
      ),
      doorPaint,
    );
  }

  void _drawEnvelopingArc(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required double strokeWidth,
    required Color color,
  }) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      155 * math.pi / 180,
      230 * math.pi / 180,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant SignalNestPainter oldDelegate) {
    return oldDelegate.state != state ||
        oldDelegate.emitProgress != emitProgress;
  }
}

class TreeStatusLabel extends StatelessWidget {
  final TreeState state;
  final String label;

  const TreeStatusLabel({
    super.key,
    required this.state,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = switch (state) {
      TreeState.connected => AppBrand.secondary,
      TreeState.connecting => AppBrand.warning,
      TreeState.disconnected => cs.onSurface,
      TreeState.error => AppBrand.destructive,
    };

    return Text(
      label,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            height: 1.15,
          ),
    );
  }
}
