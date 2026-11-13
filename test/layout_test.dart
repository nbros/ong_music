// The window modes (bottom bar or navigation rail, column widths, sheets beside the rail), the pointer and what a
// mouse brings (scroll bar lane, key cap, chip arrows), and the tooltips.
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/ui/about_page.dart';
import 'package:ong_music/src/ui/highlights_page.dart';
import 'package:ong_music/src/ui/layout.dart';
import 'package:ong_music/src/ui/nav_rail.dart';
import 'package:ong_music/src/ui/ong_log_page.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/sheets.dart';
import 'package:ong_music/src/ui/widgets.dart';

import 'fixtures.dart';
import 'ui_harness.dart';

/// The test catalogue with 20 more highlights ("Song 1" to "Song 20"): a list longer than any window of the tests.
CatalogueState longCatalogue() => CatalogueState(
  catalogue: testCatalogue(
    moreHighlights: [for (var i = 1; i <= 20; i++) hRow(order: '${3 + i}', title: 'Song $i')],
  ),
  fetchedAt: testNow,
);

/// The sheet on screen (a [BottomSheet] takes the whole width, the sheet is
/// its [Material]).
Rect sheetRect(WidgetTester tester) =>
    tester.getRect(find.descendant(of: find.byType(BottomSheet), matching: find.byType(Material)).first);

/// The navigation rail.
Finder rail() => find.byType(AppNavigationRail);

/// The scroll view of the list of [page] (a page type).
Finder listOf(Type page) => find.descendant(of: find.byType(page), matching: find.byType(CustomScrollView));

/// Moves a mouse over [at]: the pointer becomes a mouse.
Future<TestPointer> hoverWithMouse(WidgetTester tester, Offset at) async {
  final mouse = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(mouse.hover(at));
  await tester.pumpAndSettle();
  return mouse;
}

/// The scroll bar of the scroll view [scrollView] is in.
Scrollbar scrollbarOf(WidgetTester tester, Finder scrollView) =>
    tester.widget<Scrollbar>(find.ancestor(of: scrollView, matching: find.byType(Scrollbar)).first);

/// Whether the `/` key cap of the search field of the visible tab shows.
bool keyCapShown(WidgetTester tester) {
  final cap = find.descendant(of: find.byType(ListSearchField).hitTestable(), matching: find.text('/'));
  if (cap.evaluate().isEmpty) return false;
  return tester.widget<Visibility>(find.ancestor(of: cap, matching: find.byType(Visibility)).first).visible;
}

/// The arrow of the chip row of the visible tab towards [icon], when it shows.
Finder chipArrow(IconData icon) => find.descendant(of: find.byType(ChipRow).hitTestable(), matching: find.byIcon(icon));

/// Whether the arrow towards [icon] of the chip row of the visible tab shows.
bool chipArrowShown(WidgetTester tester, IconData icon) {
  final arrow = chipArrow(icon);
  if (arrow.evaluate().isEmpty) return false;
  return tester.widget<Visibility>(find.ancestor(of: arrow, matching: find.byType(Visibility)).first).visible;
}

/// The scroll position of the chip row of the visible tab.
ScrollPosition chipScroll(WidgetTester tester) => tester
    .state<ScrollableState>(find.descendant(of: find.byType(ChipRow).hitTestable(), matching: find.byType(Scrollable)))
    .position;

void main() {
  group('window mode', () {
    test('from the size of the window', () {
      expect(WindowMode.of(const Size(599, 900)), WindowMode.compact);
      expect(WindowMode.of(const Size(600, 900)), WindowMode.medium);
      expect(WindowMode.of(const Size(839, 900)), WindowMode.medium);
      expect(WindowMode.of(const Size(840, 900)), WindowMode.expanded);
      // a low window stays medium at any width, but a narrow one is compact
      expect(WindowMode.of(const Size(840, 479)), WindowMode.medium);
      expect(WindowMode.of(const Size(2000, 479)), WindowMode.medium);
      expect(WindowMode.of(const Size(840, 480)), WindowMode.expanded);
      expect(WindowMode.of(const Size(599, 300)), WindowMode.compact);
      // phones: upright, sideways
      expect(WindowMode.of(const Size(412, 892)), WindowMode.compact);
      expect(WindowMode.of(const Size(892, 412)), WindowMode.medium);
    });

    for (final (width, hasRail) in [(599.0, false), (600.0, true), (839.0, true), (840.0, true)]) {
      testWidgets('${width.round()} px wide: ${hasRail ? 'a rail' : 'the bottom bar'}', (tester) async {
        await pumpApp(tester, size: Size(width, 892));
        expect(rail(), hasRail ? findsOneWidget : findsNothing);
        expect(find.byType(NavigationBar), hasRail ? findsNothing : findsOneWidget);
      });
    }

    testWidgets('a compact window keeps the phone layout: the bar, the content as wide as the window', (tester) async {
      await pumpApp(tester, size: const Size(599, 892));
      expect(tester.getRect(listOf(HighlightsPage)).left, 0);
      expect(tester.getRect(listOf(HighlightsPage)).width, 599);
      expect(tester.getRect(find.byType(NavigationBar)).bottom, 892);
    });

    testWidgets('the mode follows the window, and the tabs keep their state', (tester) async {
      await pumpApp(tester, size: const Size(412, 892), state: longCatalogue());
      await goToTab(tester, 'Ong Log');
      await tester.enterText(searchField(), 'zelda');
      await tester.pumpAndSettle();
      await goToTab(tester, 'Highlights');
      await tester.enterText(searchField(), 'song');
      await tester.pumpAndSettle();
      final list = tester.state<ScrollableState>(
        find.descendant(of: listOf(HighlightsPage), matching: find.byType(Scrollable)),
      );
      list.position.jumpTo(40);
      await tester.pumpAndSettle();

      for (final size in [const Size(892, 412), const Size(1400, 900), const Size(412, 892)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$size');
        expect(rail(), size.width >= 600 ? findsOneWidget : findsNothing, reason: '$size');
        expect(selectedTab(tester), 0, reason: '$size');
        expect(find.text('song'), findsOneWidget, reason: '$size');
        // the same list, where it was
        final now = tester.state<ScrollableState>(
          find.descendant(of: listOf(HighlightsPage), matching: find.byType(Scrollable)),
        );
        expect(now, same(list), reason: '$size');
        expect(now.position.pixels, 40, reason: '$size');
      }
      await goToTab(tester, 'Ong Log');
      expect(find.text('zelda'), findsOneWidget);
    });
  });

  group('navigation rail', () {
    testWidgets('the sizes of the design, the app picture, the three destinations', (tester) async {
      await pumpApp(tester, size: const Size(700, 900));
      expect(tester.getRect(rail()), const Rect.fromLTWH(0, 0, 80, 900));
      final picture = find.descendant(of: rail(), matching: find.byType(Image));
      expect(tester.getRect(picture), const Rect.fromLTWH(20, 16, 40, 40));
      final tops = [
        for (final label in ['Highlights', 'Ong Log', 'About'])
          tester.getRect(find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first),
      ];
      expect(tops.map((r) => r.top), [82, 150, 218]);
      expect(tops.map((r) => r.size), everyElement(const Size(80, 56)));
      // the content right of it
      expect(tester.getRect(listOf(HighlightsPage)).left, 80);

      // the selected destination in the colours of the bar's, the others in the secondary text colour
      final scheme = Theme.of(tester.element(rail())).colorScheme;
      Color iconOf(String label) => tester
          .widget<Icon>(
            find.descendant(
              of: find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first,
              matching: find.byType(Icon),
            ),
          )
          .color!;
      Color labelOf(String label) => tester.widget<Text>(find.text(label)).style!.color!;
      expect((iconOf('Highlights'), labelOf('Highlights')), (scheme.onSecondaryContainer, scheme.onSurface));
      expect((iconOf('Ong Log'), labelOf('Ong Log')), (scheme.onSurfaceVariant, scheme.onSurfaceVariant));
    });

    testWidgets('selects a tab as the bar does; Android back from another tab returns to Highlights', (tester) async {
      final app = await pumpApp(tester, size: const Size(892, 412));
      await tester.tap(searchField());
      await tester.pumpAndSettle();
      await goToTab(tester, 'About');
      expect(find.byType(AboutPage).hitTestable(), findsOneWidget);
      expect(selectedTab(tester), 2);
      expect(FocusManager.instance.primaryFocus?.context?.widget, isNot(isA<EditableText>()));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(selectedTab(tester), 0);
      expect(app.effects.exits, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(app.effects.exits, 1);
    });

    testWidgets('screen readers: tabs with their names and state, the picture unsaid', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpApp(tester, size: const Size(700, 900));
      expect(
        tester.getSemantics(find.ancestor(of: find.text('Highlights'), matching: find.byType(InkWell)).first),
        isSemantics(label: 'Highlights\nTab 1 of 3', isSelected: true, isButton: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(find.ancestor(of: find.text('About'), matching: find.byType(InkWell)).first),
        isSemantics(label: 'About\nTab 3 of 3', isSelected: false, isButton: true, hasTapAction: true),
      );
      // the picture is decoration: the rail says its three tabs and nothing else
      expect(
        tester.widget<Image>(find.descendant(of: rail(), matching: find.byType(Image))).excludeFromSemantics,
        isTrue,
      );
      final said = <String>[];
      void collect(SemanticsNode node) {
        if (node.label.isNotEmpty) said.add(node.label);
        node.visitChildren((child) {
          collect(child);
          return true;
        });
      }

      // the node of the tab bar holds the picture and the three destinations
      final tabBar = find.descendant(
        of: rail(),
        matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.role == SemanticsRole.tabBar),
      );
      collect(tester.getSemantics(tabBar));
      expect(said, ['Highlights\nTab 1 of 3', 'Ong Log\nTab 2 of 3', 'About\nTab 3 of 3']);
      semantics.dispose();
    });

    testWidgets('hover changes a colour, nothing moves', (tester) async {
      await pumpApp(tester, size: const Size(700, 900));
      final ongLog = find.ancestor(of: find.text('Ong Log'), matching: find.byType(InkWell)).first;
      final indicator = find.descendant(of: ongLog, matching: find.byType(AnimatedContainer));
      Color color() => (tester.widget<AnimatedContainer>(indicator).decoration! as BoxDecoration).color!;
      final before = (tester.getRect(ongLog), tester.getRect(indicator), color());
      await hoverWithMouse(tester, tester.getCenter(ongLog));
      expect(color(), isNot(before.$3));
      expect((tester.getRect(ongLog), tester.getRect(indicator)), (before.$1, before.$2));
    });

    testWidgets('no hover colour while the pointer is touch', (tester) async {
      await pumpApp(tester, size: const Size(700, 900), pointer: PointerKind.touch);
      final ongLog = find.ancestor(of: find.text('Ong Log'), matching: find.byType(InkWell)).first;
      final indicator = find.descendant(of: ongLog, matching: find.byType(AnimatedContainer));
      Color color() => (tester.widget<AnimatedContainer>(indicator).decoration! as BoxDecoration).color!;
      final before = color();
      // a hover event all the same (a stylus held over the screen): the pointer stays touch
      await hoverWithMouse(tester, tester.getCenter(ongLog));
      expect(color(), before);
    });

    testWidgets('a phone held sideways: the rail takes the cutout on its side, the content the other', (tester) async {
      await pumpApp(tester, size: const Size(892, 412));
      // camera on the left, status bar at the top, gesture bar at the bottom
      tester.view.padding = const FakeViewPadding(left: 30, top: 24, bottom: 16);
      tester.view.viewPadding = const FakeViewPadding(left: 30, top: 24, bottom: 16);
      await tester.pumpAndSettle();
      expect(tester.getRect(rail()), const Rect.fromLTWH(0, 0, 110, 412));
      expect(tester.getRect(find.descendant(of: rail(), matching: find.byType(Image))).topLeft, const Offset(50, 40));
      // the column of the list centred in what the rail leaves: the cutout counts once, in the rail
      final page = tester.getRect(find.byType(HighlightsPage));
      expect((page.left, page.right), (110 + (892 - 110 - 720) / 2, 892 - (892 - 110 - 720) / 2));
      expect(page.top, 24);

      // camera on the right: the content keeps away from it
      tester.view.padding = const FakeViewPadding(right: 30, top: 24, bottom: 16);
      tester.view.viewPadding = const FakeViewPadding(right: 30, top: 24, bottom: 16);
      await tester.pumpAndSettle();
      expect(tester.getRect(rail()).width, 80);
      final other = tester.getRect(find.byType(HighlightsPage));
      expect((other.left, other.right), (80 + (892 - 80 - 30 - 720) / 2, 892 - 30 - (892 - 80 - 30 - 720) / 2));
    });

    testWidgets('large text in a phone held sideways: no overflow, every destination within reach', (tester) async {
      await pumpApp(tester, size: const Size(892, 412), textScale: 2);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.descendant(of: rail(), matching: find.text('About')),
        50,
        scrollable: find.descendant(of: rail(), matching: find.byType(Scrollable)),
      );
      await goToTab(tester, 'About');
      expect(selectedTab(tester), 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('large text: the labels grow as those of the bottom bar do, up to 1.3 times', (tester) async {
      // (at twice the size "Highlights" would not fit in the rail; the test font cannot show it)
      await pumpApp(tester, size: const Size(700, 900), textScale: 2);
      final label = find.descendant(of: rail(), matching: find.text('Highlights'));
      expect(MediaQuery.textScalerOf(tester.element(label)).scale(10), 13);
      expect(tester.getSize(label).height, 26);
      // the rest of the app follows the system
      expect(MediaQuery.textScalerOf(tester.element(searchField())).scale(10), 20);
    });

    testWidgets('a phone held sideways, typing: the rail stays, the chips go until the keyboard does', (tester) async {
      await pumpApp(tester, size: const Size(800, 360));
      final chips = find.descendant(of: find.byType(HighlightsPage), matching: find.byType(ChipRow));
      await tester.tap(searchField());
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      await tester.enterText(searchField(), 'survive');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(rail(), findsOneWidget);
      expect(chips.hitTestable(), findsNothing);
      expect(tester.getRect(listOf(HighlightsPage)).bottom, 160);
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(chips.hitTestable(), findsOneWidget);
    });
  });

  group('medium window', () {
    testWidgets('a list in a column of 720 px at most, centred right of the rail; About in 640', (tester) async {
      // (narrower than an expanded window, which has a list pane and a detail pane)
      await pumpApp(tester, size: const Size(830, 900));
      const middle = 80 + (830 - 80) / 2;
      for (final (tab, page, width) in [
        ('Highlights', HighlightsPage, 720.0),
        ('Ong Log', OngLogPage, 720.0),
        ('About', AboutPage, 640.0),
      ]) {
        await goToTab(tester, tab);
        final column = tester.getRect(find.byType(page));
        expect((column.width, column.center.dx), (width, middle), reason: tab);
      }
      // narrower than that: all the room right of the rail
      tester.view.physicalSize = const Size(700, 900);
      await tester.pumpAndSettle();
      await goToTab(tester, 'Highlights');
      expect(tester.getRect(find.byType(HighlightsPage)), const Rect.fromLTRB(80, 0, 700, 900));
    });

    testWidgets('a sheet is centred right of the rail, the scrim covers the whole window', (tester) async {
      await pumpApp(tester, size: const Size(830, 900));
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      final sheet = sheetRect(tester);
      expect((sheet.width, sheet.center.dx, sheet.bottom), (640, 80 + (830 - 80) / 2, 900));
      final scrim = find.byWidgetPredicate((w) => w is ModalBarrier && w.dismissible);
      expect(tester.getRect(scrim.last), const Rect.fromLTWH(0, 0, 830, 900));

      // narrower: the sheet takes what the rail leaves; a compact window: the whole width, as on a phone
      tester.view.physicalSize = const Size(700, 900);
      await tester.pumpAndSettle();
      expect((sheetRect(tester).left, sheetRect(tester).right), (80, 700));
      tester.view.physicalSize = const Size(412, 892);
      await tester.pumpAndSettle();
      expect((sheetRect(tester).left, sheetRect(tester).right, sheetRect(tester).bottom), (0, 412, 892));
      expect(find.byType(HighlightSheet), findsOneWidget, reason: 'the same sheet, still open');
    });

    testWidgets('a sheet beside a rail that takes a cutout', (tester) async {
      await pumpApp(tester, size: const Size(892, 412));
      tester.view.padding = const FakeViewPadding(left: 30);
      tester.view.viewPadding = const FakeViewPadding(left: 30);
      await tester.pumpAndSettle();
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      final sheet = sheetRect(tester);
      expect((sheet.width, sheet.center.dx), (640, 110 + (892 - 110) / 2));
    });
  });

  group('pointer', () {
    testWidgets('starts from the platform, then follows the pointer events', (tester) async {
      await pumpApp(tester, state: longCatalogue());
      final list = listOf(HighlightsPage);
      final position = tester
          .state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable)))
          .position;
      position.jumpTo(30);
      await tester.pumpAndSettle();
      // a phone: touch
      expect(scrollbarOf(tester, list).thumbVisibility, isFalse);

      // a mouse plugged in
      final mouse = await hoverWithMouse(tester, const Offset(200, 400));
      expect(scrollbarOf(tester, list).thumbVisibility, isTrue);
      expect(keyCapShown(tester), isTrue);
      await tester.sendEventToBinding(mouse.removePointer());

      // the screen touched again
      // (a touch that does nothing: a tap on a row would open its video)
      final finger = TestPointer(2, PointerDeviceKind.touch);
      await tester.sendEventToBinding(finger.down(tester.getCenter(list)));
      await tester.sendEventToBinding(finger.cancel());
      await tester.pumpAndSettle();
      expect(scrollbarOf(tester, list).thumbVisibility, isFalse);
      expect(keyCapShown(tester), isFalse);
      expect(position.pixels, 30, reason: 'the list stays where it was');
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('a desktop starts with a mouse; a touch screen makes it touch, a trackpad a mouse again', (
      tester,
    ) async {
      await pumpApp(tester);
      final list = listOf(HighlightsPage);
      expect(scrollbarOf(tester, list).thumbVisibility, isTrue);
      final touch = TestPointer(2, PointerDeviceKind.touch);
      await tester.sendEventToBinding(touch.down(const Offset(200, 400)));
      await tester.sendEventToBinding(touch.up());
      await tester.pumpAndSettle();
      expect(scrollbarOf(tester, list).thumbVisibility, isFalse);
      final trackpad = TestPointer(3, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(trackpad.panZoomStart(const Offset(200, 400)));
      await tester.sendEventToBinding(trackpad.panZoomEnd());
      await tester.pumpAndSettle();
      expect(scrollbarOf(tester, list).thumbVisibility, isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('a stylus is touch', (tester) async {
      await pumpApp(tester);
      final list = listOf(HighlightsPage);
      expect(scrollbarOf(tester, list).thumbVisibility, isTrue);
      final stylus = TestPointer(4, PointerDeviceKind.stylus);
      await tester.sendEventToBinding(stylus.down(tester.getCenter(list)));
      await tester.sendEventToBinding(stylus.cancel());
      await tester.pumpAndSettle();
      expect(scrollbarOf(tester, list).thumbVisibility, isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });

  group('with a mouse', () {
    testWidgets('scroll bars always shown, in a lane: nothing under them, pinned header included', (tester) async {
      await pumpApp(tester, size: const Size(830, 900), pointer: PointerKind.mouse);
      final column = tester.getRect(find.byType(HighlightsPage));
      final list = listOf(HighlightsPage);
      expect(scrollbarOf(tester, list).thumbVisibility, isTrue);
      expect(tester.getRect(list).right, column.right - scrollbarLane);
      expect(tester.getRect(detailsButtons().first).right, column.right - scrollbarLane);

      await goToTab(tester, 'Ong Log');
      final log = listOf(OngLogPage);
      tester.state<ScrollableState>(find.descendant(of: log, matching: find.byType(Scrollable))).position.jumpTo(30);
      await tester.pumpAndSettle();
      final headers = find.byType(StreamHeader).hitTestable();
      expect(headers, findsWidgets);
      for (final header in headers.evaluate()) {
        expect(tester.getRect(find.byElementPredicate((e) => e == header)).right, column.right - scrollbarLane);
      }

      await goToTab(tester, 'About');
      final about = aboutScrollable();
      expect(scrollbarOf(tester, about).thumbVisibility, isTrue);
      expect(tester.getRect(about).right, tester.getRect(find.byType(AboutPage)).right - scrollbarLane);

      await goToTab(tester, 'Highlights');
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      final sheetScroll = find.descendant(of: find.byType(HighlightSheet), matching: find.byType(CustomScrollView));
      expect(scrollbarOf(tester, sheetScroll).thumbVisibility, isTrue);
      expect(tester.getRect(sheetScroll).right, sheetRect(tester).right - scrollbarLane);
    });

    testWidgets('a mouse can drag every scroll bar, on Android too', (tester) async {
      // (the Material scroll bar is not draggable by default on Android: a tablet or a Chromebook with a mouse)
      await pumpApp(tester, size: const Size(700, 400), pointer: PointerKind.mouse);
      await goToTab(tester, 'About');
      final about = aboutScrollable();
      final position = tester.state<ScrollableState>(about).position;
      expect(position.pixels, 0);
      final lane = Offset(tester.getRect(find.byType(AboutPage)).right - scrollbarLane / 2, 30);
      await tester.dragFrom(lane, const Offset(0, 80), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(50));

      // the same in a sheet
      await goToTab(tester, 'Highlights');
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      final sheetScroll = find.descendant(of: find.byType(HighlightSheet), matching: find.byType(CustomScrollView));
      final sheetPosition = tester
          .state<ScrollableState>(find.descendant(of: sheetScroll, matching: find.byType(Scrollable)).first)
          .position;
      expect(sheetPosition.maxScrollExtent, greaterThan(0), reason: 'a sheet longer than the low window');
      final sheetLane = Offset(sheetRect(tester).right - scrollbarLane / 2, tester.getRect(sheetScroll).top + 20);
      await tester.dragFrom(sheetLane, const Offset(0, 60), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(sheetPosition.pixels, greaterThan(0));
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('with touch: the scroll bars over the content, shown while scrolling', (tester) async {
      await pumpApp(tester, size: const Size(830, 900), pointer: PointerKind.touch);
      final column = tester.getRect(find.byType(HighlightsPage));
      final list = listOf(HighlightsPage);
      expect(scrollbarOf(tester, list).thumbVisibility, isFalse);
      expect(tester.getRect(list).right, column.right);
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      final sheetScroll = find.descendant(of: find.byType(HighlightSheet), matching: find.byType(CustomScrollView));
      expect(tester.getRect(sheetScroll).right, sheetRect(tester).right);
    });

    testWidgets('the wheel over the lane scrolls the list', (tester) async {
      await pumpApp(tester, size: const Size(700, 400), pointer: PointerKind.mouse, state: longCatalogue());
      final list = listOf(HighlightsPage);
      final position = tester
          .state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable)))
          .position;
      final mouse = await hoverWithMouse(tester, Offset(700 - scrollbarLane / 2, tester.getCenter(list).dy));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 40)));
      await tester.pumpAndSettle();
      expect(position.pixels, 40);
    });

    testWidgets('the key cap: with a mouse, in an empty field without the focus; it moves nothing', (tester) async {
      await pumpApp(tester, pointer: PointerKind.mouse);
      expect(keyCapShown(tester), isTrue);
      final text = find.descendant(of: searchField(), matching: find.byType(EditableText));
      final before = (tester.getRect(pill()), tester.getRect(text));
      await tester.tap(searchField());
      await tester.pumpAndSettle();
      expect(keyCapShown(tester), isFalse);
      expect((tester.getRect(pill()), tester.getRect(text)), before);
      await tester.enterText(searchField(), 'zelda');
      await tester.pumpAndSettle();
      expect(keyCapShown(tester), isFalse);
      await tester.tap(find.byTooltip('Clear'));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(keyCapShown(tester), isTrue);
      expect((tester.getRect(pill()), tester.getRect(text)), before);
      // and on the other tab
      await goToTab(tester, 'Ong Log');
      expect(keyCapShown(tester), isTrue);
    });

    testWidgets('no key cap with touch', (tester) async {
      await pumpApp(tester, pointer: PointerKind.touch);
      expect(keyCapShown(tester), isFalse);
      expect(find.descendant(of: find.byType(ListSearchField), matching: find.text('/')), findsNothing);
    });

    testWidgets('the chip arrows: where the row can scroll, over it; they move nothing', (tester) async {
      await pumpApp(tester, pointer: PointerKind.mouse);
      final labels = ['All', 'Popular', 'Game OST', 'Disney'];
      Map<String, Rect> chips() => {for (final label in labels) label: tester.getRect(chip(label))};
      // 412 px: the row goes on past the right edge
      expect(chipArrowShown(tester, Icons.chevron_left), isFalse);
      expect(chipArrowShown(tester, Icons.chevron_right), isTrue);
      final row = tester.getRect(find.byType(ChipRow).hitTestable());
      expect(tester.getRect(chipArrow(Icons.chevron_right)).center.dx, row.right - 8 - 16);
      expect(tester.getSize(find.byType(ChipRow).hitTestable()).height, 48);

      final scroll = chipScroll(tester);
      final before = chips();
      // the left arrow comes when the row is scrolled a little: the chips moved by the scroll alone
      scroll.jumpTo(10);
      await tester.pumpAndSettle();
      expect(chipArrowShown(tester, Icons.chevron_left), isTrue);
      expect(chips(), {for (final e in before.entries) e.key: e.value.shift(const Offset(-10, 0))});
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(chipArrowShown(tester, Icons.chevron_left), isFalse);
      expect(chips(), before);

      // a click on the right arrow scrolls by seven tenths of the row
      // (a wider catalogue of genres than the test one would need more than one click to the end)
      final page = 0.7 * scroll.viewportDimension;
      await tester.tap(chipArrow(Icons.chevron_right), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(scroll.pixels, closeTo(page.clamp(0, scroll.maxScrollExtent), 0.01));
      expect(chipArrowShown(tester, Icons.chevron_left), isTrue);
      // to the end: the right arrow goes
      for (var i = 0; i < 10 && chipArrowShown(tester, Icons.chevron_right); i++) {
        await tester.tap(chipArrow(Icons.chevron_right), kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
      }
      expect(scroll.pixels, scroll.maxScrollExtent);
      expect(chipArrowShown(tester, Icons.chevron_right), isFalse);
      await tester.tap(chipArrow(Icons.chevron_left), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(scroll.pixels, closeTo((scroll.maxScrollExtent - page).clamp(0, scroll.maxScrollExtent), 0.01));
    });

    testWidgets('the chip arrows: the same chips with or without them, a touch takes them away', (tester) async {
      await pumpApp(tester);
      final labels = ['All', 'Popular', 'Game OST', 'Disney'];
      Map<String, Rect> chips() => {for (final label in labels) label: tester.getRect(chip(label))};
      final touch = chips();
      expect(chipArrowShown(tester, Icons.chevron_right), isFalse);
      await hoverWithMouse(tester, const Offset(200, 600));
      expect(chipArrowShown(tester, Icons.chevron_right), isTrue);
      expect(chips(), touch);
      // a chip under the fade (but not under the button) can still be clicked
      final arrow = tester.getRect(chipArrow(Icons.chevron_right));
      final fadeLeft = tester.getRect(find.byType(ChipRow).hitTestable()).right - 64;
      expect(arrow.left, greaterThan(fadeLeft));
    });

    testWidgets('the chip arrows: without animation when the system asks for less motion; their names', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpApp(tester, pointer: PointerKind.mouse);
      expect(find.semantics.byLabel('More filters'), findsOneWidget);
      expect(find.semantics.byLabel('Previous filters'), findsNothing);
      await tester.tap(chipArrow(Icons.chevron_right), kind: PointerDeviceKind.mouse);
      await tester.pump();
      final scroll = chipScroll(tester);
      expect(scroll.pixels, closeTo((0.7 * scroll.viewportDimension).clamp(0, scroll.maxScrollExtent), 0.01));
      expect(scroll.pixels, greaterThan(0), reason: 'at once');
      await tester.pumpAndSettle();
      expect(find.semantics.byLabel('Previous filters'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('no chip arrows with touch', (tester) async {
      await pumpApp(tester, pointer: PointerKind.touch);
      expect(chipArrowShown(tester, Icons.chevron_right), isFalse);
      chipScroll(tester).jumpTo(10);
      await tester.pumpAndSettle();
      expect(chipArrowShown(tester, Icons.chevron_left), isFalse);
    });
  });

  group('tooltips', () {
    /// The tooltip messages found under [of] (an empty one shows nothing).
    Set<String> tooltipsIn(WidgetTester tester, Finder of) => {
      for (final t in tester.widgetList<Tooltip>(find.descendant(of: of, matching: find.byType(Tooltip))))
        if ((t.message ?? t.richMessage?.toPlainText() ?? '').isNotEmpty) t.message ?? t.richMessage!.toPlainText(),
    };

    testWidgets('none on the navigation destinations, the ⋮ buttons and the video pills', (tester) async {
      await pumpApp(tester);
      expect(tooltipsIn(tester, find.byType(NavigationBar)), isEmpty);
      expect(tooltipsIn(tester, find.byType(HighlightRow)), isEmpty);
      await goToTab(tester, 'Ong Log');
      expect(find.byType(VideoPill), findsWidgets);
      expect(tooltipsIn(tester, find.byType(PlayRow)), isEmpty);
      tester.view.physicalSize = const Size(900, 900);
      await tester.pumpAndSettle();
      expect(tooltipsIn(tester, rail()), isEmpty);
    });

    testWidgets('the buttons without text keep theirs', (tester) async {
      await pumpApp(tester, fullscreen: FakeFullscreen());
      expect(find.byTooltip('Full screen'), findsOneWidget);
      await tester.enterText(searchField(), 'i');
      await tester.pumpAndSettle();
      expect(find.byTooltip('Clear'), findsOneWidget);
      await tester.enterText(searchField(), '');
      await tester.pumpAndSettle();
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      for (final message in ['Share', 'Copy title and link', 'Add to favourites']) {
        expect(find.byTooltip(message), findsOneWidget, reason: message);
      }
    });

    testWidgets('screen readers still hear the names', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpApp(tester);
      expect(
        tester.getSemantics(detailsButtons().first),
        isSemantics(label: 'Details', isButton: true, hasTapAction: true),
      );
      expect(find.semantics.byLabel(RegExp(r'^Highlights\n')), findsOneWidget);
      await goToTab(tester, 'Ong Log');
      expect(find.semantics.byLabel('Watch the video'), findsWidgets);
      semantics.dispose();
    });
  });
}
