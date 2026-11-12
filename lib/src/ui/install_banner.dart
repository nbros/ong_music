/// "Add to Home Screen" advice for iPhone and iPad users of the web app: a
/// banner until dismissed, and a section of the About tab.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state/settings_state.dart';
import '../web/install_hint.dart';
import '../web/web_platform.dart';
import 'actions.dart';
import 'theme.dart';

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

/// Title of the advice.
String installHintTitle(InstallHint hint) => switch (hint.kind) {
  InstallHintKind.openInSafari => 'Open in Safari to install Ong Music',
  _ => 'Install Ong Music on your ${hint.device}',
};

/// The advice in one or two lines, for the banner.
String installHintShortText(InstallHint hint) => switch (hint.kind) {
  InstallHintKind.openInSafari => 'This app’s browser can’t add it to your Home Screen: open the page in Safari.',
  _ => 'In Safari, tap the menu button next to the address, then Share, View More and “Add to Home Screen”.',
};

/// The full advice, for the About tab.
String installHintText(InstallHint hint) => switch (hint.kind) {
  InstallHintKind.openInSafari =>
    'This page is open inside another app, which can’t add it to your Home Screen. '
        'Open it in Safari (look for “Open in Safari” or “Open in browser” in this app’s menu, or copy the link), '
        'then follow the steps shown there.',
  _ =>
    'In Safari, tap the menu button next to the address (on older iOS versions, the Share button), '
        'then Share, View More and “Add to Home Screen”. In another browser, look for “Add to Home Screen” '
        'in its Share menu. Ong Music then opens full screen from its icon, like an app. '
        'Not in the menu? Open this page in Safari first.',
};

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
class InstallBanner extends ConsumerWidget {
  const InstallBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hint = ref.watch(installHintProvider);
    if (!hint.isVisible || ref.watch(installBannerDismissedProvider)) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 12),
                child: Icon(
                  hint.kind == InstallHintKind.openInSafari ? Icons.open_in_browser : Icons.ios_share,
                  color: scheme.onSecondaryContainer,
                ),
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
    );
  }
}

/// The advice in the About tab: always there on iPhone and iPad, in the
/// browser.
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

class _HintBody extends StatelessWidget {
  const _HintBody({required this.hint, required this.color, this.short = false});

  final InstallHint hint;
  final Color color;

  /// The banner: [installHintShortText] instead of [installHintText].
  final bool short;

  @override
  Widget build(BuildContext context) {
    final on3 = OngColors.of(context).on3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          installHintTitle(hint),
          style: TextStyle(fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w500, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          short ? installHintShortText(hint) : installHintText(hint),
          style: TextStyle(fontSize: 13, height: 18 / 13, color: color.withValues(alpha: 0.85)),
        ),
        if (hint.kind == InstallHintKind.openInSafari)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: color, padding: const EdgeInsets.symmetric(horizontal: 8)),
              onPressed: () => _copyLink(context),
              icon: Icon(Icons.link, size: 18, color: on3),
              label: const Text('Copy link'),
            ),
          )
        else
          const SizedBox(height: 8),
      ],
    );
  }
}
