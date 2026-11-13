// The hover of the rows of the licences page in the desktop look, in a list long enough to scroll under its app
// bar. In a file of its own: the packages added to the licences stay for the whole file.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/ui/instant_feedback.dart';

import 'top_bar_test.dart' show licensedPackage, mouseAt, openLicences, pumpDesktop, windows;
import 'ui_harness.dart';

/// What the hover layer of the licences page paints: the rectangle and its
/// colour, or null.
(Rect, Color)? hoverOf(WidgetTester tester) {
  final layer = find.byType(InstantTileHover);
  final painter = tester
      .widget<CustomPaint>(find.descendant(of: layer, matching: find.byType(CustomPaint)).first)
      .foregroundPainter;
  if (painter == null) return null;
  final canvas = _RectCanvas();
  painter.paint(canvas, tester.getSize(layer));
  return (canvas.rect!.shift(tester.getTopLeft(layer)), canvas.color!);
}

class _RectCanvas extends Fake implements Canvas {
  Rect? rect;
  Color? color;

  @override
  void drawRect(Rect rect, Paint paint) {
    this.rect = rect;
    color = paint.color;
  }
}

void main() {
  LicenseRegistry.addLicense(() => Stream.value(const LicenseEntryWithLineBreaks([licensedPackage], 'A licence.')));
  for (var i = 0; i < 40; i++) {
    LicenseRegistry.addLicense(() => Stream.value(LicenseEntryWithLineBreaks(['package_$i'], 'A licence.')));
  }

  /// The licences page of a wide window, its list of packages scrolled by
  /// [scroll] px; returns the list's scrollable.
  Future<Finder> licences(WidgetTester tester, double scroll) async {
    await pumpDesktop(tester, const Size(1340, 830));
    await goToTab(tester, 'About');
    await openLicences(tester);
    final list = find.descendant(of: find.byType(InstantTileHover), matching: find.byType(Scrollable)).first;
    await tester.drag(list, Offset(0, -scroll), kind: PointerDeviceKind.touch);
    await tester.pumpAndSettle();
    return list;
  }

  List<Rect> tiles(WidgetTester tester) => [
    for (final e in find.byType(ListTile).evaluate()) tester.getRect(find.byWidget(e.widget)),
  ];

  testWidgets('a row half under the app bar: the app bar is never tinted, the row only in the list', (tester) async {
    final list = await licences(tester, 150);
    final viewport = tester.getRect(list);
    final under = tiles(tester).firstWhere((r) => r.top < viewport.top && r.bottom > viewport.top + 8);
    // the strip of the app bar over the row: nothing under the mouse is a row
    final mouse = await mouseAt(tester, Offset(under.center.dx, viewport.top - 4));
    await mouse.moveTo(Offset(under.center.dx, viewport.top - 3));
    await tester.pump();
    expect(hoverOf(tester), isNull);
    // the part of the row in the list: tinted there only
    await mouse.moveTo(Offset(under.center.dx, viewport.top + 4));
    await tester.pump();
    final (rect, _) = hoverOf(tester)!;
    expect(rect, Rect.fromLTRB(under.left, viewport.top, under.right, under.bottom));
  }, variant: windows);

  testWidgets('the list scrolled under a mouse at rest: the tint follows the row under it', (tester) async {
    final list = await licences(tester, 0);
    final viewport = tester.getRect(list);
    final at = Offset(viewport.center.dx, viewport.top + 300);
    final mouse = await mouseAt(tester, at);
    await mouse.moveTo(at.translate(0, 1));
    await tester.pump();
    final (before, _) = hoverOf(tester)!;
    expect(before.contains(at.translate(0, 1)), isTrue);
    // another pointer scrolls the list; the mouse does not move
    await tester.drag(list, const Offset(0, -100), kind: PointerDeviceKind.touch);
    await tester.pumpAndSettle();
    final now = tiles(tester).firstWhere((r) => r.contains(at.translate(0, 1)));
    final (after, _) = hoverOf(tester)!;
    expect(after, now);
    expect(after, isNot(before));
  }, variant: windows);
}
