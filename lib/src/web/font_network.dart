/// What the web app knows of the network, for the fonts it downloads. The browser side is `fontNetwork()` (web
/// platform); the native apps have none.
library;

import 'package:flutter/foundation.dart';

/// The network as the fonts see it.
abstract interface class FontNetwork {
  /// Whether the browser is online (`navigator.onLine`, followed by its `online` and `offline` events). Online does
  /// not mean that Google Fonts answers.
  ValueListenable<bool> get online;

  /// How many bytes of fonts of its own the web engine has fetched from Google Fonts (`fonts.gstatic.com/s/…`) for
  /// characters no registered font draws (a font whose size the browser does not tell counts as [unknownFontBytes]).
  /// Registering fonts makes the engine create those again too.
  ValueListenable<int> get engineFontBytes;

  /// Whether registering a font makes the engine create every registered font again, at a cost that grows with their
  /// bytes: the CanvasKit build (measured: some 20 ms more for 131 KB of the engine's fonts, half a second once it has
  /// the 2 MB of Noto Sans KR); not skwasm (40–60 ms whatever the engine has).
  bool get registrationRecreatesFonts;
}

/// Whether [url] is a font the web engine fetches for its own fallback: a whole font, or one of its usual slices
/// (`fonts.gstatic.com/s/…`); not a font cut down for the app (`fonts.gstatic.com/l/…`), nor the engine's default
/// Roboto, which it fetches from there at every start when the app is built without `--no-web-resources-cdn`
/// (`flutter run`, a plain `flutter build web`): it is no sign of a character the kits were late for.
bool isEngineFont(String url) =>
    url.startsWith('https://fonts.gstatic.com/s/') && !url.startsWith('https://fonts.gstatic.com/s/roboto/');

/// What a font of the engine whose size the browser does not tell counts for (see [FontNetwork.engineFontBytes]).
const int unknownFontBytes = 1 << 20;
