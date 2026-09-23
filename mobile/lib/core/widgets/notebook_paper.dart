import 'package:flutter/material.dart';

import '../theme.dart';

/// Soft school-grid sheet in the house palette. One quiet margin rule.
class NotebookPaper extends StatelessWidget {
  const NotebookPaper({
    super.key,
    required this.child,
    this.emphasized = false,
  });

  final Widget child;

  /// Bottom bar: same sheet, less blur, stronger lines.
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      painter: _NotebookPaperPainter(
        paper: dark ? AppBrand.paperDark : AppBrand.paperLight,
        grid: dark ? AppBrand.paperGrid : AppBrand.paperGridLight,
        margin: AppBrand.paperMargin,
        emphasized: emphasized,
        dark: dark,
      ),
      child: child,
    );
  }
}

class _NotebookPaperPainter extends CustomPainter {
  const _NotebookPaperPainter({
    required this.paper,
    required this.grid,
    required this.margin,
    required this.emphasized,
    required this.dark,
  });

  final Color paper;
  final Color grid;
  final Color margin;
  final bool emphasized;
  final bool dark;

  static const double _cell = 28;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = paper);

    final gridAlpha = emphasized ? (dark ? 0.24 : 0.62) : (dark ? 0.12 : 0.40);
    final gridBlur = emphasized ? 0.7 : 2.2;
    final gridPaint = Paint()
      ..color = grid.withValues(alpha: gridAlpha)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, gridBlur);

    for (var x = _cell; x < size.width; x += _cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = _cell; y < size.height; y += _cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final marginAlpha =
        emphasized ? (dark ? 0.58 : 0.72) : (dark ? 0.34 : 0.5);
    final marginPaint = Paint()
      ..color = margin.withValues(alpha: marginAlpha)
      ..strokeWidth = emphasized ? 2.6 : 2.2
      ..style = PaintingStyle.stroke
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        emphasized ? 0.8 : 1.5,
      );
    const marginX = 22.0;
    canvas.drawLine(
      const Offset(marginX, 0),
      Offset(marginX, size.height),
      marginPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _NotebookPaperPainter oldDelegate) {
    return oldDelegate.paper != paper ||
        oldDelegate.grid != grid ||
        oldDelegate.margin != margin ||
        oldDelegate.emphasized != emphasized ||
        oldDelegate.dark != dark;
  }
}
