import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The DOM mark, drawn rather than loaded.
///
/// The shipped asset is an opaque dark square with a white house in it: on a
/// dark rail the square is a hole, and a colour filter over it is a coin flip
/// because the box is opaque rather than transparent. Drawing the mark is the
/// only way to get what the brand wants — the mascot in one colour with DOM
/// cut out of it — at any size, on any ground.
class ProxyDomMark extends StatelessWidget {
  const ProxyDomMark({
    super.key,
    required this.ink,
    this.size = 26,
  });

  /// The colour the house is painted in. The letters stay whatever is behind.
  final Color ink;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _DomMarkPainter(ink)),
    );
  }
}

class _DomMarkPainter extends CustomPainter {
  const _DomMarkPainter(this.ink);

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    // The house: a gabled roof over a body, filled solid like the mascot rather
    // than outlined — an outline reads as a generic icon, and the mark has to
    // be the same creature as the one on the home screen.
    final w = size.width;
    final h = size.height;
    final roof = Path()
      ..moveTo(w * 0.06, h * 0.54)
      ..lineTo(w * 0.50, h * 0.08)
      ..lineTo(w * 0.94, h * 0.54)
      ..lineTo(w * 0.50, h * 0.40)
      ..close();
    final body = Path()
      ..moveTo(w * 0.16, h * 0.50)
      ..lineTo(w * 0.84, h * 0.50)
      ..lineTo(w * 0.84, h * 0.92)
      ..lineTo(w * 0.16, h * 0.92)
      ..close();

    canvas.drawPath(roof, Paint()..color = ink);
    canvas.drawPath(body, Paint()..color = ink);

    // DOM, cut out of it. A real hole, not a dark fill: the letters take
    // whatever is behind the mark, so the mark belongs to the ground.
    //
    // `BlendMode.clear` on the layer itself wipes the whole layer, so the
    // letters go through as a picture composited with `dstOut` — erase exactly
    // where the glyphs are and nowhere else.
    final text = TextPainter(
      text: TextSpan(
        text: 'DOM',
        style: TextStyle(
          fontFamily: 'Onest',
          fontSize: h * 0.25,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final at = Offset(w * 0.5 - text.width / 2, h * 0.71 - text.height / 2);
    final recorder = ui.PictureRecorder();
    final pictureCanvas = Canvas(recorder);
    text.paint(pictureCanvas, Offset.zero);
    final picture = recorder.endRecording();

    canvas.saveLayer(Offset.zero & size, Paint()..blendMode = BlendMode.dstOut);
    canvas.translate(at.dx, at.dy);
    canvas.drawPicture(picture);
    canvas.restore();
    picture.dispose();
  }

  @override
  bool shouldRepaint(covariant _DomMarkPainter old) => old.ink != ink;
}