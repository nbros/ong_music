import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../logger.dart';
import 'font_network.dart';

/// [FontNetwork] of the browser: `navigator.onLine` and its events, and the resource timing of the page (the entries
/// before it too) for the fonts of the engine. One for the app's lifetime.
final class BrowserFontNetwork implements FontNetwork {
  BrowserFontNetwork() {
    web.window
      ..addEventListener('online', ((web.Event _) => _online.value = true).toJS)
      ..addEventListener('offline', ((web.Event _) => _online.value = false).toJS);
    try {
      web.PerformanceObserver(
        ((web.PerformanceObserverEntryList list, web.PerformanceObserver _) {
          var bytes = _engineFontBytes.value;
          for (final entry in list.getEntries().toDart) {
            if (!isEngineFont(entry.name)) continue;
            final size = (entry as web.PerformanceResourceTiming).encodedBodySize;
            bytes += size > 0 ? size : unknownFontBytes;
          }
          _engineFontBytes.value = bytes;
        }).toJS,
      ).observe(web.PerformanceObserverInit(type: 'resource', buffered: true));
    } catch (e) {
      logger.w('Cannot observe the fonts of the engine', error: e);
    }
  }

  final ValueNotifier<bool> _online = ValueNotifier(web.window.navigator.onLine);
  final ValueNotifier<int> _engineFontBytes = ValueNotifier(0);

  @override
  ValueListenable<bool> get online => _online;

  @override
  ValueListenable<int> get engineFontBytes => _engineFontBytes;

  /// CanvasKit runs the JavaScript build; the WebAssembly build runs skwasm: what the app's loader does
  /// (`web/flutter_bootstrap.js`), not a rule of Flutter's, where a WebAssembly build may be given CanvasKit.
  @override
  bool get registrationRecreatesFonts => !kIsWasm;
}
