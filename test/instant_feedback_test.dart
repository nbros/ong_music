// The instant feedback of the desktop look at its edges: a control that goes away while it is pressed, and the mouse
// cursor of the app's own ink wells (the rest is in top_bar_test.dart).
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/ui/instant_feedback.dart';
import 'package:ong_music/src/ui/rows.dart';

import 'top_bar_test.dart' show pumpDesktop, windows;

void main() {
  testWidgets('a state layer removed while the mouse is down on it takes the release without an error', (tester) async {
    final states = ValueNotifier<Set<WidgetState>>({});
    addTearDown(states.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: StateLayer(
            states: states,
            hover: Colors.transparent,
            focus: Colors.transparent,
            press: const Color(0x33000000),
            child: const SizedBox.square(dimension: 100),
          ),
        ),
      ),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(tester.getCenter(find.byType(StateLayer)));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Windows app: a row keeps the arrow cursor, as its buttons do', (tester) async {
    await pumpDesktop(tester, const Size(700, 800));
    final row = find.byType(HighlightRow).first;
    final well = find.descendant(of: row, matching: find.byType(AppInkWell)).first;
    final cursor = tester
        .widget<MouseRegion>(find.descendant(of: well, matching: find.byType(MouseRegion)).first)
        .cursor;
    expect(cursor, SystemMouseCursors.basic);
  }, variant: windows);
}
