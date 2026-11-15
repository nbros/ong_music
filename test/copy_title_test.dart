// Copying the title and the artist of a song: a long press on its row, the copy button beside the title of its
// fiche. The text is the title as the sheets write it, "Artist - Track".
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/ui/actions.dart';
import 'package:ong_music/src/ui/layout.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/sheets.dart';

import 'fixtures.dart';
import 'ui_harness.dart';

Finder _highlightRow(String track) => find.ancestor(of: find.text(track), matching: find.byType(HighlightRow)).first;

Finder _playRow(String track) => find.ancestor(of: find.text(track), matching: find.byType(PlayRow)).first;

/// The copy button beside the title of the fiche on screen, whatever its state.
Finder _copyTitle() => find.byWidgetPredicate(
  (w) =>
      w is IconButton &&
      (w.tooltip == 'Copy title and artist' || w.tooltip == 'Copy title' || w.tooltip == 'Copied') &&
      w.icon is AnimatedSwitcher,
);

/// The semantics of the row showing [track], as a screen reader finds it.
SemanticsData _rowSemantics(WidgetTester tester, Finder row) =>
    tester.getSemantics(find.descendant(of: row, matching: find.byType(InkWell)).first).getSemanticsData();

/// The hint screen readers give for the long press of [data] (an overriding custom action).
String? _longPressHint(SemanticsData data) => [
  for (final id in data.customSemanticsActionIds ?? const <int>[])
    if (CustomSemanticsAction.getAction(id) case final action? when action.action == SemanticsAction.longPress)
      action.hint,
].singleOrNull;

void main() {
  test('the text copied is the title as the sheets write it, "Artist - Track", the track alone without artist', () {
    expect(songCopyText('Gloria Gaynor - I Will Survive'), 'Gloria Gaynor - I Will Survive');
    expect(songCopyText('GarbageHag'), 'GarbageHag');
    expect(
      [copiedText, copyFailedText, copyTitleAndArtistText, copyTitleText],
      ['Copied', 'Couldn’t copy', 'Copy title and artist', 'Copy title'],
    );
  });

  group('A long press on a row', () {
    testWidgets('of the Highlights: copies, with the haptic feedback and "Copied"; a tap still opens the video', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await tester.longPress(_highlightRow('Song of Storms'));
      await tester.pump();
      expect(app.effects.clipboard, 'Zelda - Song of Storms');
      expect(app.effects.haptics, 1);
      expect(find.text('Copied'), findsOneWidget);
      expect(app.effects.opened, isEmpty, reason: 'the long press does not open the video');
      expect(find.byType(HighlightSheet), findsNothing);
      await waitForMessage(tester);

      await tester.tap(_highlightRow('Song of Storms'));
      await tester.pumpAndSettle();
      expect(app.effects.opened.single.toString(), contains('aaaaaaaaaaa'));
      expect(app.effects.clipboard, 'Zelda - Song of Storms');
      // the ⋮ button still opens the fiche
      await tester.tap(find.descendant(of: _highlightRow('I Will Survive'), matching: detailsButtons()));
      await tester.pumpAndSettle();
      expect(find.byType(HighlightSheet), findsOneWidget);
    });

    testWidgets('of the Ong Log, and of a setlist in a fiche: copies the same way', (tester) async {
      final app = await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      await tester.longPress(_playRow('Lost Woods'));
      await tester.pump();
      expect(app.effects.clipboard, 'Zelda - Lost Woods');
      expect(find.text('Copied'), findsOneWidget);
      expect(find.byType(SongSheet), findsNothing, reason: 'nor does it open the song');
      await waitForMessage(tester);

      await tester.tap(find.text('Fri 1 Mar 2024'));
      await tester.pumpAndSettle();
      final inSheet = find.ancestor(
        of: find.descendant(of: find.byType(StreamSheet), matching: find.text('I Will Survive')),
        matching: find.byType(PlayRow),
      );
      await tester.longPress(inSheet);
      await tester.pump();
      expect(app.effects.clipboard, 'Gloria Gaynor - I Will Survive');
      expect(find.text('Copied'), findsOneWidget, reason: 'above the sheet');
      expect(find.byType(StreamSheet), findsOneWidget);
      expect(find.byType(SongSheet), findsNothing);
      expect(app.effects.haptics, 2);
      await waitForMessage(tester);
    });

    testWidgets('says so when the clipboard refuses', (tester) async {
      final app = await pumpApp(tester);
      app.effects.clipboardWorks = false;
      await tester.longPress(_highlightRow('Song of Storms'));
      await tester.pump();
      expect(find.text('Couldn’t copy'), findsOneWidget);
      expect(find.text('Copied'), findsNothing);
      await waitForMessage(tester);
    });

    testWidgets('is offered to screen readers, named "Copy title and artist"', (tester) async {
      final handle = tester.ensureSemantics();
      final app = await pumpApp(tester);
      for (final row in [_highlightRow('Song of Storms')]) {
        final data = _rowSemantics(tester, row);
        expect(data.hasAction(SemanticsAction.longPress), isTrue);
        expect(_longPressHint(data), 'Copy title and artist');
      }
      await goToTab(tester, 'Ong Log');
      final data = _rowSemantics(tester, _playRow('Lost Woods'));
      expect(data.hasAction(SemanticsAction.longPress), isTrue);
      expect(_longPressHint(data), 'Copy title and artist');
      final node = tester.getSemantics(
        find.descendant(of: _playRow('Lost Woods'), matching: find.byType(InkWell)).first,
      );
      tester.semantics.longPress(find.semantics.byPredicate((n) => n.id == node.id));
      await tester.pump();
      expect(app.effects.clipboard, 'Zelda - Lost Woods');
      await waitForMessage(tester);
      handle.dispose();
    });

    testWidgets('in an expanded window: copies, and leaves the selection as it was', (tester) async {
      final app = await pumpApp(tester, size: const Size(1280, 800));
      List<bool?> selection() => [
        for (final row in tester.widgetList<HighlightRow>(find.byType(HighlightRow))) row.selected,
      ];
      final before = selection();
      expect(before.where((s) => s ?? false), hasLength(1));
      expect(tester.widget<HighlightRow>(_highlightRow('Song of Storms')).selected, isFalse);
      await tester.longPress(_highlightRow('Song of Storms'));
      await tester.pump();
      expect(app.effects.clipboard, 'Zelda - Song of Storms');
      expect(selection(), before);
      await waitForMessage(tester);
    });

    testWidgets('desktop look: a finger copies, a mouse held down still clicks', (tester) async {
      final app = await pumpApp(tester, desktop: true, size: const Size(1280, 800));
      await goToTab(tester, 'Ong Log');
      await tester.longPress(_playRow('Lost Woods'));
      await tester.pump();
      expect(app.effects.clipboard, 'Zelda - Lost Woods');
      await waitForMessage(tester);

      app.effects.clipboard = null;
      final mouse = await tester.startGesture(
        tester.getCenter(_playRow('Song of Storms')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(seconds: 1));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(app.effects.clipboard, isNull);
      expect(find.text('Copied'), findsNothing);
      expect(find.byType(SongSheet), findsOneWidget, reason: 'the slow click opened the song, in the pane');
    });
  });

  group('The copy button of a fiche', () {
    Future<void> openHighlight(WidgetTester tester, String track) async {
      await tester.tap(find.descendant(of: _highlightRow(track), matching: detailsButtons()));
      await tester.pumpAndSettle();
    }

    testWidgets('of a highlight: beside the title, left of the star; a check mark for 2 s, nothing moves', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await openHighlight(tester, 'I Will Survive');
      final button = _copyTitle();
      expect(tester.widget<IconButton>(button).tooltip, 'Copy title and artist');
      // a plain icon, not a tonal circle
      expect(
        tester.widget<Material>(find.descendant(of: button, matching: find.byType(Material)).first).color,
        Colors.transparent,
      );
      final star = find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'Add to favourites');
      final rect = tester.getRect(button);
      expect(rect.size, const Size(48, 48), reason: 'the tap target of the theme, as the star');
      expect(rect.right, tester.getRect(star).left);
      expect(rect.center.dy, tester.getRect(star).center.dy);
      final title = find.descendant(of: find.byType(HighlightSheet), matching: find.byType(SelectableText)).first;
      expect(tester.getRect(title).right, lessThanOrEqualTo(rect.left));
      final parts = [
        button,
        star,
        title,
        find.text('Gloria Gaynor'),
        find.byTooltip('Copy title and link'),
        find.text('Watch on YouTube'),
      ];
      List<Rect> rects() => [for (final p in parts) tester.getRect(p.first)];
      final before = rects();

      await tester.tap(button);
      await tester.pump();
      expect(app.effects.clipboard, 'Gloria Gaynor - I Will Survive');
      expect(tester.takeAnnouncements().map((a) => a.message), ['Copied']);
      await tester.pumpAndSettle();
      expect(find.descendant(of: button, matching: find.byIcon(Icons.check)), findsOneWidget);
      expect(tester.widget<IconButton>(button).tooltip, 'Copied');
      expect(find.text('Copied'), findsNothing, reason: 'no message');
      expect(rects(), before);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.descendant(of: button, matching: find.byIcon(Icons.copy)), findsOneWidget);
      expect(tester.widget<IconButton>(button).tooltip, 'Copy title and artist');
      expect(rects(), before);
    });

    testWidgets('of a song: beside the title, the same text', (tester) async {
      final app = await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      await tester.tap(find.text('Lost Woods'));
      await tester.pumpAndSettle();
      expect(find.byType(SongSheet), findsOneWidget);
      final title = find.descendant(of: find.byType(SongSheet), matching: find.byType(SelectableText)).first;
      final titleTop = tester.getRect(title).top;
      expect(tester.getRect(title).right, lessThanOrEqualTo(tester.getRect(_copyTitle()).left));
      await tester.tap(_copyTitle());
      await tester.pumpAndSettle();
      expect(app.effects.clipboard, 'Zelda - Lost Woods');
      expect(tester.widget<IconButton>(_copyTitle()).tooltip, 'Copied');
      expect(tester.getRect(title).top, titleTop);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('without artist: "Copy title", the title alone; a refusal said in a message', (tester) async {
      final catalogue = catalogueOf(
        highlights: [hRow(order: '1', title: 'Tune', link: 'https://youtu.be/abcdefghijk')],
      );
      final app = await pumpApp(
        tester,
        state: CatalogueState(catalogue: catalogue, fetchedAt: testNow),
      );
      await openHighlight(tester, 'Tune');
      expect(tester.widget<IconButton>(_copyTitle()).tooltip, 'Copy title');
      await tester.tap(_copyTitle());
      await tester.pumpAndSettle();
      expect(app.effects.clipboard, 'Tune');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      app.effects.clipboardWorks = false;
      await tester.tap(_copyTitle());
      await tester.pump();
      expect(find.text('Couldn’t copy'), findsOneWidget);
      expect(find.descendant(of: _copyTitle(), matching: find.byIcon(Icons.check)), findsNothing);
      await waitForMessage(tester);
    });

    testWidgets('desktop: 40 px, as the star', (tester) async {
      await pumpApp(tester, pointer: PointerKind.mouse);
      await openHighlight(tester, 'Song of Storms');
      expect(tester.getSize(_copyTitle()), const Size(40, 40));
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });
}
