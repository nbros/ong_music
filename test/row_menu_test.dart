// The menu of a row: a long press with a finger or a stylus, a right click (in the web app, not on a link of the page,
// whose menu stays the browser's), the long press action of screen readers. Copy title, Copy link, Share, the star,
// Watch on YouTube.
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/state/settings_state.dart';
import 'package:ong_music/src/ui/instant_feedback.dart';
import 'package:ong_music/src/ui/row_menu.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/sheets.dart';
import 'package:ong_music/src/ui/widgets.dart';
import 'package:ong_music/src/web/context_menu.dart';

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

/// A click of the mouse's secondary button at [at].
Future<void> _rightClick(WidgetTester tester, Offset at) async {
  final mouse = await tester.startGesture(at, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
  await mouse.up();
  await tester.pumpAndSettle();
}

/// The browser's side of a right click in the web app: the pointer goes down on a link of the page when [onLink].
class FakeContextMenus implements ContextMenus {
  bool onLink = false;

  /// The answers to the claims of the app, in order.
  final claims = <bool>[];

  /// The states of the app's menu the app reported, in order.
  final reported = <bool>[];

  bool _appMenuOpen = false;

  @override
  bool claimClick() {
    claims.add(!onLink);
    return !onLink;
  }

  @override
  bool get appMenuOpen => _appMenuOpen;

  @override
  set appMenuOpen(bool open) {
    _appMenuOpen = open;
    reported.add(open);
  }
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

/// The surface of the open menu.
Finder _surface() => find.ancestor(of: find.byType(PopupMenuItem<void>).first, matching: find.byType(Material)).first;

/// How opaque [finder] is drawn: the product of the fades above it.
double _opacity(WidgetTester tester, Finder finder) => tester
    .widgetList<FadeTransition>(find.ancestor(of: finder, matching: find.byType(FadeTransition)))
    .fold(1.0, (opacity, fade) => opacity * fade.opacity.value);

/// The opacities of the open menu's surface and of each of its items, in their order.
List<double> _opacities(WidgetTester tester) => [
  _opacity(tester, _surface()),
  for (var i = 0; i < find.byType(PopupMenuItem<void>).evaluate().length; i++)
    _opacity(tester, find.byType(PopupMenuItem<void>).at(i)),
];

/// The places of the open menu's surface and of each of its items, in their order.
List<Rect> _rects(WidgetTester tester) => [
  tester.getRect(_surface()),
  for (var i = 0; i < find.byType(PopupMenuItem<void>).evaluate().length; i++)
    tester.getRect(find.byType(PopupMenuItem<void>).at(i)),
];

/// Follows the fade of a menu that has just been asked for (by the frame drawn next): at its full size and in its
/// place from that frame on, all of it equally opaque, more and more, opaque at [rowMenuFadeIn].
Future<void> _expectFadeIn(WidgetTester tester) async {
  await tester.pump();
  expect(find.byType(PopupMenuItem<void>), findsWidgets);
  final first = _rects(tester);
  final seen = <double>[];
  for (final step in const [16, 44, 60]) {
    await tester.pump(Duration(milliseconds: step));
    final opacities = _opacities(tester);
    expect(opacities.toSet(), hasLength(1), reason: 'the surface and the items together, no item after another');
    expect(_rects(tester), first, reason: 'nothing grows, nothing moves (at ${seen.length})');
    seen.add(opacities.first);
  }
  expect(seen[0], inExclusiveRange(0, 1));
  expect(seen[1], inExclusiveRange(seen[0], 1));
  expect(seen[2], 1, reason: 'opaque at the end of the fade, ${rowMenuFadeIn.inMilliseconds} ms');
  await tester.pumpAndSettle();
  expect(_rects(tester), first);
  expect(_opacities(tester).toSet(), {1.0});
}

/// A window of [size] (system bars of [padding]) filled with one row whose menu has [count] items.
Future<void> _pumpBare(
  WidgetTester tester, {
  Size size = const Size(412, 892),
  FakeViewPadding padding = FakeViewPadding.zero,
  int count = 3,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = padding;
  tester.view.viewPadding = padding;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [contextMenusProvider.overrideWith((ref) => null)],
      child: MaterialApp(
        theme: theme,
        home: Material(
          child: RowMenuArea(
            items: (context, ref) => [
              for (var i = 0; i < count; i++) (icon: Icons.copy, label: 'Item $i', onSelected: () {}),
            ],
            child: const SizedBox.expand(),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('A highlight row', () {
    testWidgets('a long press: the menu, with the haptic feedback; nothing else happens', (tester) async {
      final app = await pumpApp(tester);
      await _longPress(tester, _highlightRow('I Will Survive'));
      expect(_items(tester), ['Copy title', 'Copy video link', 'Share', 'Add to favourites']);
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
      await _choose(tester, 'Copy video link');
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
      expect(_items(tester), ['Copy title', 'Copy video link', 'Add to favourites']);
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

    testWidgets('a right click opens it where the pointer is (the native apps: no menu of a browser)', (tester) async {
      final app = await pumpApp(tester);
      // (near the left edge: the menu fits at the right of the pointer)
      final at = tester.getTopLeft(_highlightRow('Song of Storms')) + const Offset(30, 20);
      await _rightClick(tester, at);
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

  group('In the web app', () {
    testWidgets('the browser\'s side is there as a row comes in, before the first right click', (tester) async {
      // (it only knows whether a pointer went down on a link if it was listening then)
      var made = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contextMenusProvider.overrideWith((ref) {
              made++;
              return FakeContextMenus();
            }),
          ],
          child: MaterialApp(
            home: Material(
              child: RowMenuArea(items: (context, ref) => const [], child: const SizedBox(width: 100, height: 50)),
            ),
          ),
        ),
      );
      expect(made, 1);
    });

    testWidgets('a right click on a row: its menu at the pointer, the browser\'s kept closed, reported open', (
      tester,
    ) async {
      final menus = FakeContextMenus();
      final app = await pumpApp(tester, contextMenus: menus, links: FakeLinkAnchors());
      final at = tester.getTopLeft(_highlightRow('Song of Storms')) + const Offset(30, 20);
      await _rightClick(tester, at);
      expect(_items(tester).first, 'Copy title');
      expect((tester.getRect(find.byType(PopupMenuItem<void>).first).left - at.dx).abs(), lessThan(1));
      expect(menus.claims, [true], reason: 'claimed at the pointer down');
      expect(menus.appMenuOpen, isTrue, reason: 'a right click that closes it opens no menu of the browser');
      expect(app.effects.opened, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<void>), findsNothing);
      expect(menus.reported, [true, false]);
      expect(menus.appMenuOpen, isFalse);
    });

    testWidgets('a right click closing the menu: claims nothing, opens nothing more', (tester) async {
      final menus = FakeContextMenus();
      await pumpApp(tester, contextMenus: menus);
      await _rightClick(tester, tester.getTopLeft(_highlightRow('Song of Storms')) + const Offset(30, 20));
      // on the barrier, outside the menu
      await _rightClick(tester, const Offset(400, 880));
      expect(find.byType(PopupMenuItem<void>), findsNothing);
      expect(menus.claims, [true], reason: 'the barrier is not a row');
      expect(menus.reported, [true, false]);
    });

    testWidgets('a right click on a link of the page: the browser\'s menu alone, the row\'s does not open', (
      tester,
    ) async {
      final menus = FakeContextMenus()..onLink = true;
      final app = await pumpApp(tester, contextMenus: menus, links: FakeLinkAnchors());
      final row = _highlightRow('Song of Storms');
      await _rightClick(tester, tester.getCenter(row));
      expect(find.byType(PopupMenuItem<void>), findsNothing);
      expect(menus.claims, [false]);
      expect(menus.reported, isEmpty);
      expect(app.effects.opened, isEmpty, reason: 'nor the video');
      // the next right click, off the link: the row's again
      menus.onLink = false;
      await _rightClick(tester, tester.getCenter(row));
      expect(_items(tester).first, 'Copy title');
      expect(menus.claims, [false, true]);
    });

    testWidgets('a right click on a play row too', (tester) async {
      final menus = FakeContextMenus();
      await pumpApp(tester, contextMenus: menus);
      await goToTab(tester, 'Ong Log');
      await _rightClick(tester, tester.getTopLeft(_playRow('Lost Woods')) + const Offset(30, 20));
      expect(_items(tester), ['Copy title']);
      expect(menus.claims, [true]);
      menus.onLink = true;
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await _rightClick(tester, tester.getTopLeft(_playRow('Lost Woods')) + const Offset(30, 20));
      expect(find.byType(PopupMenuItem<void>), findsNothing);
    });

    testWidgets('a left click claims nothing; a long press with a finger reports the menu open', (tester) async {
      final menus = FakeContextMenus();
      final app = await pumpApp(tester, contextMenus: menus);
      final mouse = await tester.startGesture(
        tester.getCenter(_highlightRow('Song of Storms')),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.up();
      await tester.pumpAndSettle();
      expect(app.effects.opened.single.toString(), contains('aaaaaaaaaaa'));
      expect(menus.claims, isEmpty);
      await _longPress(tester, _highlightRow('I Will Survive'));
      expect(_items(tester).first, 'Copy title');
      expect(menus.claims, isEmpty);
      expect(menus.reported, [true]);
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
      await _choose(tester, 'Copy video link');
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
      expect(_items(tester), ['Copy title', 'Watch on YouTube', 'Copy video link', 'Share']);
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
      await _choose(tester, 'Copy video link');
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
  group('Its fade', () {
    testWidgets('a right click: the whole menu fades in, at its full size and in its place from the first frame', (
      tester,
    ) async {
      await pumpApp(tester);
      final mouse = await tester.startGesture(
        tester.getTopLeft(_highlightRow('Song of Storms')) + const Offset(30, 20),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await mouse.up();
      await _expectFadeIn(tester);
    });

    testWidgets('a long press with a finger: the same fade', (tester) async {
      await pumpApp(tester);
      final finger = await tester.startGesture(tester.getCenter(_highlightRow('I Will Survive')));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await finger.up();
      expect(find.byType(PopupMenuItem<void>), findsWidgets, reason: 'asked for');
      final first = _rects(tester);
      expect(_opacities(tester).toSet(), hasLength(1));
      expect(_opacities(tester).first, lessThan(1));
      await tester.pumpAndSettle();
      expect(_rects(tester), first);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.longPress(_highlightRow('I Will Survive'));
      // (the long press of the tester pumps no frame after it: the menu is asked for)
      await _expectFadeIn(tester);
    });

    testWidgets('closing: a short fade out, in its place, then nothing', (tester) async {
      await pumpApp(tester);
      await _longPress(tester, _highlightRow('I Will Survive'));
      final rects = _rects(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 45));
      expect(_rects(tester), rects);
      expect(_opacities(tester).toSet(), hasLength(1));
      expect(_opacities(tester).first, inExclusiveRange(0, 1));
      await tester.pump(rowMenuFadeOut - const Duration(milliseconds: 45));
      expect(_opacities(tester).toSet(), {0.0}, reason: 'faded out at ${rowMenuFadeOut.inMilliseconds} ms');
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(PopupMenuItem<void>), findsNothing, reason: 'gone the frame after');
    });

    testWidgets('with less motion: there at once, gone at once, by a finger or a mouse', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpApp(tester);
      final finger = await tester.startGesture(tester.getCenter(_highlightRow('I Will Survive')));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await finger.up();
      expect(_opacities(tester).toSet(), {1.0}, reason: 'fully shown at the first frame');
      final rects = _rects(tester);
      await tester.pumpAndSettle();
      expect(_rects(tester), rects);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(PopupMenuItem<void>), findsNothing, reason: 'gone at the first frame');

      final mouse = await tester.startGesture(
        tester.getTopLeft(_highlightRow('Song of Storms')) + const Offset(30, 20),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await mouse.up();
      await tester.pump();
      expect(_opacities(tester).toSet(), {1.0});
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      expect(find.byType(PopupMenuItem<void>), findsNothing);
    });
  });

  group('Its place and its look', () {
    Future<Rect> openAt(WidgetTester tester, Offset at) async {
      await _rightClick(tester, at);
      final rect = tester.getRect(_surface());
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      return rect;
    }

    testWidgets('its corner at the pointer: to its right in the left half, to its left in the right half', (
      tester,
    ) async {
      await _pumpBare(tester);
      final left = await openAt(tester, const Offset(150, 300));
      expect(left.topLeft, const Offset(150, 300));
      final right = await openAt(tester, const Offset(262, 300));
      expect(right.topRight, const Offset(262, 300));
      expect(right.size, left.size);
    });

    testWidgets('kept 8 px inside the window and clear of the system bars, at each edge', (tester) async {
      await _pumpBare(tester, padding: const FakeViewPadding(top: 24, bottom: 48));
      final bottomRight = await openAt(tester, const Offset(410, 880));
      expect(bottomRight.right, 412 - 8);
      expect(bottomRight.bottom, 892 - 48 - 8);
      final topLeft = await openAt(tester, const Offset(2, 2));
      expect(topLeft.topLeft, const Offset(8, 24 + 8));
      final bottomLeft = await openAt(tester, const Offset(2, 891));
      expect(bottomLeft.left, 8);
      expect(bottomLeft.bottom, 892 - 48 - 8);
      final topRight = await openAt(tester, const Offset(411, 10));
      expect(topRight.topRight, const Offset(412 - 8, 24 + 8));
    });

    testWidgets('taller than the window: inside it, and it scrolls', (tester) async {
      await _pumpBare(tester, size: const Size(412, 300), count: 20);
      await _rightClick(tester, const Offset(30, 40));
      final surface = tester.getRect(_surface());
      expect(surface.top, 8);
      expect(surface.bottom, 300 - 8);
      final last = find.text('Item 19');
      expect(tester.getRect(last).top, greaterThan(surface.bottom));
      await tester.drag(find.text('Item 2'), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.getRect(last).bottom, lessThanOrEqualTo(surface.bottom));
      expect(find.byType(PopupMenuItem<void>), findsWidgets, reason: 'a drag inside does not close it');
    });

    testWidgets('Material 3\'s look, a width of 56 px steps; the theme\'s when the app sets one', (tester) async {
      await _pumpBare(tester);
      await _rightClick(tester, const Offset(30, 40));
      final scheme = Theme.of(tester.element(_surface())).colorScheme;
      var surface = tester.widget<Material>(_surface());
      expect(surface.type, MaterialType.card);
      expect(surface.color, scheme.surfaceContainer);
      expect(surface.elevation, 3);
      expect(surface.shadowColor, scheme.shadow);
      expect(surface.surfaceTintColor, Colors.transparent);
      expect(surface.shape, const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4))));
      expect(tester.getSize(_surface()).width % 56, 0);
      expect(tester.getSize(_surface()).width, inInclusiveRange(112, 280));
      expect(tester.getRect(find.byType(PopupMenuItem<void>).first).top - tester.getRect(_surface()).top, 8);

      const shape = StadiumBorder();
      await _pumpBare(
        tester,
        theme: ThemeData(
          popupMenuTheme: const PopupMenuThemeData(
            color: Colors.red,
            elevation: 10,
            shape: shape,
            shadowColor: Colors.blue,
            surfaceTintColor: Colors.green,
            menuPadding: EdgeInsets.symmetric(vertical: 2),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await _rightClick(tester, const Offset(30, 40));
      surface = tester.widget<Material>(_surface());
      expect(
        (surface.color, surface.elevation, surface.shape, surface.shadowColor, surface.surfaceTintColor),
        (Colors.red, 10.0, shape, Colors.blue, Colors.green),
      );
      expect(tester.getRect(find.byType(PopupMenuItem<void>).first).top - tester.getRect(_surface()).top, 2);
    });

    testWidgets('screen readers: a menu, a route of its own, named "Popup menu"; focus stays among its items', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpBare(tester);
      await _rightClick(tester, const Offset(30, 40));
      final menu = find.bySemanticsLabel('Popup menu');
      expect(
        tester.getSemantics(menu),
        isSemantics(label: 'Popup menu', role: SemanticsRole.menu, scopesRoute: true, namesRoute: true),
      );
      handle.dispose();

      FocusNode? focused() => FocusManager.instance.primaryFocus;
      final labels = <String>[];
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final item = find.ancestor(
          of: find.byElementPredicate((e) => e == focused()?.context),
          matching: find.byType(PopupMenuItem<void>),
        );
        labels.add(tester.widget<Text>(find.descendant(of: item, matching: find.byType(Text))).data!);
      }
      expect(labels, ['Item 0', 'Item 1', 'Item 2', 'Item 0']);
    });
  });
}
