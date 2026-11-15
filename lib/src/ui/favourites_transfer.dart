/// Moving the favourites between the app on a phone, the web app and another
/// device: the `Favourites` section of the About tab, its export as a text,
/// and the import of such a text.
///
/// (Android's own backup carries the favourites to a new phone by itself.)
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/catalogue.dart';
import '../data/model.dart';
import '../data/parser.dart';
import '../data/text.dart';
import '../state/catalogue_state.dart';
import '../state/settings_state.dart';
import 'actions.dart';
import 'format.dart';

/// The title of the section of the About tab.
const String favouritesSectionTitle = 'Favourites';

/// The button of the section that opens the import dialog, and the one of the dialog that imports.
const String _importLabel = 'Import';

/// A `Highlight.key` that is the id of a YouTube video (the key of a highlight without video holds a space).
final _youtubeKey = RegExp(r'^[\w-]{11}$');

/// The highlight of each key of [catalogue]: the newest one of the highlights sharing a video. Made once per list
/// of highlights.
final _byKey = Expando<Map<String, Highlight>>('highlights by key');

Map<String, Highlight> _highlightsByKey(Catalogue catalogue) =>
    _byKey[catalogue.highlights] ??= {for (final h in catalogue.highlights) h.key: h};

/// The lines of the export of [favourites] (in the order they were added), one per favourite, as "Share" gives
/// its highlight (`highlightShareText`): its title and its link, its title alone without video. A favourite whose
/// highlight is not in [catalogue] (or without catalogue) is its link alone when its key is a YouTube video, and
/// is left out otherwise (nothing would find it again).
List<String> favouriteLines(Set<String> favourites, Catalogue? catalogue) {
  final byKey = catalogue == null ? const <String, Highlight>{} : _highlightsByKey(catalogue);
  return [
    for (final key in favourites)
      if (byKey[key] case final highlight?)
        highlightShareText(highlight)
      else if (_youtubeKey.hasMatch(key))
        shortVideoUrl(key),
  ];
}

/// The lines of the export of the favourites, on the current catalogue: their number is the count of the
/// section.
final favouriteLinesProvider = Provider<List<String>>(
  (ref) => favouriteLines(ref.watch(favouritesProvider), ref.watch(currentCatalogueProvider)),
);

/// The text of an export: a first line with the number of [lines], then the lines.
String favouritesExportText(List<String> lines) => ['My Ong Music favourites (${lines.length})', ...lines].join('\n');

/// The keys of the highlights of [catalogue] that [text] names, in the order of the text, each once: every YouTube
/// link in it, wherever it is (a forwarded message, lines wrapped, words around the list); and a line without
/// link, by its title, a highlight without video. A highlight not in [catalogue] is not named.
///
/// Highlights without video sharing a title are named the newest first, one per line naming it.
List<String> favouriteKeysIn(String text, Catalogue catalogue) {
  final byKey = _highlightsByKey(catalogue);
  final keys = <String>{};
  // the highlights without video by title, newest first: made only when a line has no link
  Map<String, List<Highlight>>? untitled;
  for (final line in text.split('\n')) {
    final ids = youtubeIdsIn(line);
    if (ids.isNotEmpty) {
      for (final id in ids) {
        if (byKey.containsKey(id)) keys.add(id);
      }
      continue;
    }
    final title = songKey(line);
    if (title.isEmpty) continue;
    untitled ??= () {
      final map = <String, List<Highlight>>{};
      for (final h in catalogue.highlights.reversed) {
        if (h.youtubeId == null && h.songKey.isNotEmpty) (map[h.songKey] ??= []).add(h);
      }
      return map;
    }();
    for (final h in untitled[title] ?? const <Highlight>[]) {
      if (keys.add(h.key)) break;
    }
  }
  return keys.toList();
}

/// What the section says of the favourites: `12 favourites`.
String favouriteCountText(int count) => plural(count, 'favourite');

/// The `Favourites` section of the About tab, under its title: the number of favourites, `Export` and `Import`.
///
/// The number is that of the lines an export writes. Its text changes in the room left of the buttons, which
/// stay at the right edge: nothing moves.
class FavouritesSection extends ConsumerWidget {
  const FavouritesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(favouriteLinesProvider);
    final loaded = ref.watch(currentCatalogueProvider.select((c) => c != null));
    final scheme = Theme.of(context).colorScheme;
    final buttonStyle = TextButton.styleFrom(textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
      // the count at the left, the buttons at the right; under it when they do not fit beside it (large text)
      child: OverflowBar(
        alignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            // its line as high as the buttons, in either layout
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(favouriteCountText(lines.length), style: TextStyle(fontSize: 14, color: scheme.onSurface)),
          ),
          // one under the other when even a line of their own is too narrow
          OverflowBar(
            children: [
              TextButton(
                onPressed: lines.isEmpty ? null : () => _export(context, ref, lines),
                style: buttonStyle,
                child: const Text('Export'),
              ),
              TextButton(
                // the text is read against the highlights
                onPressed: loaded ? () => showImportFavouritesDialog(context) : null,
                style: buttonStyle,
                child: const Text(_importLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Gives the export to the share sheet, or copies it where there is none (or it failed).
Future<void> _export(BuildContext context, WidgetRef ref, List<String> lines) async {
  final text = favouritesExportText(lines);
  if (ref.read(canShareProvider) && await ref.read(textSharerProvider)(text)) return;
  final copied = await copyText(text);
  if (copied && context.mounted) showMessage(context, 'Copied');
}

/// The import dialog: the exported text pasted, its favourites added to the user's.
Future<void> showImportFavouritesDialog(BuildContext context) async {
  final added = await showDialog<int>(context: context, builder: (context) => const _ImportDialog());
  if (added == null || !context.mounted) return;
  showMessage(context, added == 0 ? 'Already in your favourites' : '${favouriteCountText(added)} added');
}

class _ImportDialog extends ConsumerStatefulWidget {
  const _ImportDialog();

  @override
  ConsumerState<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<_ImportDialog> {
  final _text = TextEditingController();
  bool _nothing = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _import() {
    final catalogue = ref.read(currentCatalogueProvider);
    final keys = catalogue == null ? const <String>[] : favouriteKeysIn(_text.text, catalogue);
    if (keys.isEmpty) {
      setState(() => _nothing = true);
      return;
    }
    // the number added, 0 when all were favourites already
    Navigator.of(context).pop(ref.read(favouritesProvider.notifier).addAll(keys));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    // with the keyboard up on a small phone, the field scrolls and the buttons stay in reach
    scrollable: true,
    title: const Text('Import favourites'),
    // the line kept for the error is the room between the field and the buttons
    contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
    content: SizedBox(
      width: 400,
      child: TextField(
        controller: _text,
        autofocus: true,
        minLines: 4,
        maxLines: 6,
        keyboardType: TextInputType.multiline,
        autocorrect: false,
        enableSuggestions: false,
        // the error goes when the text changes
        onChanged: (_) {
          if (_nothing) setState(() => _nothing = false);
        },
        decoration: InputDecoration(
          hintText: 'Paste the exported text',
          // the line of the error is there before it: the buttons do not move when it comes
          helperText: ' ',
          errorText: _nothing ? 'That text holds no favourites.' : null,
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      TextButton(onPressed: _import, child: const Text(_importLabel)),
    ],
  );
}
