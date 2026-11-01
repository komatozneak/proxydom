import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/widgets/proxydom_ground.dart';

/// The yard animates forever; whatever sits on it must not be repainted with
/// it. When it was, every frame of the ground repainted the whole app.
void main() {
  testWidgets('the app on the ground is not repainted by the ground clock', (
    tester,
  ) async {
    final counter = _CountingPainter();
    final glow = GroundGlow();
    await tester.pumpWidget(
      MaterialApp(
        home: ProxydomGround(
          state: glow,
          child: CustomPaint(painter: counter, size: const Size(200, 200)),
        ),
      ),
    );
    final afterFirstFrame = counter.paints;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(counter.paints, afterFirstFrame);
    glow.dispose();
  });
}

class _CountingPainter extends CustomPainter {
  int paints = 0;

  @override
  void paint(Canvas canvas, Size size) => paints++;

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
