import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/data/catalogue.dart';
import 'package:ong_music/src/data/font_kits.dart';
import 'package:ong_music/src/data/rare_characters.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/ui/font_warm_up.dart';
import 'package:ong_music/src/web/font_network.dart';

import 'fixtures.dart';
import 'ui_harness.dart';

/// Timers on a clock that moves only when told to ([elapse]).
class FakeTimers {
  Duration now = Duration.zero;
  final List<_FakeTimer> _timers = [];

  Timer start(Duration duration, void Function() callback) {
    final timer = _FakeTimer(now + duration, callback);
    _timers.add(timer);
    return timer;
  }

  /// Moves the clock by [duration], firing the timers that come due, in order.
  void elapse(Duration duration) {
    final end = now + duration;
    while (true) {
      final due = _timers.where((t) => t.isActive && t.due <= end).toList()..sort((a, b) => a.due.compareTo(b.due));
      if (due.isEmpty) break;
      now = due.first.due;
      due.first.fire();
    }
    now = end;
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this.due, this._callback);

  final Duration due;
  final void Function() _callback;
  bool _active = true;

  void fire() {
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

/// A value the tests set; tells whether anyone listens.
class FakeValue<T> extends ChangeNotifier implements ValueListenable<T> {
  FakeValue(this._value);

  T _value;

  @override
  T get value => _value;

  set value(T value) {
    _value = value;
    notifyListeners();
  }

  bool get listened => hasListeners;
}

/// The network as the tests say: online ([value]) or not, the engine with fonts of its own or not, registering
/// re-creating them (CanvasKit) or not (skwasm, the default here).
class FakeFontNetwork implements FontNetwork {
  FakeFontNetwork({bool online = true, int engineFontBytes = 0, this.registrationRecreatesFonts = false})
    : online = FakeValue(online),
      engineFontBytes = FakeValue(engineFontBytes);

  @override
  final bool registrationRecreatesFonts;

  @override
  final FakeValue<bool> online;

  @override
  final FakeValue<int> engineFontBytes;

  set value(bool online) => this.online.value = online;

  bool get listened => online.listened || engineFontBytes.listened;
}

const ms = Duration(milliseconds: 1);

FontKit kitOf(String name, String text) => (name: name, family: 'Noto Sans JP', text: text);

/// A rule on [FakeTimers] whose downloads end when the test says ([downloads]), and the names of what it registered,
/// one list per registration.
({FontWarmUp rule, FakeTimers timers, Map<FontKit, Completer<Uint8List>> downloads, List<List<String>> registered})
fakeRule({FakeFontNetwork? network}) {
  final timers = FakeTimers();
  final downloads = <FontKit, Completer<Uint8List>>{};
  final registered = <List<String>>[];
  final rule = FontWarmUp(
    download: (kit) => (downloads[kit] = Completer<Uint8List>()).future,
    register: (fonts) async => registered.add([for (final (kit, _) in fonts) kit.name]),
    network: network ?? FakeFontNetwork(),
    startTimer: timers.start,
  );
  return (rule: rule, timers: timers, downloads: downloads, registered: registered);
}

final a = kitOf('Ong JP 1', 'あ'), b = kitOf('Ong KR 1', '한');
final bytes = Uint8List.fromList([1]);

/// A catalogue whose texts hold rare characters: a highlight titled in Japanese, a play in Korean requested by an
/// Arabic name.
final rareCatalogue = testCatalogue(
  moreHighlights: [hRow(order: '4', title: '東方 - 月', upload: '2024-03-08')],
  moreSongs: [
    start('2024-03-03'),
    sRow(date: '2024-03-03 20:00:00', title: '봄 🎶', requester: 'ا'),
  ],
);

/// The kits of [characters] and of the app's own texts, as `name: text`.
List<String> kitTexts(String characters) => [
  for (final k in planFontKits({...characters.runes, ...appRareCharacters.runes})) '${k.name}: ${k.text}',
];

CatalogueState loaded(Catalogue catalogue) => CatalogueState(catalogue: catalogue, fetchedAt: testNow);

void main() {
  group('the rule', () {
    test('downloads once the kits are planned, each kit once, all at once', () async {
      final (:rule, :timers, :downloads, :registered) = fakeRule();
      expect(downloads, isEmpty);
      rule.plan([a, b]);
      expect(downloads.keys, [a, b]);
      rule.plan([a, b]);
      expect(downloads.keys, [a, b], reason: 'a kit planned again is not asked again');
      timers.elapse(const Duration(minutes: 5));
      expect(registered, isEmpty, reason: 'nothing downloaded yet');
    });

    test(
      'a later plan (the Songs sheet came) adds its kits: downloaded and registered, the first ones not again',
      () async {
        final (:rule, :timers, :downloads, :registered) = fakeRule();
        rule.plan([a]);
        downloads[a]!.complete(bytes);
        await pumpEventQueue();
        timers.elapse(fontWarmUpFirstQuiet);
        expect(registered, [
          ['Ong JP 1'],
        ]);
        final c = kitOf('Ong JP 2', '月');
        rule.plan([a, b, c]);
        expect(downloads.keys, [a, b, c]);
        downloads[b]!.complete(bytes);
        downloads[c]!.complete(bytes);
        await pumpEventQueue();
        rule.moved();
        timers.elapse(fontWarmUpQuiet);
        expect(registered, [
          ['Ong JP 1'],
          ['Ong KR 1', 'Ong JP 2'],
        ]);
        expect(rule.planned, [a, b, c]);
      },
    );

    test('a later plan asks nothing of a family the API would not cut down', () async {
      final (:rule, :timers, :downloads, :registered) = fakeRule();
      rule.plan([a]);
      downloads.remove(a)!.completeError(const FontKitUnavailable('slices'));
      await pumpEventQueue();
      const korean = (name: 'Ong KR 1', family: 'Noto Sans KR', text: '한');
      rule.plan([a, kitOf('Ong JP 2', '月'), korean]);
      expect(downloads.keys, [korean], reason: 'another family is asked');
    });

    test('registers what came, together, a short while after, when nothing has moved yet', () async {
      final (:rule, :timers, :downloads, :registered) = fakeRule();
      rule.plan([a, b]);
      downloads[a]!.complete(bytes);
      downloads[b]!.complete(bytes);
      await pumpEventQueue();
      timers.elapse(fontWarmUpFirstQuiet - ms);
      expect(registered, isEmpty);
      timers.elapse(ms);
      expect(registered, [
        ['Ong JP 1', 'Ong KR 1'],
      ]);
      timers.elapse(const Duration(minutes: 5));
      expect(registered, hasLength(1), reason: 'once');
    });

    test('once something moved, the longer wait', () async {
      final (:rule, :timers, :downloads, :registered) = fakeRule();
      rule
        ..plan([a])
        ..moved();
      downloads[a]!.complete(bytes);
      await pumpEventQueue();
      timers.elapse(fontWarmUpQuiet - ms);
      expect(registered, isEmpty);
      timers.elapse(ms);
      expect(registered, hasLength(1));
    });

    test('moving all along: registered the longest wait after the download', () async {
      final (:rule, :timers, :downloads, :registered) = fakeRule();
      rule.plan([a]);
      downloads[a]!.complete(bytes);
      await pumpEventQueue();
      const step = Duration(milliseconds: 100);
      for (var t = Duration.zero; t < fontWarmUpLongestWait - step; t += step) {
        rule.moved();
        timers.elapse(step);
      }
      expect(registered, isEmpty);
      timers.elapse(step);
      expect(registered, hasLength(1));
    });

    test('a pointer down holds it until it is up and the wait after, or the longest wait', () async {
      final (:rule, :timers, :downloads, :registered) = fakeRule();
      rule.plan([a, b]);
      downloads[a]!.complete(bytes);
      await pumpEventQueue();
      rule.pointerDown(1);
      timers.elapse(const Duration(milliseconds: 500));
      rule.pointerUp(1);
      timers.elapse(fontWarmUpQuiet - ms);
      expect(registered, isEmpty);
      timers.elapse(ms);
      expect(registered, [
        ['Ong JP 1'],
      ]);
      // a pointer whose up never comes
      rule.pointerDown(2);
      downloads[b]!.complete(bytes);
      await pumpEventQueue();
      timers.elapse(fontWarmUpLongestWait - ms);
      expect(registered, hasLength(1));
      timers.elapse(ms);
      expect(registered.last, ['Ong KR 1']);
    });

    test('offline: nothing is downloaded until the browser is online again', () async {
      final network = FakeFontNetwork(online: false);
      final (:rule, :timers, :downloads, :registered) = fakeRule(network: network);
      rule.plan([a]);
      timers.elapse(const Duration(minutes: 10));
      expect(downloads, isEmpty);
      network.value = true;
      expect(downloads.keys, [a]);
    });

    test('a failed download is tried again later, less and less often, or at once back online', () async {
      final network = FakeFontNetwork();
      final (:rule, :timers, :downloads, :registered) = fakeRule(network: network);
      rule.plan([a, b]);
      downloads[b]!.complete(bytes);
      Future<void> fail() async {
        downloads.remove(a)!.completeError(const SocketException('down'));
        await pumpEventQueue();
      }

      await fail();
      timers.elapse(fontKitRetryDelays[0] - ms);
      expect(downloads.containsKey(a), isFalse);
      timers.elapse(ms);
      expect(downloads.keys, contains(a));
      await fail();
      timers.elapse(fontKitRetryDelays[1] - ms);
      expect(downloads.containsKey(a), isFalse);
      network
        ..value = false
        ..value = true;
      expect(downloads.keys, contains(a), reason: 'back online');
      downloads[a]!.complete(bytes);
      await pumpEventQueue();
      timers.elapse(const Duration(seconds: 5));
      expect(registered.expand((names) => names), ['Ong KR 1', 'Ong JP 1'], reason: 'each kit registered once');
    });

    test(
      '$fontKitAttempts attempts per kit, each its own count; then nothing until the browser comes back online',
      () async {
        final network = FakeFontNetwork();
        final (:rule, :timers, :downloads, :registered) = fakeRule(network: network);
        final c = kitOf('Ong SC 1', '東');
        rule.plan([a, b, c]);
        var attemptsAtA = 1, attemptsAtB = 1;
        Future<void> fail(FontKit kit) async {
          downloads.remove(kit)!.completeError(const SocketException('blocked'));
          await pumpEventQueue();
        }

        await fail(b);
        for (var i = 0; i < fontKitAttempts; i++) {
          await fail(a);
          timers.elapse(const Duration(minutes: 5));
          if (downloads.containsKey(a)) attemptsAtA++;
          if (downloads.containsKey(b)) {
            attemptsAtB++;
            downloads.remove(b);
          }
        }
        expect(attemptsAtA, fontKitAttempts);
        expect(attemptsAtB, 2, reason: 'b failed once: tried again once, its failures are its own');
        timers.elapse(const Duration(days: 1));
        expect(downloads.containsKey(a), isFalse, reason: 'no attempt for ever');
        // another kit tried again later does not bring it back
        await fail(c);
        timers.elapse(fontKitRetryDelays.first);
        expect(downloads.keys, contains(c));
        expect(downloads.containsKey(a), isFalse, reason: 'not with the attempts of another kit');
        network
          ..value = false
          ..value = true;
        expect(downloads.keys, contains(a), reason: 'back online');
      },
    );

    test('a kit the API will not cut down is never asked again; the others are registered', () async {
      final network = FakeFontNetwork();
      final (:rule, :timers, :downloads, :registered) = fakeRule(network: network);
      rule.plan([a, b]);
      downloads.remove(a)!.completeError(const FontKitUnavailable('slices'));
      downloads[b]!.complete(bytes);
      await pumpEventQueue();
      timers.elapse(const Duration(days: 1));
      network
        ..value = false
        ..value = true;
      timers.elapse(const Duration(days: 1));
      expect(downloads.containsKey(a), isFalse);
      expect(registered, [
        ['Ong KR 1'],
      ]);
    });

    test('once the engine has fonts of its own, no longest wait: registered only when nothing moves', () async {
      final network = FakeFontNetwork(engineFontBytes: 60 * 1024);
      final (:rule, :timers, :downloads, :registered) = fakeRule(network: network);
      rule.plan([a]);
      downloads[a]!.complete(bytes);
      await pumpEventQueue();
      const step = Duration(milliseconds: 100);
      for (var i = 0; i < 100; i++) {
        rule.moved();
        timers.elapse(step);
      }
      expect(registered, isEmpty, reason: 'ten seconds of moves');
      timers.elapse(fontWarmUpQuiet);
      expect(registered, hasLength(1));
    });

    test('the engine\'s own fonts coming stop the longest wait already counting', () async {
      final network = FakeFontNetwork();
      final (:rule, :timers, :downloads, :registered) = fakeRule(network: network);
      rule.plan([a]);
      downloads[a]!.complete(bytes);
      await pumpEventQueue();
      const step = Duration(milliseconds: 100);
      for (var i = 0; i < 50; i++) {
        if (i == 5) network.engineFontBytes.value = 60 * 1024;
        rule.moved();
        timers.elapse(step);
      }
      expect(registered, isEmpty);
      timers.elapse(fontWarmUpQuiet);
      expect(registered, hasLength(1));
    });

    test('CanvasKit: beyond $maxRecreatedFontBytes bytes of the engine\'s own fonts, no kit is registered nor '
        'downloaded any more; below, registered when nothing moves', () async {
      final network = FakeFontNetwork(registrationRecreatesFonts: true);
      final (:rule, :timers, :downloads, :registered) = fakeRule(network: network);
      rule.plan([a, b]);
      downloads[a]!.complete(bytes);
      await pumpEventQueue();
      network.engineFontBytes.value = maxRecreatedFontBytes + 1;
      timers.elapse(const Duration(minutes: 10));
      expect(registered, isEmpty, reason: 'neither when nothing moves, nor at the longest wait');
      downloads.remove(b)!.completeError(const SocketException('down'));
      await pumpEventQueue();
      timers.elapse(const Duration(minutes: 10));
      network
        ..value = false
        ..value = true;
      expect(downloads.containsKey(b), isFalse, reason: 'no download either');
      // as many bytes as allowed: registered when nothing moves
      final small = fakeRule(
        network: FakeFontNetwork(registrationRecreatesFonts: true, engineFontBytes: maxRecreatedFontBytes),
      );
      small.rule.plan([a]);
      small.downloads[a]!.complete(bytes);
      await pumpEventQueue();
      small.timers.elapse(fontWarmUpQuiet);
      expect(small.registered, hasLength(1));
      // skwasm, whatever the engine has: registered when nothing moves
      final skwasm = fakeRule(network: FakeFontNetwork(engineFontBytes: 10 * maxRecreatedFontBytes));
      skwasm.rule.plan([a]);
      skwasm.downloads[a]!.complete(bytes);
      await pumpEventQueue();
      skwasm.timers.elapse(fontWarmUpQuiet);
      expect(skwasm.registered, hasLength(1));
    });

    test('nothing once disposed; the network no longer listened to', () async {
      final network = FakeFontNetwork(online: false);
      final (:rule, :timers, :downloads, :registered) = fakeRule(network: network);
      rule
        ..plan([a])
        ..dispose();
      expect(network.listened, isFalse);
      network.value = true;
      timers.elapse(const Duration(minutes: 10));
      expect(downloads, isEmpty);
      final other = fakeRule();
      other.rule
        ..plan([a])
        ..dispose();
      other.downloads[a]!.complete(bytes);
      await pumpEventQueue();
      other.timers.elapse(const Duration(minutes: 10));
      expect(other.registered, isEmpty);
    });
  });

  group('in the app', () {
    testWidgets('downloads the kits of the catalogue once the list is shown, registers them when nothing moves', (
      tester,
    ) async {
      final asked = <FontKit>[];
      final registered = <String>[];
      final app = await pumpApp(
        tester,
        state: CatalogueState(isRefreshing: true),
        settle: false,
        fontNetwork: FakeFontNetwork(),
        fontKitDownload: (kit) async {
          asked.add(kit);
          return bytes;
        },
        fontKitRegistration: (fonts) async => registered.addAll([for (final (kit, _) in fonts) kit.name]),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(asked, isEmpty, reason: 'the loading screen');
      app.notifier.emit(loaded(rareCatalogue));
      await tester.pump();
      expect(find.text('月'), findsOneWidget, reason: 'the list is shown');
      // the frame that shows it, then the collection of its characters
      await tester.pump();
      await tester.pump(ms);
      expect([for (final k in asked) '${k.name}: ${k.text}'], kitTexts('東方月봄🎶ا'));
      expect(registered, isEmpty, reason: 'a download registers nothing by itself');
      await tester.pump(fontWarmUpFirstQuiet);
      expect(registered, [for (final k in asked) k.name]);
    });

    // the songs hold a kanji the highlights do not, besides Korean, an emoji and Arabic
    final withKanji = testCatalogue(
      moreHighlights: [hRow(order: '4', title: '東方 - 月', upload: '2024-03-08')],
      moreSongs: [
        start('2024-03-03'),
        sRow(date: '2024-03-03 20:00:00', title: '日 - 봄 🎶', requester: 'ا'),
      ],
    );

    testWidgets('the Songs sheet coming: kits for the characters only it holds, the first ones not asked again', (
      tester,
    ) async {
      final asked = <FontKit>[];
      final registered = <String>[];
      final app = await pumpApp(
        tester,
        state: CatalogueState(catalogue: withKanji.highlightsOnly, fetchedAt: testNow),
        settle: false,
        fontNetwork: FakeFontNetwork(),
        fontKitDownload: (kit) async {
          asked.add(kit);
          return bytes;
        },
        fontKitRegistration: (fonts) async => registered.addAll([for (final (kit, _) in fonts) kit.name]),
      );
      await tester.pump();
      await tester.pump(ms);
      final first = [...asked];
      expect([for (final k in first) '${k.name}: ${k.text}'], kitTexts('東方月'), reason: 'the highlights alone');
      await tester.pump(fontWarmUpFirstQuiet);
      expect(registered, [for (final k in first) k.name]);
      app.notifier.emit(loaded(withKanji));
      await tester.pump();
      await tester.pump();
      await tester.pump(ms);
      final more = asked.skip(first.length).toList();
      expect(
        [for (final k in more) '${k.name}: ${k.text}'],
        [
          for (final k in planFontKits({...'東方月日봄🎶ا'.runes, ...appRareCharacters.runes}, planned: first))
            '${k.name}: ${k.text}',
        ],
      );
      // a family that has a kit already gets another one for the characters only the songs hold
      expect([for (final k in more) '${k.name}: ${k.text}'], contains('Ong JP 2: 日'));
      expect(more.where(first.contains), isEmpty, reason: 'nothing downloaded again');
      await tester.pump(fontWarmUpFirstQuiet);
      await tester.pump(fontWarmUpQuiet);
      expect(registered, [
        for (final k in [...first, ...more]) k.name,
      ], reason: 'each kit registered once');
    });

    testWidgets('text typed in a field postpones the registration', (tester) async {
      final registered = <String>[];
      await pumpApp(
        tester,
        state: loaded(rareCatalogue),
        settle: false,
        fontNetwork: FakeFontNetwork(),
        fontKitDownload: (kit) async => bytes,
        fontKitRegistration: (fonts) async => registered.addAll([for (final (kit, _) in fonts) kit.name]),
      );
      // the focus moves to the search field without a pointer (as with its keyboard shortcut): not a move
      await tester.showKeyboard(find.byType(TextField).first);
      for (var i = 0; i < 8; i++) {
        await tester.enterText(find.byType(TextField).first, 'zelda'.substring(0, i % 5 + 1));
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(registered, isEmpty);
      await tester.pump(fontWarmUpLongestWait);
      expect(registered, isNotEmpty);
    });

    testWidgets('a scroll postpones the registration', (tester) async {
      final registered = <String>[];
      final long = testCatalogue(
        moreHighlights: [
          for (var i = 4; i < 60; i++) hRow(order: '$i', title: 'Video $i', upload: '2024-01-02'),
          hRow(order: '60', title: '東方 - 月', upload: '2024-03-08'),
        ],
      );
      await pumpApp(
        tester,
        state: loaded(long),
        settle: false,
        fontNetwork: FakeFontNetwork(),
        fontKitDownload: (kit) async => bytes,
        fontKitRegistration: (fonts) async => registered.addAll([for (final (kit, _) in fonts) kit.name]),
      );
      // a mouse wheel: no pointer goes down, only the list moves
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      final at = tester.getCenter(find.text('月'));
      for (var i = 0; i < 8; i++) {
        await tester.sendEventToBinding(mouse.hover(at));
        await tester.sendEventToBinding(mouse.scroll(const Offset(0, 20)));
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('月'), findsNothing, reason: 'the list has moved');
      expect(registered, isEmpty);
      await tester.pump(fontWarmUpLongestWait);
      expect(registered, isNotEmpty);
    });

    testWidgets('a press on the list holds the registration', (tester) async {
      final registered = <String>[];
      await pumpApp(
        tester,
        state: loaded(rareCatalogue),
        settle: false,
        fontNetwork: FakeFontNetwork(),
        fontKitDownload: (kit) async => bytes,
        fontKitRegistration: (fonts) async => registered.addAll([for (final (kit, _) in fonts) kit.name]),
      );
      final press = await tester.startGesture(tester.getCenter(find.text('月')));
      await tester.pump(fontWarmUpLongestWait - const Duration(milliseconds: 300));
      expect(registered, isEmpty);
      await press.cancel();
      await tester.pump(fontWarmUpLongestWait);
      expect(registered, isNotEmpty);
    });

    testWidgets('a catalogue replaced while its characters are collected: the kits of the new one', (tester) async {
      final asked = <FontKit>[];
      var gate = Completer<void>();
      final app = await pumpApp(
        tester,
        state: CatalogueState(isRefreshing: true),
        settle: false,
        fontNetwork: FakeFontNetwork(),
        fontKitDownload: (kit) async {
          asked.add(kit);
          return bytes;
        },
        fontPause: () => gate.future,
      );
      app.notifier.emit(loaded(rareCatalogue));
      await tester.pump();
      await tester.pump();
      app.notifier.emit(
        loaded(
          testCatalogue(
            moreHighlights: [hRow(order: '4', title: 'Ω ☆')],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        final open = gate;
        gate = Completer<void>();
        open.complete();
        await tester.pump();
      }
      expect([for (final k in asked) '${k.name}: ${k.text}'], kitTexts('☆'));
    });

    testWidgets('nothing at all where there is no network of fonts (the native apps)', (tester) async {
      final asked = <FontKit>[];
      await pumpApp(
        tester,
        state: loaded(rareCatalogue),
        fontKitDownload: (kit) async {
          asked.add(kit);
          return bytes;
        },
      );
      await tester.pump(const Duration(minutes: 1));
      expect(asked, isEmpty);
    });

    testWidgets('gone: no longer listens to the network nor to the text fields', (tester) async {
      final network = FakeFontNetwork();
      await pumpApp(tester, state: loaded(rareCatalogue), settle: false, fontNetwork: network);
      expect(network.listened, isTrue);
      final field = TextEditingController();
      final focus = FocusNode();
      addTearDown(field.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: TextField(controller: field, focusNode: focus),
          ),
        ),
      );
      expect(network.listened, isFalse);
      // a text field focused and typed into after the app is gone reaches nothing disposed
      focus.requestFocus();
      await tester.pump();
      field.text = 'typed';
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('the fallback of the texts of the app', () {
    /// The fallback of the text [text] as the running app draws it (its theme, merged into the text's style).
    List<String>? fallbackOf(WidgetTester tester, String text) =>
        tester.renderObject<RenderParagraph>(find.text(text).first).text.style?.fontFamilyFallback;

    for (final dark in [false, true]) {
      testWidgets(
        'web (${dark ? 'dark' : 'light'} theme): Roboto, then, once the engine has them, the kits registered',
        (tester) async {
          final registration = Completer<void>();
          final planned = <FontKit>[];
          var asked = false;
          await pumpApp(
            tester,
            state: loaded(rareCatalogue),
            settle: false,
            prefs: {if (dark) 'themeMode': 'dark'},
            fontNetwork: FakeFontNetwork(),
            fontKitDownload: (kit) async {
              planned.add(kit);
              return bytes;
            },
            fontKitRegistration: (fonts) {
              asked = true;
              return registration.future;
            },
          );
          expect(Theme.of(tester.element(find.text('月').first)).brightness, dark ? Brightness.dark : Brightness.light);
          expect(fallbackOf(tester, '月'), ['Roboto']);
          await tester.pump(fontWarmUpFirstQuiet);
          await tester.pump(fontWarmUpFirstQuiet);
          expect(planned, isNotEmpty);
          expect(asked, isTrue, reason: 'registration asked of the engine');
          await tester.pump();
          expect(fallbackOf(tester, '月'), ['Roboto'], reason: 'the engine does not have them yet');
          registration.complete();
          // the families reach the themes at once (no theme animation), then the texts in the 100 ms Material's
          // default text style takes to flip a fallback
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          expect(fallbackOf(tester, '月'), ['Roboto', ...kitFamiliesOf(planned)]);
          expect(fallbackOf(tester, 'Ong Log'), ['Roboto', ...kitFamiliesOf(planned)], reason: 'every text');
        },
      );
    }

    testWidgets('elsewhere (the native apps): no fallback of the app\'s own', (tester) async {
      await pumpApp(tester, state: loaded(rareCatalogue), prefs: {'themeMode': 'dark'});
      await tester.pump(const Duration(minutes: 1));
      expect(fallbackOf(tester, '月'), isNull);
    });
  });

  group('the app\'s own texts', () {
    test('the rare characters of the sources are those of appRareCharacters', () {
      final found = <int>{};
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart') || file.path.endsWith('.g.dart')) continue;
        for (final line in file.readAsLinesSync()) {
          if (line.trimLeft().startsWith('//')) continue;
          final code = line.contains(' // ') ? line.substring(0, line.indexOf(' // ')) : line;
          addRareCharacters(code, found);
        }
      }
      expect(String.fromCharCodes(found.toList()..sort()), appRareCharacters);
    });
  });
}
