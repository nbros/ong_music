// Browser only: flutter test --platform chrome test/link_anchor_web_test.dart
//
// The links of the page laid over the controls that open outside addresses (§7b), and the links of the semantics
// tree: what the browser does with a click, and what is left to the app.
@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/web/link_anchor_web.dart';
import 'package:ong_music/src/web/web_platform.dart';
import 'package:web/web.dart' as web;

/// A click of the mouse's main button, with the keys [ctrl], [meta], [shift], [alt] held.
web.MouseEvent clickEvent({bool ctrl = false, bool meta = false, bool shift = false, bool alt = false}) =>
    web.MouseEvent(
      'click',
      web.MouseEventInit(bubbles: true, cancelable: true, ctrlKey: ctrl, metaKey: meta, shiftKey: shift, altKey: alt),
    );

/// What happened to a click: whether the browser may still follow the link (its default action is not
/// prevented), and whether the listeners on the link itself heard it (the engine's own, for a semantics link).
typedef Outcome = ({bool browserFollows, bool reachedLink});

/// Dispatches [event] at [link] and tells what became of it. The test's own listeners then prevent the default
/// action: nothing is opened.
Outcome dispatch(web.Element link, web.MouseEvent event) {
  var reached = false;
  var preventedAtLink = false;
  var preventedAtWindow = false;
  final onLink = ((web.Event e) {
    reached = true;
    preventedAtLink = e.defaultPrevented;
    e.preventDefault();
  }).toJS;
  // after the app's listener on the window (capture), before the link's own listeners
  final onWindow = ((web.Event e) {
    preventedAtWindow = e.defaultPrevented;
    // the link will not hear it: nothing else will stop the browser
    if (e.cancelBubble) e.preventDefault();
  }).toJS;
  link.addEventListener('click', onLink);
  web.window.addEventListener('click', onWindow, true.toJS);
  link.dispatchEvent(event);
  link.removeEventListener('click', onLink);
  web.window.removeEventListener('click', onWindow, true.toJS);
  return (browserFollows: !(reached ? preventedAtLink : preventedAtWindow), reachedLink: reached);
}

/// An element of the page, removed at the end of the test.
T attach<T extends web.Element>(T element) {
  web.document.body!.append(element);
  addTearDown(() => element.remove());
  return element;
}

void main() {
  test('the browser has links of the page', () {
    expect(linkAnchors(), isNotNull);
  });

  group('the link over a control', () {
    late web.HTMLAnchorElement a;
    setUp(() {
      a = attach(web.document.createElement('a') as web.HTMLAnchorElement);
      BrowserLinkAnchors.prepare(a, Uri.parse('https://www.youtube.com/watch?v=aaaaaaaaaaa'));
    });

    test('to its address, in another tab, unseen, out of the keyboard and of screen readers', () {
      expect(a.href, 'https://www.youtube.com/watch?v=aaaaaaaaaaa');
      expect(a.target, '_blank');
      expect(a.rel.split(' '), containsAll(['noopener', 'noreferrer']));
      expect(a.tabIndex, -1);
      expect(a.getAttribute('aria-hidden'), 'true');
      expect(a.style.opacity, '0');
      expect((a.style.width, a.style.height, a.style.display), ('100%', '100%', 'block'));
    });

    test('a plain click is the app\'s: the browser does not open it a second time', () {
      expect(dispatch(a, clickEvent()).browserFollows, isFalse);
    });

    test('a click with Ctrl, ⌘, Shift or Alt is the browser\'s', () {
      expect(dispatch(a, clickEvent(ctrl: true)).browserFollows, isTrue);
      expect(dispatch(a, clickEvent(meta: true)).browserFollows, isTrue);
      expect(dispatch(a, clickEvent(shift: true)).browserFollows, isTrue);
      expect(dispatch(a, clickEvent(alt: true)).browserFollows, isTrue);
    });
  });

  group('a link of the semantics tree', () {
    late web.Element link;
    setUpAll(BrowserLinkAnchors.new);
    setUp(() {
      final host = attach(web.document.createElement('flt-semantics-host'));
      link = web.document.createElement('a')..setAttribute('href', 'https://www.twitch.tv/jonathanong');
      host.append(link);
    });

    test('a plain click: the app opens it (the engine hears it), the browser does not follow it in the app\'s tab', () {
      expect(dispatch(link, clickEvent()), (browserFollows: false, reachedLink: true));
    });

    test('with Ctrl or ⌘: the browser opens it in another tab, and the app does not hear it', () {
      expect(dispatch(link, clickEvent(ctrl: true)), (browserFollows: true, reachedLink: false));
      expect(dispatch(link, clickEvent(meta: true)), (browserFollows: true, reachedLink: false));
      expect(link.getAttribute('target'), '_blank');
    });

    test('a click on its text, inside it', () {
      final text = web.document.createElement('span');
      link.append(text);
      expect(dispatch(text, clickEvent()).browserFollows, isFalse);
    });

    test('other links of the page are left alone', () {
      final other = attach(web.document.createElement('a')..setAttribute('href', 'https://example.com/'));
      expect(dispatch(other, clickEvent()), (browserFollows: true, reachedLink: true));
      final local = web.document.createElement('a')..setAttribute('href', '#/log');
      link.parentElement!.append(local);
      expect(dispatch(local, clickEvent()), (browserFollows: true, reachedLink: true));
    });
  });
}
