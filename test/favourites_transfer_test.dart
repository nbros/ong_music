// Moving the favourites: the Favourites section of the About tab, the exported text, and its import.
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/state/settings_state.dart';
import 'package:ong_music/src/ui/app.dart';
import 'package:ong_music/src/ui/favourites_transfer.dart';
import 'package:ong_music/src/ui/format.dart';
import 'package:ong_music/src/ui/theme.dart';

import 'fixtures.dart';
import 'ui_harness.dart';

const _key = FavouritesNotifier.key;

/// The key of the highlight of [testCatalogue] without video (Moana - How Far I'll Go).
final String _moana = testCatalogue().highlights[2].key;

/// More highlights: a nocturne with a video, and a second "How Far I'll Go" without video.
final _more = [
  hRow(
    order: '4',
    title: 'Chopin - Nocturne Op. 9 No. 2',
    genre: 'CLASSICAL',
    link: 'https://youtu.be/wxyzABCDEFG',
    upload: '2024-03-08',
  ),
  hRow(order: '5', title: "Moana - How Far I'll Go", genre: 'DISNEY', upload: '2024-03-09'),
];

CatalogueState _state() => loadedState(testCatalogue(moreHighlights: _more), testNow);

/// The About tab, scrolled to the Favourites section.
Future<void> _toSection(WidgetTester tester) async {
  await goToTab(tester, 'About');
  // the buttons, with some room under them
  await tester.scrollUntilVisible(find.text('Data'), 100, scrollable: aboutScrollable());
  await tester.pumpAndSettle();
}

/// The text of the import dialog.
Finder _field() => find.descendant(of: find.byType(UnwrappedTextField), matching: find.byType(EditableText));

Finder _button(String label) => find.widgetWithText(TextButton, label);

bool _enabled(WidgetTester tester, String label) => tester.widget<TextButton>(_button(label).first).onPressed != null;

/// The favourites of the running app.
Set<String> _favourites(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(OngMusicApp))).read(favouritesProvider);

/// Opens the import dialog and types [text] in it.
Future<void> _importText(WidgetTester tester, String text) async {
  await tapVisible(tester, _button('Import').first);
  expect(find.text('Import favourites'), findsOneWidget);
  await tester.enterText(_field(), text);
  await tester.pump();
  await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: _button('Import')));
  await tester.pumpAndSettle();
}

void main() {
  test('the export: one line per favourite in the order they were added, the number of lines first', () {
    final catalogue = testCatalogue(moreHighlights: _more);
    final lines = favouriteLines({
      'aaaaaaaaaaa',
      // a video that left the catalogue: its link alone
      'lmnopqrstuv',
      'wxyzABCDEFG',
      // a highlight without video that left it: nothing would find it again
      '9 gone without video',
      _moana,
    }, catalogue);
    expect(favouritesExportText(lines), '''
My Ong Music favourites (4)
Zelda - Song of Storms — https://youtu.be/aaaaaaaaaaa
https://youtu.be/lmnopqrstuv
Chopin - Nocturne Op. 9 No. 2 — https://youtu.be/wxyzABCDEFG
Moana - How Far I'll Go''');
    // without catalogue, the videos alone
    expect(favouriteLines({'aaaaaaaaaaa', _moana}, null), ['https://youtu.be/aaaaaaaaaaa']);
  });

  test('the import reads every YouTube link wherever it is, and the titles of the highlights without video', () {
    final catalogue = testCatalogue(moreHighlights: _more);
    const forwarded = '''
Forwarded message:
> My Ong Music favourites (4)
> Chopin - Nocturne Op. 9 No. 2 —
> https://youtu.be/wxyzABCDEFG
> Zelda - Song of Storms — https://www.youtube.com/watch?v=aaaaaaaaaaa&t=42s and also
https://m.youtube.com/watch?feature=share&v=bbbbbbbbbbb (Gloria) https://youtu.be/notInTheApp
  Moana - How Far I'll Go
Moana - How Far I'll Go
Moana - How Far I'll Go
Moana - How Far I'll Go
Sent from my phone''';
    final keys = favouriteKeysIn(forwarded, catalogue);
    final moanas = [
      for (final h in catalogue.highlights.reversed)
        if (h.youtubeId == null) h.key,
    ];
    // in the order of the text; the two highlights titled so, the newest first, once each; nothing else
    expect(keys, ['wxyzABCDEFG', 'aaaaaaaaaaa', 'bbbbbbbbbbb', ...moanas]);
    expect(favouriteKeysIn('My Ong Music favourites (0)\nhello', catalogue), isEmpty);
  });

  testWidgets('the section: the number of favourites, Export only with some, Import once the highlights are in', (
    tester,
  ) async {
    final app = await pumpApp(tester, state: const CatalogueState(isRefreshing: true), settle: false);
    // the spinner of the list turns: no settling
    await tester.tap(find.descendant(of: navigation(), matching: find.text('About')));
    await tester.pump(const Duration(seconds: 1));
    await tester.scrollUntilVisible(find.text('Data'), 100, scrollable: aboutScrollable());
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0 favourites'), findsOneWidget);
    expect(_enabled(tester, 'Export'), isFalse);
    expect(_enabled(tester, 'Import'), isFalse);
    app.notifier.emit(_state());
    await tester.pumpAndSettle();
    await _toSection(tester);
    expect(_enabled(tester, 'Import'), isTrue);

    // the count changes in place: the buttons stay where they are
    final export = tester.getRect(_button('Export'));
    final import = tester.getRect(_button('Import'));
    final below = tester.getRect(find.text('Data'));
    await ProviderScope.containerOf(
      tester.element(find.byType(OngMusicApp)),
    ).read(favouritesProvider.notifier).toggle(testCatalogue().highlights[0]);
    await tester.pumpAndSettle();
    expect(find.text('1 favourite'), findsOneWidget);
    expect(_enabled(tester, 'Export'), isTrue);
    expect((tester.getRect(_button('Export')), tester.getRect(_button('Import'))), (export, import));
    expect(tester.getRect(find.text('Data')), below);
  });

  testWidgets('Export gives the text to the share sheet, or copies it where there is none', (tester) async {
    final prefs = {
      _key: ['aaaaaaaaaaa', _moana],
    };
    const text =
        "My Ong Music favourites (2)\nZelda - Song of Storms — https://youtu.be/aaaaaaaaaaa\nMoana - How Far I'll Go";
    final app = await pumpApp(tester, prefs: prefs, state: _state());
    await _toSection(tester);
    expect(find.text('2 favourites'), findsOneWidget);
    await tapVisible(tester, _button('Export'));
    expect(app.effects.shared, [text]);
    expect(find.text('Copied'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    final desktop = await pumpApp(tester, prefs: prefs, state: _state(), canShare: false);
    await _toSection(tester);
    await tapVisible(tester, _button('Export'));
    expect(desktop.effects.shared, isEmpty);
    expect(desktop.effects.clipboard, text);
    expect(find.text('Copied'), findsOneWidget);
    await waitForMessage(tester);
  });

  testWidgets('Import adds what the text names after the favourites there, and says how many', (tester) async {
    final app = await pumpApp(
      tester,
      prefs: {
        _key: ['bbbbbbbbbbb'],
      },
      state: _state(),
    );
    await _toSection(tester);
    await _importText(
      tester,
      "My Ong Music favourites (3)\nMoana - How Far I'll Go\nhttps://youtu.be/wxyzABCDEFG\nGloria https://youtu.be/bbbbbbbbbbb",
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('2 favourites added'), findsOneWidget);
    final moana = testCatalogue(moreHighlights: _more).highlights[4].key;
    expect(_favourites(tester).toList(), ['bbbbbbbbbbb', moana, 'wxyzABCDEFG']);
    expect(app.prefs.getStringList(_key), ['bbbbbbbbbbb', moana, 'wxyzABCDEFG']);
    expect(find.text('3 favourites'), findsOneWidget);
    await waitForMessage(tester);

    await _importText(tester, 'https://youtu.be/aaaaaaaaaaa');
    expect(find.text('1 favourite added'), findsOneWidget);
    await waitForMessage(tester);

    // all of it there already
    await _importText(tester, 'https://youtu.be/aaaaaaaaaaa https://youtu.be/wxyzABCDEFG');
    expect(find.text('Already in your favourites'), findsOneWidget);
    expect(_favourites(tester), hasLength(4));
    await waitForMessage(tester);
  });

  testWidgets('a text naming nothing keeps the dialog open with its error, which goes with the next change', (
    tester,
  ) async {
    await pumpApp(tester, state: _state());
    await _toSection(tester);
    await tapVisible(tester, _button('Import').first);
    expect(find.text('Paste the exported text'), findsOneWidget);
    final actions = tester.getRect(find.text('Cancel'));
    await tester.enterText(_field(), 'https://youtu.be/notInTheApp\nNo such song');
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: _button('Import')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('That text holds no favourites.'), findsOneWidget);
    // the error took a line kept for it
    expect(tester.getRect(find.text('Cancel')), actions);
    await tester.enterText(_field(), 'https://youtu.be/notInTheApp\nNo such song!');
    await tester.pumpAndSettle();
    expect(find.text('That text holds no favourites.'), findsNothing);
    expect(_favourites(tester), isEmpty);
  });

  testWidgets('Android Back and Escape close the dialog, Cancel too, adding nothing', (tester) async {
    await pumpApp(tester, state: _state());
    await _toSection(tester);
    for (final close in <Future<void> Function()>[
      () => tester.binding.handlePopRoute(),
      () => tester.sendKeyEvent(LogicalKeyboardKey.escape),
      () => tester.tap(find.text('Cancel')),
    ]) {
      await tapVisible(tester, _button('Import').first);
      await tester.enterText(_field(), 'https://youtu.be/aaaaaaaaaaa');
      await close();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    }
    expect(_favourites(tester), isEmpty);
    expect(find.textContaining('added'), findsNothing);
  });

  testWidgets('on a small phone, the keyboard up, the buttons of the dialog stay above it', (tester) async {
    await pumpApp(tester, state: _state(), size: const Size(320, 568));
    await _toSection(tester);
    await tapVisible(tester, _button('Import').first);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.enterText(_field(), List.filled(12, 'https://youtu.be/aaaaaaaaaaa').join('\n'));
    await tester.pumpAndSettle();
    for (final label in ['Cancel', 'Import']) {
      final button = find.descendant(of: find.byType(AlertDialog), matching: _button(label));
      expect(button.hitTestable(), findsOneWidget, reason: label);
      expect(tester.getRect(button).bottom, lessThanOrEqualTo(568 - 260), reason: label);
    }
    // and the field keeps the room of a few lines, its text scrolling in it
    expect(tester.getRect(_field()).height, greaterThan(100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the page under the dialog is where it was once the dialog and its keyboard are gone', (tester) async {
    // a phone with a gesture bar: the keyboard rises over it step by step, and takes its inset as it does
    void keyboard(double height) {
      tester.view.viewInsets = FakeViewPadding(bottom: height);
      tester.view.padding = FakeViewPadding(top: 24, bottom: height > 24 ? 0 : 24 - height);
    }

    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewInsets);
    await pumpApp(tester, state: _state(), size: const Size(412, 892));
    await goToTab(tester, 'About');
    // the end of the page, where the footer is
    final position = tester.state<ScrollableState>(aboutScrollable()).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    final before = position.pixels;
    final button = tester.getRect(_button('Import').first);
    await tester.tap(_button('Import').first);
    await tester.pumpAndSettle();
    for (final height in <double>[10, 40, 120, 300]) {
      keyboard(height);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.enterText(_field(), 'nothing');
    await tester.pumpAndSettle();
    for (final height in <double>[120, 40, 10, 0]) {
      keyboard(height);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: _button('Cancel')));
    await tester.pumpAndSettle();
    expect(position.pixels, before);
    expect(tester.getRect(_button('Import').first), button);
  });

  testWidgets('what one device exports, another imports whole', (tester) async {
    // a title read back names the newest highlight without video of that title
    final keys = ['wxyzABCDEFG', testCatalogue(moreHighlights: _more).highlights[4].key, 'aaaaaaaaaaa'];
    await pumpApp(tester, prefs: {_key: keys}, state: _state());
    final text = favouritesExportText(favouriteLines(_favourites(tester), testCatalogue(moreHighlights: _more)));
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, state: _state());
    await _toSection(tester);
    await _importText(tester, text);
    expect(find.text('3 favourites added'), findsOneWidget);
    expect(_favourites(tester).toList(), keys);
    await waitForMessage(tester);
  });

  testWidgets('an export read back on the same device adds nothing, even for one of two titles alike', (tester) async {
    final catalogue = testCatalogue(moreHighlights: _more);
    // the older of the two "How Far I'll Go" without video
    final text = favouritesExportText(favouriteLines({_moana}, catalogue));
    expect(favouriteKeysIn(text, catalogue, favourites: {_moana}), [_moana]);
    // elsewhere the text cannot tell them apart: the newest
    expect(favouriteKeysIn(text, catalogue), [catalogue.highlights[4].key]);

    await pumpApp(
      tester,
      prefs: {
        _key: [_moana],
      },
      state: _state(),
    );
    await _toSection(tester);
    await _importText(tester, text);
    expect(find.text('Already in your favourites'), findsOneWidget);
    expect(_favourites(tester), {_moana});
    await waitForMessage(tester);
  });

  for (final (size, counts) in [
    (const Size(360, 900), [9, 10]),
    (const Size(412, 900), [100, 1000]),
  ]) {
    testWidgets('at large text, the section keeps its height when the count gains a digit ($size)', (tester) async {
      final heights = <double>[];
      for (final count in counts) {
        await pumpApp(
          tester,
          size: size,
          textScale: 2,
          prefs: {
            _key: [for (var i = 0; i < count; i++) 'z${i.toString().padLeft(10, '0')}'],
          },
          state: _state(),
        );
        await goToTab(tester, 'About');
        await tester.scrollUntilVisible(find.byType(FavouritesSection), 100, scrollable: aboutScrollable());
        await tester.pumpAndSettle();
        expect(find.text('${formatCount(count)} favourites'), findsOneWidget);
        heights.add(tester.getSize(find.byType(FavouritesSection)).height);
        await tester.pumpWidget(const SizedBox());
      }
      expect(heights.toSet(), hasLength(1), reason: '$heights');
    });
  }

  testWidgets('Export says so when the clipboard refuses', (tester) async {
    final app = await pumpApp(
      tester,
      prefs: {
        _key: ['aaaaaaaaaaa'],
      },
      state: _state(),
      canShare: false,
    );
    app.effects.clipboardWorks = false;
    await _toSection(tester);
    await tapVisible(tester, _button('Export'));
    expect(find.text('Couldn’t copy'), findsOneWidget);
    expect(find.text('Copied'), findsNothing);
    await waitForMessage(tester);
  });

  group('the field of the import dialog', () {
    /// An export of [count] lines, each one far wider than a phone.
    String longExport(int count) => [
      'My Ong Music favourites ($count)',
      for (var i = 0; i < count; i++)
        'Artist number $i - A title much too long for one line of a phone $i — https://youtu.be/aaaaaaaaaaa',
    ].join('\n');

    RenderEditable editable(WidgetTester tester) => tester.state<EditableTextState>(_field()).renderEditable;

    /// The scroll of the field along [axis]: sideways around the text, upright in it.
    ScrollPosition scroll(WidgetTester tester, Axis axis) => tester
        .stateList<ScrollableState>(
          find.descendant(of: find.byType(UnwrappedTextField), matching: find.byType(Scrollable)),
        )
        .firstWhere((s) => axisDirectionToAxis(s.axisDirection) == axis)
        .position;

    /// The part of the text the box shows.
    Rect view(WidgetTester tester) =>
        tester.getRect(find.descendant(of: find.byType(UnwrappedTextField), matching: find.byType(Scrollable)).first);

    /// Whether the caret is in the part of the text the box shows.
    bool caretInView(WidgetTester tester) {
      final text = editable(tester);
      final caret = text.getLocalRectForCaret(text.selection!.extent);
      return view(tester).inflate(1).contains(text.localToGlobal(caret.center));
    }

    /// How many rows the line [index] of the text takes.
    int rowsOfLine(WidgetTester tester, int index) {
      final text = editable(tester);
      final value = text.text!.toPlainText();
      final lines = value.split('\n');
      final start = [for (var i = 0; i < index; i++) lines[i].length + 1].fold(0, (a, b) => a + b);
      final boxes = text.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + lines[index].length),
      );
      return {for (final b in boxes) b.top.round()}.length;
    }

    Future<void> open(WidgetTester tester) async {
      await goToTab(tester, 'About');
      await tester.scrollUntilVisible(_button('Import'), 100, scrollable: aboutScrollable());
      await tapVisible(tester, _button('Import'));
    }

    testWidgets('each line stays one line, however long, and nothing moves: a paste, a long line, the error', (
      tester,
    ) async {
      await pumpApp(tester, state: _state());
      await open(tester);
      Rect dialog() => tester.getRect(find.byType(Dialog));
      Rect field() => tester.getRect(find.byType(UnwrappedTextField));
      final (box, around) = (field(), dialog());
      await tester.enterText(_field(), longExport(12));
      await tester.pumpAndSettle();
      for (var i = 0; i < 13; i++) {
        expect(rowsOfLine(tester, i), 1, reason: 'line $i');
      }
      expect((field(), dialog()), (box, around));
      // one line, longer still, typed at the end of the first one
      await tester.enterText(_field(), longExport(12).replaceFirst('\n', '${'x' * 200}\n'));
      await tester.pumpAndSettle();
      expect(rowsOfLine(tester, 0), 1);
      expect((field(), dialog()), (box, around));
      await tester.enterText(_field(), 'no favourites here\nnor here');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: _button('Import')));
      await tester.pumpAndSettle();
      expect(find.text('That text holds no favourites.'), findsOneWidget);
      expect((field(), dialog()), (box, around));
      // the outline does not scroll with the text
      final outline = find.descendant(of: find.byType(UnwrappedTextField), matching: find.byType(InputDecorator));
      expect(tester.getRect(outline), tester.getRect(outline));
      expect(view(tester).width, lessThan(tester.getRect(outline).width));
    });

    testWidgets('a paste shows the start of the text; the caret is followed as it moves', (tester) async {
      await pumpApp(tester, state: _state());
      await open(tester);
      await tester.enterText(_field(), longExport(12));
      await tester.pumpAndSettle();
      expect(editable(tester).selection, const TextSelection.collapsed(offset: 0));
      expect((scroll(tester, Axis.horizontal).pixels, scroll(tester, Axis.vertical).pixels), (0, 0));

      // to the end of the first line: the view follows sideways
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(scroll(tester, Axis.horizontal).pixels, greaterThan(0));
      expect(caretInView(tester), isTrue);
      // down the lines: upright too
      for (var i = 0; i < 8; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.pumpAndSettle();
      expect(scroll(tester, Axis.vertical).pixels, greaterThan(0));
      expect(caretInView(tester), isTrue);
      // back to the start of the line
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(scroll(tester, Axis.horizontal).pixels, 0);
      expect(caretInView(tester), isTrue);
      // typing at the end of a long line
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      tester.testTextInput.enterText('${editable(tester).text!.toPlainText()}!');
      await tester.pumpAndSettle();
      expect(caretInView(tester), isTrue);
    });

    testWidgets('a finger drags the text sideways and upright', (tester) async {
      await pumpApp(tester, state: _state());
      await open(tester);
      await tester.enterText(_field(), longExport(12));
      await tester.pumpAndSettle();
      final selection = editable(tester).selection;
      await tester.dragFrom(view(tester).center, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(scroll(tester, Axis.horizontal).pixels, greaterThan(100));
      expect(scroll(tester, Axis.vertical).pixels, 0);
      await tester.dragFrom(view(tester).center, const Offset(0, -60));
      await tester.pumpAndSettle();
      expect(scroll(tester, Axis.vertical).pixels, greaterThan(30));
      // a drag is no tap: the caret stays
      expect(editable(tester).selection, selection);
    });

    testWidgets('the mouse wheel goes upright; sideways with Shift, or a sideways wheel', (tester) async {
      await pumpApp(tester, state: _state(), size: const Size(1280, 800), desktop: true);
      await tester.tap(find.descendant(of: navigation(), matching: find.text('About')));
      await tester.pumpAndSettle();
      await tapVisible(tester, _button('Import').first);
      await tester.enterText(_field(), longExport(12));
      await tester.pumpAndSettle();
      final mouse = TestPointer(1, PointerDeviceKind.mouse)..hover(view(tester).center);
      Future<(double, double)> wheel(Offset delta, {bool shift = false}) async {
        final h = scroll(tester, Axis.horizontal).pixels, v = scroll(tester, Axis.vertical).pixels;
        if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendEventToBinding(mouse.scroll(delta));
        if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        return (scroll(tester, Axis.horizontal).pixels - h, scroll(tester, Axis.vertical).pixels - v);
      }

      expect(await wheel(const Offset(0, 40)), (0, 40));
      // Shift and an upright wheel (Windows, Linux)
      expect(await wheel(const Offset(0, 50), shift: true), (50, 0));
      // Shift and a wheel the system made sideways (macOS)
      expect(await wheel(const Offset(30, 0), shift: true), (30, 0));
      // a trackpad, sideways
      expect(await wheel(const Offset(-80, 0)), (-80, 0));
    });

    testWidgets('select all, and the long press that pastes, as in any field', (tester) async {
      await pumpApp(tester, state: _state());
      const clip = 'My Ong Music favourites (1)\nZelda - Song of Storms — https://youtu.be/aaaaaaaaaaa';
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        return switch (call.method) {
          'Clipboard.getData' => {'text': clip},
          'Clipboard.hasStrings' => {'value': true},
          _ => null,
        };
      });
      await open(tester);
      await tester.longPress(_field());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();
      expect(editable(tester).text!.toPlainText(), clip);
      // the start of the text, the caret there
      expect(editable(tester).selection, const TextSelection.collapsed(offset: 0));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(editable(tester).selection, const TextSelection(baseOffset: 0, extentOffset: clip.length));
    });

    testWidgets('right to left: one line each, the caret followed, Shift and the wheel', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, desktop: false),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  child: UnwrappedTextField(controller: controller, lines: 5, hintText: 'hint'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tapAt(view(tester).center);
      await tester.pump();
      tester.testTextInput.enterText(
        [for (var i = 0; i < 8; i++) 'שיר ארוך מאוד עם כותרת ארוכה $i — https://youtu.be/aaaaaaaaaaa'].join('\n'),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 8; i++) {
        expect(rowsOfLine(tester, i), 1, reason: 'line $i');
      }
      expect(caretInView(tester), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(scroll(tester, Axis.horizontal).pixels, greaterThan(0));
      expect(caretInView(tester), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(caretInView(tester), isTrue);
      // laid out from the right: the wheel goes the way the framework's own sideways scrolls go
      final mouse = TestPointer(1, PointerDeviceKind.mouse)..hover(view(tester).center);
      final before = scroll(tester, Axis.horizontal).pixels;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -50)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(scroll(tester, Axis.horizontal).pixels, before + 50);
      expect(tester.takeException(), isNull);
    });

    testWidgets('large text on a small phone, the keyboard up: the field and the buttons in reach', (tester) async {
      await pumpApp(tester, state: _state(), size: const Size(320, 568), textScale: 2);
      await open(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(_field(), longExport(12));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final label in ['Cancel', 'Import']) {
        final button = find.descendant(of: find.byType(AlertDialog), matching: _button(label));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        expect(button.hitTestable(), findsOneWidget, reason: label);
        expect(tester.getRect(button).bottom, lessThanOrEqualTo(568 - 260), reason: label);
      }
      expect(rowsOfLine(tester, 1), 1);
    });
  });
}
