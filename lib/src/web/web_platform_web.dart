import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import '../logger.dart';
import 'browser_history.dart';
import 'browser_history_web.dart';
import 'embedded_video.dart';
import 'fullscreen.dart';
import 'install_hint.dart';
import 'link_anchor.dart';
import 'link_anchor_web.dart';
import 'youtube_web.dart';

/// The browser, or null outside a browser (native apps).
BrowserEnvironment? currentBrowser() {
  final navigator = web.window.navigator;
  // navigator.standalone: iOS only, true when launched from the home screen
  final iosStandalone = (navigator as JSObject).getProperty<JSAny?>('standalone'.toJS);
  final standalone =
      (iosStandalone.isA<JSBoolean>() && (iosStandalone as JSBoolean).toDart) ||
      web.window.matchMedia('(display-mode: standalone)').matches ||
      web.window.matchMedia('(display-mode: fullscreen)').matches;
  return BrowserEnvironment(
    userAgent: navigator.userAgent,
    maxTouchPoints: navigator.maxTouchPoints,
    standalone: standalone,
  );
}

/// The full screen mode of the whole page (the document element, so that
/// the sheets and the navigation bar are in it too), or null where the browser
/// offers none (see [offersFullscreen]).
///
/// The standard Fullscreen API, or its `webkit` names in Safari before 16.4
/// (macOS, and iPadOS from 12), whose request returns no promise.
PageFullscreen? pageFullscreen() {
  final root = web.document.documentElement as JSObject?;
  if (root == null) return null;
  bool function(String name) => root.getProperty<JSAny?>(name.toJS).isA<JSFunction>();
  final names = function('requestFullscreen')
      ? _FullscreenNames.standard
      : function('webkitRequestFullscreen')
      ? _FullscreenNames.webkit
      : null;
  if (names == null) return null;
  final enabled = (web.document as JSObject).getProperty<JSAny?>(names.enabled.toJS);
  final isEnabled = enabled.isA<JSBoolean>() && (enabled as JSBoolean).toDart;
  if (!offersFullscreen(currentBrowser(), enabled: isEnabled)) return null;
  return _BrowserFullscreen(root, names);
}

/// Where videos play inside the app: YouTube's embedded player.
VideoEmbedder? videoEmbedder() => YouTubeEmbedder();

/// The history of the tab.
BrowserHistory? browserHistory() => PageHistory();

/// The links of the page laid over the controls that open outside addresses.
LinkAnchors? linkAnchors() => BrowserLinkAnchors();

/// The names of one version of the Fullscreen API.
enum _FullscreenNames {
  standard('fullscreenEnabled', 'fullscreenElement', 'requestFullscreen', 'exitFullscreen', ''),
  webkit(
    'webkitFullscreenEnabled',
    'webkitFullscreenElement',
    'webkitRequestFullscreen',
    'webkitExitFullscreen',
    'webkit',
  );

  const _FullscreenNames(this.enabled, this.element, this.request, this.exit, String eventPrefix)
    : change = '${eventPrefix}fullscreenchange',
      error = '${eventPrefix}fullscreenerror';

  final String enabled, element, request, exit, change, error;
}

/// [PageFullscreen] of the browser, with [_names]. One for the app's lifetime
/// (its event listeners are never removed).
final class _BrowserFullscreen implements PageFullscreen {
  _BrowserFullscreen(this._root, this._names) {
    web.document
      ..addEventListener(_names.change, ((web.Event _) => _changed(true)).toJS)
      ..addEventListener(_names.error, ((web.Event _) => _changed(false)).toJS);
  }

  final JSObject _root;
  final _FullscreenNames _names;
  late final _state = ValueNotifier<bool>(_current());

  /// The outcome of a request without promise (Safari before 16.4): the next
  /// change (accepted) or error (refused) event.
  Completer<bool>? _outcome;

  bool _current() => (web.document as JSObject).getProperty<JSAny?>(_names.element.toJS) != null;

  void _changed(bool accepted) {
    _state.value = _current();
    final outcome = _outcome;
    _outcome = null;
    if (outcome != null && !outcome.isCompleted) outcome.complete(accepted);
  }

  @override
  ValueListenable<bool> get isFullscreen => _state;

  @override
  Future<bool> enter() async {
    if (_current()) return true;
    final outcome = _outcome = Completer<bool>();
    try {
      // right away: the browser grants full screen only within the user gesture
      final result = _root.callMethod<JSAny?>(_names.request.toJS);
      if (result.isA<JSPromise>()) {
        await (result as JSPromise<JSAny?>).toDart;
        return true;
      }
      return await outcome.future.timeout(const Duration(seconds: 2), onTimeout: _current);
    } catch (e) {
      logger.w('The browser refused full screen', error: e);
      return false;
    } finally {
      if (identical(_outcome, outcome)) _outcome = null;
      _state.value = _current();
    }
  }

  @override
  Future<void> exit() async {
    if (!_current()) return;
    try {
      final result = (web.document as JSObject).callMethod<JSAny?>(_names.exit.toJS);
      if (result.isA<JSPromise>()) await (result as JSPromise<JSAny?>).toDart;
    } catch (e) {
      logger.w('Cannot leave full screen', error: e);
    } finally {
      _state.value = _current();
    }
  }
}

/// Registers Roboto Medium (a web-only asset) in the `Roboto` family, next to
/// the Roboto Regular that `flutter build web --no-web-resources-cdn`
/// bundles: without it, every medium (500) text renders as regular.
///
/// The app starts after it, to draw its first frame with the right font, but
/// does not wait for more than a few seconds on a network that stalls.
///
/// Also adds the licence of Roboto, which only the web app distributes, to
/// the licences page.
Future<void> loadWebFonts() async {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Roboto'], await rootBundle.loadString('assets/fonts/Roboto-LICENSE.txt'));
  });
  try {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Medium.ttf'))).load().timeout(const Duration(seconds: 5));
  } catch (e) {
    logger.w('Cannot load Roboto Medium', error: e);
  }
}

@JS('Date')
extension type _JsDate._(JSObject _) implements JSObject {
  external factory _JsDate(int year, int monthIndex, int day, int hours);
  external String toLocaleTimeString();
}

/// Whether the browser shows times on a 24-hour clock, from how it writes
/// 1 pm in its own locale ("13:00:00" or "1:00:00 PM"). Flutter has no such
/// setting on web and would always use AM/PM. Null when it cannot tell.
bool? browserUses24HourClock() {
  try {
    return _JsDate(2020, 0, 1, 13).toLocaleTimeString().contains('13');
  } catch (e) {
    logger.w('Cannot read the clock format of the browser', error: e);
    return null;
  }
}

/// Whether the page is hidden right now (a tab opened behind another one).
bool pageIsHidden() => web.document.hidden;

String _hex(Color color) => '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Colours the browser bars (theme-color) and the page behind the app with
/// the app theme, which may differ from the system one (theme setting).
///
/// Every theme-color tag gets the colour: the two of index.html (one per
/// system theme) and the engine's own (`#flutterweb-theme`, written by the
/// `Title` of `MaterialApp`, transparent here), which would win otherwise.
void setBrowserTheme({required Color background, required bool dark}) {
  final document = web.document;
  final color = _hex(background);
  final metas = document.querySelectorAll('meta[name="theme-color"]');
  for (var i = 0; i < metas.length; i++) {
    final meta = metas.item(i) as web.HTMLMetaElement?;
    meta?.removeAttribute('media');
    meta?.content = color;
  }
  (document.querySelector('meta[name="color-scheme"]') as web.HTMLMetaElement?)?.content = dark ? 'dark' : 'light';
  final root = document.documentElement as web.HTMLElement?;
  root?.setAttribute('data-theme', dark ? 'dark' : 'light');
  root?.style.backgroundColor = color;
}
