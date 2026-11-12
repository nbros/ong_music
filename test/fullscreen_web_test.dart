// Browser only: flutter test --platform chrome test/fullscreen_web_test.dart
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/web/web_platform.dart';

final JSObject document = globalContext['document']! as JSObject;
final JSObject root = document['documentElement']! as JSObject;

/// Gives [object] an own property [name] of [value], hiding the browser's
/// one (on a prototype) until the end of the test.
void shadow(JSObject object, String name, JSAny? value) {
  final descriptor = JSObject()
    ..['value'] = value
    ..['configurable'] = true.toJS;
  (globalContext['Object']! as JSObject).callMethod('defineProperty'.toJS, object, name.toJS, descriptor);
  addTearDown(() => object.delete(name.toJS));
}

/// Fires the event [type] at the document, as the browser does.
void fire(String type) {
  final event = (globalContext['Event']! as JSFunction).callAsConstructor<JSObject>(type.toJS);
  document.callMethod('dispatchEvent'.toJS, event);
}

/// Runs [callback] in a task of its own (`setTimeout`).
void later(void Function() callback) => globalContext.callMethod('setTimeout'.toJS, callback.toJS, 0.toJS);

void main() {
  test('offered by a desktop Chrome', () {
    expect(pageFullscreen(), isNotNull);
  });

  test('not offered where the browser disables it (an iframe without allowfullscreen)', () {
    shadow(document, 'fullscreenEnabled', false.toJS);
    expect(pageFullscreen(), isNull);
  });

  test('not offered without a request function for elements (Safari on iPhone)', () {
    shadow(root, 'requestFullscreen', null);
    shadow(root, 'webkitRequestFullscreen', null);
    expect(pageFullscreen(), isNull);
  });

  test('a request out of a user gesture is refused, without throwing', () async {
    final fullscreen = pageFullscreen()!;
    expect(await fullscreen.enter(), isFalse);
    expect(fullscreen.isFullscreen.value, isFalse);
    await fullscreen.exit();
  });

  test('follows the changes of the browser', () {
    final fullscreen = pageFullscreen()!;
    expect(fullscreen.isFullscreen.value, isFalse);
    shadow(document, 'fullscreenElement', root);
    fire('fullscreenchange');
    expect(fullscreen.isFullscreen.value, isTrue);
    document.delete('fullscreenElement'.toJS);
    fire('fullscreenchange');
    expect(fullscreen.isFullscreen.value, isFalse);
  });

  group('Safari before 16.4 (webkit names, no promise)', () {
    setUp(() => shadow(root, 'requestFullscreen', null));

    test('follows the changes of the browser', () {
      final fullscreen = pageFullscreen()!;
      shadow(document, 'webkitFullscreenElement', root);
      fire('webkitfullscreenchange');
      expect(fullscreen.isFullscreen.value, isTrue);
    });

    test('a request: the next change or error event tells the outcome', () async {
      final fullscreen = pageFullscreen()!;
      var calls = 0;
      var accept = false;
      shadow(
        root,
        'webkitRequestFullscreen',
        () {
          calls++;
          // later, as a browser answers
          final answer = accept;
          later(() {
            if (answer) shadow(document, 'webkitFullscreenElement', root);
            fire(answer ? 'webkitfullscreenchange' : 'webkitfullscreenerror');
          });
        }.toJS,
      );
      expect(await fullscreen.enter(), isFalse);
      expect(fullscreen.isFullscreen.value, isFalse);
      accept = true;
      expect(await fullscreen.enter(), isTrue);
      expect(fullscreen.isFullscreen.value, isTrue);
      expect(calls, 2);

      shadow(
        document,
        'webkitExitFullscreen',
        () {
          document.delete('webkitFullscreenElement'.toJS);
          fire('webkitfullscreenchange');
        }.toJS,
      );
      await fullscreen.exit();
      expect(fullscreen.isFullscreen.value, isFalse);
    });
  });
}
