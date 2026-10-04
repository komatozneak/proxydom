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
  final double size;

  static const String asset = 'assets/icon/logo_mark_word.svg';

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
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
/// The two are one mark, so they are laid out as one. That means two things the
/// sidebar never had: a gap small enough to read as a word space rather than a
/// seam, and DOM's centre sitting on the word's cap centre.
///
/// That offset is arithmetic, not taste. DOM's centre lands at 59.3% of the
/// house's height — the body of a house sits low, the roof does not — so a mark
/// centred against the word would hang its letters under the baseline. The cap
/// centre, meanwhile, is not the middle of the text box either: it sits
/// 0.021 em above it, from Onest's own metrics (ascent 0.970, descent 0.305,
/// cap 0.707 — `(asc+desc)/2 - asc + cap/2`). Both terms are in the offset
/// below, so the two centres meet at any size.
class ProxyDomLockup extends StatelessWidget {
  const ProxyDomLockup({
    super.key,
    required this.ink,
    required this.label,
    this.markSize = 30,
    this.fontSize = 17,
  });

  final Color ink;
  final String label;
  final double markSize;
  final double fontSize;

  /// Where DOM's centre sits in the mark box, as a fraction of its height.
  static const double _domCentre = 0.593;

  /// How far the cap centre rises above the middle of the text box, in em.
  /// Onest: (0.970 + 0.305) / 2 - 0.970 + 0.707 / 2.
  static const double _capRise = 0.021;

  /// Word space in the lockup, scaled off the mark so it holds at any size.
  double get _gap => markSize * 0.115;

  double get _markLift => markSize * (_domCentre - 0.5) + fontSize * _capRise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final word = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium?.copyWith(
        color: ink,
        // The wordmark carries the weight the monogram used to: the mark sits
        // beside it now, not before it.
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        fontSize: fontSize,
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(child: word),
        SizedBox(width: _gap),
        Transform.translate(
          offset: Offset(0, -_markLift),
          child: ProxyDomMark(size: markSize, ink: ink),
        ),
      ],
    );
  }
}