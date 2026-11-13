import 'dart:ui' show Color;

import 'browser_history.dart';
import 'embedded_video.dart';
import 'font_network.dart';
import 'fullscreen.dart';
import 'install_hint.dart';
import 'link_anchor.dart';

/// The browser, or null outside a browser (native apps).
BrowserEnvironment? currentBrowser() => null;

/// The full screen mode of the whole page, or null where the browser offers
/// none (see `offersFullscreen`); always null outside a browser.
PageFullscreen? pageFullscreen() => null;

/// Where videos play inside the app; null outside a browser, where they open
/// on YouTube.
VideoEmbedder? videoEmbedder() => null;

/// The history of the browser's tab; null outside a browser.
BrowserHistory? browserHistory() => null;

/// The links of the page over the controls that open outside addresses;
/// null outside a browser, where the controls only open them.
LinkAnchors? linkAnchors() => null;

/// Whether the browser is online, for the fonts it downloads; null outside a browser, where no font is downloaded.
FontNetwork? fontNetwork() => null;

/// Registers the fonts that the web build needs and does not get by itself.
Future<void> loadWebFonts() async {}

/// Whether the browser shows times on a 24-hour clock; null outside a browser,
/// where the system tells Flutter itself.
bool? browserUses24HourClock() => null;

/// Whether the page is hidden right now (a tab opened behind another one);
/// false outside a browser.
bool pageIsHidden() => false;

/// Colours the browser bars (theme-color) and the page behind the app.
void setBrowserTheme({required Color background, required bool dark}) {}
