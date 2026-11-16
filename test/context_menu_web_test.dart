// Browser only: flutter test --platform chrome test/context_menu_web_test.dart
//
// Which menu a right click opens in the web app: the browser's, unless a row of the app claimed the click at its
// pointer down (refused on a link of the page) or a menu of the app is open. The events are dispatched by hand, in
// the order of macOS (the browser's menu event between the pointer down and the pointer up); the app's pointer down
// is the call of claimClick that follows the pointer down.
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/web/context_menu.dart';
import 'package:ong_music/src/web/web_platform.dart';
import 'package:web/web.dart' as web;

/// The secondary button of the mouse going down on [target].
void pointerDown(web.Element target) => target.dispatchEvent(
  web.PointerEvent(
    'pointerdown',
    web.PointerEventInit(bubbles: true, cancelable: true, pointerType: 'mouse', button: 2, buttons: 2),
  ),
);

/// The browser's menu event of a right click on [target]: whether the browser opens its menu (its default action is
/// not prevented). An event dispatched by a script opens none itself: nothing shows on the test's page.
bool browserMenuOpens(web.Element target) {
  final event = web.MouseEvent('contextmenu', web.MouseEventInit(bubbles: true, cancelable: true, button: 2));
  return target.dispatchEvent(event);
}

/// An element of the page, removed at the end of the test.
T attach<T extends web.Element>(T element) {
  web.document.body!.append(element);
  addTearDown(() => element.remove());
  return element;
}

web.Element link(String href) => web.document.createElement('a')..setAttribute('href', href);

void main() {
  late ContextMenus menus;
  late web.Element plain;

  setUp(() {
    menus = contextMenus()!;
    plain = attach(web.document.createElement('div'));
    // whatever an earlier test left: no claim, no menu of the app
    menus.appMenuOpen = false;
    pointerDown(plain);
  });

  test('the browser decides between its menu and the app\'s, one for the whole app', () {
    expect(contextMenus(), same(contextMenus()));
  });

  test('a right click nobody claims: the browser\'s menu', () {
    pointerDown(plain);
    expect(browserMenuOpens(plain), isTrue);
  });

  test('a right click a row claims: the browser\'s menu stays closed', () {
    pointerDown(plain);
    expect(menus.claimClick(), isTrue);
    expect(browserMenuOpens(plain), isFalse);
  });

  test('on a link of the page: the claim refused, the browser\'s menu', () {
    final a = attach(link('https://www.youtube.com/watch?v=aaaaaaaaaaa'));
    pointerDown(a);
    expect(menus.claimClick(), isFalse);
    expect(browserMenuOpens(a), isTrue);
  });

  test('on the text inside a link, on a link of the semantics tree: refused too', () {
    final text = web.document.createElement('span');
    attach(link('https://youtu.be/aaaaaaaaaaa')).append(text);
    pointerDown(text);
    expect(menus.claimClick(), isFalse);
    expect(browserMenuOpens(text), isTrue);

    final semantics = link('https://www.twitch.tv/jonathanong');
    attach(web.document.createElement('flt-semantics-host')).append(semantics);
    pointerDown(semantics);
    expect(menus.claimClick(), isFalse);
    expect(browserMenuOpens(semantics), isTrue);
  });

  test('an <a> without an address is no link', () {
    final a = attach(web.document.createElement('a'));
    pointerDown(a);
    expect(menus.claimClick(), isTrue);
    expect(browserMenuOpens(a), isFalse);
  });

  test('a claim ends at the next pointer down: it never keeps a later menu of the browser closed', () {
    pointerDown(plain);
    expect(menus.claimClick(), isTrue);
    // (the browser's menu event of the claimed click never came)
    pointerDown(plain);
    expect(browserMenuOpens(plain), isTrue);
  });

  test('a claim keeps the browser\'s menu closed once', () {
    pointerDown(plain);
    expect(menus.claimClick(), isTrue);
    expect(browserMenuOpens(plain), isFalse);
    expect(browserMenuOpens(plain), isTrue, reason: 'a menu event without its pointer down: the keyboard\'s menu key');
  });

  test('a claim after a refusal, off the link: accepted', () {
    final a = attach(link('https://youtu.be/aaaaaaaaaaa'));
    pointerDown(a);
    expect(menus.claimClick(), isFalse);
    expect(browserMenuOpens(a), isTrue);
    pointerDown(plain);
    expect(menus.claimClick(), isTrue);
    expect(browserMenuOpens(plain), isFalse);
  });

  group('while a menu of the app is open', () {
    test('a right click anywhere, a link too, opens no menu of the browser', () {
      menus.appMenuOpen = true;
      pointerDown(plain);
      expect(browserMenuOpens(plain), isFalse);
      final a = attach(link('https://youtu.be/aaaaaaaaaaa'));
      pointerDown(a);
      expect(browserMenuOpens(a), isFalse);
    });

    test('nor the right click that closes it before the browser\'s menu event (the order of Windows)', () {
      menus.appMenuOpen = true;
      pointerDown(plain);
      menus.appMenuOpen = false;
      expect(browserMenuOpens(plain), isFalse);
    });

    test('once it has closed: the browser\'s menu again', () {
      menus.appMenuOpen = true;
      pointerDown(plain);
      expect(browserMenuOpens(plain), isFalse);
      menus.appMenuOpen = false;
      pointerDown(plain);
      expect(browserMenuOpens(plain), isTrue);
    });
  });
}
