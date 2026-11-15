// The menu of a row: a long press with a finger or a stylus, a right click in the native apps, the long press action
// of screen readers. Copy title, Copy link, Share, the star, Watch on YouTube.
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/state/settings_state.dart';
import 'package:ong_music/src/ui/instant_feedback.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/sheets.dart';
import 'package:ong_music/src/ui/widgets.dart';

import 'ui_harness.dart';

Finder _highlightRow(String track) => find.ancestor(of: find.text(track), matching: find.byType(HighlightRow)).first;

Finder _playRow(String track) => find.ancestor(of: find.text(track), matching: find.byType(PlayRow)).first;

/// The items of the open menu, in their order.
List<String> _items(WidgetTester tester) => [
  for (final item in tester.widgetList<PopupMenuItem<void>>(find.byType(PopupMenuItem<void>)))
    tester
        .widgetList<Text>(find.descendant(of: find.byWidget(item), matching: find.byType(Text)))
        .map((t) => t.data!)
        .join(),
];

/// The icons of the open menu, in their order.
List<IconData?> _icons(WidgetTester tester) => [
  for (final item in tester.widgetList<PopupMenuItem<void>>(find.byType(PopupMenuItem<void>)))
    tester.widget<Icon>(find.descendant(of: find.byWidget(item), matching: find.byType(Icon))).icon,
];

Future<void> _longPress(WidgetTester tester, Finder row) async {
  await tester.longPress(row);
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String item) async {
  await tester.tap(find.descendant(of: find.byType(PopupMenuItem<void>), matching: find.text(item)));
  await tester.pump();
}

/// The hint screen readers give for the long press of [data] (an overriding custom action).
String? _longPressHint(SemanticsData data) => [
  for (final id in data.customSemanticsActionIds ?? const <int>[])
    if (CustomSemanticsAction.getAction(id) case final action? when action.action == SemanticsAction.longPress)
      action.hint,
].singleOrNull;

void main() {
  group('A highlight row', () {
    testWidgets('a long press: the menu, with the haptic feedback; nothing else happens', (tester) async {
      final app = await pumpApp(tester);
      await _longPress(tester, _highlightRow('I Will Survive'));
      expect(_items(tester), ['Copy title', 'Copy link', 'Share', 'Add to favourites']);
      expect(_icons(tester), [Icons.copy, Icons.link, Icons.share, Icons.star_border]);
      expect(app.effects.haptics, 1);
      expect(app.effects.opened, isEmpty, reason: 'the video does not open');
      expect(find.byType(HighlightSheet), findsNothing);
    });

    testWidgets('each item does what it says', (tester) async {
      final app = await pumpApp(tester);
      final row = _highlightRow('I Will Survive');
      await _longPress(tester, row);
      await _choose(tester, 'Copy title');
      expect(app.effects.clipboard, 'Gloria Gaynor - I Will Survive');
      expect(find.text('Copied'), findsOneWidget, reason: 'the version of Android unknown: the message');
      await waitForMessage(tester);
      expect(find.byType(PopupMenuItem<void>), findsNothing, reason: 'closed by the choice');

      await _longPress(tester, row);
      await _choose(tester, 'Copy link');
      expect(app.effects.clipboard, 'https://youtu.be/bbbbbbbbbbb');
      await waitForMessage(tester);

      await _longPress(tester, row);
      await _choose(tester, 'Share');
      await tester.pumpAndSettle();
      expect(app.effects.shared, ['Gloria Gaynor - I Will Survive — https://youtu.be/bbbbbbbbbbb']);

      await _longPress(tester, row);
      await _choose(tester, 'Add to favourites');
      await tester.pumpAndSettle();
      expect(app.prefs.getStringList(FavouritesNotifier.key), ['bbbbbbbbbbb']);
      await _longPress(tester, row);
      expect(_items(tester).last, 'Remove from favourites');
      expect(_icons(tester).last, Icons.star);
      await _choose(tester, 'Remove from favourites');
      await tester.pumpAndSettle();
      expect(app.prefs.getStringList(FavouritesNotifier.key), isEmpty);
    });

    testWidgets('without video: no link, nothing to share; without share sheet: no Share', (tester) async {
      await pumpApp(tester);
      await _longPress(tester, _highlightRow("How Far I'll Go"));
      expect(_items(tester), ['Copy title', 'Add to favourites']);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<void>), findsNothing, reason: 'closed by a tap outside');
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, canShare: false);
      await _longPress(tester, _highlightRow('I Will Survive'));
      expect(_items(tester), ['Copy title', 'Copy link', 'Add to favourites']);
    });

    testWidgets('a mouse held down never opens it: the slow click opens the video', (tester) async {
      final app = await pumpApp(tester);
      final mouse = await tester.startGesture(
        tester.getCenter(_highlightRow('Song of Storms')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(seconds: 1));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<void>), findsNothing);
      expect(app.effects.opened.single.toString(), contains('aaaaaaaaaaa'));
      expect(app.effects.haptics, 0);
    });

    testWidgets('a right click opens it where the pointer is', (tester) async {
      final app = await pumpApp(tester);
      // (near the left edge: the menu fits at the right of the pointer)
      final at = tester.getTopLeft(_highlightRow('Song of Storms')) + const Offset(30, 20);
      final mouse = await tester.startGesture(at, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await mouse.up();
      await tester.pumpAndSettle();
      expect(_items(tester).first, 'Copy title');
      final menu = tester.getRect(find.byType(PopupMenuItem<void>).first);
      expect((menu.left - at.dx).abs(), lessThan(1), reason: 'its corner at the pointer');
      expect(app.effects.opened, isEmpty);
    });

    testWidgets('closes on Android Back and on Escape, nothing else closing with it', (tester) async {
      final app = await pumpApp(tester);
      await _longPress(tester, _highlightRow('I Will Survive'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<void>), findsNothing);
      expect(app.effects.exits, 0);
      await _longPress(tester, _highlightRow('I Will Survive'));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<void>), findsNothing);
      expect(selectedTab(tester), 0);
    });

    testWidgets('kept inside the window, clear of the system bars; the row tinted while it is open', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 48);
      await pumpApp(tester);
      final row = _highlightRow("How Far I'll Go");
      Color tint() =>
          (tester
                      .widget<DecoratedBox>(
                        find
                            .descendant(
                              of: row,
                              matching: find.byWidgetPredicate(
                                (w) => w is DecoratedBox && w.position == DecorationPosition.foreground,
                              ),
                            )
                            .first,
                      )
                      .decoration
                  as ShapeDecoration)
              .color!;
      expect(tint().a, 0);
      final finger = await tester.startGesture(tester.getBottomRight(row) - const Offset(2, 2));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      await finger.up();
      await tester.pumpAndSettle();
      final menu = tester.getRect(find.byType(PopupMenuItem<void>).last);
      expect(menu.right, lessThanOrEqualTo(412));
      expect(menu.bottom, lessThanOrEqualTo(892 - 48));
      expect(tint().a, greaterThan(0));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tint().a, 0);
    });

    testWidgets('screen readers: a long press action named "Shows more actions", which opens it', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      final ink = find.descendant(of: _highlightRow('I Will Survive'), matching: find.byType(AppInkWell)).first;
      final node = tester.getSemantics(ink);
      expect(node.getSemanticsData().hasAction(SemanticsAction.longPress), isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(_longPressHint(node.getSemanticsData()), 'Shows more actions');
      tester.semantics.longPress(find.semantics.byPredicate((n) => n.id == node.id));
      await tester.pumpAndSettle();
      expect(_items(tester).first, 'Copy title');
      handle.dispose();
    });

    testWidgets('in an expanded window: the selection stays as it was', (tester) async {
      await pumpApp(tester, size: const Size(1280, 800));
      List<bool?> selection() => [
        for (final row in tester.widgetList<HighlightRow>(find.byType(HighlightRow))) row.selected,
      ];
      final before = selection();
      await _longPress(tester, _highlightRow('Song of Storms'));
      expect(_items(tester), isNotEmpty);
      expect(selection(), before);
    });
  });

  group('After a copy', () {
    testWidgets('Android 13 and higher: no message, the system shows the copy; screen readers hear "Copied"', (
      tester,
    ) async {
      final app = await pumpApp(tester, androidSdk: 36);
      await _longPress(tester, _highlightRow('I Will Survive'));
      tester.takeAnnouncements();
      await _choose(tester, 'Copy title');
      await tester.pumpAndSettle();
      expect(app.effects.clipboard, 'Gloria Gaynor - I Will Survive');
      expect(find.text('Copied'), findsNothing);
      expect(tester.takeAnnouncements().map((a) => a.message), ['Copied']);
    });

    testWidgets('Android 12 and lower: the message', (tester) async {
      await pumpApp(tester, androidSdk: 32);
      await _longPress(tester, _highlightRow('I Will Survive'));
      await _choose(tester, 'Copy link');
      expect(find.text('Copied'), findsOneWidget);
      await waitForMessage(tester);
    });

    testWidgets('a refusal of the clipboard: "Couldn’t copy", everywhere', (tester) async {
      final app = await pumpApp(tester, androidSdk: 36);
      app.effects.clipboardWorks = false;
      await _longPress(tester, _highlightRow('I Will Survive'));
      await _choose(tester, 'Copy title');
      expect(find.text('Couldn’t copy'), findsOneWidget);
      await waitForMessage(tester);
    });
  });

  group('A play row', () {
    testWidgets('with a video: copy, watch, copy the link, share', (tester) async {
      final app = await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      final row = find.ancestor(of: find.byType(VideoPill).first, matching: find.byType(PlayRow));
      final title = tester.widget<PlayRow>(row).play.title;
      final video = tester.widget<PlayRow>(row).catalogue.highlightOf(tester.widget<PlayRow>(row).play)!.youtubeId!;
      await _longPress(tester, row);
      expect(_items(tester), ['Copy title', 'Watch on YouTube', 'Copy link', 'Share']);
      expect(_icons(tester), [Icons.copy, Icons.play_arrow, Icons.link, Icons.share]);
      expect(find.byType(SongSheet), findsNothing, reason: 'the song does not open');
      await _choose(tester, 'Watch on YouTube');
      await tester.pumpAndSettle();
      expect(app.effects.opened.single.toString(), contains(video));
      await _longPress(tester, row);
      await _choose(tester, 'Copy title');
      expect(app.effects.clipboard, title);
      await waitForMessage(tester);
      await _longPress(tester, row);
      await _choose(tester, 'Copy link');
      expect(app.effects.clipboard, 'https://youtu.be/$video');
      await waitForMessage(tester);
      await _longPress(tester, row);
      await _choose(tester, 'Share');
      await tester.pumpAndSettle();
      expect(app.effects.shared.single, endsWith('https://youtu.be/$video'));
    });

    testWidgets('without video: Copy title alone; in a setlist too, above its sheet', (tester) async {
      final app = await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      await _longPress(tester, _playRow('Lost Woods'));
      expect(_items(tester), ['Copy title']);
      await _choose(tester, 'Copy title');
      expect(app.effects.clipboard, 'Zelda - Lost Woods');
      await waitForMessage(tester);

      await tester.tap(find.text('Fri 1 Mar 2024'));
      await tester.pumpAndSettle();
      final inSheet = find.ancestor(
        of: find.descendant(of: find.byType(StreamSheet), matching: find.text('Lost Woods')),
        matching: find.byType(PlayRow),
      );
      await _longPress(tester, inSheet);
      expect(_items(tester), ['Copy title']);
      expect(find.byType(StreamSheet), findsOneWidget);
    });

    testWidgets('screen readers: the same action, named', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      final ink = find.descendant(of: _playRow('Lost Woods'), matching: find.byType(AppInkWell)).first;
      expect(_longPressHint(tester.getSemantics(ink).getSemanticsData()), 'Shows more actions');
      handle.dispose();
    });
  });

  group('Desktop look', () {
    testWidgets('a finger opens it, with the haptic feedback; a mouse held down still clicks', (tester) async {
      final app = await pumpApp(tester, desktop: true, size: const Size(1280, 800));
      await goToTab(tester, 'Ong Log');
      await _longPress(tester, _playRow('Lost Woods'));
      expect(_items(tester), ['Copy title']);
      expect(app.effects.haptics, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      final mouse = await tester.startGesture(
        tester.getCenter(_playRow('Song of Storms')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(seconds: 1));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<void>), findsNothing);
      expect(find.byType(SongSheet), findsOneWidget, reason: 'the slow click opened the song, in the pane');
    });

    testWidgets('screen readers: the long press action, named, which opens it', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, desktop: true);
      final row = _highlightRow('I Will Survive');
      final node = tester.getSemantics(find.descendant(of: row, matching: find.byType(AppInkWell)).first);
      expect(node.getSemanticsData().hasAction(SemanticsAction.longPress), isTrue);
      expect(_longPressHint(node.getSemanticsData()), 'Shows more actions');
      tester.semantics.longPress(find.semantics.byPredicate((n) => n.id == node.id));
      await tester.pumpAndSettle();
      expect(_items(tester).first, 'Copy title');
      handle.dispose();
    });
  });
}
