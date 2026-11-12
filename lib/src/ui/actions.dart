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

/// Shares `"<title> — https://youtu.be/<id>"`, or copies it when sharing is
/// unavailable.
Future<void> shareHighlight(BuildContext context, WidgetRef ref, Highlight highlight) async {
  final id = highlight.youtubeId;
  final text = id == null ? highlight.title : '${highlight.title} — ${shortVideoUrl(id)}';
  final shared = await ref.read(textSharerProvider)(text);
  if (shared) return;
  final copied = await copyText(text);
  if (context.mounted) {
    showMessage(context, copied ? 'Sharing isn’t available here: link copied' : 'Sharing isn’t available here');
  }
}

/// Copies the title of [highlight]; false when the clipboard refused (a
/// browser may). The caller shows the confirmation on the button itself:
/// Android 13+ already shows its own clipboard preview, so a message would be
/// a second notification.
Future<bool> copyTitle(Highlight highlight) => copyText(highlight.title);

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

/// Shows a short message at the bottom of the screen, above any bottom sheet
/// (a [SnackBar] would stay under an open sheet).
void showMessage(BuildContext context, String text) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _messageTimer?.cancel();
  _messageEntry?.remove();
  final entry = OverlayEntry(builder: (context) => _Message(text: text));
  _messageEntry = entry;
  overlay.insert(entry);
  _messageTimer = Timer(const Duration(milliseconds: 2600), () {
    if (identical(_messageEntry, entry)) {
      entry.remove();
      _messageEntry = null;
    }
  });
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final padding = MediaQuery.paddingOf(context);
    return Positioned(
      left: 16,
      right: 16,
      bottom: padding.bottom + 96,
      child: IgnorePointer(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 180),
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
              ),
              child: Semantics(
                liveRegion: true,
                child: Material(
                  color: scheme.inverseSurface,
                  elevation: 6,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text(text, style: TextStyle(color: scheme.onInverseSurface, fontSize: 14)),
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
