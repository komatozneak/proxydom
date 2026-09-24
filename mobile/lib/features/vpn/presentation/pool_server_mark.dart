import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../data/subscription_label.dart';

/// Rounded tile: red YouTube play, green gamepad, or a flag emoji.
class PoolServerMark extends StatelessWidget {
  const PoolServerMark({super.key, required this.label});

  final PoolServerLabel label;

  @override
  Widget build(BuildContext context) {
    final color = switch (label.tile) {
      PoolTile.youtube => AppBrand.youtubePlay,
      PoolTile.gaming => AppBrand.secondary,
      PoolTile.flag => Theme.of(context).colorScheme.surfaceContainerHighest,
    };
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: switch (label.tile) {
        PoolTile.youtube => const CustomPaint(
            size: Size(18, 14),
            painter: _PlayPainter(),
          ),
        PoolTile.gaming => const Text('🎮', style: TextStyle(fontSize: 20)),
        PoolTile.flag => Text(
            label.flag.isEmpty ? '🌐' : label.flag,
            style: const TextStyle(fontSize: 22),
          ),
      },
    );
  }
}

class _PlayPainter extends CustomPainter {
  const _PlayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = AppBrand.surfaceElevatedLight);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
