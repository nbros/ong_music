/// The About tab: Jonathan Ong and his links, then the settings and the data.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vector_graphics/vector_graphics.dart';

import '../data/catalogue.dart';
import '../data/schedule.dart';
import '../state/catalogue_state.dart';
import '../state/settings_state.dart';
import '../state/twitch_state.dart';
import 'actions.dart';
import 'format.dart';
import 'install_banner.dart';
import 'instant_feedback.dart';
import 'layout.dart';
import 'list_scaffold.dart';
import 'outside_link.dart';
import 'theme.dart';
import 'view_state.dart';
import 'widgets.dart';

/// The app version, passed by CI with `--dart-define=APP_VERSION=…`.
const String appVersion = String.fromEnvironment('APP_VERSION');

const twitchUrl = 'https://www.twitch.tv/jonathanong';
const privacyPolicyUrl = 'https://ongmusic.nbros.dev/privacy-policy';
const spreadsheetUrl = 'https://docs.google.com/spreadsheets/d/14ARzE_zSMNhp0ZQV34ti2741PbA-5wAjsXRAW8EgJ-4';

/// The link tiles: label, URL, icon.
final List<(String, String, Widget Function(BuildContext))> aboutLinks = [
  (
    'YouTube',
    'https://www.youtube.com/@JonathanOng/videos',
    (_) => const VectorGraphic(loader: AssetBytesLoader('assets/icons/youtube.svg'), width: 28, height: 28),
  ),
  (
    'Albums',
    'https://www.theorangejacketbrigade.com/albums',
    (c) => Icon(Icons.album, size: 28, color: Theme.of(c).colorScheme.onSurface),
  ),
  (
    'TikTok',
    'https://www.tiktok.com/@jongmusic/',
    (_) => const VectorGraphic(loader: AssetBytesLoader('assets/icons/tiktok2.svg'), width: 28, height: 28),
  ),
  (
    'Instagram',
    'https://instagram.com/jonathanong77',
    (_) => const VectorGraphic(loader: AssetBytesLoader('assets/icons/instagram.svg'), width: 28, height: 28),
  ),
  (
    'Twitter',
    'https://twitter.com/jonathanong77',
    (_) => const VectorGraphic(loader: AssetBytesLoader('assets/icons/twitter.svg'), width: 28, height: 28),
  ),
  ('Merch', 'https://jonathanong.threadless.com/', (_) => Image.asset('assets/jacket.png', width: 28, height: 28)),
  (
    'Stickers',
    'https://stukem.com/collections/jonathanong',
    (_) => ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.asset('assets/ongZoom.png', width: 28, height: 28),
    ),
  ),
];

/// The helper text under the Twitch name field.
String twitchNameHelp(String name, Catalogue? catalogue) {
  if (name.trim().isEmpty) return 'Your name will show in orange in every list.';
  final requester = catalogue?.requesterNamed(name);
  if (requester == null || requester.requestCount == 0) return 'No request under that name yet.';
  return 'Found ${plural(requester.requestCount, 'request')} by ${requester.name}, now in orange. '
      'Tap the “You” chip to see only yours.';
}

/// The About tab: one column; in an expanded window, two cards side by side
/// (the artist on the left, the app's settings on the right) and the footer
/// under both.
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  /// The widest the two cards are together, with their outer margins.
  static const double maxCardsWidth = 1040;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expanded = AppLayout.modeOf(context) == WindowMode.expanded;
    final scheme = Theme.of(context).colorScheme;
    // inside a card, what stood on the background stands on the card
    final background = expanded ? scheme.surfaceContainer : scheme.surface;
    final artist = [
      _Hero(ring: background, inCard: expanded),
      // links
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth / 4;
            return Wrap(
              runSpacing: 14,
              children: [
                for (final (label, url, icon) in aboutLinks)
                  SizedBox(
                    width: width,
                    child: OutsideLink(
                      url: url,
                      label: label,
                      onOpen: () => openLink(context, ref, url),
                      builder: (context, open) => _LinkTile(
                        label: label,
                        icon: icon(context),
                        color: expanded ? scheme.surfaceContainerHigh : scheme.surfaceContainer,
                        onTap: open,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      const InstallSection(),
    ];
    final settings = [
      _SectionTitle('Appearance', top: expanded ? 16 : 24),
      const _ThemeSelector(),
      const _SectionTitle('Your Twitch name'),
      const _TwitchNameField(),
      const _SectionTitle('Data'),
      const _DataSection(),
    ];
    final bottom = MediaQuery.paddingOf(context).bottom;
    if (!expanded) {
      return LaneScrollbar(
        child: ListView(
          // the scrollbar follows the primary scroll controller: desktop does not attach it by itself
          primary: true,
          padding: EdgeInsets.only(top: 20, bottom: bottom),
          children: [...artist, ...settings, const _Footer()],
        ),
      );
    }
    Widget card(List<Widget> children) => Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
      decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(28)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
    return LaneScrollbar(
      child: ListView(
        primary: true,
        padding: EdgeInsets.only(bottom: bottom),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxCardsWidth),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 16,
                  children: [
                    Expanded(child: card([const SizedBox(height: 20), ...artist])),
                    Expanded(child: card(settings)),
                  ],
                ),
              ),
            ),
          ),
          const _Footer(top: 16),
        ],
      ),
    );
  }
}

/// The artist's picture, in a ring of [ring] and of the brand colour, his
/// name, introduction, and the Twitch button with its status line.
class _Hero extends StatelessWidget {
  const _Hero({required this.ring, required this.inCard});

  final Color ring;

  /// In a card: the picture keeps its ring clear of the card's top and of the name.
  final bool inCard;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ong = OngColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            margin: EdgeInsets.only(top: inCard ? 5 : 0, bottom: inCard ? 17 : 12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF3D2C3),
              boxShadow: [
                BoxShadow(color: ong.brand, spreadRadius: 5),
                BoxShadow(color: ring, spreadRadius: 3),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/ongZoom.png',
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                excludeFromSemantics: true,
              ),
            ),
          ),
          Text(
            'Jonathan Ong',
            style: TextStyle(fontSize: 24, height: 32 / 24, fontWeight: FontWeight.w500, color: scheme.onSurface),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 16),
            child: Text(
              'Classically trained pianist from Sydney who streams on Twitch, known for his '
              'multi-instrumental loops and virtuosic piano playing.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 20 / 14),
            ),
          ),
          const _TwitchSection(),
        ],
      ),
    );
  }
}

/// What the Twitch status line says: its text, and its label for screen readers.
typedef TwitchStatusText = ({String text, String label, bool live});

/// The status line under "Watch on Twitch" at [now], null when nothing is
/// known. [clock] formats a time of day (local, the device's 12/24-hour
/// preference).
TwitchStatusText? twitchStatusText(
  bool live,
  ScheduleStatus schedule,
  DateTime now,
  String Function(DateTime time) clock,
) {
  final current = schedule.current;
  final next = schedule.next;
  if (live) {
    if (current == null) return (text: 'Live now', label: 'Live now', live: true);
    final since = clock(current.start);
    return (text: 'Live now · since $since', label: 'Live now, since $since', live: true);
  }
  if (current != null) {
    final start = clock(current.start);
    final end = clock(current.end);
    return (text: 'Scheduled now: $start – $end', label: 'Scheduled now, from $start to $end', live: false);
  }
  if (next != null) {
    final text = 'Next stream: ${formatDayFrom(next.start, now)} at ${clock(next.start)}';
    return (text: text, label: text, live: false);
  }
  return null;
}

/// "Watch on Twitch" and the status line under it.
///
/// Tells [TwitchNotifier] when it is on screen: the About tab selected and the
/// app in the foreground (the About tab is built at startup, hidden).
class _TwitchSection extends ConsumerStatefulWidget {
  const _TwitchSection();

  @override
  ConsumerState<_TwitchSection> createState() => _TwitchSectionState();
}

class _TwitchSectionState extends ConsumerState<_TwitchSection> {
  late final TwitchNotifier _notifier;
  late final AppLifecycleListener _lifecycle;

  /// Rebuilds when the text changes with the time alone (an occurrence starts
  /// or ends, a day passes, a live result gets old).
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(twitchProvider.notifier);
    _lifecycle = AppLifecycleListener(onStateChange: (_) => _sync(rebuild: true));
    // after the first frame: never before it, and not while building
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _lifecycle.dispose();
    _notifier.setWatching(false);
    super.dispose();
  }

  void _sync({bool rebuild = false}) {
    if (!mounted) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final foreground =
        lifecycle == null || lifecycle == AppLifecycleState.resumed || lifecycle == AppLifecycleState.inactive;
    _notifier.setWatching(foreground && ref.read(selectedTabProvider) == AppTab.about);
    if (rebuild && foreground) setState(() {});
  }

  void _scheduleTick(TwitchState twitch, ScheduleStatus schedule, DateTime now) {
    _tick?.cancel();
    final local = now.toLocal();
    final times = [
      schedule.current?.end,
      schedule.next?.start,
      DateTime(local.year, local.month, local.day + 1),
      if (twitch.isLiveAt(now)) twitch.liveCheckedAt!.add(liveResultMaxAge),
    ];
    var wait = const Duration(hours: 6);
    for (final time in times) {
      if (time == null) continue;
      final until = time.difference(now);
      if (until < wait) wait = until;
    }
    if (wait < const Duration(seconds: 1)) wait = const Duration(seconds: 1);
    _tick = Timer(wait, () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(selectedTabProvider, (_, _) => _sync());
    final twitch = ref.watch(twitchProvider);
    final now = ref.read(clockProvider)();
    final schedule = twitch.scheduleAt(now);
    final live = twitch.isLiveAt(now);
    _scheduleTick(twitch, schedule, now);
    final status = twitchStatusText(
      live,
      schedule,
      now,
      (time) => TimeOfDay.fromDateTime(time.toLocal()).format(context),
    );
    final scheme = Theme.of(context).colorScheme;
    final ong = OngColors.of(context);
    return Column(
      children: [
        OutsideLink(
          url: twitchUrl,
          label: live ? 'Watch live on Twitch' : 'Watch on Twitch',
          onOpen: () => openLink(context, ref, twitchUrl),
          builder: (context, open) => FilledButton.icon(
            onPressed: open,
            style: platformButtonStyle(
              context,
              FilledButton.styleFrom(
                backgroundColor: ong.brand,
                foregroundColor: ong.onBrand,
                padding: const EdgeInsets.fromLTRB(16, 0, 20, 0),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
            icon: VectorGraphic(
              loader: const AssetBytesLoader('assets/icons/twitch.svg'),
              width: 20,
              height: 20,
              // decoration: without this the button is announced as an image
              excludeFromSemantics: true,
              colorFilter: ColorFilter.mode(ong.onBrand, BlendMode.srcIn),
            ),
            label: Text(live ? 'Watch live on Twitch' : 'Watch on Twitch'),
          ),
        ),
        // The line keeps its place while nothing is known yet (the answers come a moment after the tab
        // opens): what is below must not move when it appears.
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: MediaQuery.textScalerOf(context).scale(13) * 18 / 13),
            child: status == null
                ? null
                : Semantics(
                    container: true,
                    label: status.label,
                    excludeSemantics: true,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (status.live)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Container(
                                key: const ValueKey('live-dot'),
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(color: ong.live, shape: BoxShape.circle),
                              ),
                            ),
                          TextSpan(text: status.text),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 18 / 13,
                        color: status.live ? scheme.onSurface : scheme.onSurfaceVariant,
                        fontWeight: status.live ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.label, required this.icon, required this.color, required this.onTap});

  final String label;
  final Widget icon;

  /// The colour of the tile behind the icon.
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      link: true,
      label: label,
      // the ink well's own action goes with its semantics
      onTap: onTap,
      excludeSemantics: true,
      child: AppInkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
                child: icon,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.top = 24});

  final String text;

  /// Space above: less at the top of a card.
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(16, top, 16, 8),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 18 / 13,
          fontWeight: FontWeight.w500,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    ),
  );
}

class _ThemeSelector extends ConsumerWidget {
  const _ThemeSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themePreferenceProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SegmentedButton<ThemePreference>(
        showSelectedIcon: false,
        expandedInsets: EdgeInsets.zero,
        segments: const [
          ButtonSegment(value: ThemePreference.system, icon: Icon(Icons.contrast, size: 18), label: Text('System')),
          ButtonSegment(value: ThemePreference.light, icon: Icon(Icons.light_mode, size: 18), label: Text('Light')),
          ButtonSegment(value: ThemePreference.dark, icon: Icon(Icons.dark_mode, size: 18), label: Text('Dark')),
        ],
        selected: {current},
        onSelectionChanged: (selection) => ref.read(themePreferenceProvider.notifier).set(selection.single),
      ),
    );
  }
}

class _TwitchNameField extends ConsumerStatefulWidget {
  const _TwitchNameField();

  @override
  ConsumerState<_TwitchNameField> createState() => _TwitchNameFieldState();
}

class _TwitchNameFieldState extends ConsumerState<_TwitchNameField> {
  late final TextEditingController _controller = TextEditingController(text: ref.read(twitchNameProvider));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(twitchNameProvider);
    final catalogue = ref.watch(currentCatalogueProvider);
    final on3 = OngColors.of(context).on3;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            // the hint alone ("Optional") does not say what the field is
            label: 'Your Twitch name',
            child: TextField(
              controller: _controller,
              onChanged: (value) => ref.read(twitchNameProvider.notifier).set(value),
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Optional',
                prefixIcon: Icon(Icons.person, size: 20, color: on3),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              twitchNameHelp(name, catalogue),
              style: TextStyle(fontSize: 12, height: 16 / 12, color: on3),
            ),
          ),
        ],
      ),
    );
  }
}

class _DataSection extends ConsumerStatefulWidget {
  const _DataSection();

  @override
  ConsumerState<_DataSection> createState() => _DataSectionState();
}

class _DataSectionState extends ConsumerState<_DataSection> {
  /// Moves "Updated 5 minutes ago" along.
  late final Timer _tick = Timer.periodic(const Duration(minutes: 1), (_) {
    if (mounted) setState(() {});
  });

  @override
  void initState() {
    super.initState();
    _tick;
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        // with large text in a low window, the buttons stay in reach
        scrollable: true,
        title: const Text('Clear downloaded data?'),
        content: const Text('The highlights and the Ong Log will be downloaded again.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(catalogueProvider.notifier).clearDownloadedData();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(catalogueProvider);
    final scheme = Theme.of(context).colorScheme;
    final on3 = OngColors.of(context).on3;
    final small = TextStyle(fontSize: 12, height: 16 / 12, color: on3);
    final fetchedAt = state.fetchedAt;
    final String title;
    if (state.isRefreshing) {
      title = 'Updating…';
    } else if (fetchedAt == null) {
      title = 'Not downloaded yet';
    } else {
      title = 'Updated ${formatAgo(fetchedAt, ref.read(clockProvider)())}';
    }
    final error = state.lastError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 14, height: 20 / 14, color: scheme.onSurface),
                    ),
                    if (state.hasData)
                      Text(
                        '${plural(state.highlightCount, 'highlight')} · ${plural(state.playCount, 'song')} · '
                        '${plural(state.streamCount, 'stream')}',
                        style: small,
                      ),
                    if (error != null && !state.isRefreshing)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'The last refresh failed. ${describeLoadError(error)}',
                          style: small.copyWith(color: scheme.error),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: state.isRefreshing ? null : () => ref.read(catalogueProvider.notifier).refresh(),
                icon: state.isRefreshing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('Refreshes by itself, at most every 6 hours.', style: small),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text('Clear downloaded data', style: TextStyle(fontSize: 14, color: scheme.onSurface)),
              ),
              TextButton(
                onPressed: state.isRefreshing ? null : _confirmClear,
                style: TextButton.styleFrom(textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The licences page of the framework, as [showLicensePage] shows it; in the
/// desktop look, with the hover of its rows at once ([InstantTileHover]).
void _showLicences(BuildContext context) {
  final version = appVersion.isEmpty ? null : appVersion;
  if (!AppLayout.desktopOf(context)) {
    showLicensePage(context: context, applicationName: 'Ong Music', applicationVersion: version);
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => InstantTileHover(
        child: LicensePage(applicationName: 'Ong Music', applicationVersion: version),
      ),
    ),
  );
}

class _Footer extends ConsumerWidget {
  const _Footer({this.top = 12});

  /// Space above.
  final double top;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on3 = OngColors.of(context).on3;
    final style = TextStyle(fontSize: 12, height: 16 / 12, color: on3);
    Widget link(String label, VoidCallback onTap) => Semantics(
      link: true,
      child: AppInkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            widthFactor: 1,
            child: Text(label, style: style.copyWith(color: Theme.of(context).colorScheme.primary)),
          ),
        ),
      ),
    );
    Widget outsideLink(String label, String url) => OutsideLink(
      url: url,
      label: label,
      onOpen: () => openLink(context, ref, url),
      builder: (context, open) => link(label, open),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(16, top, 16, 20),
      child: Column(
        children: [
          Text(appVersion.isEmpty ? 'Ong Music' : 'Ong Music $appVersion', textAlign: TextAlign.center, style: style),
          // the three links on one line down to a phone 360 px wide
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              outsideLink('Privacy policy', privacyPolicyUrl),
              Text(' · ', style: style),
              outsideLink('Community spreadsheet', spreadsheetUrl),
              Text(' · ', style: style),
              // the open source software the app is made with, and its licences
              link('Licences', () => _showLicences(context)),
            ],
          ),
          Text('Fan-made, not affiliated with Jonathan Ong.', textAlign: TextAlign.center, style: style),
        ],
      ),
    );
  }
}
