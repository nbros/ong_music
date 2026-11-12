// The favourite highlights: their key, their storage, what they count and
// filter, across restarts and refreshes.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/catalogue.dart';
import 'package:ong_music/src/data/repository.dart';
import 'package:ong_music/src/data/sheet_cache.dart';
import 'package:ong_music/src/data/sheets.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/state/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

/// Answers with [sheets], whatever they are at the time of the call.
class _Fetcher implements SheetFetcher {
  _Fetcher(this.sheets);

  RawSheets sheets;

  @override
  Future<RawSheets> fetch() async => sheets;
}

/// Three highlights: #1 and #2, and a row without number after #2, which
/// carries #2 too.
List<List<String>> _rows({String firstTitle = 'Zelda - Song of Storms'}) => [
  hRow(order: '1', title: firstTitle, upload: '2024-03-05'),
  hRow(order: '2', title: 'Gloria Gaynor - I Will Survive', upload: '2024-03-06'),
  hRow(order: '', title: 'Moana - How Far I’ll Go', upload: '2024-03-07'),
];

RawSheets _sheets(List<List<String>> rows) =>
    RawSheets(highlightsCsv: highlightsCsv(rows), songsCsv: sampleSheets().songsCsv);

void main() {
  const key = FavouritesNotifier.key;
  final now = DateTime.utc(2026, 11, 12, 12);

  /// A container over preferences holding [values], with the real catalogue
  /// notifier: [fetcher] answers its downloads, nothing in cache at start.
  Future<(ProviderContainer, SharedPreferences)> start(Map<String, Object> values, _Fetcher fetcher) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer.test(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        sheetFetcherProvider.overrideWithValue(fetcher),
        sheetCacheProvider.overrideWithValue(MemorySheetCache()),
        catalogueParserProvider.overrideWithValue(parseOnCurrentIsolate),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    // keeps the catalogue alive, as the UI does
    container.listen(catalogueProvider, (_, _) {});
    await container.read(catalogueProvider.notifier).idle;
    return (container, prefs);
  }

  Catalogue catalogue(ProviderContainer c) => c.read(currentCatalogueProvider)!;
  List<String> titles(ProviderContainer c, HighlightFilter filter) {
    final results = c.read(highlightResultsProvider(filter))!;
    return [for (final id in results.ids) catalogue(c).highlights[id].title];
  }

  test('a highlight is known by its number and its song key', () {
    final highlights = catalogueOf(highlights: _rows()).highlights;
    expect(
      [for (final h in highlights) h.key],
      ['1 zelda song of storms', '2 gloria gaynor i will survive', '2 moana how far i ll go'],
    );
    // case, accents and punctuation of the title do not change it
    final retyped = catalogueOf(highlights: _rows(firstTitle: 'ZELDA – Song of Störms!')).highlights;
    expect(retyped.first.key, highlights.first.key);
  });

  test('round trip: a star is stored at once and read back after a restart, in the order given', () async {
    final fetcher = _Fetcher(_sheets(_rows()));
    final (c, prefs) = await start({}, fetcher);
    expect(c.read(favouritesProvider), isEmpty);
    expect(c.read(favouriteCountProvider), 0);
    final [first, second, third] = catalogue(c).highlights;
    final notifier = c.read(favouritesProvider.notifier);
    await notifier.toggle(third);
    await notifier.toggle(first);
    expect(prefs.getStringList(key), [third.key, first.key]);
    expect(c.read(favouriteCountProvider), 2);
    // the row sharing #2 with "I Will Survive" is starred alone
    expect(c.read(favouritesProvider).contains(second.key), isFalse);

    // restart
    final (c2, _) = await start({key: prefs.getStringList(key)!}, fetcher);
    expect(c2.read(favouritesProvider), [third.key, first.key]);
    expect(c2.read(favouriteCountProvider), 2);
    expect(titles(c2, const HighlightFilter(favourites: true)), ['Moana - How Far I’ll Go', 'Zelda - Song of Storms']);

    // a second tap removes it
    await c2.read(favouritesProvider.notifier).toggle(third);
    expect(c2.read(favouritesProvider), [first.key]);
    final (c3, _) = await start({key: c2.read(favouritesProvider).toList()}, fetcher);
    expect(c3.read(favouritesProvider), [first.key]);
  });

  test('a favourite absent from the catalogue is kept but does not count', () async {
    final fetcher = _Fetcher(_sheets(_rows()));
    final (c, prefs) = await start({
      key: ['999 a highlight removed from the sheet'],
    }, fetcher);
    expect(c.read(favouritesProvider), hasLength(1));
    expect(c.read(favouriteCountProvider), 0);
    // nothing to filter on: the filter keeps everything, as without the chip
    expect(titles(c, const HighlightFilter(favourites: true)), hasLength(3));

    final first = catalogue(c).highlights.first;
    await c.read(favouritesProvider.notifier).toggle(first);
    expect(c.read(favouriteCountProvider), 1);
    expect(titles(c, const HighlightFilter(favourites: true)), ['Zelda - Song of Storms']);
    expect(prefs.getStringList(key), ['999 a highlight removed from the sheet', first.key]);
  });

  test('favourites follow their highlights through a refresh, and survive "Clear downloaded data"', () async {
    final fetcher = _Fetcher(_sheets(_rows()));
    final (c, prefs) = await start({}, fetcher);
    final storms = catalogue(c).highlights.first;
    final moana = catalogue(c).highlights.last;
    await c.read(favouritesProvider.notifier).toggle(storms);
    await c.read(favouritesProvider.notifier).toggle(moana);

    // a refresh brings a row inserted at the top of the sheet: every id moves
    fetcher.sheets = _sheets([hRow(order: '0', title: 'A new first row', upload: '2024-03-01'), ..._rows()]);
    await c.read(catalogueProvider.notifier).refresh();
    expect(catalogue(c).highlightCount, 4);
    expect(catalogue(c).highlights[1].id, isNot(storms.id));
    expect(c.read(favouriteCountProvider), 2);
    expect(titles(c, const HighlightFilter(favourites: true)), ['Moana - How Far I’ll Go', 'Zelda - Song of Storms']);

    // then one without "Song of Storms": kept, not counted; then with it again
    fetcher.sheets = _sheets(_rows().sublist(1));
    await c.read(catalogueProvider.notifier).clearDownloadedData();
    expect(catalogue(c).highlightCount, 2);
    expect(c.read(favouritesProvider), [storms.key, moana.key]);
    expect(prefs.getStringList(key), [storms.key, moana.key]);
    expect(c.read(favouriteCountProvider), 1);
    fetcher.sheets = _sheets(_rows());
    await c.read(catalogueProvider.notifier).clearDownloadedData();
    expect(c.read(favouriteCountProvider), 2);
  });

  for (final (name, garbage) in [
    ('a string', 'Song of Storms' as Object),
    ('a number', 42),
    ('a list of numbers', <Object>[1, 2]),
    ('a list mixing strings and numbers', <Object>['1 zelda song of storms', 2]),
  ]) {
    test('$name under the key reads as no favourite, and the next star replaces it', () async {
      final fetcher = _Fetcher(_sheets(_rows()));
      final (c, prefs) = await start({key: garbage}, fetcher);
      expect(c.read(favouritesProvider), isEmpty);
      expect(c.read(favouriteCountProvider), 0);
      final first = catalogue(c).highlights.first;
      await c.read(favouritesProvider.notifier).toggle(first);
      expect(c.read(favouritesProvider), [first.key]);
      expect(prefs.getStringList(key), [first.key]);
    });
  }
}
