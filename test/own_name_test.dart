import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/sheets.dart';
import 'package:ong_music/src/ui/theme.dart';
import 'package:ong_music/src/ui/widgets.dart';

import 'fixtures.dart';
import 'ui_harness.dart';

/// A window wide enough for the requester of a highlight row to show: the
/// letters of the test font are as wide as they are high.
const _wide = Size(700, 892);

/// The text of a requester line holding [name], inside [within] when given.
Finder _line(String name, {Finder? within}) {
  final line = find.byWidgetPredicate(
    (w) => w is RequesterText && w.span.toPlainText(includeSemanticsLabels: false).contains(name),
  );
  return within == null ? line : find.descendant(of: within, matching: line);
}

/// The texts of the spans of [span] with their styles, merged with those of
/// the spans around them ([inherited] for [span]).
List<(String, TextStyle)> _styled(InlineSpan span, [TextStyle inherited = const TextStyle()]) {
  if (span is! TextSpan) return const [];
  final style = inherited.merge(span.style);
  return [
    if (span.text case final text?) (text, style),
    for (final child in span.children ?? const <InlineSpan>[]) ..._styled(child, style),
  ];
}

/// The colour of the span whose text is [text] in [span], [color] being the
/// colour [span] inherits; null when there is no such span.
Color? _colorOf(InlineSpan span, String text, Color? color) =>
    _styled(span, TextStyle(color: color)).where((s) => s.$1 == text).firstOrNull?.$2.color;

/// The texts of the spans of [span] that have a background colour, theirs or
/// inherited.
List<String> _backgrounds(InlineSpan span) => [
  for (final (text, style) in _styled(span))
    if (style.backgroundColor != null) text,
];

/// The rounded boxes painted by [line], in order, with their colours.
List<(RRect, Color)> _boxes(WidgetTester tester, Finder line) {
  final boxes = <(RRect, Color)>[];
  expect(
    tester.renderObject(line),
    paints..everything((method, arguments) {
      // back to a plain colour: a paint keeps it as 32 bits
      if (method == #drawRRect) boxes.add((arguments[0] as RRect, Color((arguments[1] as Paint).color.toARGB32())));
      return true;
    }),
  );
  return boxes;
}

RenderParagraph _paragraph(WidgetTester tester, Finder line) =>
    tester.renderObject<RenderParagraph>(find.descendant(of: line, matching: find.byType(RichText)).first);

/// [name] in [line]: on the brand orange, in the colour made for it, without
/// any "You" badge.
void _expectHighlighted(WidgetTester tester, Finder line, String name) {
  final ong = OngColors.of(tester.element(line));
  final widget = tester.widget<RequesterText>(line);
  expect(_colorOf(widget.span, name, widget.style.color), ong.onBrand, reason: name);
  expect(_boxes(tester, line).first.$2, ong.brand, reason: name);
  // the rounded box, not a span background, square and as high as the line
  expect(_backgrounds(widget.span), isEmpty, reason: name);
  expect(widget.span.toPlainText(includeSemanticsLabels: false), isNot(contains('YOU')));
  expect(find.descendant(of: line, matching: find.text('YOU')), findsNothing);
}

/// [name] in [line] as any other text of the line.
void _expectPlain(WidgetTester tester, Finder line, String name) {
  final widget = tester.widget<RequesterText>(line);
  expect(_colorOf(widget.span, name, widget.style.color), widget.style.color, reason: name);
  expect(tester.renderObject(line), isNot(paints..rrect()), reason: name);
}

/// The contrast ratio of two opaque colours (WCAG 2).
double _contrast(Color a, Color b) {
  final (la, lb) = (a.computeLuminance(), b.computeLuminance());
  return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
}

void main() {
  group('the user’s own name', () {
    testWidgets('highlighted in the rows of both lists, the others untouched', (tester) async {
      await pumpApp(tester, prefs: {'twitchName': 'JSBACH64'}, size: _wide);
      _expectHighlighted(tester, _line('jsbach64'), 'jsbach64');
      _expectPlain(tester, _line('shadowvanta'), 'shadowvanta');
      expect(find.textContaining('YOU'), findsNothing);

      await goToTab(tester, 'Ong Log');
      final mine = _line('jsbach64', within: find.byType(PlayRow));
      expect(mine, findsNWidgets(2));
      for (final line in [mine.first, mine.last]) {
        _expectHighlighted(tester, line, 'jsbach64');
      }
      _expectPlain(tester, _line('MannyHub'), 'MannyHub');
      _expectPlain(tester, _line('shadowvanta'), 'shadowvanta');
      expect(find.textContaining('YOU'), findsNothing);
      // the flag of a play keeps its tag
      expect(find.text('TIER 3'), findsOneWidget);
    });

    testWidgets('highlighted in the sheets, the others untouched', (tester) async {
      await pumpApp(tester, prefs: {'twitchName': 'jsbach64'});
      // highlight sheet: "Requested by …"
      await tester.tap(find.byTooltip('Details').at(2)); // Song of Storms
      await tester.pumpAndSettle();
      final requested = _line('Requested by', within: find.byType(HighlightSheet));
      expect(
        tester.widget<RequesterText>(requested).span.toPlainText(includeSemanticsLabels: false),
        'Requested by \u00A0jsbach64\u00A0',
      );
      _expectHighlighted(tester, requested, 'jsbach64');
      Navigator.of(tester.element(find.byType(HighlightSheet))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Details').at(1)); // I Will Survive
      await tester.pumpAndSettle();
      _expectPlain(tester, _line('Requested by', within: find.byType(HighlightSheet)), 'shadowvanta');
      Navigator.of(tester.element(find.byType(HighlightSheet))).pop();
      await tester.pumpAndSettle();

      // stream sheet
      await goToTab(tester, 'Ong Log');
      await tester.tap(find.text('Sat 2 Mar 2024'));
      await tester.pumpAndSettle();
      final stream = find.byType(StreamSheet);
      _expectHighlighted(tester, _line('jsbach64', within: stream), 'jsbach64');
      _expectPlain(tester, _line('shadowvanta', within: stream), 'shadowvanta');

      // song sheet
      await tester.tap(find.descendant(of: stream, matching: find.text('Song of Storms')));
      await tester.pumpAndSettle();
      _expectHighlighted(tester, _line('jsbach64', within: find.byType(SongSheet)), 'jsbach64');
      Navigator.of(tester.element(find.byType(SongSheet))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('I Will Survive').first);
      await tester.pumpAndSettle();
      final song = find.byType(SongSheet);
      _expectPlain(tester, _line('MannyHub', within: song), 'MannyHub');
      _expectPlain(tester, _line('shadowvanta', within: song), 'shadowvanta');
      expect(find.textContaining('YOU'), findsNothing);
    });

    testWidgets('the highlight covers the name and its padding exactly', (tester) async {
      await pumpApp(tester, prefs: {'twitchName': 'jsbach64'}, size: _wide);
      // the line starts with two widgets (genre dot, person icon), one character each in the text
      final line = _line('jsbach64');
      final paragraph = _paragraph(tester, line);
      final start = paragraph.text.toPlainText(includeSemanticsLabels: false).indexOf('\u00A0jsbach64\u00A0');
      final expected = paragraph
          .getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: start + 10))
          .map((box) => box.toRect())
          .reduce((a, b) => a.expandToInclude(b));
      final (pill, _) = _boxes(tester, line).single;
      expect(pill.outerRect, rectMoreOrLessEquals(expected));
      expect(pill.tlRadiusX, greaterThan(0));
    });

    testWidgets('a screen reader hears it as the user’s, the others as before', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpApp(tester, prefs: {'twitchName': 'jsbach64'});
      String label(Finder finder) => tester.getSemantics(finder).label;
      final rows = find.byType(HighlightRow);
      expect(label(rows.at(2)), endsWith('Game OST · 2 Mar 2024 · \njsbach64, you'));
      expect(label(rows.at(1)), endsWith('Popular · 2 Mar 2024 · \nshadowvanta'));
      // the same when a search hit splits the name
      await tester.enterText(searchField(), 'bach');
      await tester.pumpAndSettle();
      expect(label(find.byType(HighlightRow)), endsWith('Game OST · 2 Mar 2024 · \njsbach64, you'));
      await tester.tap(find.byTooltip('Details'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Requested by jsbach64, you\n2 requests in the Ong Log'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a search hit in it: a box of the mark colour inside the highlight', (tester) async {
      await pumpApp(tester, prefs: {'twitchName': 'jsbach64'}, size: _wide);
      await tester.enterText(searchField(), 'bach');
      await tester.pumpAndSettle();
      final line = _line('jsbach64');
      final context = tester.element(line);
      final ong = OngColors.of(context);
      final span = tester.widget<RequesterText>(line).span;
      // not the square background of the other hits, which would cover the highlight
      expect(_backgrounds(span), isEmpty);
      expect(_colorOf(span, 'bach', null), Theme.of(context).colorScheme.onSurface);
      expect(_colorOf(span, 'js', null), ong.onBrand);
      final [(pill, brand), (hit, mark)] = _boxes(tester, line);
      expect((brand, mark), (ong.brand, ong.mark));
      expect(hit.left, greaterThan(pill.left));
      expect(hit.right, lessThan(pill.right));
      expect((hit.top, hit.bottom), (pill.top, pill.bottom));

      // another requester's hit as before
      await tester.enterText(searchField(), 'vanta');
      await tester.pumpAndSettle();
      expect(_backgrounds(tester.widget<RequesterText>(_line('shadowvanta')).span), ['vanta']);
      _expectPlain(tester, _line('shadowvanta'), 'shadow');

      // the Ong Log too
      await goToTab(tester, 'Ong Log');
      await tester.enterText(searchField(), 'bach');
      await tester.pumpAndSettle();
      final plays = _line('jsbach64', within: find.byType(PlayRow));
      expect(plays, findsNWidgets(2));
      expect(_boxes(tester, plays.first).map((box) => box.$2), [ong.brand, ong.mark]);
    });

    test('its colours meet WCAG AA for small text in both themes', () {
      for (final brightness in Brightness.values) {
        final theme = buildTheme(brightness);
        final ong = theme.extension<OngColors>()!;
        expect(_contrast(ong.onBrand, ong.brand), greaterThanOrEqualTo(4.5), reason: '$brightness name');
        expect(
          _contrast(theme.colorScheme.onSurface, ong.mark),
          greaterThanOrEqualTo(4.5),
          reason: '$brightness search hit',
        );
      }
    });

    // A long name on a narrow screen: the highlight is cut with the text, and
    // the rows keep their heights. In Roboto, the font of the app: the test
    // font, whose letters are as wide as high, would leave no room for the name
    // after genre and date, and overflow a stream header at 2x. Last in the
    // file, as the font stays loaded.
    group('in Roboto', () {
      setUpAll(() async {
        final font = File('assets/fonts/Roboto-Medium.ttf').readAsBytes().then(ByteData.sublistView);
        await (FontLoader('Roboto')..addFont(font)).load();
      });

      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('cut by the ellipsis on a 320 px screen at text scale $scale', (tester) async {
          // as long as a Twitch name can be
          const name = 'MrWorldWideMegaMusicMaker';
          final catalogue = catalogueOf(
            highlights: [
              hRow(title: 'A track', requester: name, link: 'https://youtu.be/aaaaaaaaaaa', upload: '2026-01-02'),
            ],
            songs: [
              start('2024-03-01'),
              sRow(date: '2024-03-01 20:00:00', title: 'A track', requester: name),
            ],
          );
          await pumpApp(
            tester,
            size: const Size(320, 700),
            textScale: scale,
            prefs: {'twitchName': name},
            state: CatalogueState(catalogue: catalogue, fetchedAt: testNow),
          );
          final metrics = ListMetrics.of(tester.element(find.byType(HighlightRow)));

          /// The highlight in [line] is there when the start of the name is
          /// ([shown]), within the line, whose end is cut when [cut].
          void expectFits(Finder line, {required bool shown, required bool cut}) {
            final paragraph = _paragraph(tester, line);
            expect(paragraph.didExceedMaxLines, cut);
            final boxes = _boxes(tester, line);
            expect(boxes, shown ? hasLength(1) : isEmpty);
            for (final (box, _) in boxes) {
              expect(box.left, greaterThanOrEqualTo(0));
              expect(box.right, lessThanOrEqualTo(paragraph.size.width));
            }
          }

          expect(tester.takeException(), isNull);
          expect(tester.getSize(find.byType(HighlightRow)).height, metrics.highlightRow);
          // larger, genre and date leave no room for the name
          expectFits(_line(name), shown: scale == 1, cut: true);

          await goToTab(tester, 'Ong Log');
          expect(tester.takeException(), isNull);
          expect(tester.getSize(find.byType(PlayRow)).height, metrics.playRow);
          expectFits(_line(name, within: find.byType(PlayRow)), shown: true, cut: true);

          await tester.tap(find.byType(PlayRow));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(tester.getSize(find.byType(HistoryRow)).height, metrics.historyRow);
          expectFits(_line(name, within: find.byType(HistoryRow)), shown: true, cut: scale == 2);
        });
      }
    });
  });
}
