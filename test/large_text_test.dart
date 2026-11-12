import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/state/catalogue_state.dart';

import 'fixtures.dart';
import 'ui_harness.dart';

void main() {
  // Rows have a height computed from the text scale, not measured: every
  // combination of lines must fit in it, at any scale.
  for (final scale in [1.0, 1.15, 1.3, 1.5, 2.0]) {
    testWidgets('rows fit their computed height at text scale $scale', (tester) async {
      final catalogue = catalogueOf(
        highlights: [
          // a title on two lines, without artist
          hRow(
            order: '1',
            title: 'A rather long title that wraps onto two lines here',
            link: 'https://youtu.be/abcdefghijk',
          ),
          hRow(order: '2', title: 'A rather long title that wraps onto two lines here', requester: 'someone'),
          hRow(order: '3', title: 'An artist - And a rather long track name that would wrap too', requester: 'someone'),
          hRow(order: '4', title: 'Short'),
        ],
        songs: [
          start('2024-03-01'),
          sRow(
            date: '2024-03-01 20:00:00',
            title: 'A rather long title that would wrap onto two lines',
            requester: 'someone',
          ),
          sRow(date: '2024-03-01 20:30:00', title: 'An artist - A track', requester: 'someone', notes: 'Tier 3'),
          sRow(date: '2024-03-01 21:00:00', title: 'Short'),
        ],
      );
      await pumpApp(
        tester,
        textScale: scale,
        state: CatalogueState(catalogue: catalogue, fetchedAt: testNow),
      );
      expect(tester.takeException(), isNull);
      await goToTab(tester, 'Ong Log');
      expect(tester.takeException(), isNull);
    });
  }
}
