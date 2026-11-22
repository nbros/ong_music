/// Side effects of the UI: opening links, sharing, copying, short messages.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/model.dart';
import '../data/song_links.dart';
import '../logger.dart';
import '../web/web_platform.dart';
import 'video_preview.dart';

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

/// Whether "Share" is offered: not where there is no share sheet (most
/// browsers on a computer), "Copy" beside it doing what is left. Overridden
/// in tests.
final canShareProvider = Provider<bool>((ref) => canShareText());

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

/// Opens the video of [highlight] (it must have a YouTube id) on YouTube,
/// stopping first the video playing inside the app, if any: never two sounds.
Future<void> openVideo(BuildContext context, WidgetRef ref, Highlight highlight) {
  ref.read(inPlaceVideosProvider).stop();
  return openLink(context, ref, highlight.url);
}

/// Opens [link], a moment of the full recording of a stream (a VOD), on YouTube as [openVideo] does: the video
/// playing inside the app stops first. Never in the in-place player.
Future<void> openVod(BuildContext context, WidgetRef ref, Uri link) {
  ref.read(inPlaceVideosProvider).stop();
  return openLink(context, ref, link.toString());
}

/// Opens [link], the original of a song (a YouTube video), outside the app as [openVideo] does (the YouTube app, or a
/// new tab on the web): the video playing inside the app stops first, never two sounds.
Future<void> openOriginal(BuildContext context, WidgetRef ref, SongLink link) {
  ref.read(inPlaceVideosProvider).stop();
  return openLink(context, ref, link.url);
}

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
    final what = highlight.youtubeId == null ? 'title' : 'link';
    showMessage(context, copied ? 'Sharing isn’t available here: $what copied' : 'Sharing isn’t available here');
  }
}

/// Copies what "Share" shares for [highlight] ([highlightShareText]); false
/// when the clipboard refused (a browser may). The caller shows the
/// confirmation on the button itself: Android 13+ already shows its own
/// clipboard preview, so a message would be a second notification.
Future<bool> copyHighlight(Highlight highlight) => copyText(highlightShareText(highlight));

// ------------------------------------------------------------------ wording of the copies and of the menus of rows
// Each label in one place: the menu of a row, the buttons of a fiche and screen readers take them from here.

/// What a copy button shows and screen readers hear once its text is copied, and the message of a copy from a menu
/// where the system shows nothing of its own.
const copiedText = 'Copied';

/// The message of a copy the clipboard refused.
const copyFailedText = 'Couldn’t copy';

/// Copying the title of a song, artist included ([songCopyText]): an item of the menu of its row, the tooltip of the
/// copy button of its fiche.
const copyTitleText = 'Copy title';

/// Copying the short link of a video ([shortVideoUrl]): an item of the menu of a row.
const copyVideoLinkText = 'Copy video link';

/// Opening the original of a song ([openOriginal], `SongLinks`): the line of the fiche of the song and of a highlight,
/// an item of the menu of a row (approved by the user).
const listenToTheOriginalText = 'Listen to the original';

/// Copying the link of the original of a song (`SongLink.url`): an item of the menu of a row, the tooltip of the copy
/// button of the line of a fiche (approved by the user).
const copyOriginalLinkText = 'Copy original link';

/// Sharing a highlight ([shareHighlight]): the button of its fiche, an item of the menu of a row.
const shareText = 'Share';

/// Opening a video on YouTube: the button of the fiche of a highlight, an item of the menu of a play.
const watchOnYouTubeText = 'Watch on YouTube';

/// Opening a play at its moment in the full recording of its stream (`VodLinks.linkOf`): an item of the menu of a
/// play, the tooltip of the button of its row (approved by the user).
const watchInTheVodText = 'Watch in the VOD';

/// Opening the full recording of a stream from its start: the button of its fiche (approved by the user).
const watchTheVodText = 'Watch the VOD';

/// The full name of the button of part [part] of the recording of a stream in several videos: what screen readers
/// say and its tooltip shows ([vodPartText] is written on it).
String watchTheVodPartText(int part) => 'Watch the VOD, part $part';

/// What the button of part [part] of the recording of a stream in several videos shows: short, so that its buttons
/// stand side by side on one line; the icon says a player opens (approved by the user).
String vodPartText(int part) => 'VOD $part';

/// The star of a highlight, as a button of its fiche and as an item of the menu of its row.
const addToFavouritesText = 'Add to favourites';
const removeFromFavouritesText = 'Remove from favourites';

/// What the long press of a row does, for screen readers.
const moreActionsHint = 'Shows more actions';

/// What copying the title of a song gives: its title as the sheets write it, `"Artist - Track"` (the track alone
/// without artist), the form "Copy title and link" gives too. The one place of that form.
String songCopyText(String title) => title;

/// The API level of Android, or null elsewhere (the web, Windows) or when it cannot be read: read once, from the
/// activity of the app (`MainActivity.kt`). Overridden in tests.
final androidSdkProvider = FutureProvider<int?>((ref) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    return await const MethodChannel('nbros.ong_music/system').invokeMethod<int>('sdkInt');
  } catch (e) {
    logger.w('Cannot read the version of Android', error: e);
    return null;
  }
});

/// Whether the system shows what is copied by itself: Android 13 and higher (API 33) preview the clipboard.
bool systemPreviewsCopies(int? androidSdk) => androidSdk != null && androidSdk >= 33;

/// Copies [text] from an item of a menu, then confirms it as the platform needs it: the message [copiedText] where the
/// system shows nothing of its own, only an announcement for screen readers where it does (Android 13 and higher: a
/// message would be a second notification); [copyFailedText] when the clipboard refused. [context] is the one of what
/// the menu was opened on: the menu itself is gone by then.
Future<void> copyAndConfirm(BuildContext context, String text) async {
  final view = View.of(context);
  final direction = Directionality.of(context);
  final copied = await copyText(text);
  if (!context.mounted) return;
  if (!copied) return showMessage(context, copyFailedText);
  final sdk = ProviderScope.containerOf(context, listen: false).read(androidSdkProvider).value;
  if (systemPreviewsCopies(sdk)) {
    SemanticsService.sendAnnouncement(view, copiedText, direction);
  } else {
    // the message is a live region: screen readers say it
    showMessage(context, copiedText);
  }
}

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
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final rise = MediaQuery.disableAnimationsOf(context) ? 0.0 : 8.0;
    return Positioned(
      left: 16,
      right: 16,
      // above the navigation bar, or above the keyboard that covers it
      bottom: keyboard > 0 ? keyboard + 16 : padding.bottom + 96,
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
