// The field that never wraps its lines measures them again when a font comes: the web app fetches the fonts of rare
// characters (a Hebrew title) once they show, after the text was first measured. A file of its own: the font loaded
// here stays loaded for the rest of the file.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/ui/favourites_transfer.dart';
import 'package:ong_music/src/ui/theme.dart';

void main() {
  testWidgets('a font that comes after the text: the lines are measured again, and stay one line each', (tester) async {
    final controller = TextEditingController(
      text: [
        for (var i = 0; i < 6; i++) 'Artist $i - A long title of a song $i — https://youtu.be/aaaaaaaaaaa',
      ].join('\n'),
    );
    addTearDown(controller.dispose);
    final theme = buildTheme(Brightness.light);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: UnwrappedTextField(controller: controller, lines: 5, hintText: 'hint'),
            ),
          ),
        ),
      ),
    );
    final editable = find.descendant(of: find.byType(UnwrappedTextField), matching: find.byType(EditableText));
    final before = tester.getSize(editable).width;

    // the family of the field's text, with other widths than the test font's (which draws every character as wide
    // as its size)
    final family = theme.textTheme.bodyLarge!.fontFamily!;
    final bytes = File('assets/fonts/Roboto-Medium.ttf').readAsBytesSync();
    await tester.runAsync(() => (FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)))).load());
    await tester.pumpAndSettle();

    final after = tester.getSize(editable).width;
    expect(after, lessThan(before * 0.8), reason: 'measured again: $before, then $after');
    // still one line each, at the new width
    final text = tester.state<EditableTextState>(editable).renderEditable;
    final boxes = text.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: controller.text.length));
    expect({for (final b in boxes) b.top.round()}, hasLength(6));
  });
}
