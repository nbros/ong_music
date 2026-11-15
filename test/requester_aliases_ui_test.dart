// "You" for a user whose Twitch name is one of the names of their group, not the one shown (see
// `requester_aliases.dart`).
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/requester_aliases.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/widgets.dart';

import 'fixtures.dart';
import 'ui_harness.dart';

/// Amy, shown under that name, requested a highlight and three songs, one of them under amy_alt.
final aliasCatalogue = catalogueOf(
  highlights: [
    hRow(title: 'Zelda - Lost Woods', requester: 'Amy'),
    hRow(title: 'Moana - Shiny', requester: 'Carol', upload: '2024-01-03'),
  ],
  songs: [
    start('2024-03-01'),
    sRow(date: '2024-03-01 20:00:00', title: 'Zelda - Lost Woods', requester: 'Amy'),
    sRow(date: '2024-03-01 20:10:00', title: 'Moana - Shiny', requester: 'Carol'),
    sRow(date: '2024-03-01 20:20:00', title: 'Zelda - Song of Storms', requester: 'amy_alt'),
    sRow(date: '2024-03-01 20:30:00', title: 'Gloria Gaynor - I Will Survive', requester: 'Amy'),
  ],
  aliases: RequesterAliases([
    ['amy_alt', 'Amy'],
  ]),
);

/// The names drawn as the user's own (in orange) in the requester lines on screen.
List<String> ownNames(WidgetTester tester) => [
  for (final text in tester.widgetList<RequesterText>(find.byType(RequesterText).hitTestable()))
    ...() {
      final names = <String>[];
      text.span.visitChildren((span) {
        final label = span is TextSpan ? span.semanticsLabel : null;
        if (label != null && label.endsWith(', you')) names.add(label.substring(0, label.length - 5));
        return true;
      });
      return names;
    }(),
];

void main() {
  testWidgets('the Twitch name amy_alt is Amy: "You", her name in orange, every request of hers', (tester) async {
    await pumpApp(tester, prefs: {'twitchName': 'amy_alt'}, state: loadedState(aliasCatalogue, testNow));
    // Highlights: hers
    expect(chip('You'), findsOneWidget);
    expect(ownNames(tester), ['Amy']);
    await tester.tap(chip('You'));
    await tester.pumpAndSettle();
    expect(find.byType(HighlightRow), findsOneWidget);
    expect(find.text('Lost Woods'), findsOneWidget);

    await goToTab(tester, 'Ong Log');
    expect(ownNames(tester), ['Amy', 'Amy', 'Amy']);
    await tester.tap(chip('You'));
    await tester.pumpAndSettle();
    expect(find.byType(PlayRow), findsNWidgets(3));
    expect(find.text('Shiny'), findsNothing);

    await goToTab(tester, 'About');
    expect(find.text('Found 3 requests by Amy, now in orange. Tap the “You” chip to see only yours.'), findsOneWidget);
  });

  testWidgets('a search for amy_alt finds every request of Amy', (tester) async {
    await pumpApp(tester, state: loadedState(aliasCatalogue, testNow));
    await goToTab(tester, 'Ong Log');
    await tester.enterText(searchField(), 'amy_alt');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(PlayRow), findsNWidgets(3));
    expect(ownNames(tester), isEmpty);
  });
}
