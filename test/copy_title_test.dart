// The copy buttons of a fiche: the small one beside the title (the title as the sheets write it, "Artist - Track"),
// and the tonal one under it (the title and the link), in two columns with the star and Share.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/ui/actions.dart';
import 'package:ong_music/src/ui/layout.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/sheets.dart';
import 'package:ong_music/src/ui/widgets.dart';

import 'ui_harness.dart';

Finder _highlightRow(String track) => find.ancestor(of: find.text(track), matching: find.byType(HighlightRow)).first;

/// The copy button beside the title of the fiche on screen, whatever its state.
Finder _copyTitle() => find.byWidgetPredicate(
  (w) => w is IconButton && (w.tooltip == 'Copy title' || w.tooltip == 'Copied') && w.icon is AnimatedSwitcher,
);

Finder _tooltip(String tooltip) => find.byWidgetPredicate((w) => w is IconButton && w.tooltip == tooltip);

Finder _star() => _tooltip('Add to favourites');

Future<void> _openHighlight(WidgetTester tester, String track) async {
  await tester.tap(find.descendant(of: _highlightRow(track), matching: detailsButtons()));
  await tester.pumpAndSettle();
}

void main() {
  test('the text copied is the title as the sheets write it, "Artist - Track", the track alone without artist', () {
    expect(songCopyText('Gloria Gaynor - I Will Survive'), 'Gloria Gaynor - I Will Survive');
    expect(songCopyText('GarbageHag'), 'GarbageHag');
  });

  group('The highlight fiche', () {
    testWidgets('a copy icon beside the title, a link icon under it; a check mark for 2 s, nothing moves', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await _openHighlight(tester, 'I Will Survive');
      final button = _copyTitle();
      expect(tester.widget<IconButton>(button).tooltip, 'Copy title', reason: 'with an artist too');
      expect(find.descendant(of: button, matching: find.byIcon(Icons.copy)), findsOneWidget);
      // a plain icon, not a tonal circle
      expect(
        tester.widget<Material>(find.descendant(of: button, matching: find.byType(Material)).first).color,
        Colors.transparent,
      );
      final link = _tooltip('Copy title and link');
      expect(find.descendant(of: link, matching: find.byIcon(Icons.link)), findsOneWidget);
      final title = find.descendant(of: find.byType(HighlightSheet), matching: find.byType(SelectableText)).first;
      expect(tester.getRect(title).right, lessThanOrEqualTo(tester.getRect(button).left));
      final parts = [button, _star(), title, find.text('Gloria Gaynor'), find.text('Watch on YouTube')];
      List<Rect> rects() => [for (final p in parts) tester.getRect(p.first)];
      final before = rects();
      final linkRect = tester.getRect(link);

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
      expect(rects(), before);

      // the tonal button keeps its check mark, in its own place
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(app.effects.clipboard, 'Gloria Gaynor - I Will Survive — https://youtu.be/bbbbbbbbbbb');
      final copied = find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'Copied');
      expect(find.descendant(of: copied, matching: find.byIcon(Icons.check)), findsOneWidget);
      expect(tester.getRect(copied), linkRect);
      expect(rects(), before);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('two columns: the copy icon over Share, the star over the link; 48 px targets', (tester) async {
      await pumpApp(tester);
      await _openHighlight(tester, 'I Will Survive');
      final copy = tester.getRect(_copyTitle());
      final star = tester.getRect(_star());
      expect((copy.size, star.size), (const Size(48, 48), const Size(48, 48)));
      expect(copy.center.dx, tester.getRect(_tooltip('Share')).center.dx);
      expect(star.center.dx, tester.getRect(_tooltip('Copy title and link')).center.dx);
      expect(copy.center.dy, star.center.dy);
    });

    testWidgets('without share sheet: the star over the link, the copy icon at the same distance from it', (
      tester,
    ) async {
      await pumpApp(tester, canShare: false);
      await _openHighlight(tester, 'I Will Survive');
      final copy = tester.getRect(_copyTitle());
      final star = tester.getRect(_star());
      expect(star.center.dx, tester.getRect(_tooltip('Copy title and link')).center.dx);
      expect(star.center.dx - copy.center.dx, 48 + 8);
    });

    testWidgets('without video: no copy button beside the title, the tonal one copies the title alone', (tester) async {
      final app = await pumpApp(tester);
      await _openHighlight(tester, "How Far I'll Go");
      expect(_copyTitle(), findsNothing);
      final tonal = _tooltip('Copy title');
      expect(
        find.descendant(of: tonal, matching: find.byIcon(Icons.copy)),
        findsOneWidget,
        reason: 'it copies no link',
      );
      // the title has the room up to the star, which stands over the tonal button
      final title = find.descendant(of: find.byType(HighlightSheet), matching: find.byType(SelectableText)).first;
      final block = find.ancestor(of: title, matching: find.byType(Expanded)).first;
      expect(tester.getRect(block).right, tester.getRect(_star()).left);
      expect(tester.getRect(_star()).center.dx, tester.getRect(tonal).center.dx);
      await tester.tap(tonal);
      await tester.pumpAndSettle();
      expect(app.effects.clipboard, "Moana - How Far I'll Go");
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a refusal of the clipboard: said in a message, no check mark', (tester) async {
      final app = await pumpApp(tester);
      await _openHighlight(tester, 'I Will Survive');
      app.effects.clipboardWorks = false;
      await tester.tap(_copyTitle());
      await tester.pump();
      expect(find.text('Couldn’t copy'), findsOneWidget);
      expect(find.descendant(of: _copyTitle(), matching: find.byIcon(Icons.check)), findsNothing);
      await waitForMessage(tester);
    });

    testWidgets('desktop: 40 px, as the star, in the same two columns', (tester) async {
      await pumpApp(tester, pointer: PointerKind.mouse);
      await _openHighlight(tester, 'I Will Survive');
      expect(tester.getSize(_copyTitle()), const Size(40, 40));
      expect(tester.getRect(_copyTitle()).center.dx, tester.getRect(_tooltip('Share')).center.dx);
      expect(tester.getRect(_star()).center.dx, tester.getRect(_tooltip('Copy title and link')).center.dx);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });

  group('The song fiche', () {
    Future<void> openSong(WidgetTester tester) async {
      await goToTab(tester, 'Ong Log');
      await tester.tap(find.text('I Will Survive').first);
      await tester.pumpAndSettle();
      expect(find.byType(SongSheet), findsOneWidget);
    }

    /// The right edge of the glyph of the copy button, and those of the type icons of the rows under it: the middle of
    /// each icon, plus half its size (a type icon has a box wider than its glyph).
    (double, List<double>) iconEnds(WidgetTester tester) {
      double end(Finder icon) =>
          tester.getRect(icon).center.dx +
          (tester.widget<Icon>(icon).size ?? IconTheme.of(tester.element(icon)).size!) / 2;
      final copy = find.descendant(of: _copyTitle(), matching: find.byType(Icon));
      final icons = find.descendant(
        of: find.descendant(of: find.byType(SongSheet), matching: find.byType(PlayTypeIcon)),
        matching: find.byType(Icon),
      );
      return (end(copy), [for (var i = 0; i < icons.evaluate().length; i++) end(icons.at(i))]);
    }

    testWidgets('the copy icon in the column of the type icons of the rows; the same text', (tester) async {
      final app = await pumpApp(tester);
      await openSong(tester);
      expect(tester.widget<IconButton>(_copyTitle()).tooltip, 'Copy title');
      expect(tester.getSize(_copyTitle()), const Size(48, 48));
      final (copy, types) = iconEnds(tester);
      expect(types, isNotEmpty);
      for (final end in types) {
        expect(copy, end);
      }
      expect(tester.getRect(_copyTitle()).right, lessThanOrEqualTo(tester.getRect(find.byType(SongSheet)).right));
      final title = find.descendant(of: find.byType(SongSheet), matching: find.byType(SelectableText)).first;
      expect(tester.getRect(title).right, lessThanOrEqualTo(tester.getRect(_copyTitle()).left));
      await tester.tap(_copyTitle());
      await tester.pumpAndSettle();
      expect(app.effects.clipboard, 'Gloria Gaynor - I Will Survive');
      expect(tester.widget<IconButton>(_copyTitle()).tooltip, 'Copied');
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('desktop: the same column, with a 40 px box', (tester) async {
      await pumpApp(tester, pointer: PointerKind.mouse);
      await openSong(tester);
      expect(tester.getSize(_copyTitle()), const Size(40, 40));
      final (copy, types) = iconEnds(tester);
      for (final end in types) {
        expect(copy, end);
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });
}
