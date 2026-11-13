// The labels of the top bar measured in the font they are drawn in. In a file
// of its own: it gives a real font (Roboto Medium) to the family of the text
// theme of Windows, Segoe UI, for the whole file; the other tests draw every
// text in the test font, whose glyphs are all one em wide.
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/ui/layout.dart';
import 'package:ong_music/src/ui/top_bar.dart';

import 'ui_harness.dart';

void main() {
  setUpAll(() async {
    final bytes = File('assets/fonts/Roboto-Medium.ttf').readAsBytesSync();
    await (FontLoader('Segoe UI')..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });

  testWidgets('each label is given the width it is drawn at, in the family of the platform', (tester) async {
    await pumpApp(tester, size: const Size(1340, 830), desktop: true, pointer: PointerKind.mouse);
    for (final label in ['Highlights', 'Ong Log', 'About']) {
      final text = find.descendant(of: find.byType(AppTopBar), matching: find.text(label));
      final paragraph = tester.renderObject<RenderParagraph>(text);
      // drawn in the family of the platform's text theme
      expect(paragraph.text.style!.fontFamily, 'Segoe UI');
      // the box of the label (measured by the bar) is the width of the text, rounded up: no more, no less
      final drawn = paragraph.getMaxIntrinsicWidth(double.infinity);
      expect(tester.getSize(text).width, drawn.ceilToDouble(), reason: label);
      // in Roboto Medium, far narrower than the test font's 14 px per letter
      expect(drawn, lessThan(label.length * 14 * 0.7), reason: label);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
