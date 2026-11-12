/// What only the web build does: browser detection, fonts, browser bars.
/// No-ops in the native apps (conditional import), so they never load
/// `dart:js_interop` or `package:web`.
library;

export 'web_platform_stub.dart' if (dart.library.js_interop) 'web_platform_web.dart';
