import 'package:flutter/material.dart';

import '../theme.dart';

/// The brand, drawn in code: the app icon and the desktop lockup.
///
/// Both are pixel drawings, so they are painted from their cells rather than
/// from images — they stay sharp at every size, they take the theme's colours,
/// and the lockup spells the app title in whatever language the app is in.
/// The launcher PNGs are printed from these same widgets by
/// `tool/bake_brand_icons.dart`, so the icon on the home screen and the icon
/// in the window cannot drift apart.

// ── The icon ────────────────────────────────────────────────────────────────

/// The app icon: a pixel key standing in front of the outline of a house —
/// a stepped roof with its chimney, and the house's corners as brackets.
///
/// Laid out on a 100×100 field; [size] scales it.
class ProxyDomKeyIcon extends StatelessWidget {
  const ProxyDomKeyIcon({
    super.key,
    this.size = 32,
    this.tile = true,
    this.dark,
  });

  final double size;

  /// Draw the rounded tile behind the mark. Off, the mark stands on whatever
  /// is behind it — the caption, the rail.
  final bool tile;

  /// Which palette: the dark tile with a light key, or the reverse. Null
  /// follows the theme.
  final bool? dark;

  @override
  Widget build(BuildContext context) {
    final night = dark ?? Theme.of(context).brightness == Brightness.dark;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: KeyIconPainter(
          tile: tile ? (night ? AppBrand.inkLight : AppBrand.inkDark) : null,
          key: night ? AppBrand.inkDark : AppBrand.inkLight,
          frame: AppBrand.mascotGold,
        ),
      ),
    );
  }
}

/// Paints [ProxyDomKeyIcon]. Public so the launcher bake can drive it directly.
class KeyIconPainter extends CustomPainter {
  KeyIconPainter({required this.tile, required this.key, required this.frame});

  final Color? tile;
  final Color key;
  final Color frame;

  /// The key, top to bottom: ring, collar, blade with its bitting.
  static const List<String> keyCells = [
    '..####..',
    '.######.',
    '##....##',
    '##....##',
    '##....##',
    '##....##',
    '.######.',
    '..####..',
    '..####..',
    '.######.',
    '...##...',
    '...##...',
    '...####.',
    '...####.',
    '...##...',
    '...###..',
    '...##...',
    '...####.',
    '...####.',
    '...##...',
    '...#....',
  ];
  static const double cell = 4;
  static const Offset keyOrigin = Offset(34, 10);

  /// Gap between the key and the house behind it.
  static const double gap = 2.2;

  static Path _rect(double l, double t, double r, double b) =>
      Path()..addRect(Rect.fromLTRB(l, t, r, b));

  /// A gable of [steps] stairs, [width] wide at [base] and [height] tall.
  static Path _stairs(
      double cx, double base, double width, double height, int steps) {
    final p = Path();
    final sw = width / 2 / steps, sh = height / steps;
    for (var i = 0; i < steps; i++) {
      p.addRect(Rect.fromLTRB(cx - width / 2 + i * sw, base - (i + 1) * sh,
          cx + width / 2 - i * sw, base - i * sh + 0.01));
    }
    return p;
  }

  static Path keyPath() {
    final p = Path();
    for (var r = 0; r < keyCells.length; r++) {
      for (var c = 0; c < keyCells[r].length; c++) {
        if (keyCells[r][c] == '#') {
          p.addRect(Rect.fromLTWH(keyOrigin.dx + c * cell,
              keyOrigin.dy + r * cell, cell + 0.01, cell + 0.01));
        }
      }
    }
    return p;
  }

  /// The roof outline, the chimney and the corner brackets, minus the room
  /// the key needs: the gap around it and the inside of its ring.
  static Path framePath() {
    const sw = 84 / 2 / 6, sh = 40 / 6;
    const chimneyX = 50 - 42 + 1.5 * sw;
    final outer = Path.combine(PathOperation.union, _stairs(50, 54, 84, 40, 6),
        _rect(chimneyX, 54 - 3.2 * sh, chimneyX + 0.9 * sw, 54 - 1.5 * sh));
    var frame = Path.combine(
        PathOperation.difference, outer, _stairs(50, 54.1, 66, 31, 6));
    for (final b in [
      _rect(17, 84, 20, 94),
      _rect(17, 91, 27, 94),
      _rect(80, 84, 83, 94),
      _rect(73, 91, 83, 94),
    ]) {
      frame = Path.combine(PathOperation.union, frame, b);
    }
    final halo = Path();
    for (var r = 0; r < keyCells.length; r++) {
      for (var c = 0; c < keyCells[r].length; c++) {
        if (keyCells[r][c] == '#') {
          halo.addRRect(RRect.fromRectAndRadius(
              Rect.fromLTWH(keyOrigin.dx + c * cell, keyOrigin.dy + r * cell,
                      cell, cell)
                  .inflate(gap),
              const Radius.circular(gap)));
        }
      }
    }
    frame = Path.combine(PathOperation.difference, frame, halo);
    return Path.combine(
        PathOperation.difference,
        frame,
        _rect(keyOrigin.dx, keyOrigin.dy, keyOrigin.dx + 8 * cell,
            keyOrigin.dy + 8 * cell));
  }

  static final Path _key = keyPath();
  static final Path _frame = framePath();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    if (tile != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(0, 0, 100, 100), const Radius.circular(23)),
        Paint()..color = tile!,
      );
    }
    canvas.drawPath(_frame, Paint()..color = frame);
    canvas.drawPath(_key, Paint()..color = key);
    canvas.restore();
  }

  @override
  bool shouldRepaint(KeyIconPainter old) =>
      old.tile != tile || old.key != key || old.frame != frame;
}

// ── The desktop lockup ──────────────────────────────────────────────────────

/// The desktop lockup: one long key-house. The first word of the app title is
/// cut out of the key's blade, the second out of the house at its end; the
/// house has a low roof, a wide fan window in the eave, a chimney and a lit
/// door, and the blade carries wide bitting along its bottom edge, flush with
/// the ground line of the house.
class ProxyDomLockup extends StatelessWidget {
  const ProxyDomLockup({
    super.key,
    required this.label,
    required this.ink,
    this.height = 56,
    this.door,
  });

  /// The app title, as the user's language spells it: «Прокси Дом», "Proxy Dom".
  final String label;
  final Color ink;
  final double height;

  /// The light in the door. Null takes the mascot gold for the theme.
  final Color? door;

  @override
  Widget build(BuildContext context) {
    final grid = LockupGrid.of(label);
    if (grid == null) {
      // A title the pixel font cannot spell is still the title.
      return Text(label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: ink));
    }
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final cell = grid.cellSize(height, dpr);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        width: cell * grid.columns,
        height: height,
        child: CustomPaint(
          painter: _LockupPainter(
            grid: grid,
            cell: cell,
            top: ((height - cell * grid.rows) / 2 * dpr).roundToDouble() / dpr,
            ink: ink,
            door: door ??
                (dark ? AppBrand.mascotGoldLit : AppBrand.mascotGoldDeep),
          ),
        ),
      ),
    );
  }
}

/// The lockup's cells, built from the title once and cached.
class LockupGrid {
  LockupGrid._(this.cells, this.columns, this.rows);

  /// Cell value per (column, row): 1 metal, 2 light.
  final Map<(int, int), int> cells;
  final int columns;
  final int rows;

  static const int metal = 1;
  static const int light = 2;

  static final Map<String, LockupGrid?> _cache = {};

  /// Null when the title is not two words the pixel font can spell.
  static LockupGrid? of(String label) =>
      _cache.putIfAbsent(label, () => _build(label));

  /// Whole device pixels when that costs little height, so the cells stay sharp.
  double cellSize(double height, double dpr) {
    final exact = height * dpr / rows;
    final snapped = exact.floorToDouble();
    return (snapped >= 1 && snapped / exact >= 0.85 ? snapped : exact) / dpr;
  }

  static const Map<String, List<String>> font = {
    'П': [
      '######',
      '######',
      '##..##',
      '##..##',
      '##..##',
      '##..##',
      '##..##',
      '##..##'
    ],
    'Р': [
      '#####.',
      '######',
      '##..##',
      '##..##',
      '######',
      '#####.',
      '##....',
      '##....'
    ],
    'P': [
      '#####.',
      '######',
      '##..##',
      '##..##',
      '######',
      '#####.',
      '##....',
      '##....'
    ],
    'О': [
      '.####.',
      '######',
      '##..##',
      '##..##',
      '##..##',
      '##..##',
      '######',
      '.####.'
    ],
    'O': [
      '.####.',
      '######',
      '##..##',
      '##..##',
      '##..##',
      '##..##',
      '######',
      '.####.'
    ],
    'К': [
      '##..##',
      '##.##.',
      '####..',
      '###...',
      '###...',
      '####..',
      '##.##.',
      '##..##'
    ],
    'С': [
      '.#####',
      '######',
      '##....',
      '##....',
      '##....',
      '##....',
      '######',
      '.#####'
    ],
    'И': [
      '##..##',
      '##..##',
      '##.###',
      '######',
      '######',
      '###.##',
      '##..##',
      '##..##'
    ],
    'Д': [
      '..####',
      '.#####',
      '.##.##',
      '.##.##',
      '.##.##',
      '.##.##',
      '######',
      '##..##'
    ],
    'М': [
      '##...##',
      '###.###',
      '#######',
      '##.#.##',
      '##...##',
      '##...##',
      '##...##',
      '##...##'
    ],
    'M': [
      '##...##',
      '###.###',
      '#######',
      '##.#.##',
      '##...##',
      '##...##',
      '##...##',
      '##...##'
    ],
    'R': [
      '#####.',
      '######',
      '##..##',
      '##..##',
      '#####.',
      '####..',
      '##.##.',
      '##..##'
    ],
    'X': [
      '##..##',
      '##..##',
      '.####.',
      '..##..',
      '..##..',
      '.####.',
      '##..##',
      '##..##'
    ],
    'Y': [
      '##..##',
      '##..##',
      '##..##',
      '.####.',
      '..##..',
      '..##..',
      '..##..',
      '..##..'
    ],
    'D': [
      '#####.',
      '######',
      '##..##',
      '##..##',
      '##..##',
      '##..##',
      '######',
      '#####.'
    ],
  };

  static const String _bits = '333002200333000220022200';
  static const List<String> _fan = ['.###..###.', '####..####', '####..####'];
  static const List<String> _door = ['.##.', '####', '####'];

  static int _width(String s) =>
      s.split('').fold<int>(0, (w, ch) => w + font[ch]![0].length) +
      s.length -
      1;

  static LockupGrid? _build(String label) {
    final words = label.toUpperCase().trim().split(RegExp(r'\s+'));
    if (words.length != 2 ||
        words.join().split('').any((ch) => !font.containsKey(ch))) {
      return null;
    }
    final word = words[0], houseWord = words[1];
    final cells = <(int, int), int>{};
    void fill(int c0, int c1, int r0, int r1, [int v = metal]) {
      for (var c = c0; c <= c1; c++) {
        for (var r = r0; r <= r1; r++) {
          cells[(c, r)] = v;
        }
      }
    }

    void stamp(List<String> bm, int c0, int r0, int? v) {
      for (var dr = 0; dr < bm.length; dr++) {
        for (var dc = 0; dc < bm[dr].length; dc++) {
          if (bm[dr][dc] != '#') continue;
          if (v == null) {
            cells.remove((c0 + dc, r0 + dr));
          } else {
            cells[(c0 + dc, r0 + dr)] = v;
          }
        }
      }
    }

    void cut(String s, int c0, int r0) {
      var x = c0;
      for (final ch in s.split('')) {
        stamp(font[ch]!, x, r0, null);
        x += font[ch]![0].length + 1;
      }
    }

    const tipPad = 5, endPad = 3, houseH = 19, step = 3, overhang = 2;
    final tw = _width(word);
    final b1 = tipPad + tw + endPad;
    final x0 = b1 + 1;
    const y0 = 13;
    var w = _width(houseWord) + 7;
    w += w % 2;

    // The house: body, a low roof in stairs of three, a chimney below the ridge.
    fill(x0, x0 + w - 1, y0, y0 + houseH - 1);
    var left = x0 - overhang, right = x0 + w - 1 + overhang, row = y0 - 1;
    final starts = <int, int>{};
    while (right - left + 1 >= 2) {
      fill(left, right, row, row);
      starts[row] = left;
      if (right - left + 1 <= 2 * step) break;
      left += step;
      right -= step;
      row--;
    }
    final peak = row;
    final centre = (2 * x0 + w - 1) / 2;
    final top = peak + 3;
    const eave = y0 - 1;
    final c0 = starts[top + 1]! - 2;
    var bottom = top + 1;
    while (starts.containsKey(bottom + 1) && starts[bottom]! > c0) {
      bottom++;
    }
    fill(c0, c0 + 1, top - 1, bottom);
    assert(top + 1 <= eave);

    // The key: blade, its word, a bevelled tip, the bitting.
    const bt = y0 + 4;
    fill(0, b1, bt, bt + 11);
    cut(word, tipPad, bt + 2);
    for (var k = 0; k < 3; k++) {
      for (var r = 0; r < 3 - k; r++) {
        cells.remove((k, bt + r));
      }
    }
    for (var i = 0, c = 2; c < b1 - 2; i++, c++) {
      final d = int.parse(_bits[i % _bits.length]);
      if (d > 0) fill(c, c, bt + 12, bt + 11 + d);
    }

    // The house's word, the fan window cut into the eave, the lit door.
    cut(houseWord, x0 + (w - _width(houseWord)) ~/ 2, bt + 2);
    stamp(_fan, (centre - 4.5).floor(), y0 - 3, null);
    stamp(_door, (centre - 1.5).floor(), y0 + houseH - 4, light);

    // Normalise to the origin.
    var minC = 1 << 30, maxC = -(1 << 30), minR = 1 << 30, maxR = -(1 << 30);
    for (final (c, r) in cells.keys) {
      if (c < minC) minC = c;
      if (c > maxC) maxC = c;
      if (r < minR) minR = r;
      if (r > maxR) maxR = r;
    }
    final out = <(int, int), int>{
      for (final e in cells.entries)
        (e.key.$1 - minC, e.key.$2 - minR): e.value,
    };
    return LockupGrid._(out, maxC - minC + 1, maxR - minR + 1);
  }
}

class _LockupPainter extends CustomPainter {
  _LockupPainter({
    required this.grid,
    required this.cell,
    required this.top,
    required this.ink,
    required this.door,
  });

  final LockupGrid grid;
  final double cell;
  final double top;
  final Color ink;
  final Color door;

  @override
  void paint(Canvas canvas, Size size) {
    // Runs of cells per row go into one path each colour, so the shape is
    // filled as one: cells painted one by one leave hairline seams.
    final metal = Path(), light = Path();
    for (var r = 0; r < grid.rows; r++) {
      var c = 0;
      while (c < grid.columns) {
        final v = grid.cells[(c, r)];
        if (v == null) {
          c++;
          continue;
        }
        var end = c;
        while (grid.cells[(end + 1, r)] == v) {
          end++;
        }
        final run = Rect.fromLTRB(
            c * cell, top + r * cell, (end + 1) * cell, top + (r + 1) * cell);
        if (v == LockupGrid.metal) {
          metal.addRect(run.inflate(cell * 0.01));
        } else {
          light.addRect(run.inflate(cell * 0.04));
        }
        c = end + 1;
      }
    }
    canvas.drawPath(light, Paint()..color = door);
    canvas.drawPath(metal, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_LockupPainter old) =>
      old.grid != grid ||
      old.cell != cell ||
      old.top != top ||
      old.ink != ink ||
      old.door != door;
}
