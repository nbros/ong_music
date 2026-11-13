/// [LinkAnchors] of the browser: a transparent `<a>` element over the
/// control, in a platform view. Web build only (see `web_platform.dart`).
///
/// One element at a time: the app lays it over a control only while the
/// mouse rests on it (see `OutsideLink`), so that the lists, with a video
/// button on many of their thousands of rows, never hold one per row (each
/// platform view costs the page a layer of its own while it scrolls).
library;

import 'dart:js_interop';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'link_anchor.dart';

/// A click the browser handles itself: with Ctrl, ⌘, Shift or Alt (another
/// tab or window, a download). A plain click is the app's.
bool _isBrowserClick(web.MouseEvent event) => event.ctrlKey || event.metaKey || event.shiftKey || event.altKey;

/// [LinkAnchors] of the page. One for the app's lifetime (its listener on the
/// window is never removed).
final class BrowserLinkAnchors implements LinkAnchors {
  BrowserLinkAnchors() {
    // capture: before the engine's own listener on the element
    web.window.addEventListener('click', _onSemanticsClick.toJS, true.toJS);
  }

  @override
  Widget anchor(Uri uri) => HtmlElementView.fromTagName(
    // another address, another element
    key: ValueKey(uri),
    tagName: 'a',
    // the app's control under it keeps its pointer events: the element is for the browser only
    hitTestBehavior: PlatformViewHitTestBehavior.transparent,
    onElementCreated: (element) => prepare(element as web.HTMLAnchorElement, uri),
  );

  /// Makes [a] the link to [uri] laid over a control.
  @visibleForTesting
  static void prepare(web.HTMLAnchorElement a, Uri uri) {
    a
      ..href = uri.toString()
      ..target = '_blank'
      ..rel = 'noopener noreferrer'
      // the app's control has the focus and the semantics, not this copy
      ..tabIndex = -1
      ..setAttribute('aria-hidden', 'true');
    a.style
      ..display = 'block'
      ..width = '100%'
      ..height = '100%'
      ..opacity = '0'
      // the app's cursor, not the browser's own one for links
      ..cursor = 'unset';
    // A plain click opens the address through the app (the pointer events under the element reach it first,
    // and it stops the video playing in place): the browser must not open it a second time.
    a.addEventListener(
      'click',
      ((web.MouseEvent event) {
        if (!_isBrowserClick(event)) event.preventDefault();
      }).toJS,
    );
  }

  /// A click on a link of the semantics tree (a screen reader on, or the
  /// accessibility of the page turned on): these are `<a href>` elements
  /// too, without target, that the browser would follow in the app's own tab.
  /// A plain click stays the app's (the engine turns it into a tap), a click
  /// the browser handles itself is the browser's alone.
  static void _onSemanticsClick(web.MouseEvent event) {
    final target = event.target;
    if (target == null || !target.isA<web.Element>()) return;
    final link = (target as web.Element).closest('flt-semantics-host a[href]');
    if (link == null) return;
    final href = link.getAttribute('href') ?? '';
    if (!href.startsWith('https://') && !href.startsWith('http://')) return;
    if (_isBrowserClick(event)) {
      link.setAttribute('target', '_blank');
      link.setAttribute('rel', 'noopener noreferrer');
      // not to the element's own listener: the app would open it too
      event.stopPropagation();
    } else {
      event.preventDefault();
    }
  }
}
