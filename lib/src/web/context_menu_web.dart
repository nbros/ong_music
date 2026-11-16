/// [ContextMenus] of the browser: listeners on the window, before the
/// engine's own, that keep the browser's menu closed for the right clicks the
/// app claims. Web build only (see `web_platform.dart`).
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'context_menu.dart';

/// [ContextMenus] of the page. One for the app's lifetime (its listeners on the window are never removed).
final class BrowserContextMenus implements ContextMenus {
  BrowserContextMenus() {
    // capture: before the engine's own listener, so before the app hears the pointer down and claims it
    web.window
      ..addEventListener('pointerdown', _onPointerDown.toJS, true.toJS)
      ..addEventListener('contextmenu', _onContextMenu.toJS, true.toJS);
  }

  /// Whether the last pointer went down on a link of the page: the `<a>` laid over a control (`OutsideLink`), a link
  /// of the semantics tree, or any other.
  bool _onLink = false;

  /// Whether the browser's menu stays closed for the click of the last pointer down.
  bool _claimed = false;

  /// Whether the browser's menu event of the click of the last pointer down has come already.
  bool _menuEventPassed = false;

  @override
  bool appMenuOpen = false;

  void _onPointerDown(web.PointerEvent event) {
    final target = event.target;
    _onLink = target != null && target.isA<web.Element>() && (target as web.Element).closest('a[href]') != null;
    // known now: on Windows, the app's menu has closed by the browser's event of the click that closes it
    _claimed = appMenuOpen;
    _menuEventPassed = false;
  }

  void _onContextMenu(web.MouseEvent event) {
    if (_claimed || appMenuOpen) event.preventDefault();
    _claimed = false;
    _menuEventPassed = true;
  }

  @override
  bool claimClick() {
    // too late once the browser's menu event has come (the engine holds the pointer events of a tappable node of the
    // semantics tree back for a moment): the browser has opened its menu, the app must not open its own too
    if (_onLink || _menuEventPassed) return false;
    return _claimed = true;
  }
}
