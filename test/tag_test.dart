// The small boxed labels of the plays ("TIER 3", "RAFFLE"): their capital letters in the middle of their box.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/ui/theme.dart';
import 'package:ong_music/src/ui/widgets.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('capital letters sit in the middle of the box, as drawn: ${brightness.name} theme', (tester) async {
      // the real font: the test font has other proportions
      await tester.runAsync(() async {
        final font = File('assets/fonts/Roboto-Medium.ttf').readAsBytesSync();
        await (FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(font)))).load();
      });
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(brightness),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(key: key, child: const Tag('Raffle')),
            ),
          ),
        ),
      );
      // the size of the design: 14 px of text between two borders of 1 px, 6 px after the text before it
      final box = tester.getSize(find.byType(Tag));
      expect(box.height, 16);

      // drawn 8 times larger, to measure tenths of a pixel
      const scale = 8.0;
      late ui.Image image;
      late ByteData pixels;
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        image = await boundary.toImage(pixelRatio: scale);
        pixels = (await image.toByteData())!;
      });
      addTearDown(image.dispose);
      final background = Theme.of(tester.element(find.byType(Tag))).colorScheme.surface;
      // how far a pixel is from the background, 0 to 255; a transparent one is the background
      int distance(int x, int y) {
        final o = (y * image.width + x) * 4;
        final alpha = pixels.getUint8(o + 3) / 255;
        int channel(int i, double of) => ((pixels.getUint8(o + i) - of * 255).abs() * alpha).round();
        return [channel(0, background.r), channel(1, background.g), channel(2, background.b)].reduce((a, b) => a + b);
      }

      // the rows where the letters are: across the middle of the box, away from its side borders and corners
      final left = (image.width * 0.3).round(), right = (image.width * 0.9).round();
      final border = scale.round();
      int? first, last;
      for (var y = border * 2; y < image.height - border * 2; y++) {
        var ink = 0;
        for (var x = left; x < right; x++) {
          if (distance(x, y) > 150) ink++;
        }
        if (ink > 0) {
          first ??= y;
          last = y;
        }
      }
      final above = first! / scale - 1, below = (image.height - 1 - last!) / scale - 1;
      // as high as Roboto's capital letters at 10 px
      expect(14 - above - below, closeTo(7.1, 0.2));
      expect(above, closeTo(below, 0.25), reason: '$above px above the letters, $below px below');
    });
  }
}
