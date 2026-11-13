/// [BrowserHistory] of the page: `window.history`, whose entries Flutter's
/// engine tags with its own count (`{serialCount, state}`). Web build only
/// (see `web_platform.dart`).
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'browser_history.dart';

/// [BrowserHistory] of the page.
final class PageHistory implements BrowserHistory {
  @override
  ({int position, int over}) get current {
    final state = web.window.history.state;
    if (state == null || !state.isA<JSObject>()) return (position: 0, over: 0);
    final entry = state as JSObject;
    final serial = entry.getProperty<JSAny?>('serialCount'.toJS);
    final position = serial != null && serial.isA<JSNumber>() ? (serial as JSNumber).toDartDouble.toInt() : 0;
    final own = entry.getProperty<JSAny?>('state'.toJS);
    var over = 0;
    if (own != null && own.isA<JSObject>()) {
      final value = (own as JSObject).getProperty<JSAny?>('over'.toJS);
      if (value != null && value.isA<JSNumber>()) over = (value as JSNumber).toDartDouble.toInt();
    }
    return (position: position, over: over);
  }

  @override
  void go(int delta) => web.window.history.go(delta);
}
