/// The living house as cells, not as a picture.
///
/// The lockup in `proxydom_brand.dart` is already built out of cells, so the
/// mascot is built the same way: same cell, same stepped silhouette, same
/// palette tokens. A bitmap mascot would need a new export for every state
/// (asleep, awake, fading) and would drift from the logo the first time either
/// was redrawn; here the house and the logo cannot disagree.
///
/// Colours are `AppBrand` tokens only, so the house follows the theme.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme.dart';

/// What a cell of the house is: a wall, a lit edge, the face, the door.
enum PixelHousePart { none, body, lit, shade, face, faceDeep, door, outline }

/// The shape of the home, as numbers.
///
/// One look is shipped — [PixelHouseSpec.organic] — but the numbers stay
/// exposed: the silhouette came out of a design pass with a dozen variants and
/// the next pass should not have to start from Dart code again.
@immutable
class PixelHouseSpec {
  const PixelHouseSpec({
    required this.n,
    required this.bodyW,
    required this.bodyH,
    required this.roofH,
    required this.ridge,
    required this.overhang,
    required this.roofPow,
    required this.roofStep,
    required this.flare,
    required this.taper,
    required this.bulge,
    required this.baseRound,
    required this.lean,
    required this.chimW,
    required this.chimH,
    required this.chimTilt,
    required this.chimIn,
    required this.chimneyAt,
    required this.chimCap,
    required this.droop,
    required this.ybot,
    required this.faceTopF,
    required this.faceBotF,
    required this.faceWF,
    required this.faceApex,
    required this.faceStep,
    required this.facePow,
    required this.faceMargin,
    required this.faceRound,
    required this.eyeSet,
    required this.eyeScale,
    required this.eyeLift,
    required this.eyeSpread,
    required this.doorW,
    required this.doorH,
    required this.doorGap,
    required this.shade,
    required this.outline,
    required this.offStyle,
    required this.ringDy,
  });

  /// Grid cells per side. The house is drawn at an integer number of device
  /// pixels per cell, so this is the resolution of the whole hero: the glow,
  /// the light circle and the house share one grid.
  final int n;
  final int bodyW;
  final int bodyH;
  final int roofH;
  final int ridge;
  final int overhang;
  final double roofPow;
  final int roofStep;
  final int flare;
  final int taper;
  final int bulge;
  final int baseRound;
  final int lean;
  final int chimW;
  final int chimH;
  final int chimTilt;
  final int chimIn;
  final double chimneyAt;
  final bool chimCap;

  /// The eave tips sag one row below the wall line: the house looks heavy, and
  /// the corners stop reading as a stepped roof borrowed from the lockup.
  final bool droop;
  final double ybot;
  final double faceTopF;
  final double faceBotF;
  final double faceWF;
  final int faceApex;
  final int faceStep;
  final double facePow;
  final int faceMargin;
  final int faceRound;
  final String eyeSet;
  final double eyeScale;
  final int eyeLift;
  final double eyeSpread;
  final int doorW;
  final int doorH;
  final int doorGap;
  final bool shade;
  final bool outline;

  /// `faded` — gold at rest, washed towards the paper. `ink` — the ink of the
  /// lockup, for a house that belongs to the wordmark more than to the light.
  final String offStyle;
  final double ringDy;

  /// The look signed off for the connect button: a soft, almost hand-drawn
  /// cottage — a convex roof with a drooping eave tip, a tilted capped chimney,
  /// a bulging wall, a rounded base, an arched door and the largest eye set so
  /// the face reads at button size.
  static const PixelHouseSpec organic = PixelHouseSpec(
    n: 54,
    bodyW: 28,
    bodyH: 12,
    roofH: 17,
    ridge: 3,
    overhang: 3,
    roofPow: 0.70,
    roofStep: 1,
    flare: 2,
    taper: 0,
    bulge: 2,
    baseRound: 3,
    lean: 0,
    chimW: 3,
    chimH: 5,
    chimTilt: 1,
    chimIn: 1,
    chimneyAt: 0.36,
    chimCap: true,
    droop: true,
    ybot: 0.74,
    faceTopF: 0.16,
    faceBotF: 0.84,
    faceWF: 0.90,
    faceApex: 3,
    faceStep: 1,
    facePow: 0.55,
    faceMargin: 2,
    faceRound: 2,
    eyeSet: 'xl',
    eyeScale: 1,
    eyeLift: 2,
    eyeSpread: 0.42,
    doorW: 6,
    doorH: 4,
    doorGap: 1,
    shade: true,
    outline: true,
    offStyle: 'faded',
    ringDy: 0.04,
  );
}

/// Where the face sits on the house, in grid cells.
@immutable
class PixelHouseFace {
  const PixelHouseFace({
    required this.base,
    required this.offset,
    required this.scale,
    required this.left,
    required this.right,
  });

  /// Bottom row of the eyes.
  final int base;

  /// Half the distance between the two eyes, from the centre line.
  final int offset;
  final double scale;
  final int left;
  final int right;
}

/// The door, in grid cells: where it stands and how wide it is.
@immutable
class PixelHouseDoor {
  const PixelHouseDoor({
    required this.left,
    required this.right,
    required this.width,
    required this.height,
    required this.bottom,
  });

  final int left;
  final int right;
  final int width;
  final int height;
  final int bottom;
}

/// The chimney's mouth, for the sleep smoke.
@immutable
class PixelHouseChimney {
  const PixelHouseChimney({
    required this.x,
    required this.y,
    required this.width,
  });

  final int x;
  final int y;
  final int width;
}

/// One built house: the cells to paint and the anchors the face, door and the
/// light circle hang off.
///
/// Built once per pose (upright, tall, wide) and reused every frame; [cells] is
/// a flat `x, y, part` list so the painter can walk it without allocating.
class PixelHouse {
  PixelHouse({
    required this.spec,
    required this.cells,
    required this.faceMask,
    required this.occupied,
    required this.aura,
    required this.topRow,
    required this.bottom,
    required this.gx,
    required this.gy,
    required this.rcx,
    required this.rcy,
    required this.face,
    required this.door,
    required this.chimney,
  });

  final PixelHouseSpec spec;

  /// `x, y, PixelHousePart.index` triples.
  final Int32List cells;

  /// Which cells are the dark window. The sleep smoke and the eyes are only
  /// ever drawn inside it, so the `z` cannot drift onto the gold roof.
  final Uint8List faceMask;

  /// Row-major silhouette: every wall, window and door cell. The tap burst
  /// marches out from the centre along each ray until this says empty, so the
  /// sparks leave from the mascot's own edge and not from a guessed radius.
  final Uint8List occupied;

  /// `x, y, distance from the silhouette, Bayer threshold` quads. The distance
  /// is read in bands, so the pixels around the house come out stepped.
  final Float32List aura;

  final int topRow;
  final int bottom;
  final double gx;
  final double gy;

  /// Centre of the light circle: a little below the house centre, so the ring
  /// sits around the walls rather than around the roof.
  final double rcx;
  final double rcy;
  final PixelHouseFace face;
  final PixelHouseDoor door;
  final PixelHouseChimney chimney;

  int get n => spec.n;
}

/// Eye masks. Drawn, never scaled: the arcs stay one cell thick.
const Map<String, List<String>> _eyeSmall = {
  'happy': ['.##.', '#..#'],
  'sleep': ['####'],
  'open': ['.##.', '.##.', '.##.'],
  'blink': ['.##.'],
  'err': ['##..', '..##', '##..'],
};

const Map<String, List<String>> _eyeLarge = {
  'happy': ['.####.', '##..##', '#....#'],
  'sleep': ['##..##', '.####.'],
  'open': ['.####.', '######', '######', '.####.'],
  'blink': ['######'],
  'err': ['##....', '.###..', '...###', '.###..', '##....'],
};

const Map<String, List<String>> _eyeXl = {
  'happy': ['..####..', '.######.', '###..###', '##....##'],
  'sleep': ['##....##', '.######.', '..####..'],
  'open': [
    '..####..',
    '.######.',
    '########',
    '########',
    '.######.',
    '..####..'
  ],
  'blink': ['.######.', '########'],
  'err': ['###.....', '.####...', '...#####', '.####...', '###.....'],
};

const Map<String, int> _eyeWidths = {'small': 4, 'large': 6, 'xl': 8};

/// The eye mask for a set and a mood. Falls back to the largest set.
List<String> pixelEyeMask(String set, String mood) {
  final masks = switch (set) {
    'small' => _eyeSmall,
    'large' => _eyeLarge,
    _ => _eyeXl,
  };
  return masks[mood] ?? masks['happy']!;
}

int pixelEyeWidth(String set) => _eyeWidths[set] ?? 8;

const List<int> _bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];

/// Ordered dithering, 4x4: a threshold in `0..1` per cell, so a density reads
/// as a dot pattern instead of a grey wash.
double pixelBayer(int x, int y) => _bayer[((y & 3) << 2) | (x & 3)] / 16;

/// JavaScript's `Math.round`: halves go up, not away from zero.
int roundHalfUp(double value) => (value + 0.5).floor();

/// A house built from [spec], squashed or stretched about its ground line.
///
/// [poseDh] and [poseDw] are whole cells, so the squash never lands between
/// rows; [withEffects] is off for the pose variants, which only need the cells
/// and the anchors — the glow comes from the upright house.
PixelHouse buildPixelHouse(
  PixelHouseSpec spec, {
  int poseDh = 0,
  int poseDw = 0,
  bool withEffects = true,
}) {
  final n = spec.n;
  final sil = Uint8List(n * n);
  final face = Uint8List(n * n);
  final door = Uint8List(n * n);

  void set(Uint8List cells, int x, int y) {
    if (x < 0 || y < 0 || x >= n || y >= n) return;
    cells[y * n + x] = 1;
  }

  var w = spec.bodyW + poseDw;
  w += w % 2;
  final bodyH = spec.bodyH + poseDh;
  final roofH = spec.roofH;
  final bottom = roundHalfUp(n * spec.ybot);
  final y0 = bottom - bodyH + 1;
  final eave = y0 - 1;
  final peak = eave - roofH + 1;
  final cxL = n ~/ 2 - 1;
  final cxR = n ~/ 2;
  final lean = spec.lean;
  int shift(int r) => roundHalfUp(
        lean * math.max(0, bottom - r) / math.max(1, bottom - peak),
      );

  final half = <int, int>{};
  final ridge = spec.ridge.toDouble();
  final eaveHalf = w / 2 + spec.overhang;
  final step = spec.roofStep;
  for (var r = peak; r <= eave; r++) {
    final u = roofH <= 1 ? 1.0 : (r - peak) / (roofH - 1);
    var h = ridge + (eaveHalf - ridge) * math.pow(u, spec.roofPow);
    if (step > 1) {
      h = ridge + step * roundHalfUp((h - ridge) / step);
    }
    half[r] = roundHalfUp(h);
  }
  // The eave kicks out over two rows, so its tips stay thick rather than
  // opening into thin wings.
  if (spec.flare != 0) {
    half[eave] = half[eave]! + spec.flare;
    if (eave - 1 >= peak) {
      half[eave - 1] = math.max(half[eave - 1]!, half[eave]! - 1);
    }
  }
  for (var r = y0; r <= bottom; r++) {
    final u = bodyH <= 1 ? 1.0 : (r - y0) / (bodyH - 1);
    half[r] = roundHalfUp(
      w / 2 +
          spec.taper * u +
          spec.bulge * math.sin(math.pi * (0.15 + 0.7 * u)),
    );
  }
  final baseRound = spec.baseRound;
  for (var k = 0; k < baseRound; k++) {
    half[bottom - k] = half[bottom - k]! - (baseRound - k);
  }

  int left(int r) => cxL - half[r]! + 1 + shift(r);
  int right(int r) => cxR + half[r]! - 1 + shift(r);

  for (var r = peak; r <= bottom; r++) {
    for (var x = left(r); x <= right(r); x++) {
      set(sil, x, r);
    }
  }
  if (spec.droop) {
    set(sil, left(eave), eave + 1);
    set(sil, right(eave), eave + 1);
  }

  // Chimney on the left slope, its foot sunk into the roof.
  final cw = spec.chimW;
  final chH = spec.chimH;
  final rc = peak + roundHalfUp(roofH * spec.chimneyAt);
  final c0 = left(rc) + spec.chimIn;
  final c1 = c0 + cw - 1;
  final ctop = rc - chH;
  final tilt = spec.chimTilt;
  for (var r = ctop; r <= eave; r++) {
    final t = r < rc - chH ~/ 2 ? -tilt : 0;
    for (var x = c0 + t; x <= c1 + t; x++) {
      set(sil, x, r);
    }
    if (r >= rc && left(r) <= c0) break;
  }
  if (spec.chimCap) {
    set(sil, c0 - tilt - 1, ctop);
    set(sil, c1 - tilt + 1, ctop);
  }

  // The face: the mascot's rounded triangle, kept a gold margin from the roof,
  // stepped on the sides and clipped at the bottom so the door has a lintel.
  final height = bottom - peak + 1;
  final dw = spec.doorW;
  final dh = spec.doorH;
  final faceTop = peak + roundHalfUp(height * spec.faceTopF);
  final faceBottom = math.min(
    peak + roundHalfUp(height * spec.faceBotF),
    bottom - dh - spec.doorGap,
  );
  final maxHalf = math.max(3, roundHalfUp(w * spec.faceWF / 2));
  final margin = spec.faceMargin;
  final fs = spec.faceStep;
  final round = spec.faceRound;
  final apex = spec.faceApex;
  final faceRows = math.max(2, faceBottom - faceTop + 1);
  final faceHalf = <int, int>{};
  for (var r = faceTop; r <= faceBottom; r++) {
    final u = (r - faceTop) / (faceRows - 1);
    var h = apex +
        fs * (((maxHalf - apex) * math.pow(u, spec.facePow)) / fs).floor();
    if (r == faceTop && h > 2) h -= 1;
    h = math.min(h, half[r]! - margin);
    if (r == faceBottom) {
      h -= round + (round > 1 && h > 6 ? 1 : 0);
    } else if (r == faceBottom - 1 && round > 1) {
      h -= 1;
    }
    if (h < 1) continue;
    faceHalf[r] = h;
    for (var k = 0; k < h; k++) {
      set(face, cxL - k + shift(r), r);
      set(face, cxR + k + shift(r), r);
    }
  }

  // An arched door: six cells wide, two cut at the top.
  for (var r = bottom - dh + 1; r <= bottom; r++) {
    final i = r - (bottom - dh + 1);
    final trim =
        dw >= 6 ? (i == 0 ? 2 : (i == 1 ? 1 : 0)) : (i == 0 && dw >= 4 ? 1 : 0);
    for (var k = 0; k < dw ~/ 2 - trim; k++) {
      set(door, cxL - k + shift(r), r);
      set(door, cxR + k + shift(r), r);
    }
  }

  final eyeShift = shift(faceBottom);
  return _finishHouse(
    spec: spec,
    sil: sil,
    face: face,
    door: door,
    topRow: math.min(ctop, peak),
    bottom: bottom,
    gx: n / 2 + lean / 2,
    faceBottom: faceBottom,
    faceHalf: faceHalf,
    maxHalf: maxHalf,
    cxL: cxL,
    cxR: cxR,
    eyeShift: eyeShift,
    chimney: PixelHouseChimney(x: c0 - tilt, y: ctop, width: cw),
    withEffects: withEffects,
  );
}

/// Roles (lit edge, shade, face, door), the aura distance field and the eye
/// placement — shared by every house shape.
PixelHouse _finishHouse({
  required PixelHouseSpec spec,
  required Uint8List sil,
  required Uint8List face,
  required Uint8List door,
  required int topRow,
  required int bottom,
  required double gx,
  required int faceBottom,
  required Map<int, int> faceHalf,
  required int maxHalf,
  required int cxL,
  required int cxR,
  required int eyeShift,
  required PixelHouseChimney chimney,
  required bool withEffects,
}) {
  final n = spec.n;

  bool silAt(int x, int y) =>
      x >= 0 && y >= 0 && x < n && y < n && sil[y * n + x] == 1;
  bool faceAt(int x, int y) =>
      x >= 0 && y >= 0 && x < n && y < n && face[y * n + x] == 1;

  final cells = <int>[];
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final i = y * n + x;
      PixelHousePart part = PixelHousePart.none;
      if (sil[i] == 0) {
        if (spec.outline &&
            (silAt(x - 1, y) ||
                silAt(x + 1, y) ||
                silAt(x, y - 1) ||
                silAt(x, y + 1))) {
          part = PixelHousePart.outline;
        }
      } else if (door[i] == 1) {
        part = PixelHousePart.door;
      } else if (face[i] == 1) {
        final up = silAt(x, y - 1) && !faceAt(x, y - 1);
        final left = silAt(x - 1, y) && !faceAt(x - 1, y);
        part = (up || left) ? PixelHousePart.faceDeep : PixelHousePart.face;
      } else {
        final up = !silAt(x, y - 1);
        final left = !silAt(x - 1, y);
        final right = !silAt(x + 1, y);
        final down = !silAt(x, y + 1);
        part = (up || left)
            ? PixelHousePart.lit
            : ((right || down) ? PixelHousePart.shade : PixelHousePart.body);
      }
      if (part != PixelHousePart.none) {
        cells
          ..add(x)
          ..add(y)
          ..add(part.index);
      }
    }
  }

  final gy = (topRow + bottom + 1) / 2;
  final auraOut = <double>[];
  if (withEffects) {
    // Chamfer distance from the silhouette: the aura hugs the walls instead of
    // being a circle that ignores the roof.
    final distance = Float32List(n * n)..fillRange(0, n * n, 1e9);
    for (var i = 0; i < n * n; i++) {
      if (sil[i] == 1) distance[i] = 0;
    }
    void relax(int x, int y, int nx, int ny, double weight) {
      if (nx < 0 || ny < 0 || nx >= n || ny >= n) return;
      final candidate = distance[ny * n + nx] + weight;
      if (candidate < distance[y * n + x]) distance[y * n + x] = candidate;
    }

    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        relax(x, y, x - 1, y, 1);
        relax(x, y, x, y - 1, 1);
        relax(x, y, x - 1, y - 1, 1.414);
        relax(x, y, x + 1, y - 1, 1.414);
      }
    }
    for (var y = n - 1; y >= 0; y--) {
      for (var x = n - 1; x >= 0; x--) {
        relax(x, y, x + 1, y, 1);
        relax(x, y, x, y + 1, 1);
        relax(x, y, x + 1, y + 1, 1.414);
        relax(x, y, x - 1, y + 1, 1.414);
      }
    }
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final i = y * n + x;
        if (sil[i] == 1) continue;
        final d = distance[i];
        // Only the three bands the painter draws are worth keeping: the old
        // cutoff of 11 filled the array with cells no band ever read.
        if (d <= 6.5) {
          auraOut.addAll([x.toDouble(), y.toDouble(), d, pixelBayer(x, y)]);
        }
      }
    }
  }

  final eyeBase = faceBottom - spec.eyeLift;
  final eyeHalf = faceHalf[eyeBase] ?? maxHalf;
  final eyeScale = spec.eyeScale;
  final maskWidth = pixelEyeWidth(spec.eyeSet) * eyeScale;
  final eyeOffset = math.max(
    (maskWidth / 2).ceil() + eyeScale.round(),
    roundHalfUp(eyeHalf * spec.eyeSpread),
  );

  return PixelHouse(
    spec: spec,
    cells: Int32List.fromList(cells),
    faceMask: face,
    occupied: Uint8List.fromList(sil),
    aura: Float32List.fromList(auraOut),
    topRow: topRow,
    bottom: bottom,
    gx: gx,
    gy: gy,
    rcx: gx,
    rcy: gy + n * spec.ringDy,
    face: PixelHouseFace(
      base: eyeBase,
      offset: eyeOffset,
      scale: eyeScale,
      left: cxL + eyeShift,
      right: cxR + eyeShift,
    ),
    door: PixelHouseDoor(
      left: cxL,
      right: cxR,
      width: spec.doorW,
      height: spec.doorH,
      bottom: bottom,
    ),
    chimney: chimney,
  );
}

/// The colours of one house: lit gold or faded, by theme.
@immutable
class PixelHouseInk {
  const PixelHouseInk({
    required this.body,
    required this.lit,
    required this.shade,
    required this.face,
    required this.faceDeep,
    required this.door,
    required this.outline,
    required this.eye,
  });

  final Color body;
  final Color lit;
  final Color shade;
  final Color face;
  final Color faceDeep;
  final Color door;
  final Color outline;
  final Color eye;

  Color of(PixelHousePart part) => switch (part) {
        PixelHousePart.body => body,
        PixelHousePart.lit => lit,
        PixelHousePart.shade => shade,
        PixelHousePart.face => face,
        PixelHousePart.faceDeep => faceDeep,
        PixelHousePart.door => door,
        PixelHousePart.outline => outline,
        PixelHousePart.none => body,
      };

  /// The house at work: three golds, the dark window and the cream door.
  ///
  /// The lit edge is a half step over the body, not a full one: a flat ridge
  /// row painted in the full highlight read as a row the gold had not reached
  /// yet. The outline is the shade gold, so the border is the house's own
  /// shadow rather than a dark line drawn around it.
  static PixelHouseInk gold(PixelHouseSpec spec) {
    const body = AppBrand.mascotGold;
    final lit =
        spec.shade ? Color.lerp(body, AppBrand.mascotGoldLit, 0.55)! : body;
    final shade = spec.shade ? AppBrand.mascotGoldDeep : body;
    return PixelHouseInk(
      body: body,
      lit: lit,
      shade: shade,
      face: AppBrand.mascotFace,
      faceDeep: spec.shade
          ? Color.lerp(AppBrand.mascotFace, AppBrand.shadeSource, 0.35)!
          : AppBrand.mascotFace,
      door: AppBrand.mascotCream,
      outline: AppBrand.mascotGoldDeep,
      eye: AppBrand.mascotCream,
    );
  }

  /// The house at rest: the same shape washed towards the paper, so it still
  /// reads as a house rather than as a grey placeholder.
  static PixelHouseInk faded(PixelHouseSpec spec, {required bool dark}) {
    if (spec.offStyle == 'ink') {
      final ink = dark ? AppBrand.inkDark : AppBrand.inkLight;
      final paper = dark ? AppBrand.groundDark : AppBrand.paperLight;
      final door = dark ? AppBrand.mascotGoldLit : AppBrand.mascotGoldDeep;
      return PixelHouseInk(
        body: ink,
        lit: ink,
        shade: ink,
        face: paper,
        faceDeep: paper,
        door: door,
        outline: ink,
        eye: ink,
      );
    }
    final fadeTo = dark ? AppBrand.surfaceRaisedDark : AppBrand.stoneShade;
    final k = dark ? 0.55 : 0.62;
    Color wash(Color color, double amount) =>
        Color.lerp(color, fadeTo, amount)!;
    const body = AppBrand.mascotGold;
    return PixelHouseInk(
      body: wash(body, k),
      // No highlight on the resting house: a paler row along the roof read as
      // the last line the wash had not reached.
      lit: wash(body, k),
      shade: wash(spec.shade ? AppBrand.mascotGoldDeep : body, k - 0.05),
      face: wash(AppBrand.mascotFace, 0.3),
      faceDeep: wash(AppBrand.mascotFace, 0.2),
      door: wash(AppBrand.mascotCream, 0.45),
      // Same wash as the shade: the outline is the house's edge, not a line
      // darker than everything else.
      outline: wash(spec.shade ? AppBrand.mascotGoldDeep : body, k),
      eye: wash(AppBrand.mascotCream, 0.35),
    );
  }
}
