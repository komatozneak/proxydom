import 'package:flutter/material.dart';

/// Softens the viewport edges a scroll cuts through.
///
/// A list clips its children at the viewport boundary, so a half-scrolled row
/// leaves a hard-edged strip of type. This mask fades only the edge that has
/// content hidden past it: at rest the first row is whole, and once the list
/// has moved its top edge fades in; the same for the bottom.
class ScrollEdgeFade extends StatefulWidget {
  const ScrollEdgeFade({
    super.key,
    required this.child,
    this.extent = 18,
  });

  final Widget child;

  /// How many logical pixels the fade covers at each edge.
  final double extent;

  @override
  State<ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<ScrollEdgeFade> {
  bool _before = false;
  bool _after = false;

  void _measure(ScrollMetrics metrics) {
    final before = metrics.pixels > 0.5;
    final after = metrics.pixels < metrics.maxScrollExtent - 0.5;
    if (before == _before && after == _after) return;
    if (!mounted) return;
    setState(() {
      _before = before;
      _after = after;
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _measure(notification.metrics);
        return false;
      },
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          _measure(notification.metrics);
          return false;
        },
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          // A fresh closure every build; a method tear-off compares equal, and
          // the mask layer would keep the shader from the edge state before the
          // first scroll.
          shaderCallback: (bounds) => _shader(bounds),
          child: widget.child,
        ),
      ),
    );
  }

  Shader _shader(Rect bounds) {
    if (bounds.height <= 0) {
      return const LinearGradient(
        colors: [Colors.white, Colors.white],
      ).createShader(bounds);
    }
    final fade = widget.extent.clamp(0.0, bounds.height / 2);
    final colors = <Color>[];
    final stops = <double>[];
    if (_before) {
      colors.add(Colors.transparent);
      stops.add(0);
    }
    colors.add(Colors.white);
    stops.add(_before ? fade / bounds.height : 0);
    colors.add(Colors.white);
    stops.add(_after ? 1 - fade / bounds.height : 1);
    if (_after) {
      colors.add(Colors.transparent);
      stops.add(1);
    }
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: colors,
      stops: stops,
    ).createShader(bounds);
  }
}
