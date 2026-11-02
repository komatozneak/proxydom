// Bakes the launcher icon of the mascot: the pixel house alone, square, no
// wordmark and no fireflies — at 48 px the ring is dust, the face is what a
// person remembers.
//
//   cd mobile && flutter test tool/bake_mascot_icon.dart
//   dart run flutter_launcher_icons
//   python tool/bake_windows_icon.py
//
// The house comes from the same `buildPixelHouse` grid the connect button
// draws, so the icon cannot drift from the mascot. Writes, all 1024 px, into
// assets/icon/:
//   app_icon_mascot.png      full-bleed tile for iOS (the system rounds it)
//   app_icon_mascot_win.png  rounded tile on black, the .ico source
//   fg_mascot.png            Android adaptive foreground, transparent
//   mono_mascot.png          Android 13+ themed icon: walls with cut-outs
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/core/widgets/pixel_house.dart';

const double _side = 1024;
const int _size = 1024;

/// How much of the square the house's bounding box takes. The adaptive layer
/// keeps the margin the previous icon used: 72% of the canvas, and the
/// launcher XML adds its 12% inset on top.
const double _tileFill = 0.80;
const double _adaptiveFill = 0.72;

final PixelHouse _house = buildPixelHouse(PixelHouseSpec.organic);

({int minX, int maxX, int minY, int maxY}) _bounds() {
  var minX = 1 << 30;
  var maxX = -1;
  var minY = 1 << 30;
  var maxY = -1;
  final cells = _house.cells;
  for (var i = 0; i < cells.length; i += 3) {
    final x = cells[i];
    final y = cells[i + 1];
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }
  return (minX: minX, maxX: maxX, minY: minY, maxY: maxY);
}

/// Paints the house into a square of [box], its bounding box taking [fill] of
/// the width.
///
/// [silhouette] paints every wall cell in one colour and leaves the window and
/// the door as holes — the shape the themed-icon tint needs. Otherwise the
/// cells use [ink], with the happy eyes drawn over the window.
void _paintHouse(
  Canvas canvas, {
  required PixelHouseInk ink,
  double fill = _tileFill,
  Color? silhouette,
  bool eyes = true,
}) {
  final bounds = _bounds();
  final cellsWide = bounds.maxX - bounds.minX + 1;
  final cellsHigh = bounds.maxY - bounds.minY + 1;
  final cell = (_side * fill / cellsWide).floorToDouble();
  final originX =
      ((_side - cellsWide * cell) / 2).roundToDouble() - bounds.minX * cell;
  final originY =
      ((_side - cellsHigh * cell) / 2).roundToDouble() - bounds.minY * cell;

  Rect at(int x, int y) => Rect.fromLTWH(
        originX + x * cell,
        originY + y * cell,
        cell,
        cell,
      );

  final paths = <Color, Path>{};
  final cells = _house.cells;
  for (var i = 0; i < cells.length; i += 3) {
    final x = cells[i];
    final y = cells[i + 1];
    final part = PixelHousePart.values[cells[i + 2]];
    if (silhouette != null) {
      // The window and the door are holes: the launcher paints the tint on the
      // walls, and the holes show the wallpaper through the house.
      if (part == PixelHousePart.face ||
          part == PixelHousePart.faceDeep ||
          part == PixelHousePart.door) {
        continue;
      }
      (paths[silhouette] ??= Path()).addRect(at(x, y));
      continue;
    }
    (paths[ink.of(part)] ??= Path()).addRect(at(x, y));
  }
  for (final entry in paths.entries) {
    canvas.drawPath(
      entry.value,
      Paint()
        ..color = entry.key
        ..isAntiAlias = false,
    );
  }

  if (!eyes) return;
  final face = _house.face;
  final mask = pixelEyeMask('xl', 'happy');
  final scale = face.scale.round();
  final maskWidth = mask.first.length * scale;
  final maskHeight = mask.length * scale;
  final eyePath = Path();
  for (final side in const [-1, 1]) {
    final x0 = side > 0
        ? face.right + face.offset - maskWidth ~/ 2
        : face.left - face.offset + maskWidth ~/ 2 - maskWidth + 1;
    final y0 = face.base - maskHeight + 1;
    for (var ry = 0; ry < mask.length; ry++) {
      for (var rx = 0; rx < mask[ry].length; rx++) {
        if (mask[ry][rx] != '#') continue;
        for (var a = 0; a < scale; a++) {
          for (var b = 0; b < scale; b++) {
            eyePath.addRect(at(x0 + rx * scale + b, y0 + ry * scale + a));
          }
        }
      }
    }
  }
  canvas.drawPath(
    eyePath,
    Paint()
      // In the themed silhouette the eyes are the same tint as the walls: the
      // window keeps the face instead of reading as an empty hole.
      ..color = silhouette ?? ink.eye
      ..isAntiAlias = false,
  );
}

Future<void> _write(String name, void Function(Canvas canvas) draw) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.clipRect(const Rect.fromLTWH(0, 0, _side, _side));
  draw(canvas);
  final image = await recorder.endRecording().toImage(_size, _size);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  File('assets/icon/$name').writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  test('bake mascot launcher sources', () async {
    final ink = PixelHouseInk.gold(PixelHouseSpec.organic);

    // iOS: edge to edge, the system rounds the corners.
    await _write('app_icon_mascot.png', (canvas) {
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, _side, _side),
        Paint()..color = AppBrand.inkLight,
      );
      _paintHouse(canvas, ink: ink);
    });

    // Windows: a rounded tile on a black field. bake_windows_icon.py floods
    // the black corners away, so the .ico adapts to light and dark shells.
    await _write('app_icon_mascot_win.png', (canvas) {
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, _side, _side),
        Paint()..color = const Color(0xFF000000),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, _side, _side),
          const Radius.circular(200),
        ),
        Paint()..color = AppBrand.inkLight,
      );
      _paintHouse(canvas, ink: ink);
    });

    // Android adaptive: the house alone; the XML supplies the paper and the
    // inset that keeps it inside every launcher mask.
    await _write('fg_mascot.png', (canvas) {
      _paintHouse(canvas, ink: ink, fill: _adaptiveFill);
    });

    // Android 13+ themed icon: one silhouette, the window and the door cut
    // out, so the launcher tint draws a house with a dark window — and the
    // eyes stay inside it, or the themed icon loses the mascot's face.
    await _write('mono_mascot.png', (canvas) {
      _paintHouse(
        canvas,
        ink: ink,
        fill: _adaptiveFill,
        silhouette: AppBrand.lightSource,
      );
    });
  });
}
