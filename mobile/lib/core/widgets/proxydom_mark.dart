import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

/// The DOM mark — the house with DOM cut out of it, plus the door under the O.
///
/// It is traced, not drawn. The hand-painted version that used to live here was
/// a roof triangle over a body rectangle with `BlendMode.dstOut` glyphs: it had
/// no door, its corners were hard, and at any size past a favicon it read as a
/// generic house icon rather than as the mascot. `tool/build_logo_mark.py`
/// traces the same contour the landing paints as a CSS mask, from the same
/// source icon, so the window header and the website header are one drawing.
class ProxyDomMark extends StatelessWidget {
  const ProxyDomMark({
    super.key,
    required this.ink,
    this.size = 26,
  });

  /// The colour the house is painted in. The letters and the door stay whatever
  /// is behind the mark, so it belongs to whatever ground it sits on.
  final Color ink;

  /// Height of the drawing, in logical pixels — not the side of a square box.
  /// The file's viewBox is 299x279, so a square box letterboxes the house into
  /// 93% of its own height and the mark comes out smaller than the frame it was
  /// asked to fill. Sizing by height is what lets the lockup take a whole band.
  final double size;

  static const String asset = 'assets/icon/logo_mark_word.svg';

  /// The file's own proportions, from the viewBox `tool/build_logo_mark.py`
  /// writes. `test/proxydom_mark_test.dart` reads the SVG back, so the two cannot
  /// drift apart without a test going red.
  static const double aspect = 299 / 279;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * aspect,
      height: size,
      child: SvgPicture.asset(
        asset,
        // The file is a mask: everything opaque stays, so the knockouts are
        // transparent pixels. Recolouring therefore means tinting the alpha,
        // which leaves those holes exactly as they are.
        colorFilter: ColorFilter.mode(ink, BlendMode.srcIn),
      ),
    );
  }
}

/// The lockup: one building, with the word cut out of a wing built onto the
/// house.
///
/// The word does not stand next to the mascot; it is part of it. A long, low
/// wing runs out of the house's left wall at the height of the walls, and the
/// word is knocked out of that wing the way DOM is knocked out of the house.
/// Read left to right it is one sign — ПРОКСИ DOM — while the house keeps its
/// chimney, its ridge and its door, so the silhouette is still the mascot's.
///
/// Everything is measured in the house's own units (the 299x279 viewBox) and
/// scaled by [size], so the wing and the word cannot drift off the house as the
/// lockup grows.
class ProxyDomLockup extends StatelessWidget {
  const ProxyDomLockup({
    super.key,
    required this.ink,
    required this.label,
    this.door,
    this.size = 40,
  });

  /// The colour of the building. The letters are holes in it.
  final Color ink;

  /// The first half of the name. Set in capitals: inside the wing it is a sign,
  /// and DOM beside it is in capitals too.
  final String label;

  /// The light in the door. Null takes the mascot gold for the current theme.
  final Color? door;

  /// Height of the house. Everything else in the lockup follows from it.
  final double size;

  /// DOM in the traced drawing: its letters run from y 116.72 to y 214.34, and
  /// its D starts at x 36. The word in the wing stands on the same line.
  static const double domTop = 116.72;
  static const double domBottom = 214.34;
  static const double domLeft = 36;

  /// Onest's caps are 0.753 em.
  static const double _capHeight = 0.753;

  /// The drawing's height in its own units.
  static const double _units = 279;

  /// The wing's roof. It meets the house's left roof slope just under the
  /// chimney, so the two outlines run into each other instead of stacking.
  static const double wingTop = 104;

  /// The wing's right edge: inside the house's left wall, which the wing has to
  /// reach to make one silhouette, and short of the D, whose left side it would
  /// otherwise fill.
  static const double wingRight = 34;

  /// Rounded like the house's own corners.
  static const double _wingRadius = 34;

  /// Air around the word, as a fraction of the house's height: the same where
  /// the wing ends on the left and between the word and the D.
  static const double _air = 0.21;

  /// The word size: caps exactly as tall as DOM, so the two halves of the name
  /// are one line of type.
  double get fittedWordSize =>
      size * (domBottom - domTop) / _units / _capHeight;

  /// Lays the word out and says where everything goes, in logical pixels.
  LockupGeometry geometry(BuildContext context) {
    final base = Theme.of(context).textTheme.titleMedium ?? const TextStyle();
    final fontSize = fittedWordSize;
    final style = base.copyWith(
      fontWeight: FontWeight.w800,
      fontSize: fontSize,
      // Tracking in em so it holds at every size; a touch tight, because the
      // letters are holes and holes read wider than ink.
      letterSpacing: fontSize * -0.02,
      height: 1,
    );
    final word = label.toUpperCase();
    final painter = TextPainter(
      text: TextSpan(text: word, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final scale = size / _units;
    final air = size * _air;
    // Worked out from the house's origin, then everything moves right by the
    // wing so the lockup's own box starts at zero.
    final wordRight = domLeft * scale - air;
    final wordLeft = wordRight - painter.width;
    final houseLeft = -(wordLeft - air);
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    return LockupGeometry(
      word: word,
      style: style,
      wordSize: painter.size,
      wordOffset: Offset(houseLeft + wordLeft, domBottom * scale - baseline),
      houseLeft: houseLeft,
      width: houseLeft + size * ProxyDomMark.aspect,
      scale: scale,
    );
  }

  @override
  Widget build(BuildContext context) {
    final geo = geometry(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final light =
        door ?? (dark ? AppBrand.mascotGoldLit : AppBrand.mascotGoldDeep);
    return Semantics(
      label: '$label DOM',
      excludeSemantics: true,
      child: SizedBox(
        width: geo.width,
        height: size,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _WingPainter(geo: geo, ink: ink, door: light),
              ),
            ),
            Positioned(
              left: geo.houseLeft,
              top: 0,
              child: ProxyDomMark(size: size, ink: ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where the lockup's parts land, in logical pixels.
class LockupGeometry {
  const LockupGeometry({
    required this.word,
    required this.style,
    required this.wordSize,
    required this.wordOffset,
    required this.houseLeft,
    required this.width,
    required this.scale,
  });

  /// The word as it is cut, already in capitals.
  final String word;
  final TextStyle style;
  final Size wordSize;

  /// Top-left of the word's box.
  final Offset wordOffset;

  /// Where the house's own box starts.
  final double houseLeft;

  /// The whole lockup.
  final double width;

  /// Logical pixels per unit of the traced drawing.
  final double scale;

  /// Maps a point of the drawing's viewBox into the lockup.
  Offset house(double x, double y) => Offset(houseLeft + x * scale, y * scale);

  double get wingTop => house(0, ProxyDomLockup.wingTop).dy;
  double get wingRight => house(ProxyDomLockup.wingRight, 0).dx;

  Rect get wordRect => wordOffset & wordSize;
}

class _WingPainter extends CustomPainter {
  _WingPainter({required this.geo, required this.ink, required this.door});

  final LockupGeometry geo;
  final Color ink;
  final Color door;

  @override
  void paint(Canvas canvas, Size size) {
    final h = geo.house;
    final r = ProxyDomLockup._wingRadius * geo.scale;
    final top = geo.wingTop;
    final bottom = size.height;
    // The house's bottom-left corner is rounded, so a square wing would leave a
    // notch between the two. The wing's foot runs out under that curve and is
    // hidden by the house everywhere else.
    final wing = Path()
      ..moveTo(r, top)
      ..lineTo(geo.wingRight, top)
      ..lineTo(geo.wingRight, h(0, 255).dy)
      ..lineTo(h(72, 0).dx, bottom)
      ..lineTo(r, bottom)
      ..arcToPoint(Offset(0, bottom - r), radius: Radius.circular(r))
      ..lineTo(0, top + r)
      ..arcToPoint(Offset(r, top), radius: Radius.circular(r))
      ..close();

    // The word is a hole, not paint in the ground's colour, so it is cut inside
    // a layer of its own: whatever is behind the lockup shows through it.
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawPath(wing, Paint()..color = ink);
    TextPainter(
      text: TextSpan(
        text: geo.word,
        style: geo.style.copyWith(
          foreground: Paint()..blendMode = BlendMode.dstOut,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )
      ..layout()
      ..paint(canvas, geo.wordOffset);
    canvas.restore();

    // The door is a notch in the traced house. The light goes behind it, a
    // little larger than the notch, and the house paints over all of it but the
    // opening — so it can never leak past the doorframe. The box stays clear of
    // the O above and the D and M either side.
    canvas.drawRect(
      Rect.fromPoints(h(122, 228), h(176, 278.5)),
      Paint()..color = door,
    );
  }

  @override
  bool shouldRepaint(_WingPainter old) =>
      old.ink != ink ||
      old.door != door ||
      old.geo.word != geo.word ||
      old.geo.style != geo.style ||
      old.geo.width != geo.width;
}
