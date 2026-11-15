// Browser only: flutter test --platform chrome test/page_visibility_web_test.dart
//
// The visibility of the page, which the app follows by itself: the lifecycle of the engine does not tell when a tab
// opened behind another one is first shown.
@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/web/web_platform.dart';
import 'package:web/web.dart' as web;

@JS('Object.defineProperty')
external void _defineProperty(JSObject object, String name, JSAny descriptor);

@JS('Reflect.deleteProperty')
external bool _deleteProperty(JSObject object, String name);

/// The page hidden or shown, as the browser does it: `document.hidden`, then a `visibilitychange` event.
void _setHidden(bool hidden) {
  _defineProperty(web.document, 'hidden', {'value': hidden, 'configurable': true}.jsify()!);
  web.document.dispatchEvent(web.Event('visibilitychange'));
}

void main() {
  tearDown(() {
    _deleteProperty(web.document, 'hidden');
    web.document.dispatchEvent(web.Event('visibilitychange'));
  });

  test('follows the visibility of the page, one for the app', () {
    final visibility = pageVisibility()!;
    expect(identical(visibility, pageVisibility()), isTrue);
    expect(visibility.value, !web.document.hidden);
    var changes = 0;
    void listener() => changes++;
    visibility.addListener(listener);
    _setHidden(true);
    expect((visibility.value, changes), (false, 1));
    _setHidden(false);
    expect((visibility.value, changes), (true, 2));
    visibility.removeListener(listener);
  });
}
