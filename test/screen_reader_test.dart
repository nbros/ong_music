// What a screen reader, a switch or a voice command can do: every button has its own action, a name, and a
// target as high as the finger's.
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/ui/sheets.dart';
import 'package:ong_music/src/ui/widgets.dart';

import 'ui_harness.dart';

void main() {
  /// Does the tap action of the node labelled [label], as an accessibility service does.
  Future<void> activate(WidgetTester tester, Pattern label, {int at = 0}) async {
    final node = find.semantics.byLabel(label).at(at);
    expect(node.evaluate().single.getSemanticsData().hasAction(SemanticsAction.tap), isTrue, reason: '$label');
    tester.semantics.tap(node);
    await tester.pumpAndSettle();
  }

  testWidgets('the play button of an Ong Log row is a button of its own, which opens the video', (tester) async {
    final handle = tester.ensureSemantics();
    final app = await pumpApp(tester);
    await goToTab(tester, 'Ong Log');
    final pills = find.byType(VideoPill).hitTestable();
    expect(pills, findsWidgets);
    // not merged into its row, whose action opens the history of the song
    expect(find.semantics.byLabel('Watch the video'), findsNWidgets(pills.evaluate().length));
    await activate(tester, 'Watch the video');
    expect(app.effects.opened, hasLength(1));
    expect(find.byType(SongSheet), findsNothing);
    // the row keeps its own action
    await tester.tap(find.byType(VideoPill).hitTestable().first, warnIfMissed: false);
    handle.dispose();
  });

  testWidgets('a stream header, a link tile and a video of a song sheet can be activated', (tester) async {
    final handle = tester.ensureSemantics();
    final app = await pumpApp(tester);

    await goToTab(tester, 'Ong Log');
    await activate(tester, RegExp('^Stream of '));
    expect(find.byType(StreamSheet), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // the history of a song with a video
    await tester.tap(find.text('I Will Survive').hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.byType(SongSheet), findsOneWidget);
    await activate(tester, RegExp('^Video of '));
    expect(app.effects.opened.single.toString(), contains('bbbbbbbbbbb'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await goToTab(tester, 'About');
    await activate(tester, 'Merch');
    expect(app.effects.opened, hasLength(2));
    handle.dispose();
  });

  testWidgets('a filter chip is as high as its tap target for a screen reader, and keeps its name and state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, prefs: {'twitchName': 'jsbach64'});
    for (final label in ['All', 'You', 'Game OST']) {
      final node = tester.getSemantics(chip(label));
      expect(node.rect.height, 48, reason: label);
      expect(node.getSemanticsData().label, startsWith(label), reason: label);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue, reason: label);
      // what the eye sees has not moved
      expect(tester.getSize(chip(label)).height, 32, reason: label);
    }
    expect(tester.getSemantics(chip('All')), isSemantics(isSelected: true, isButton: true));
    expect(tester.getSemantics(chip('Game OST')), isSemantics(isSelected: false, isButton: true));
    handle.dispose();
  });

  testWidgets('the Twitch name field says what it is', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester);
    await goToTab(tester, 'About');
    await tester.scrollUntilVisible(find.text('Optional'), 200, scrollable: aboutScrollable());
    final field = tester.getSemantics(find.byType(TextField).hitTestable());
    expect(field.label, contains('Your Twitch name'));
    expect(field.getSemanticsData().flagsCollection.isTextField, isTrue);
    handle.dispose();
  });
}
