/// "Add to Home Screen" advice for iPhone and iPad users of the web app, and
/// the Android app for Android users: a banner until dismissed, and a section
/// of the About tab.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state/settings_state.dart';
import '../web/install_hint.dart';
import '../web/web_platform.dart';
import 'actions.dart';
import 'instant_feedback.dart';
import 'outside_link.dart';
import 'theme.dart';

/// The Google Play page of the Android app.
const playStoreUrl = 'https://play.google.com/store/apps/details?id=nbros.ong_music';

/// The advice for this browser; [InstallHint.none] in the native apps.
/// Overridden in tests.
final installHintProvider = Provider<InstallHint>((ref) => installHintFor(currentBrowser()));

/// Whether the banner was dismissed (for good; the About tab keeps the advice).
final installBannerDismissedProvider = NotifierProvider<InstallBannerDismissedNotifier, bool>(
  InstallBannerDismissedNotifier.new,
);

/// Persists the dismissal under [key].
class InstallBannerDismissedNotifier extends Notifier<bool> {
  /// Preference key.
  static const key = 'installHintDismissed';

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(key) ?? false;

  /// Hides the banner for good.
  Future<void> dismiss() async {
    state = true;
    await ref.read(sharedPreferencesProvider).setBool(key, true);
  }
}

/// The advice to Android users, in the banner and in the About tab alike.
const playStoreAdvice = 'Install Ong Music from the Play Store for better performance.';

/// Title of the advice.
String installHintTitle(InstallHint hint) => switch (hint.kind) {
  InstallHintKind.openInSafari => 'Open in Safari to install Ong Music',
  InstallHintKind.playStore => 'Get the Android app',
  _ => 'Install Ong Music on your ${hint.device}',
};

/// In the advice texts, stand for the symbols of three buttons of Safari (see
/// [symbolSpans]): its menu button, its More button, and its Share button.
const menuSymbol = '{menu}', moreSymbol = '{more}', shareSymbol = '{share}';

/// The advice in one or two lines, for the banner.
String installHintShortText(InstallHint hint) => switch (hint.kind) {
  InstallHintKind.openInSafari => 'This app’s browser can’t add it to your Home Screen: open the page in Safari.',
  InstallHintKind.playStore => playStoreAdvice,
  _ => switch (hint.share) {
    SafariShare.inBar => 'In Safari, tap the Share button $shareSymbol, then “Add to Home Screen”.',
    SafariShare.behindMore =>
      'In Safari, tap the More button $moreSymbol next to the address, then Share and “Add to Home Screen”.',
    SafariShare.behindMenu =>
      'In Safari, tap the menu button $menuSymbol next to the address, then Share, View More and '
          '“Add to Home Screen”.',
  },
};

/// The full advice, for the About tab.
String installHintText(InstallHint hint) => switch (hint.kind) {
  InstallHintKind.openInSafari =>
    'This page is open inside another app, which can’t add it to your Home Screen. '
        'Open it in Safari (look for “Open in Safari” or “Open in browser” in this app’s menu, or copy the link), '
        'then follow the steps shown there.',
  InstallHintKind.playStore => playStoreAdvice,
  _ =>
    '${installHintShortText(hint)} In another browser, look for “Add to Home Screen” '
        'in its Share menu. Ong Music then opens full screen from its icon, like an app. '
        'Not in the menu? Open this page in Safari first.',
};

final _symbol = RegExp(r'\{(menu|more|share)\}');

/// [text] with a drawing in place of [menuSymbol], [moreSymbol] and
/// [shareSymbol]: three lines, the last one shorter; three dots; the box with
/// an arrow. [size] is their height at text scale 1: like every widget in a
/// text, they grow with the text.
///
/// Drawn after the look of Safari's buttons, with icons this app has, not
/// with Apple's own artwork. They come after the name of the button, never
/// instead of it: Safari may redraw its buttons, the words stay right.
List<InlineSpan> symbolSpans(String text, {required Color color, required double size}) {
  final spans = <InlineSpan>[];
  var start = 0;
  for (final match in _symbol.allMatches(text)) {
    spans.add(TextSpan(text: text.substring(start, match.start)));
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Icon(
          switch (match[1]) {
            'menu' => Icons.notes,
            'more' => Icons.more_horiz,
            _ => Icons.ios_share,
          },
          size: size,
          color: color,
        ),
      ),
    );
    start = match.end;
  }
  spans.add(TextSpan(text: text.substring(start)));
  return spans;
}

/// The address of the web app, for "Copy link".
String appLink() {
  final base = Uri.base;
  return Uri(scheme: base.scheme, host: base.host, port: base.hasPort ? base.port : null, path: base.path).toString();
}

Future<void> _copyLink(BuildContext context) async {
  final copied = await copyText(appLink());
  if (!context.mounted) return;
  showMessage(
    context,
    copied
        ? 'Link copied: paste it in Safari'
        : 'Couldn’t copy the link: use this app’s menu to open the page in Safari',
  );
}

/// The banner at the top of the app, until dismissed.
///
/// Not on a window lower than [minHeight] (a phone held sideways): with the
/// search field, the chips and the navigation bar, the banner would leave the
/// list no room. The About tab keeps the advice.
class InstallBanner extends ConsumerWidget {
  const InstallBanner({super.key});

  /// The banner shows from this window height.
  static const double minHeight = 480;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hint = ref.watch(installHintProvider);
    if (!hint.isVisible || ref.watch(installBannerDismissedProvider)) return const SizedBox.shrink();
    if (MediaQuery.sizeOf(context).height < minHeight) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        // never more than half the screen, which large text would exceed (it would leave no room for the page
        // below): it scrolls instead
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height / 2),
          child: SingleChildScrollView(
            primary: false,
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 12),
                  child: Icon(switch (hint.kind) {
                    InstallHintKind.openInSafari => Icons.open_in_browser,
                    InstallHintKind.playStore => Icons.install_mobile,
                    _ => Icons.ios_share,
                  }, color: scheme.onSecondaryContainer),
                ),
                Expanded(
                  child: _HintBody(hint: hint, color: scheme.onSecondaryContainer, short: true),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  onPressed: () => ref.read(installBannerDismissedProvider.notifier).dismiss(),
                  icon: Icon(Icons.close, color: scheme.onSecondaryContainer),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The advice in the About tab: always there on iPhone, iPad and Android, in
/// the browser.
class InstallSection extends ConsumerWidget {
  const InstallSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hint = ref.watch(installHintProvider);
    if (!hint.isVisible) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(16)),
        child: _HintBody(hint: hint, color: scheme.onSurface),
      ),
    );
  }
}

class _HintBody extends ConsumerWidget {
  const _HintBody({required this.hint, required this.color, this.short = false});

  final InstallHint hint;
  final Color color;

  /// The banner: [installHintShortText] instead of [installHintText].
  final bool short;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on3 = OngColors.of(context).on3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          installHintTitle(hint),
          style: TextStyle(fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w500, color: color),
        ),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            children: symbolSpans(short ? installHintShortText(hint) : installHintText(hint), color: color, size: 16),
          ),
          style: TextStyle(fontSize: 13, height: 18 / 13, color: color.withValues(alpha: 0.85)),
        ),
        if (hint.kind == InstallHintKind.openInSafari)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              style: platformButtonStyle(
                context,
                TextButton.styleFrom(foregroundColor: color, padding: const EdgeInsets.symmetric(horizontal: 8)),
              ),
              onPressed: () => _copyLink(context),
              icon: Icon(Icons.link, size: 18, color: on3),
              label: const Text('Copy link'),
            ),
          )
        else if (hint.kind == InstallHintKind.playStore)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutsideLink(
              url: playStoreUrl,
              label: 'Open the Play Store',
              onOpen: () => openLink(context, ref, playStoreUrl),
              builder: (context, open) => TextButton.icon(
                style: platformButtonStyle(
                  context,
                  TextButton.styleFrom(foregroundColor: color, padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
                onPressed: open,
                icon: Icon(Icons.open_in_new, size: 18, color: on3),
                label: const Text('Open the Play Store'),
              ),
            ),
          )
        else
          const SizedBox(height: 8),
      ],
    );
  }
}
