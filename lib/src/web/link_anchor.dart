/// The browser's own link over a control of the app that opens an outside
/// address: what the app needs from it. The browser side is `linkAnchors()`
/// (web platform); the native apps have none.
library;

import 'package:flutter/widgets.dart';

/// Where controls can be links of the browser: the web app only.
abstract interface class LinkAnchors {
  /// An invisible link of the page to [uri], as large as what it is laid
  /// over: the browser shows its address, opens it in another tab on a
  /// Ctrl/⌘-click, a middle click or from its context menu, and leaves a
  /// plain click to the app (which opens it as it always did).
  Widget anchor(Uri uri);
}
