/// The browser's own context menu over the rows that have a menu of the app:
/// what the app needs from it. The browser side is `contextMenus()` (web
/// platform); the native apps have none, and no menu of a browser.
library;

/// Which menu a right click opens, the browser's or the app's: the web app only.
///
/// One of the two, never both, never none: the browser's on a link of the page (it offers to open it in another tab
/// and to copy its address), the app's on a row that claims the click, the browser's again everywhere else. Since the
/// browser opens its menu right after the pointer goes down on macOS and Linux (after it goes up on Windows), the
/// decision is taken at the pointer down, before either.
abstract interface class ContextMenus {
  /// Keeps the browser's menu closed for the click whose pointer has just gone down (asked at that pointer down, which
  /// the app hears before the browser's menu event): true when it will, false when that pointer is on a link of the
  /// page, whose menu stays the browser's, or when the browser's menu event of that click has come already (the app
  /// heard the pointer down late: the browser's menu is open). A claim ends with the browser's menu event of that click, or with the next
  /// pointer down, whichever comes first: it never keeps a later menu of the browser closed.
  bool claimClick();

  /// Whether a menu of the app is open. A right click while it is (the click that closes it) opens no menu of the
  /// browser either, even if the app's menu closes before the browser's event (Windows).
  bool get appMenuOpen;
  set appMenuOpen(bool open);
}
