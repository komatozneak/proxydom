import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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

/// The lockup: the word, then the mark that carries the second half of the name.
///
/// The two are one mark, so they are laid out as one. That means three things.
///
/// First, scale. The word is fitted to the letters inside the house: its cap
/// height is set to the height of DOM. At its own size it drew caps a third
/// taller than the knockout letters beside it, and two sizes of type standing on
/// one line is what made the pair read as a name and an illustration parked
/// after it.
///
/// Second, the line. DOM's centre lands at 59.33% of the house's height — the
/// body of a house sits low, the roof does not — while the cap centre is only
/// 0.044 em above the middle of the text box (Onest, measured through
/// TextPainter: a 1.5 em box, the baseline at 1.0825 em, caps at 0.753 em). Both
/// terms are in [wordDrop], so the two bands meet whatever size the mark is.
///
/// Third, the direction. The word moves, not the house. The house is asked to
/// fill the height of the frame it sits in, and lifting the mark to meet the word
/// would push it out of that frame — so the word drops onto the line DOM is on.
class ProxyDomLockup extends StatelessWidget {
  const ProxyDomLockup({
    super.key,
    required this.ink,
    required this.label,
    this.size = 40,
    this.wordSize,
  });

  final Color ink;
  final String label;

  /// Height of the house. Everything else in the lockup follows from it.
  final double size;

  /// Overrides the fitted word size. Null — the usual case — fits the word to the
  /// letters inside the house.
  final double? wordSize;

  /// Where DOM sits in the drawing: its centre as a fraction of the height, and
  /// its own height as a fraction of it. Both are read off logo_mark_word.svg,
  /// where the letters run from y 116.72 to y 214.34 of a 279-unit viewBox.
  static const double _domCentre = 0.5933;
  static const double _domHeight = 0.3499;

  /// Onest's own numbers: caps at 0.753 em, and a cap centre that rides 0.044 em
  /// above the middle of the text box.
  static const double _capHeight = 0.753;
  static const double _capRise = 0.044;

  /// The word size actually used: the fitted one, unless [wordSize] overrides it.
  double get fittedWordSize => wordSize ?? size * _domHeight / _capHeight;

  /// Word space in the lockup, scaled off the mark so it holds at any size.
  /// Wider than a normal word space on purpose: the house's left wall sits at
  /// the vertical middle of the lockup, which is exactly where the word ends, so
  /// a tight gap reads as the last letter touching the house.
  double get gap => size * 0.14;

  /// How far the word sits below the centred axis to meet DOM's centre.
  double get wordDrop =>
      size * (_domCentre - 0.5) + fittedWordSize * _capRise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontSize = fittedWordSize;
    final word = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium?.copyWith(
        color: ink,
        // The wordmark carries the weight the monogram used to: the mark sits
        // beside it now, not before it.
        fontWeight: FontWeight.w800,
        // Tracking in em, not px: at 40px the mark, 0.04 em is what the word
        // looked like at 15px, and a fixed -0.6 would open it up as the type grows.
        letterSpacing: fontSize * -0.04,
        fontSize: fontSize,
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Transform.translate(
            offset: Offset(0, wordDrop),
            child: word,
          ),
        ),
        SizedBox(width: gap),
        ProxyDomMark(size: size, ink: ink),
      ],
    );
  }
}