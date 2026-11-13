// Browser only: flutter test --platform chrome test/browser_history_web_test.dart
//
// Where the browser's history is, as the web app reads it from the entries Flutter's engine tags
// (`{serialCount, state}`): the steps of what opens over the page (§7a).
@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/web/browser_history.dart';
import 'package:ong_music/src/web/web_platform.dart';
import 'package:web/web.dart' as web;

/// Sets the state of the history's current entry until the end of the test.
void entry(Object? state) {
  final before = web.window.history.state;
  addTearDown(() => web.window.history.replaceState(before, ''));
  web.window.history.replaceState(state?.jsify(), '');
}

void main() {
  final history = browserHistory()!;

  test('an entry of the engine: its place, and what it stands for over the page', () {
    entry({
      'serialCount': 3.0,
      'state': {'over': 2},
    });
    expect(history.current, (position: 3, over: 2));
    entry({'serialCount': 1.0, 'state': null});
    expect(history.current, (position: 1, over: 0));
  });

  test('an entry the engine has not tagged yet: the first step, nothing over the page', () {
    entry(null);
    expect(history.current, (position: 0, over: 0));
    entry('something else');
    expect(history.current, (position: 0, over: 0));
  });

  test('the state of a step, as it comes back from the browser', () {
    expect(overOfState({'over': 1}), 1);
    expect(overOfState({'over': 2.0}), 2);
    expect(overOfState(null), 0);
    expect(overOfState({'other': 1}), 0);
  });
}
