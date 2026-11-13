import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/data/catalogue.dart';
import 'package:ong_music/src/data/schedule.dart';
import 'package:ong_music/src/data/twitch.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/state/settings_state.dart';
import 'package:ong_music/src/state/twitch_state.dart';
import 'package:ong_music/src/ui/about_page.dart';
import 'package:ong_music/src/ui/actions.dart';
import 'package:ong_music/src/ui/app.dart';
import 'package:ong_music/src/ui/fullscreen_button.dart';
import 'package:ong_music/src/ui/install_banner.dart';
import 'package:ong_music/src/ui/layout.dart';
import 'package:ong_music/src/ui/nav_rail.dart';
import 'package:ong_music/src/ui/video_preview.dart';
import 'package:ong_music/src/ui/widgets.dart';
import 'package:ong_music/src/web/embedded_video.dart';
import 'package:ong_music/src/web/fullscreen.dart';
import 'package:ong_music/src/web/install_hint.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

/// "Now" of the UI tests.
final testNow = DateTime.utc(2026, 11, 12, 12);

/// A small catalogue: two streams, three highlights.
///
/// - 2024-03-01 (Fri): "Gloria Gaynor - I Will Survive" (loop, MannyHub),
///   "Zelda - Lost Woods" (piano, jsbach64)
/// - 2024-03-02 (Sat): "Zelda - Song of Storms" (piano, jsbach64, Tier 3),
///   "Gloria Gaynor - I Will Survive" (loop, shadowvanta)
/// - highlights: #1 Song of Storms (video, jsbach64), #2 I Will Survive
///   (video, shadowvanta, vocals, notes), #3 How Far I'll Go (no video).
///
/// [moreHighlights] come after them, [moreSongs] after the songs (a stream
/// of their own begins with [start]).
Catalogue testCatalogue({SheetRows moreHighlights = const [], SheetRows moreSongs = const []}) => catalogueOf(
  highlights: [
    hRow(
      order: '1',
      title: 'Zelda - Song of Storms',
      genre: 'GAME OST',
      link: 'https://youtu.be/aaaaaaaaaaa',
      requester: 'jsbach64',
      stream: '2024-03-02',
      upload: '2024-03-05',
    ),
    hRow(
      order: '2',
      title: 'Gloria Gaynor - I Will Survive',
      genre: 'POPULAR MUSIC',
      link: 'https://www.youtube.com/watch?v=bbbbbbbbbbb',
      requester: 'shadowvanta',
      stream: '2024-03-02',
      upload: '2024-03-06',
      vocals: 'Yes',
      notes: 'An improvised arrangement.',
    ),
    hRow(order: '3', title: "Moana - How Far I'll Go", genre: 'DISNEY', upload: '2024-03-07'),
    ...moreHighlights,
  ],
  songs: [
    start('2024-03-01'),
    sRow(
      date: '2024-03-01 20:00:00',
      uptime: '0:10:00',
      title: 'Gloria Gaynor - I Will Survive',
      genre: 'POPULAR MUSIC',
      type: 'Loop',
      requester: 'MannyHub',
    ),
    sRow(
      date: '2024-03-01 20:30:00',
      uptime: '1:05:00',
      title: 'Zelda - Lost Woods',
      type: 'Piano',
      requester: 'jsbach64',
    ),
    start('2024-03-02'),
    sRow(
      date: '2024-03-02 20:10:00',
      uptime: '0:20:00',
      title: 'Zelda - Song of Storms',
      type: 'Piano',
      requester: 'jsbach64',
      notes: 'Tier 3',
    ),
    sRow(
      date: '2024-03-02 21:00:00',
      uptime: '2:03:00',
      title: 'Gloria Gaynor - I Will Survive',
      genre: 'POPULAR MUSIC',
      type: 'Loop',
      requester: 'shadowvanta',
    ),
    ...moreSongs,
  ],
);

/// Rows of a spreadsheet, as the fixtures give them.
typedef SheetRows = List<List<String>>;

/// A [CatalogueNotifier] with a fixed state that records the calls.
class FakeCatalogueNotifier extends CatalogueNotifier {
  FakeCatalogueNotifier(this.initial);

  final CatalogueState initial;
  int refreshes = 0;
  int clears = 0;
  int staleChecks = 0;

  @override
  CatalogueState build() => initial;

  @override
  Future<void> refresh() async {
    refreshes++;
    if (refreshError case final error?) {
      state = CatalogueState(catalogue: state.catalogue, fetchedAt: state.fetchedAt, lastError: error);
    }
  }

  /// When set, [refresh] fails with it.
  Object? refreshError;

  @override
  Future<void> clearDownloadedData() async => clears++;

  @override
  Future<void> refreshIfStale() async => staleChecks++;

  /// The values given to [setForeground].
  final foreground = <bool>[];

  @override
  void setForeground(bool foreground) => this.foreground.add(foreground);

  /// Replaces the state.
  void emit(CatalogueState value) => state = value;
}

/// A [TwitchApi] answering [schedule] (default: an empty one; throws
/// [scheduleError] when set, fails when [schedule] is set to null) and
/// [live], counting the calls.
class FakeTwitchApi implements TwitchApi {
  FakeTwitchApi({StreamSchedule? schedule, this.scheduleError, this.live = false})
    : schedule = schedule ?? parseSchedule('BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n');

  StreamSchedule? schedule;
  Object? scheduleError;
  bool live;
  int scheduleCalls = 0;
  int liveCalls = 0;

  /// When set, the answers wait for it.
  Completer<void>? gate;

  @override
  Future<StreamSchedule> fetchSchedule() async {
    scheduleCalls++;
    if (gate != null) await gate!.future;
    if (scheduleError != null) throw scheduleError!;
    return schedule ?? (throw StateError('no schedule'));
  }

  @override
  Future<bool> isLive() async {
    liveCalls++;
    if (gate != null) await gate!.future;
    return live;
  }
}

/// A 1 × 1 transparent PNG: thumbnails without network.
final Uint8List transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// What the app did outside itself.
class Effects {
  final opened = <Uri>[];
  final shared = <String>[];
  String? clipboard;
  bool shareWorks = true;

  /// False: no app can open a link.
  bool openWorks = true;

  /// False: the clipboard refuses, as a browser may.
  bool clipboardWorks = true;

  /// How many times the app asked the system to close it (Android back).
  int exits = 0;
}

/// The running test app.
class TestApp {
  TestApp(this.notifier, this.effects, this.prefs, this.twitch);

  final FakeCatalogueNotifier notifier;
  final Effects effects;
  final SharedPreferences prefs;
  final FakeTwitchApi twitch;
}

/// Pumps the app with [state] (default: [testCatalogue], fetched 2 hours
/// before [testNow]) on a 412 × 892 phone, as a native app unless
/// [installHint] or [fullscreen] (default: none, as in the native apps) say
/// otherwise. The time is [clock] (default: [testNow]);
/// Twitch is [twitch] (default: nothing known, never live).
///
/// The pointer follows the pointer events from the guess of the platform, as
/// in the app, unless [pointer] pins it (whatever the test taps with: a tap of
/// a test is a touch).
///
/// Videos open on YouTube, as in the native apps, unless [videos] plays them
/// in place, as the web app does.
Future<TestApp> pumpApp(
  WidgetTester tester, {
  CatalogueState? state,
  Map<String, Object> prefs = const {},
  double textScale = 1,
  Size size = const Size(412, 892),
  bool settle = true,
  InstallHint installHint = InstallHint.none,
  FakeTwitchApi? twitch,
  DateTime Function()? clock,
  bool alwaysUse24HourFormat = false,
  bool startsInBackground = false,
  PageFullscreen? fullscreen,
  PointerKind? pointer,
  VideoEmbedder? videos,
}) async {
  // before the size: setting it makes MediaQuery read the clock format again
  tester.platformDispatcher.alwaysUse24HourFormatTestValue = alwaysUse24HourFormat;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearAlwaysUse24HourTestValue);
  final twitchApi = twitch ?? FakeTwitchApi();
  SharedPreferences.setMockInitialValues(prefs);
  final preferences = await SharedPreferences.getInstance();
  final notifier = FakeCatalogueNotifier(
    state ?? CatalogueState(catalogue: testCatalogue(), fetchedAt: testNow.subtract(const Duration(hours: 2))),
  );
  final effects = Effects();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'SystemNavigator.pop') effects.exits++;
    if (call.method == 'Clipboard.setData') {
      if (!effects.clipboardWorks) throw PlatformException(code: 'copy_fail');
      effects.clipboard = (call.arguments as Map)['text'] as String?;
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        catalogueProvider.overrideWith(() => notifier),
        clockProvider.overrideWithValue(clock ?? () => testNow),
        twitchApiProvider.overrideWithValue(twitchApi),
        installHintProvider.overrideWithValue(installHint),
        startsInBackgroundProvider.overrideWithValue(startsInBackground),
        pageFullscreenProvider.overrideWithValue(fullscreen),
        videoEmbedderProvider.overrideWithValue(videos),
        if (pointer != null) pointerProvider.overrideWith(() => PinnedPointer(pointer)),
        thumbnailImageProvider.overrideWithValue((url) => MemoryImage(transparentPng)),
        urlOpenerProvider.overrideWithValue((uri) async {
          if (!effects.openWorks) return false;
          effects.opened.add(uri);
          return true;
        }),
        textSharerProvider.overrideWithValue((text) async {
          if (!effects.shareWorks) return false;
          effects.shared.add(text);
          return true;
        }),
      ],
      child: const OngMusicApp(),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return TestApp(notifier, effects, preferences, twitchApi);
}

/// A pointer that stays [kind] whatever the pointer events.
class PinnedPointer extends PointerNotifier {
  PinnedPointer(this.kind);

  final PointerKind kind;

  @override
  PointerKind build() => kind;

  @override
  void saw(PointerDeviceKind kind) {}
}

/// The navigation: the bottom bar of a compact window, or the rail of the others.
Finder navigation() => find.byWidgetPredicate((w) => w is NavigationBar || w is AppNavigationRail);

/// Taps the navigation destination [label] (of the bar or of the rail).
Future<void> goToTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: navigation(), matching: find.text(label)));
  await tester.pumpAndSettle();
}

/// The index of the selected navigation destination.
int selectedTab(WidgetTester tester) => switch (tester.widget(navigation())) {
  NavigationBar(:final selectedIndex) || AppNavigationRail(:final selectedIndex) => selectedIndex,
  _ => throw StateError('no navigation'),
};

/// The ⋮ buttons of the highlight rows, which open the sheet of their row.
Finder detailsButtons() =>
    find.byWidgetPredicate((w) => w is IconButton && w.icon is Icon && (w.icon as Icon).semanticLabel == 'Details');

/// The search field of the visible tab.
Finder searchField() =>
    find.descendant(of: find.byType(ListSearchField).hitTestable(), matching: find.byType(TextField));

/// Lets a short message (2.6 s) go away.
Future<void> waitForMessage(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

/// Scrolls [finder] into view, then taps it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The filter chip of [label] (a chip without visible label is found by its
/// label for screen readers).
Finder chip(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is ListChip && w.label == label),
  matching: find.byType(FilterChip),
);

/// The text chip [label] shows: its label and count, or its count alone,
/// without the unseen copy that gives the chip the width of its largest count.
Finder chipText(String label) => find.descendant(
  of: chip(label),
  matching: find.byElementPredicate((e) {
    if (e.widget is! Text) return false;
    var shown = true;
    e.visitAncestorElements((a) {
      final w = a.widget;
      if (w is Visibility && !w.visible) shown = false;
      return shown && w is! FilterChip;
    });
    return shown;
  }),
);

/// The plain text of [chipText].
String chipTextOf(WidgetTester tester, String label) {
  final text = tester.widget<Text>(chipText(label));
  return text.data ?? text.textSpan!.toPlainText();
}

/// The rich text whose plain text is [text].
Finder richText(String text) => find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == text);

/// The scroll view of the About tab.
Finder aboutScrollable() => find.descendant(of: find.byType(AboutPage), matching: find.byType(Scrollable)).first;

/// A browser that accepts full screen requests, unless [refuses].
class FakeFullscreen implements PageFullscreen {
  final _state = ValueNotifier(false);
  bool refuses = false;
  int enters = 0;
  int exits = 0;

  @override
  ValueListenable<bool> get isFullscreen => _state;

  /// What the browser does by itself: Escape, its own gesture.
  set browserState(bool value) => _state.value = value;

  /// When set, [enter] answers only when this completes: a browser that
  /// takes its time.
  Completer<bool>? pending;

  @override
  Future<bool> enter() async {
    enters++;
    if (pending case final pending?) return pending.future;
    if (refuses) return false;
    _state.value = true;
    return true;
  }

  @override
  Future<void> exit() async {
    exits++;
    _state.value = false;
  }
}

/// The full screen button of the visible tab.
Finder fullscreenButton() => find.byType(FullscreenButton).hitTestable();

/// The pill of the search field of the visible tab.
Finder pill() => find.descendant(of: find.byType(ListSearchField).hitTestable(), matching: find.byType(Material)).first;

/// Checks the place of the button for a content column from [left] to
/// [right]: the pill keeps its left edge and ends 48 px from the right, the
/// button is at the right edge, as big as the ⋮ buttons of the highlight rows
/// ([column] px: 48 on a phone, 40 on desktop, which has no padded tap
/// targets), centred on the pill.
void expectLayout(
  WidgetTester tester, {
  required double left,
  required double right,
  double column = 48,
  String? reason,
}) {
  final field = tester.getRect(pill());
  final button = tester.getRect(fullscreenButton());
  expect((field.left, field.right), (left + 16, right - 48), reason: reason);
  expect(field.height, greaterThanOrEqualTo(52), reason: reason);
  final size = Size.square(column);
  expect(
    button,
    Rect.fromCenter(center: Offset(right - column / 2, field.center.dy), width: size.width, height: size.height),
    reason: reason,
  );
}

/// Plays videos in place, as the web app does, with players the test drives.
class FakeVideoEmbedder implements VideoEmbedder {
  /// Every player made, in order.
  final videos = <FakeVideo>[];

  @override
  FakeVideo play(String youtubeId) {
    final video = FakeVideo(youtubeId);
    videos.add(video);
    return video;
  }

  /// The players not disposed: those that can be heard.
  List<FakeVideo> get alive => [
    for (final v in videos)
      if (!v.disposed) v,
  ];

  /// The one player alive.
  FakeVideo get only => alive.single;
}

/// A player of [FakeVideoEmbedder]: its state is set by the test.
class FakeVideo implements EmbeddedVideo {
  FakeVideo(this.youtubeId);

  final String youtubeId;
  final _state = ValueNotifier(EmbeddedVideoState.loading);
  bool disposed = false;

  /// How many times its view was put on screen: more than once, the web app
  /// would have loaded the player again.
  int mounts = 0;

  @override
  Widget get view => FakePlayerView(video: this);

  @override
  ValueListenable<EmbeddedVideoState> get state => _state;

  /// What YouTube's player does.
  set playerState(EmbeddedVideoState value) => _state.value = value;

  @override
  void dispose() {
    expect(disposed, isFalse, reason: 'disposed twice');
    disposed = true;
  }
}

/// What a [FakeVideo] shows: a black box.
class FakePlayerView extends StatefulWidget {
  const FakePlayerView({super.key, required this.video});

  final FakeVideo video;

  @override
  State<FakePlayerView> createState() => _FakePlayerViewState();
}

class _FakePlayerViewState extends State<FakePlayerView> {
  @override
  void initState() {
    super.initState();
    widget.video.mounts++;
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}
