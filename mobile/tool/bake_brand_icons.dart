// Prints the launcher sources from the same painter the app draws its icon
// with, so the home-screen icon and the in-window icon cannot drift apart.
//
//   cd mobile && flutter test tool/bake_brand_icons.dart
//   dart run flutter_launcher_icons
//   python tool/bake_windows_icon.py
//
// Writes, all 1024 px, into assets/icon/:
//   app_icon_c1.png      full-bleed tile for iOS (the system rounds it)
//   app_icon_c1_win.png  rounded tile on transparency, the .ico source
//   fg_c1.png            Android adaptive foreground: the mark alone
//   mono_c1.png          Android 13+ themed icon: the mark as one silhouette
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/theme.dart';
import 'package:proxydom/core/widgets/proxydom_brand.dart';

const int _size = 1024;

/// The adaptive foreground keeps the same margin the mascot icon had: the
/// mark at 72% of the canvas, with the launcher XML adding its 12% inset.
const double _safeScale = 0.72;

Future<void> _write(String name, void Function(Canvas canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final image = await recorder.endRecording().toImage(_size, _size);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  File('assets/icon/$name').writeAsBytesSync(png!.buffer.asUint8List());
}

void _mark(Canvas canvas, double scale, {Color? tile, required Color key, required Color frame}) {
  final side = _size * scale;
  canvas.save();
  canvas.translate((_size - side) / 2, (_size - side) / 2);
  KeyIconPainter(tile: tile, key: key, frame: frame).paint(canvas, Size(side, side));
  canvas.restore();
}

void main() {
  test('bake launcher sources', () async {
    await _write('app_icon_c1.png', (c) {
      c.drawRect(const Rect.fromLTWH(0, 0, 1024, 1024), Paint()..color = AppBrand.inkLight);
      _mark(c, 1, key: AppBrand.inkDark, frame: AppBrand.mascotGold);
    });
    await _write('app_icon_c1_win.png', (c) {
      _mark(c, 1, tile: AppBrand.inkLight, key: AppBrand.inkDark, frame: AppBrand.mascotGold);
    });
    await _write('fg_c1.png', (c) {
      _mark(c, _safeScale, key: AppBrand.inkDark, frame: AppBrand.mascotGold);
    });
    await _write('mono_c1.png', (c) {
      _mark(c, _safeScale, key: AppBrand.inkDark, frame: AppBrand.inkDark);
    });
  });
}
