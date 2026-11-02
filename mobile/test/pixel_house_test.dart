// The pixel house has two halves that can be checked without a screen: the
// cells it is built from, and the numbers that light them.
//
// The old connect button was a PNG and an orbit widget, and the only way to
// test it was to look. The shapes here are code, so the shape is testable.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/widgets/connect_button.dart';
import 'package:proxydom/core/widgets/pixel_house.dart';
import 'package:proxydom/core/widgets/pixel_house_hero.dart';
import 'package:proxydom/l10n/app_localizations.dart';

void main() {
  group('the house grid', () {
    final house = buildPixelHouse(PixelHouseSpec.organic);

    test('the door is cut into the wall, not floating in the face', () {
      final door = house.door;
      expect(door.width, 6);
      expect(door.height, 4);
      var doorCells = 0;
      for (var i = 0; i < house.cells.length; i += 3) {
        final y = house.cells[i + 1];
        if (PixelHousePart.values[house.cells[i + 2]] == PixelHousePart.door) {
          doorCells++;
          expect(
              y, inInclusiveRange(door.bottom - door.height + 1, door.bottom));
        }
      }
      expect(doorCells, greaterThan(0));
    });

    test('the face sits above the door with a gold lintel between them', () {
      expect(house.face.base, lessThan(house.door.bottom - house.door.height));
      expect(house.face.offset, greaterThan(0));
      var faceCells = 0;
      for (var i = 0; i < house.cells.length; i += 3) {
        final part = PixelHousePart.values[house.cells[i + 2]];
        if (part == PixelHousePart.face || part == PixelHousePart.faceDeep) {
          faceCells++;
        }
      }
      // Two eyes' worth of window, and not a sliver.
      expect(faceCells, greaterThan(100));
    });

    test('the house is wider than half the grid and keeps off its edges', () {
      var minX = 1 << 30;
      var maxX = -1;
      var minY = 1 << 30;
      var maxY = -1;
      for (var i = 0; i < house.cells.length; i += 3) {
        final x = house.cells[i];
        final y = house.cells[i + 1];
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
      final span = maxX - minX + 1;
      expect(span, greaterThan(house.spec.n * 0.6));
      // A cell of margin on every side, or the aura and the circle have
      // nowhere to go.
      expect(minX, greaterThan(0));
      expect(maxX, lessThan(house.spec.n - 1));
      expect(maxY, lessThan(house.spec.n - 1));
    });

    test('the light circle is drawn around the house, not inside it', () {
      expect(house.aura.length, greaterThan(0));
      var minX = 1 << 30;
      var maxX = -1;
      for (var i = 0; i < house.cells.length; i += 3) {
        if (house.cells[i] < minX) minX = house.cells[i];
        if (house.cells[i] > maxX) maxX = house.cells[i];
      }
      final halfWidth = (maxX - minX + 1) / 2;
      for (final ring in kPixelHouseRings) {
        // A circle tucked inside the walls is dust at the edges, not a dance.
        expect(ring.rx * house.spec.n, greaterThan(halfWidth));
      }
    });

    test('the ring is inside the bright zone of the taller canvas', () {
      final ring = kPixelHouseRings.first;
      final n = house.spec.n;
      // The canvas is at least as wide as the grid and taller than it; the
      // ring has to sit in the part that draws at full strength.
      final halfW = n / 2;
      final halfH = n / 2 * 1.3;
      expect(
        pixelLightFade(dx: ring.rx * n, dy: 0, halfW: halfW, halfH: halfH),
        1,
      );
      expect(
        pixelLightFade(dx: 0, dy: ring.ry * n, halfW: halfW, halfH: halfH),
        1,
      );
    });

    test('a light dissolves before the frame instead of being cut by it', () {
      const halfW = 27.0;
      const halfH = 35.0;
      expect(pixelLightFade(dx: 0, dy: 0, halfW: halfW, halfH: halfH), 1);
      expect(
        pixelLightFade(dx: halfW * 0.85, dy: 0, halfW: halfW, halfH: halfH),
        1,
      );
      expect(
        pixelLightFade(dx: halfW * 0.999, dy: 0, halfW: halfW, halfH: halfH),
        0,
      );
      expect(
        pixelLightFade(dx: 0, dy: halfH * 0.999, halfW: halfW, halfH: halfH),
        0,
      );
      // Never brighter as it gets closer to the edge: a soft falloff, not a
      // step that would draw the frame.
      var previous = 1.0;
      for (var radius = 0.0; radius <= halfW; radius += 0.5) {
        final fade = pixelLightFade(
          dx: radius,
          dy: 0,
          halfW: halfW,
          halfH: halfH,
        );
        expect(fade, lessThanOrEqualTo(previous + 1e-9));
        previous = fade;
      }
    });

    test('the gold fill includes the outline rows', () {
      // The outline is part of the house: fully on, the line above the roof
      // must be gold too, and fully off the line under the base must not be.
      expect(pixelFillStart(topRow: 11, bottom: 40, gold: 1), 10);
      expect(pixelFillStart(topRow: 11, bottom: 40, gold: 0), greaterThan(41));
      // Halfway up, the boundary sits around the middle of the walls.
      final half = pixelFillStart(topRow: 11, bottom: 40, gold: 0.5);
      expect(half, inInclusiveRange(18, 34));
    });
  });

  group('the eyes', () {
    test('every mood has its own mask', () {
      final happy = pixelEyeMask('xl', 'happy');
      final sleep = pixelEyeMask('xl', 'sleep');
      final open = pixelEyeMask('xl', 'open');
      final error = pixelEyeMask('xl', 'err');
      expect(happy, isNot(sleep));
      expect(happy, isNot(open));
      expect(happy, isNot(error));
      expect(sleep, isNot(open));
    });

    test('a smaller grid still gets a mask instead of an empty eye', () {
      for (final set in ['small', 'large', 'xl', 'nonsense']) {
        for (final mood in ['happy', 'sleep', 'open', 'blink', 'err', 'sad']) {
          expect(pixelEyeMask(set, mood), isNotEmpty);
        }
      }
    });
  });

  group('the light', () {
    PixelHouseMotion settled(PixelHouseMood mood, {int frames = 300}) {
      final motion = PixelHouseMotion(mood);
      for (var i = 0; i < frames; i++) {
        motion.update(1 / 60);
      }
      return motion;
    }

    test('connected: the gold and the circle are fully on', () {
      final motion = settled(PixelHouseMood.on);
      expect(motion.gold, 1);
      expect(motion.lights, 1);
      expect(motion.lit, greaterThan(0.5));
      expect(motion.eyes(motion.t).mask, 'happy');
    });

    test('resting: nothing moves but the sleeping house', () {
      final motion = settled(PixelHouseMood.off);
      expect(motion.gold, 0);
      expect(motion.lights, 0);
      expect(motion.lit, 0);
      expect(motion.sparks, isEmpty);
      expect(motion.eyes(motion.t).mask, 'sleep');
    });

    test('a tap throws sparks out of the house, and they burn out', () {
      final motion = PixelHouseMotion(PixelHouseMood.on);
      motion.tap();
      expect(motion.sparks, isNotEmpty);
      for (var i = 0; i < 90; i++) {
        motion.update(1 / 60);
      }
      expect(motion.sparks, isEmpty);
    });

    test('reduce motion taps without leaving a frozen ring of sparks', () {
      final motion = PixelHouseMotion(PixelHouseMood.on);
      motion.tap(burst: false);
      expect(motion.sparks, isEmpty);
    });

    test('a drop from connected fades the circle instead of snapping it', () {
      final motion = settled(PixelHouseMood.on);
      motion.setMood(PixelHouseMood.off);
      // One frame later the circle is still there: the house is going dark,
      // not being switched.
      motion.update(1 / 60);
      expect(motion.lights, greaterThan(0.5));
      for (var i = 0; i < 300; i++) {
        motion.update(1 / 60);
      }
      expect(motion.lights, 0);
      expect(motion.lit, 0);
      expect(motion.eyes(motion.t).mask, 'sleep');
    });

    test('connecting: the circle spins faster than the resting dance', () {
      final connecting = settled(PixelHouseMood.connecting);
      final connected = settled(PixelHouseMood.on);
      expect(connecting.speed.first, greaterThan(connected.speed.first));
      expect(connecting.lights, 1);
      // The gold is climbing from the door, not switched on.
      expect(connecting.gold, inInclusiveRange(0.0, 1.0));
    });

    test('an error dims the house and drops the lights', () {
      final motion = settled(PixelHouseMood.error);
      expect(motion.err, 1);
      expect(motion.lights, 0);
      expect(motion.eyes(motion.t).mask, 'err');
    });

    test('reduce motion gives one still frame instead of a running clock', () {
      final motion = PixelHouseMotion(PixelHouseMood.connecting);
      for (var i = 0; i < 30; i++) {
        motion.update(1 / 60, reduced: true);
      }
      expect(motion.t, 0);
      expect(motion.phase, [0.0, 0.0]);
    });
  });

  testWidgets('reduce motion paints a still house and settles', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('ru'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(400, 400),
            devicePixelRatio: 2,
            disableAnimations: true,
          ),
          child: Center(
            child: PixelHouseHero(
              state: TreeState.connected,
              size: 300,
            ),
          ),
        ),
      ),
    );
    // A running ticker would never settle; with reduce motion the house is a
    // still frame and the frame is done.
    await tester.pumpAndSettle();
    expect(find.byType(PixelHouseHero), findsOneWidget);
  });
}
