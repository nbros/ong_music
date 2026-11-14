/// What the loading of the catalogue needs to share the page's only thread on the web: a pause that lets the
/// browser draw a frame, and the browser's own UTF-8 decoder.
library;

import 'dart:typed_data';

import 'slices.dart';

import 'page_thread_stub.dart' if (dart.library.js_interop) 'page_thread_web.dart' as platform;

/// Lets the thread run its other tasks before going on: on the web, a task of its own (a message to the page itself),
/// which lets the browser draw a frame and handle input first. Not a microtask, which would run before any of it,
/// nor `setTimeout(0)`, which the browser delays by 4 ms once nested: a load of 40 slices would take a third longer.
/// Elsewhere, a timer of zero.
Future<void> yieldToBrowser() => platform.yieldToBrowser();

/// Waits until the thread is idle, and tells for how long ([runWhenIdle]): on the web, an idle period of the page
/// (`requestIdleCallback`: between two frames, the time left before the next one, at most 5 ms: an input
/// that comes meanwhile waits for the slice), or after a second if none comes. Where the browser has no idle callbacks (Safari), after a task of its own
/// as [yieldToBrowser] does, for half a frame of a 120 Hz display. Elsewhere, a timer of zero, then [sliceBudget].
Future<IdleDeadline> waitForIdle() => platform.waitForIdle();

/// The UTF-8 text of [bytes], malformed sequences replaced by U+FFFD: the text of `utf8.decode` with
/// `allowMalformed: true`. On the web it is the browser's decoder (`TextDecoder`), which follows the same standard
/// (WHATWG). Compiled with dart2js, `utf8.decode` uses it too, unless the text holds a U+FFFD (a malformed byte, or the
/// character typed in a cell): it then decodes again with Dart's own decoder, in one task of the page. Measured on the
/// Songs sheet (4 MB) on a fast laptop: 2.6 ms through the browser decoder, 18–23 ms with a single U+FFFD (120 ms with
/// the CPU slowed six times); the browser decoder alone stays at 2.4–2.6 ms with it.
String decodeUtf8(Uint8List bytes) => platform.decodeUtf8(bytes);
