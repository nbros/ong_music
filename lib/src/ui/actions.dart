/// Side effects of the UI: opening links, sharing, copying, short messages.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/model.dart';
import '../logger.dart';

/// Opens a URL outside the app (browser or the site's app; a new tab on web).
typedef UrlOpener = Future<bool> Function(Uri uri);

/// Shares a text through the platform share sheet. Returns false when sharing
/// is unavailable or failed (the caller then copies the text instead).
typedef TextSharer = Future<bool> Function(String text);

/// Overridden in tests.
final urlOpenerProvider = Provider<UrlOpener>(
  (ref) => (uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    } catch (e) {
      logger.w('Cannot open $uri', error: e);
      return false;
    }
  },
);

/// Overridden in tests.
final textSharerProvider = Provider<TextSharer>(
  (ref) => (text) async {
    try {
      // No e-mail fallback: without a share sheet (most desktop browsers) the
      // web implementation then throws, and the caller copies the text instead.
      // Any result is a success: `unavailable` only means "no feedback" (web
      // returns it after a completed share).
      await SharePlus.instance.share(ShareParams(text: text, mailToFallbackEnabled: false));
      return true;
    } catch (e) {
      logger.i('Share unavailable: $e');
      return false;
    }
  },
);

/// Opens [url]; shows a message when it cannot be opened.
Future<void> openLink(BuildContext context, WidgetRef ref, String url) async {
  final uri = Uri.tryParse(url);
  final opened = uri != null && await ref.read(urlOpenerProvider)(uri);
  if (!opened && context.mounted) showMessage(context, 'Couldn’t open the link');
}

/// `https://youtu.be/<id>`.
String shortVideoUrl(String youtubeId) => 'https://youtu.be/$youtubeId';

/// Opens the video of [highlight] (it must have a YouTube id).
Future<void> openVideo(BuildContext context, WidgetRef ref, Highlight highlight) =>
    openLink(context, ref, highlight.url);

/// What "Share" and "Copy" give for [highlight]: `"<title> — https://youtu.be/<id>"`,
/// or the title alone without video.
String highlightShareText(Highlight highlight) {
  final id = highlight.youtubeId;
  return id == null ? highlight.title : '${highlight.title} — ${shortVideoUrl(id)}';
}

/// Shares [highlightShareText], or copies it when sharing is unavailable.
Future<void> shareHighlight(BuildContext context, WidgetRef ref, Highlight highlight) async {
  final text = highlightShareText(highlight);
  final shared = await ref.read(textSharerProvider)(text);
  if (shared) return;
  final copied = await copyText(text);
  if (context.mounted) {
    showMessage(context, copied ? 'Sharing isn’t available here: link copied' : 'Sharing isn’t available here');
  }
}

/// Copies what "Share" shares for [highlight] ([highlightShareText]); false
/// when the clipboard refused (a browser may). The caller shows the
/// confirmation on the button itself: Android 13+ already shows its own
/// clipboard preview, so a message would be a second notification.
Future<bool> copyHighlight(Highlight highlight) => copyText(highlightShareText(highlight));

/// Copies [text]; false when the clipboard refused or is missing.
Future<bool> copyText(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (e) {
    logger.w('Cannot copy to the clipboard', error: e);
    return false;
  }
}

OverlayEntry? _messageEntry;
Timer? _messageTimer;

/// How long a message stays, from the start of its fade in to the end of its
/// fade out.
const _messageDuration = Duration(milliseconds: 2600);

const _messageFade = Duration(milliseconds: 180);

/// Shows a short message at the bottom of the screen, above any bottom sheet
/// (a [SnackBar] would stay under an open sheet).
void showMessage(BuildContext context, String text) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _messageTimer?.cancel();
  _messageEntry?.remove();
  final key = GlobalKey<_MessageState>();
  final entry = OverlayEntry(
    builder: (context) => _Message(key: key, text: text),
  );
  _messageEntry = entry;
  overlay.insert(entry);
  void remove() {
    if (identical(_messageEntry, entry)) {
      entry.remove();
      _messageEntry = null;
    }
  }

  _messageTimer = Timer(_messageDuration - _messageFade, () {
    final state = key.currentState;
    if (state == null) return remove();
    _messageTimer = Timer(_messageFade, remove);
    state.hide();
  });
}

class _Message extends StatefulWidget {
  const _Message({super.key, required this.text});

  final String text;

  @override
  State<_Message> createState() => _MessageState();
}

/// Fades in rising by 8 px, fades out the same way (without the rise when
/// the system asks for less motion).
class _MessageState extends State<_Message> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: _messageFade)..forward();

  void hide() => _controller.reverse();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final padding = MediaQuery.paddingOf(context);
    final rise = MediaQuery.disableAnimationsOf(context) ? 0.0 : 8.0;
    return Positioned(
      left: 16,
      right: 16,
      bottom: padding.bottom + 96,
      child: IgnorePointer(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) => Opacity(
                opacity: _controller.value,
                child: Transform.translate(offset: Offset(0, rise * (1 - _controller.value)), child: child),
              ),
              child: Semantics(
                liveRegion: true,
                child: Material(
                  color: scheme.inverseSurface,
                  elevation: 6,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text(widget.text, style: TextStyle(color: scheme.onInverseSurface, fontSize: 14)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
