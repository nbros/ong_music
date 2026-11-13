/// Web: fonts for the catalogue's rare characters (Japanese, Chinese, Korean, Arabic, symbols, emoji: see
/// `data/rare_characters.dart`), cut down to those characters, downloaded early and registered while nothing moves,
/// so that no scroll pays for a whole font.
///
/// Left to itself, the web engine draws a character its fonts lack with a whole Noto font it downloads from Google
/// Fonts when a row holding it first scrolls into view, and registers it on the page's thread when the download ends,
/// whatever the visitor does: a scroll froze for 100–165 ms each time, then again for up to 75 ms per weight while
/// the 2 MB of Noto Sans KR were opened. Instead, once the list is on screen, the app collects the characters, asks
/// Google Fonts for fonts holding only them ([planFontKits]: 107 KB for the real sheets), downloads them in the
/// background, and registers them itself ([FontLoader]) when nothing moves ([FontWarmUp]); once they are registered,
/// the themes name them in the fallback of every text ([fontFallbackProvider]). Registered, they draw those
/// characters, and the engine looks for no font of its own for them; it still does, as before, for characters no kit
/// holds (a kit the API would not cut down for this browser, a refresh that brings new characters: the kits are
/// planned once per visit).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/catalogue.dart';
import '../data/font_kits.dart';
import '../data/page_thread.dart';
import '../data/rare_characters.dart';
import '../data/slices.dart';
import '../logger.dart';
import '../state/catalogue_state.dart';
import '../web/font_network.dart';
import '../web/web_platform.dart';

/// How long nothing must move (no pointer down, no scroll, no text typed) before fonts are registered, once something
/// has moved.
const Duration fontWarmUpQuiet = Duration(seconds: 1);

/// The same while nothing has moved since the list appeared: the fonts come before a first scroll is likely.
const Duration fontWarmUpFirstQuiet = Duration(milliseconds: 300);

/// Fonts downloaded wait at most this long for a moment when nothing moves, while the engine has fetched no font of
/// its own: registering them then costs a task or two of some 40–70 ms, where a row needing a font the kits hold would
/// make the engine download and register its own (100–165 ms per font, and the bytes of whole fonts). Once the engine
/// has its own fonts there is no longest wait; and in the CanvasKit build, where registering re-creates the engine's
/// fonts too, beyond [maxRecreatedFontBytes] of them no kit is registered at all: the engine goes on as without kits.
const Duration fontWarmUpLongestWait = Duration(seconds: 2);

/// The most bytes of the engine's own fonts kits may still be registered with in the CanvasKit build, where
/// registering creates them again: some 60–80 ms more (measured: about 250 ms per megabyte; the 2 MB of Noto Sans KR
/// make a task of 0.6 s, which a scroll starting then would wait for).
const int maxRecreatedFontBytes = 256 * 1024;

/// After a failed download, the next attempt waits this long: the first delay after one failure, the second after
/// two. After as many failures as attempts ([fontKitAttempts]), the kit waits for the browser to come back online (or
/// the next visit).
const List<Duration> fontKitRetryDelays = [Duration(seconds: 15), Duration(minutes: 1)];

/// The attempts at a kit before it waits for the browser to come back online.
final int fontKitAttempts = fontKitRetryDelays.length + 1;

/// The characters of the app's own texts that its fonts lack (`'$link →'` of `widgets.dart`). A test keeps it in step
/// with the sources.
const String appRareCharacters = '→';

/// Downloads the font of a kit.
typedef FontKitDownload = Future<Uint8List> Function(FontKit kit);

/// Registers fonts, each under its kit's name; done when the engine has them.
typedef FontKitRegistration = Future<void> Function(List<(FontKit, Uint8List)> fonts);

/// Registers [fonts] with the engine ([FontLoader]), all in the same turn: the engine then tells the framework once
/// that fonts changed. A font the engine refuses is logged; its characters stay with the engine's own fallback.
Future<void> registerFontKits(List<(FontKit, Uint8List)> fonts) => Future.wait([
  for (final (kit, bytes) in fonts)
    (FontLoader(kit.name)..addFont(Future.value(ByteData.sublistView(bytes)))).load().catchError(
      (Object e) => logger.w('Cannot register the font ${kit.name}', error: e),
    ),
]);

/// How the fonts of kits are downloaded. Overridden in tests.
final fontKitDownloadProvider = Provider<FontKitDownload>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return FontKitDownloader(client).download;
});

/// How fonts are registered: [registerFontKits]. Overridden in tests.
final fontKitRegistrationProvider = Provider<FontKitRegistration>((ref) => registerFontKits);

/// The network of the fonts: the browser's; null in the native apps, where the system's fonts draw every character
/// and nothing is done (no collection of the characters either). Overridden in tests.
final fontNetworkProvider = Provider<FontNetwork?>((ref) => fontNetwork());

/// What lets the page draw between two steps of the collection (see [yieldToBrowser]). Overridden in tests.
final fontWarmUpPauseProvider = Provider<Future<void> Function()>((ref) => yieldToBrowser);

/// The fallback of every text of the app's themes: null in the native apps (the system's fallback); on the web,
/// Roboto (the app's font), then the families of the kits registered, in the order they must be tried. Roboto comes
/// first again: the themes' own family is a name the web app has no font for, and the first of the fallback that
/// draws a space would draw them all.
final fontFallbackProvider = NotifierProvider<FontFallbackNotifier, List<String>?>(FontFallbackNotifier.new);

/// Holds the fallback of the themes ([fontFallbackProvider]).
class FontFallbackNotifier extends Notifier<List<String>?> {
  final Set<FontKit> _kits = {};

  @override
  List<String>? build() => ref.watch(fontNetworkProvider) == null ? null : const ['Roboto'];

  /// [kits] are registered: the themes name them too.
  void registered(Iterable<FontKit> kits) {
    if (state == null) return;
    _kits.addAll(kits);
    state = List.unmodifiable(['Roboto', ...kitFamiliesOf(_kits)]);
  }
}

/// The rule that says when to download the kits and when to register them, and does it.
///
/// Once the kits are planned ([plan], once, when the list is on screen), it downloads every kit while the browser is
/// online, all at once. A failed download is tried again after [retryDelays], [fontKitAttempts] times in all, then
/// when the browser comes back online; a kit the API will not cut down ([FontKitUnavailable]) is not asked for again.
/// It registers the fonts downloaded, all together, once no pointer is down and nothing has moved for [quiet]
/// ([firstQuiet] while nothing has moved yet): no pointer down or up, scroll or text typed; or, while the engine has
/// fetched no font of its own ([FontNetwork.engineFontBytes]), [longestWait] after a download ended, whatever moves.
/// Once the engine has more than [maxRecreatedFontBytes] of fonts of its own and registering would create them again
/// ([FontNetwork.registrationRecreatesFonts]), it downloads and registers nothing more.
///
/// The UI tells it what happens ([plan], [pointerDown], [pointerUp], [moved]); [startTimer] is replaced in tests.
final class FontWarmUp {
  /// Creates the rule.
  FontWarmUp({
    required this.download,
    required this.register,
    required this.network,
    this.quiet = fontWarmUpQuiet,
    this.firstQuiet = fontWarmUpFirstQuiet,
    this.longestWait = fontWarmUpLongestWait,
    this.retryDelays = fontKitRetryDelays,
    Timer Function(Duration duration, void Function() callback) startTimer = Timer.new,
  }) : _startTimer = startTimer {
    network.online.addListener(_onlineChanged);
    network.engineFontBytes.addListener(_engineFontsChanged);
  }

  /// Downloads the font of a kit.
  final FontKitDownload download;

  /// Registers fonts.
  final FontKitRegistration register;

  /// The network of the fonts.
  final FontNetwork network;

  /// How long nothing must move, once something has.
  final Duration quiet;

  /// How long nothing must move, while nothing has.
  final Duration firstQuiet;

  /// How long fonts downloaded wait at most for a moment when nothing moves, while the engine has no font of its own.
  final Duration longestWait;

  /// The waits after failed downloads of a kit; one more attempt than waits.
  final List<Duration> retryDelays;

  final Timer Function(Duration duration, void Function() callback) _startTimer;

  List<FontKit>? _kits;
  final Set<FontKit> _downloading = {};
  final Map<FontKit, Uint8List> _downloaded = {};
  final Set<FontKit> _registered = {};
  final Set<FontKit> _unavailable = {};
  final Map<FontKit, int> _failures = {};
  final Map<FontKit, Timer> _retries = {};
  final Set<int> _pressed = {};
  bool _touched = false;
  bool _disposed = false;
  Timer? _timer;
  Timer? _deadline;

  bool get _free => _kits != null && !_disposed && _pressed.isEmpty && !_closed;

  /// Whether registering would cost more than the kits save: the engine has fonts of its own, and would create them
  /// all again.
  bool get _closed => network.registrationRecreatesFonts && network.engineFontBytes.value > maxRecreatedFontBytes;

  /// The kits to download and register, once the list is on screen; only the first plan counts.
  void plan(List<FontKit> kits) {
    if (_kits != null) return;
    _kits = List.unmodifiable(kits);
    _downloadAll();
  }

  /// A pointer went down: nothing is registered until every pointer is up again, and [quiet] later (or
  /// [longestWait] after the download: a pointer whose up never comes holds nothing for long).
  void pointerDown(int pointer) {
    _pressed.add(pointer);
    moved();
  }

  /// A pointer went up, or was cancelled.
  void pointerUp(int pointer) {
    _pressed.remove(pointer);
    moved();
  }

  /// Something moved (a pointer, a scroll, a text typed): the wait starts again.
  void moved() {
    assert(!_disposed, 'The UI tells a disposed FontWarmUp that something moved: a listener was left behind');
    _touched = true;
    _wait();
  }

  /// Stops: nothing more is downloaded or registered.
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _deadline?.cancel();
    for (final retry in _retries.values) {
      retry.cancel();
    }
    network.online.removeListener(_onlineChanged);
    network.engineFontBytes.removeListener(_engineFontsChanged);
  }

  /// Back online: the kits that failed are tried again, at once.
  void _onlineChanged() {
    if (!network.online.value) return;
    for (final retry in _retries.values) {
      retry.cancel();
    }
    _retries.clear();
    _failures.clear();
    _downloadAll();
  }

  void _engineFontsChanged() {
    if (network.engineFontBytes.value == 0) return;
    _deadline?.cancel();
    _deadline = null;
    if (_closed) _wait();
  }

  /// Starts the downloads still to do: not under way, nor done, nor waiting to be tried again, nor given up.
  void _downloadAll() {
    final kits = _kits;
    if (kits == null || _disposed || _closed || !network.online.value) return;
    for (final kit in kits) {
      if (_downloading.contains(kit) ||
          _downloaded.containsKey(kit) ||
          _registered.contains(kit) ||
          _unavailable.contains(kit) ||
          _retries.containsKey(kit) ||
          (_failures[kit] ?? 0) >= fontKitAttempts) {
        continue;
      }
      _downloading.add(kit);
      unawaited(_download(kit));
    }
  }

  Future<void> _download(FontKit kit) async {
    try {
      final bytes = await download(kit);
      if (_disposed) return;
      _downloaded[kit] = bytes;
      if (network.engineFontBytes.value == 0) {
        _deadline ??= _startTimer(longestWait, () {
          _deadline = null;
          if (!_closed) _register();
        });
      }
      _wait();
    } on FontKitUnavailable catch (e) {
      if (_disposed) return;
      _unavailable.add(kit);
      logger.i('No font kit ${kit.name}: its characters are left to the engine ($e)');
    } catch (e) {
      if (_disposed) return;
      final failures = _failures[kit] = (_failures[kit] ?? 0) + 1;
      if (failures < fontKitAttempts) {
        logger.w('Cannot download the font ${kit.name} (attempt $failures of $fontKitAttempts)', error: e);
        _retries[kit] = _startTimer(retryDelays[failures - 1], () {
          _retries.remove(kit);
          _downloadAll();
        });
      } else {
        logger.w('Cannot download the font ${kit.name}: tried again when the browser comes back online', error: e);
      }
    } finally {
      _downloading.remove(kit);
    }
  }

  void _wait() {
    _timer?.cancel();
    _timer = _free && _downloaded.isNotEmpty
        ? _startTimer(_touched ? quiet : firstQuiet, () {
            if (_free) _register();
          })
        : null;
  }

  void _register() {
    _timer?.cancel();
    _timer = null;
    _deadline?.cancel();
    _deadline = null;
    if (_downloaded.isEmpty) return;
    final fonts = [for (final MapEntry(:key, :value) in _downloaded.entries) (key, value)];
    _registered.addAll(_downloaded.keys);
    _downloaded.clear();
    unawaited(register(fonts));
  }
}

/// Notifies when the text of the focused text field changes (typed, on a physical keyboard or a phone's), or its
/// selection moves. A move of the focus alone does not notify (the app's first frame gives the focus somewhere).
final class TextEditingActivity extends ChangeNotifier {
  TextEditingActivity() {
    FocusManager.instance.addListener(_follow);
    _follow();
  }

  TextEditingController? _controller;

  void _follow() {
    _controller?.removeListener(notifyListeners);
    final field = FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<EditableTextState>();
    _controller = field?.widget.controller?..addListener(notifyListeners);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_follow);
    _controller?.removeListener(notifyListeners);
    super.dispose();
  }
}

/// Makes the fonts of the catalogue's rare characters ready (see [FontWarmUp]) where [fontNetworkProvider] gives a
/// network; elsewhere, only [child].
///
/// Above the navigator (`MaterialApp.builder`), so that it sees the pointers, scrolls and text fields of the sheets
/// and dialogs too. Once a catalogue is on screen (after the frame that shows it: the list does not wait for any of
/// this), it collects its characters in slices between frames and plans the kits from them and from those of the
/// app's own texts. Once fonts are registered, it gives their families to the themes ([fontFallbackProvider]).
class FontWarmUpScope extends ConsumerStatefulWidget {
  const FontWarmUpScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<FontWarmUpScope> createState() => _FontWarmUpScopeState();
}

class _FontWarmUpScopeState extends ConsumerState<FontWarmUpScope> {
  FontWarmUp? _warmUp;
  TextEditingActivity? _typing;

  /// The catalogue whose characters are being collected; another one abandons the collection.
  Catalogue? _collecting;

  @override
  void initState() {
    super.initState();
    final network = ref.read(fontNetworkProvider);
    if (network == null) return;
    final register = ref.read(fontKitRegistrationProvider);
    final warmUp = _warmUp = FontWarmUp(
      download: ref.read(fontKitDownloadProvider),
      register: (fonts) async {
        await register(fonts);
        // once the engine has them: the themes are built again once, when the texts can use them
        if (mounted) ref.read(fontFallbackProvider.notifier).registered([for (final (kit, _) in fonts) kit]);
      },
      network: network,
    );
    _typing = TextEditingActivity()..addListener(warmUp.moved);
    ref.listenManual(
      catalogueProvider.select((s) => s.catalogue),
      (_, catalogue) => _shown(catalogue),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _warmUp?.dispose();
    _typing?.dispose();
    super.dispose();
  }

  /// [catalogue] is on screen after the next frame.
  void _shown(Catalogue? catalogue) {
    if (catalogue == null) return;
    _collecting = catalogue;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_collect(catalogue));
    });
  }

  /// Collects the characters of [catalogue], unless another one comes first, and plans the kits.
  Future<void> _collect(Catalogue catalogue) async {
    final characters = <int>{...appRareCharacters.runes};
    final emojiBases = <int>{};
    final steps = addCatalogueCharacters(catalogue, characters, emojiBases: emojiBases).iterator;
    try {
      await runInSlices(
        steps.moveNext,
        pause: ref.read(fontWarmUpPauseProvider),
        isAbandoned: () => !identical(_collecting, catalogue),
      );
    } on LoadAbandoned {
      return;
    }
    _warmUp?.plan(planFontKits(characters, emojiBases: emojiBases));
  }

  @override
  Widget build(BuildContext context) {
    final warmUp = _warmUp;
    if (warmUp == null) return widget.child;
    return Listener(
      // translucent: hears the events that reach anything in the window, empty space included
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => warmUp.pointerDown(event.pointer),
      onPointerUp: (event) => warmUp.pointerUp(event.pointer),
      onPointerCancel: (event) => warmUp.pointerUp(event.pointer),
      // every scroll, whatever moves it (a drag, its fling, a wheel, a trackpad, a key, the app itself)
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          warmUp.moved();
          return false;
        },
        child: widget.child,
      ),
    );
  }
}
