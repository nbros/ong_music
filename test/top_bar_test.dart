// The desktop look: the top bar of text links instead of the rail and the
// bottom bar, no ink ripple, the states of the controls shown at once. In a
// file of its own: the themes of the app are built once, for the platform of
// the first test of a file; every test here runs on Windows, and gets the look
// from the seam (desktopLookProvider), not from the platform.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/ui/about_page.dart';
import 'package:ong_music/src/ui/detail_pane.dart';
import 'package:ong_music/src/ui/fullscreen_button.dart';
import 'package:ong_music/src/ui/highlights_page.dart';
import 'package:ong_music/src/ui/instant_feedback.dart';
import 'package:ong_music/src/ui/layout.dart';
import 'package:ong_music/src/ui/nav_rail.dart';
import 'package:ong_music/src/ui/ong_log_page.dart';
import 'package:ong_music/src/ui/outside_link.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/theme.dart';
import 'package:ong_music/src/ui/top_bar.dart';
import 'package:ong_music/src/ui/view_state.dart';
import 'package:ong_music/src/ui/widgets.dart';
import 'package:ong_music/src/web/install_hint.dart';

import 'ui_harness.dart';

final windows = TargetPlatformVariant.only(TargetPlatform.windows);

/// The windows of the specification, from the widest to the narrowest.
const sizes = [Size(1340, 830), Size(900, 700), Size(700, 800), Size(500, 800), Size(400, 800), Size(320, 700)];

const labels = ['Highlights', 'Ong Log', 'About'];

Finder topBar() => find.byType(AppTopBar);

Finder barText(String label) => find.descendant(of: topBar(), matching: find.text(label));

/// The control of the link [label] of the top bar.
Finder barLink(String label) => find.ancestor(of: barText(label), matching: find.byType(InkWell)).first;

/// The line under the current link.
Finder underline(WidgetTester tester) {
  final brand = OngColors.of(tester.element(topBar())).brand;
  return find.descendant(
    of: topBar(),
    matching: find.byWidgetPredicate(
      (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == brand,
    ),
  );
}

Color labelColor(WidgetTester tester, String label) => tester.widget<Text>(barText(label)).style!.color!;

/// Pumps the app in the desktop look, with a mouse and the full screen of a
/// browser, in a window of [size].
Future<TestApp> pumpDesktop(WidgetTester tester, Size size) =>
    pumpApp(tester, size: size, desktop: true, fullscreen: FakeFullscreen(), pointer: PointerKind.mouse);

/// The colour the state layer around [inside] paints, or null when it paints
/// nothing.
Color? layerColor(WidgetTester tester, Finder inside) {
  final layer = find.ancestor(of: inside, matching: find.byType(StateLayer)).first;
  final paint = tester.widget<CustomPaint>(find.descendant(of: layer, matching: find.byType(CustomPaint)).first);
  final painter = paint.painter;
  if (painter == null) return null;
  // what it paints: one rectangle or one path, of one colour
  final recorder = _ColorCanvas();
  painter.paint(recorder, tester.getSize(find.descendant(of: layer, matching: find.byType(CustomPaint)).first));
  return recorder.color;
}

class _RectCanvas extends Fake implements Canvas {
  Rect? rect;
  Color? color;

  @override
  void drawRect(Rect rect, Paint paint) {
    this.rect = rect;
    color = paint.color;
  }
}

class _ColorCanvas extends Fake implements Canvas {
  Color? color;

  @override
  void drawRect(Rect rect, Paint paint) => color = paint.color;

  @override
  void drawPath(Path path, Paint paint) => color = paint.color;
}

/// Paints a path of [color] (to the precision of a paint's colour).
PaintPattern paintsPathOf(Color color) => paints
  ..something((method, arguments) {
    if (method != #drawPath) return false;
    final painted = (arguments[1] as Paint).color;
    return (painted.a - color.a).abs() < 1e-3 &&
        (painted.r - color.r).abs() < 1e-3 &&
        (painted.g - color.g).abs() < 1e-3 &&
        (painted.b - color.b).abs() < 1e-3;
  });

/// A mouse resting on [at], its button up.
Future<TestGesture> mouseAt(WidgetTester tester, Offset at) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: at);
  await tester.pump();
  return mouse;
}

/// The ink of every ink well on screen: how it splashes, and the colours of
/// the highlights Material fades in and out for a press and for a hover.
List<({String widget, InteractiveInkFeatureFactory splash, Color pressed, Color hovered, Duration? hover})> inkOf(
  WidgetTester tester,
) => [
  for (final element in find.byWidgetPredicate((w) => w is InkResponse).evaluate())
    if (element.widget case final InkResponse w)
      (
        widget: element.findAncestorWidgetOfExactType<IconButton>() != null
            ? 'IconButton'
            : '${w.runtimeType} in ${element.debugGetCreatorChain(4)}',
        splash: w.splashFactory ?? Theme.of(element).splashFactory,
        pressed: w.overlayColor?.resolve({WidgetState.pressed}) ?? w.highlightColor ?? Theme.of(element).highlightColor,
        hovered: w.overlayColor?.resolve({WidgetState.hovered}) ?? w.hoverColor ?? Theme.of(element).hoverColor,
        hover: w.hoverDuration,
      ),
];

/// A package of the licences page of the tests (see [main]).
const licensedPackage = 'ong_test_package';

/// The row of [licensedPackage] in the list of the licences page.
Finder licensedRow() => find.ancestor(of: find.text(licensedPackage), matching: find.byType(ListTile)).first;

/// Opens the licences page from the About tab on screen.
Future<void> openLicences(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Licences'));
  await tester.tap(find.text('Licences'));
  await tester.pumpAndSettle();
}

/// The pixels of [box] as the window shows them: from the root layer, as the
/// ink of a row is painted by a material above the row's own repaint
/// boundary.
Future<Uint8List> pixelsOf(WidgetTester tester, RenderBox box) async {
  final root = tester.binding.renderViews.first;
  final rect = MatrixUtils.transformRect(box.getTransformTo(root), Offset.zero & box.size);
  final image = await (root.debugLayer! as OffsetLayer).toImage(rect);
  final data = await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba));
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Goes through every focus stop of the screen with the Tab key, and expects
/// each control to look different with the keyboard focus than without it.
/// Returns the number of stops.
Future<int> expectFocusShows(WidgetTester tester, String screen) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final seen = <FocusNode>{};
  for (var i = 0; i < 200; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final node = FocusManager.instance.primaryFocus!;
    if (!seen.add(node)) break;
    expect(FocusManager.instance.highlightMode, FocusHighlightMode.traditional);
    final element = node.context! as Element;
    final box = element.findRenderObject()! as RenderBox;
    final focused = await pixelsOf(tester, box);
    node.unfocus();
    await tester.pumpAndSettle();
    final unfocused = await pixelsOf(tester, box);
    expect(listEquals(focused, unfocused), isFalse, reason: '$screen: ${element.debugGetCreatorChain(8)}');
    node.requestFocus();
    await tester.pumpAndSettle();
  }
  return seen.length;
}

/// The screens of the app with their controls: the lists, a fiche in the
/// pane or in a sheet, About, its dialog; [check] looks at each.
Future<void> visitScreens(WidgetTester tester, void Function(String screen) check) async {
  // expanded: a fiche in the pane, its buttons and rows
  await tester.tap(find.text('Song of Storms').first);
  await tester.pumpAndSettle();
  check('Highlights, a fiche in the pane');
  await goToTab(tester, 'Ong Log');
  await tester.tap(find.text('Lost Woods').first);
  await tester.pumpAndSettle();
  check('Ong Log, a fiche in the pane');
  await goToTab(tester, 'About');
  check('About');
  await tester.ensureVisible(find.widgetWithText(TextButton, 'Clear'));
  await tester.tap(find.widgetWithText(TextButton, 'Clear'));
  await tester.pumpAndSettle();
  check('the dialog of About');
  await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
  await tester.pumpAndSettle();
  await openLicences(tester);
  check('the licences page');
  await tester.tap(licensedRow());
  await tester.pumpAndSettle();
  check('the licences page, a package chosen');
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
  // medium: the rows with their ⋮ buttons, a sheet
  tester.view.physicalSize = const Size(700, 800);
  await goToTab(tester, 'Highlights');
  check('Highlights, medium');
  await tester.tap(detailsButtons().first);
  await tester.pumpAndSettle();
  check('a sheet');
}

void main() {
  // a package for the licences page, which otherwise has none in the tests
  LicenseRegistry.addLicense(() => Stream.value(const LicenseEntryWithLineBreaks([licensedPackage], 'A licence.')));

  group('the desktop look is decided once, from the platform', () {
    test('desktops, and the Windows app', () {
      expect(isDesktopPlatform(TargetPlatform.windows, null), isTrue);
      expect(isDesktopPlatform(TargetPlatform.macOS, null), isTrue);
      expect(isDesktopPlatform(TargetPlatform.linux, null), isTrue);
      const mac = BrowserEnvironment(
        userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.5 Safari/605.1.15',
        maxTouchPoints: 0,
        standalone: false,
      );
      expect(isDesktopPlatform(TargetPlatform.macOS, mac), isTrue);
      const chromebook = BrowserEnvironment(
        userAgent: 'Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 Chrome/157.0.0.0 Safari/537.36',
        maxTouchPoints: 10,
        standalone: false,
      );
      expect(isDesktopPlatform(TargetPlatform.linux, chromebook), isTrue);
    });

    test('phones and tablets, in their apps and their browsers; an iPad that claims to be a Mac', () {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.fuchsia]) {
        expect(isDesktopPlatform(platform, null), isFalse, reason: '$platform');
      }
      const iPadAsMac = BrowserEnvironment(
        userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.5 Safari/605.1.15',
        maxTouchPoints: 5,
        standalone: false,
      );
      // Flutter reports it as iOS with more than two touch points; as macOS with two
      expect(isDesktopPlatform(TargetPlatform.iOS, iPadAsMac), isFalse);
      expect(
        isDesktopPlatform(
          TargetPlatform.macOS,
          const BrowserEnvironment(userAgent: 'Macintosh', maxTouchPoints: 2, standalone: false),
        ),
        isFalse,
      );
    });

    // Flutter's platform for a browser that asks for desktop sites, and what the browser says
    const linuxUa =
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/157.0.0.0 Safari/537.36';
    BrowserEnvironment browser(String ua, String platform, int touch, [String? hints]) => BrowserEnvironment(
      userAgent: ua,
      platform: platform,
      maxTouchPoints: touch,
      clientHintsPlatform: hints,
      standalone: false,
    );

    test('Android asking for desktop sites keeps the phone and tablet look', () {
      // Chrome's "Desktop site": a Linux user agent; the client hints, where there are, still say Android
      expect(isDesktopPlatform(TargetPlatform.linux, browser(linuxUa, 'Linux armv81', 5, 'Android')), isFalse);
      // without client hints (or with Linux in them): a browser built for ARM, on a touch screen
      expect(isDesktopPlatform(TargetPlatform.linux, browser(linuxUa, 'Linux armv81', 5)), isFalse, reason: 'phone');
      expect(isDesktopPlatform(TargetPlatform.linux, browser(linuxUa, 'Linux aarch64', 10, 'Linux')), isFalse);
      // Firefox on Android asking for desktop sites
      expect(
        isDesktopPlatform(
          TargetPlatform.linux,
          browser('Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0', 'Linux armv8l', 5),
        ),
        isFalse,
      );
      // an iPad asking for desktop sites
      expect(
        isDesktopPlatform(
          TargetPlatform.macOS,
          browser('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15', 'MacIntel', 5),
        ),
        isFalse,
      );
    });

    test('computers keep the desktop look, with a touch screen too', () {
      const chromebookUa = 'Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 Chrome/157.0.0.0 Safari/537.36';
      const armChromebookUa =
          'Mozilla/5.0 (X11; CrOS aarch64 15359.0.0) AppleWebKit/537.36 Chrome/157.0.0.0 Safari/537.36';
      final computers = {
        'Chromebook': browser(chromebookUa, 'Linux x86_64', 10, 'Chrome OS'),
        'ARM Chromebook, touch screen': browser(armChromebookUa, 'Linux aarch64', 10, 'Chrome OS'),
        'ARM Chromebook, no client hints': browser(armChromebookUa, 'Linux aarch64', 10),
        'Linux laptop with a touch screen': browser(linuxUa, 'Linux x86_64', 10, 'Linux'),
        'Firefox on Linux': browser(
          'Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0',
          'Linux x86_64',
          0,
        ),
        'Windows laptop with a touch screen': browser(
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/157.0.0.0 Safari/537.36',
          'Win32',
          10,
          'Windows',
        ),
        'ARM Linux computer without touch screen': browser(linuxUa, 'Linux aarch64', 0),
      };
      for (final MapEntry(key: name, value: environment) in computers.entries) {
        final platform = environment.userAgent.contains('Windows') ? TargetPlatform.windows : TargetPlatform.linux;
        expect(isDesktopPlatform(platform, environment), isTrue, reason: name);
      }
    });

    testWidgets('the seam reads the platform', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(desktopLookProvider), isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('the seam reads the platform (Android)', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(desktopLookProvider), isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });

  group('the narrow-window rule of the top bar', () {
    // the widths of the name and of the labels in Roboto Medium (17 and 14 px), rounded up as the bar does
    const roboto = (name: 82.0, labels: [64.0, 53.0, 38.0]);
    ({bool name, double edge, double linksGap, double linkPadding, double scale}) at(
      double width, {
      bool button = true,
    }) => topBarLayout(width: width, nameWidth: roboto.name, labelWidths: roboto.labels, button: button);

    test('the sizes of the design while everything fits', () {
      // 20 + 32 + 10 + 82 + 20 + (64 + 53 + 38 + 8 + 6 × 14) + 40 + 16
      expect(at(467), (name: true, edge: 20.0, linksGap: 20.0, linkPadding: 14.0, scale: 1.0));
      expect(at(466).name, isFalse);
      // without the full screen button (the Windows app), 40 px more for the name
      expect(at(427, button: false).name, isTrue);
      expect(at(426, button: false).name, isFalse);
    });

    test('the name first, then the paddings and the edges, never the picture; nothing cut at 320', () {
      expect(at(375), (name: false, edge: 20.0, linksGap: 20.0, linkPadding: 14.0, scale: 1.0));
      final narrower = at(374);
      expect((narrower.name, narrower.edge, narrower.linksGap, narrower.linkPadding), (false, 16.0, 12.0, 14.0));
      // 16 + 32 + 12 + 163 + 6 × 14 + 40 + 16 = 363
      expect(at(363).linkPadding, 14);
      expect(at(362).linkPadding, lessThan(14));
      final narrowest = at(320);
      expect(narrowest.scale, 1);
      expect(narrowest.linkPadding, greaterThanOrEqualTo(4));
      // what is left: 16 + 32 + 12 + 163 + 6 × padding + 40 + 16 = 320
      expect(16 + 32 + 12 + 163 + 6 * narrowest.linkPadding + 40 + 16, closeTo(320, 0.001));
      // much larger text: the links scale down rather than be cut
      final large = topBarLayout(width: 320, nameWidth: 170, labelWidths: [138, 108, 82], button: true);
      expect(large.scale, lessThan(1));
    });
  });

  group('the top bar', () {
    for (final size in sizes) {
      testWidgets('${size.width.round()} × ${size.height.round()}: the bar and its links, no rail, no bottom bar', (
        tester,
      ) async {
        await pumpDesktop(tester, size);
        expect(tester.getRect(topBar()), Rect.fromLTWH(0, 0, size.width, topBarHeight));
        expect(find.byType(AppNavigationRail), findsNothing);
        expect(find.byType(NavigationBar), findsNothing);
        // the picture at the left, the links after it in order, whole, on one line, the button at the right
        final picture = tester.getRect(find.descendant(of: topBar(), matching: find.byType(Image)));
        expect(picture.size, const Size(32, 32));
        expect(picture.center.dy, 28);
        var end = picture.right;
        for (final label in labels) {
          final text = barText(label);
          final rect = tester.getRect(text);
          expect(rect.left, greaterThanOrEqualTo(end), reason: label);
          expect(rect.top, greaterThanOrEqualTo(0), reason: label);
          expect(rect.bottom, lessThanOrEqualTo(topBarHeight), reason: label);
          final paragraph = tester.renderObject<RenderParagraph>(text);
          expect(paragraph.didExceedMaxLines, isFalse, reason: label);
          expect(paragraph.size.width, greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity)));
          end = rect.right;
        }
        final button = tester.getRect(fullscreenButton());
        expect(button.left, greaterThanOrEqualTo(end));
        expect(button.right, size.width - 16);
        expect(button.center.dy, 28);
        // the name where it fits, never cut (the test font is wider than Roboto)
        final name = barText('Ong Music');
        if (size.width >= 700) expect(name, findsOneWidget);
        if (size.width <= 500) expect(name, findsNothing);
        if (name.evaluate().isNotEmpty) {
          expect(tester.renderObject<RenderParagraph>(name).didExceedMaxLines, isFalse);
          expect(tester.getRect(name).left, picture.right + 10);
          expect(tester.getRect(name).right, lessThanOrEqualTo(tester.getRect(barText('Highlights')).left));
        }
        // the content under the bar, the search field in place of the button
        expect(tester.getRect(pill()).top, greaterThanOrEqualTo(topBarHeight));
        expect(
          find.descendant(of: find.byType(ListSearchField), matching: find.byType(FullscreenButton)),
          findsNothing,
        );
      }, variant: windows);
    }

    for (final size in sizes) {
      testWidgets('${size.width.round()} × ${size.height.round()} without the desktop look: the navigation of today', (
        tester,
      ) async {
        await pumpApp(tester, size: size, fullscreen: FakeFullscreen(), pointer: PointerKind.mouse);
        expect(topBar(), findsNothing);
        final rail = size.width >= WindowMode.mediumMinWidth;
        expect(find.byType(AppNavigationRail), rail ? findsOneWidget : findsNothing);
        expect(find.byType(NavigationBar), rail ? findsNothing : findsOneWidget);
        // the full screen button beside the search field
        expect(
          find.descendant(of: find.byType(ListSearchField), matching: find.byType(FullscreenButton)),
          findsOneWidget,
        );
      }, variant: windows);
    }

    testWidgets('the margins of an expanded window: the list from the left edge, the pane 12 px from the bar', (
      tester,
    ) async {
      await pumpDesktop(tester, const Size(1340, 830));
      // the list pane 520 px wide from the left edge; the field 16 px in, 8 px lower than without the bar
      expect(tester.getRect(pill()), const Rect.fromLTRB(16, 56 + 8 + 6, 520 - 16, 56 + 8 + 6 + 52));
      await tester.tap(find.text('Song of Storms').first);
      await tester.pumpAndSettle();
      final pane = tester.getRect(find.descendant(of: find.byType(DetailPane), matching: find.byType(Material)).first);
      expect(pane, const Rect.fromLTRB(520 + 4, 56 + 12, 1340 - 12, 830 - 12));
    }, variant: windows);

    testWidgets('the sizes of the design: the line, the current link, its underline as wide as its label', (
      tester,
    ) async {
      await pumpDesktop(tester, const Size(1340, 830));
      final scheme = Theme.of(tester.element(topBar())).colorScheme;
      // the picture 20 px from the edge, the name 10 px after it, the first link 20 px after the name
      final picture = tester.getRect(find.descendant(of: topBar(), matching: find.byType(Image)));
      expect(picture.left, 20);
      final name = tester.getRect(barText('Ong Music'));
      expect(tester.getRect(barLink('Highlights')).left, name.right + 20);
      // 14 px of padding around each label, the links 4 px apart
      for (final label in labels) {
        expect(tester.getRect(barLink(label)).width, tester.getRect(barText(label)).width + 28, reason: label);
        expect(tester.getRect(barLink(label)).height, topBarHeight, reason: label);
      }
      expect(tester.getRect(barLink('Ong Log')).left, tester.getRect(barLink('Highlights')).right + 4);
      // the line of the bar
      final line = tester.widget<DecoratedBox>(
        find.descendant(
          of: topBar(),
          matching: find.byWidgetPredicate(
            (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).border != null,
          ),
        ),
      );
      expect((line.decoration as BoxDecoration).border, Border(bottom: BorderSide(color: scheme.outlineVariant)));
      // the current link: in onSurface, its underline 3 px high at the bottom edge, as wide as its label
      expect(underline(tester), findsOneWidget);
      final text = tester.getRect(barText('Highlights'));
      expect(tester.getRect(underline(tester)), Rect.fromLTRB(text.left, 53, text.right, 56));
      expect(labelColor(tester, 'Highlights'), scheme.onSurface);
      expect(labelColor(tester, 'Ong Log'), scheme.onSurfaceVariant);
      // on the page background
      expect(
        tester.widget<Material>(find.descendant(of: topBar(), matching: find.byType(Material)).first).color,
        scheme.surface,
      );
    }, variant: windows);

    testWidgets('the current link is the tab on screen, follows it at once; a tap on a link changes the tab', (
      tester,
    ) async {
      await pumpDesktop(tester, const Size(1340, 830));
      expect(selectedTab(tester), 0);
      await tester.tap(barLink('Ong Log'));
      // in the first frame
      await tester.pump();
      expect(selectedTab(tester), 1);
      final text = tester.getRect(barText('Ong Log'));
      expect(tester.getRect(underline(tester)), Rect.fromLTRB(text.left, 53, text.right, 56));
      await tester.pumpAndSettle();
      expect(find.byType(OngLogPage).hitTestable(), findsOneWidget);
      // a tab chosen another way (the address, Android back)
      ProviderScope.containerOf(tester.element(topBar())).read(selectedTabProvider.notifier).select(AppTab.about);
      await tester.pump();
      final about = tester.getRect(barText('About'));
      expect(tester.getRect(underline(tester)), Rect.fromLTRB(about.left, 53, about.right, 56));
      expect(find.byType(AboutPage).hitTestable(), findsOneWidget);
    }, variant: windows);

    testWidgets('hover and press: the colour of the link in the first frame; nothing moves or changes size', (
      tester,
    ) async {
      await pumpDesktop(tester, const Size(900, 700));
      final scheme = Theme.of(tester.element(topBar())).colorScheme;
      final rects = [for (final label in labels) tester.getRect(barLink(label))];
      final mouse = await mouseAt(tester, const Offset(450, 400));
      await mouse.moveTo(tester.getCenter(barLink('About')));
      await tester.pump();
      expect(labelColor(tester, 'About'), scheme.onSurface);
      expect([for (final label in labels) tester.getRect(barLink(label))], rects);
      await mouse.moveTo(const Offset(450, 400));
      await tester.pump();
      expect(labelColor(tester, 'About'), scheme.onSurfaceVariant);
      // a press dims the label in the first frame, until the release (which makes it the current link)
      await mouse.moveTo(tester.getCenter(barLink('About')));
      await mouse.down(tester.getCenter(barLink('About')));
      await tester.pump();
      expect(labelColor(tester, 'About'), scheme.onSurface.withValues(alpha: scheme.onSurface.a * 0.7));
      expect([for (final label in labels) tester.getRect(barLink(label))], rects);
      await mouse.up();
      await tester.pump();
      expect(labelColor(tester, 'About'), scheme.onSurface);
      expect([for (final label in labels) tester.getRect(barLink(label))], rects);
    }, variant: windows);

    testWidgets('screen readers: a tab bar of three tabs, the current one selected, the picture unsaid', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpDesktop(tester, const Size(900, 700));
      expect(
        tester.getSemantics(barLink('Highlights')),
        isSemantics(label: 'Highlights\nTab 1 of 3', isSelected: true, isButton: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(barLink('About')),
        isSemantics(label: 'About\nTab 3 of 3', isSelected: false, isButton: true, hasTapAction: true),
      );
      expect(
        tester.widget<Image>(find.descendant(of: topBar(), matching: find.byType(Image))).excludeFromSemantics,
        isTrue,
      );
      final tabBar = find.descendant(
        of: topBar(),
        matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.role == SemanticsRole.tabBar),
      );
      final said = <String>[];
      void collect(SemanticsNode node) {
        if (node.label.isNotEmpty) said.add(node.label);
        node.visitChildren((child) {
          collect(child);
          return true;
        });
      }

      collect(tester.getSemantics(tabBar));
      expect(said, ['Highlights\nTab 1 of 3', 'Ong Log\nTab 2 of 3', 'About\nTab 3 of 3']);
      semantics.dispose();
    }, variant: windows);

    testWidgets('the keyboard: the links in order, then the list pane, then the detail pane; Enter and Space', (
      tester,
    ) async {
      await pumpDesktop(tester, const Size(1340, 830));
      await tester.tap(find.text('Song of Storms').first);
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      String where() {
        final context = FocusManager.instance.primaryFocus!.context!;
        bool under(Type type) => _isUnder(context, type);
        if (under(AppTopBar)) {
          final text = find.descendant(of: find.byElementPredicate((e) => e == context), matching: find.byType(Text));
          return text.evaluate().isEmpty ? 'bar' : 'bar ${tester.widget<Text>(text.first).data}';
        }
        if (under(DetailPane)) return 'pane';
        if (under(HighlightsPage)) return 'list';
        return 'elsewhere';
      }

      final stops = <String>[];
      for (var i = 0; i < 40; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final stop = where();
        if (stops.isNotEmpty && stop == stops.first) break;
        stops.add(stop);
      }
      expect(stops.take(4), ['bar Highlights', 'bar Ong Log', 'bar About', 'bar']);
      // each region once, in that order
      final order = <String>[];
      for (final stop in stops) {
        final region = stop.split(' ').first;
        if (order.isEmpty || order.last != region) order.add(region);
      }
      expect(order, ['bar', 'list', 'pane']);
      // Enter and Space on a link; the focus stays on it
      while (where() != 'bar Ong Log') {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selectedTab(tester), 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(where(), 'bar About');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(selectedTab(tester), 2);
    }, variant: windows);

    testWidgets('a sheet in a medium window: centred on the window, under the scrim, clear of the bar', (tester) async {
      await pumpDesktop(tester, const Size(900, 700));
      tester.view.physicalSize = const Size(700, 800);
      await tester.pumpAndSettle();
      await tester.tap(detailsButtons().first);
      await tester.pumpAndSettle();
      final sheet = tester.getRect(
        find.descendant(of: find.byType(BottomSheet), matching: find.byType(Material)).first,
      );
      expect(sheet.center.dx, 350);
      expect(sheet.width, 640);
      expect(sheet.top, greaterThan(topBarHeight));
    }, variant: windows);
  });

  group('the top bar, at the edges', () {
    testWidgets('a sheet in a low window: never over the top bar; nine tenths of the window without the bar', (
      tester,
    ) async {
      Rect sheet() =>
          tester.getRect(find.descendant(of: find.byType(BottomSheet), matching: find.byType(Material)).first);
      Future<void> open() async {
        await tester.ensureVisible(detailsButtons().first);
        await tester.pumpAndSettle();
        await tester.tap(detailsButtons().first);
        await tester.pumpAndSettle();
      }

      // a window low enough for the fiche to take all the height the sheet may have
      await pumpDesktop(tester, const Size(700, 300));
      await open();
      expect(sheet().top, topBarHeight);
      // the same sheet in the phone and tablet look: as high as its fiche, up to nine tenths of the window
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, size: const Size(700, 300), pointer: PointerKind.mouse);
      await open();
      expect(sheet().top, lessThan(topBarHeight));
      expect(sheet().top, greaterThanOrEqualTo(30));
    }, variant: windows);

    testWidgets('real links of the page: the address of each tab under the mouse; still a tab, not a link', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpApp(
        tester,
        size: const Size(1340, 830),
        desktop: true,
        fullscreen: FakeFullscreen(),
        pointer: PointerKind.mouse,
        links: FakeLinkAnchors(),
      );
      final mouse = await mouseAt(tester, const Offset(700, 500));
      for (final (label, address) in [('Highlights', '/'), ('Ong Log', '/log'), ('About', '/about')]) {
        await mouse.moveTo(tester.getCenter(barLink(label)));
        await tester.pump(linkAnchorDelay);
        await tester.pump();
        final anchor = find.descendant(of: topBar(), matching: find.byType(FakeAnchor));
        expect(anchor, findsOneWidget, reason: label);
        // the page's own address, at the tab's place
        final uri = tester.widget<FakeAnchor>(anchor).uri;
        expect((uri.removeFragment(), uri.fragment), (Uri.base.removeFragment(), address), reason: label);
        // exactly over the link
        expect(tester.getRect(anchor), tester.getRect(barLink(label)), reason: label);
      }
      // for screen readers, the current link stays a selected tab, the others tabs
      for (final label in labels) {
        final data = tester.getSemantics(barLink(label)).getSemanticsData();
        expect(data.role, SemanticsRole.tab, reason: label);
        expect(data.flagsCollection.isLink, isFalse, reason: label);
        expect(data.flagsCollection.isSelected, label == 'Highlights' ? ui.Tristate.isTrue : ui.Tristate.isFalse);
      }
      semantics.dispose();
    }, variant: windows);

    testWidgets('large text: the labels and the name grow as those of the rail do, no more', (tester) async {
      for (final size in const [Size(1340, 830), Size(320, 700)]) {
        await pumpApp(
          tester,
          size: size,
          textScale: 3,
          desktop: true,
          fullscreen: FakeFullscreen(),
          pointer: PointerKind.mouse,
        );
        expect(tester.takeException(), isNull, reason: '$size');
        for (final text in [...labels, if (size.width > 1000) 'Ong Music']) {
          final scaler = MediaQuery.textScalerOf(tester.element(barText(text)));
          expect(scaler.scale(14), 14 * maxRailLabelTextScale, reason: '$size $text');
          expect(tester.getRect(barText(text)).top, greaterThanOrEqualTo(0), reason: '$size $text');
        }
        // the line under the current link, under its label
        expect(tester.getRect(barText('Highlights')).bottom, lessThanOrEqualTo(tester.getRect(underline(tester)).top));
      }
    }, variant: windows);

    testWidgets('very low windows: no overflow where the rail has none; the filters give way under the bar', (
      tester,
    ) async {
      for (final size in const [Size(1340, 120), Size(900, 120), Size(600, 120), Size(320, 200)]) {
        // what the phone and tablet look handles
        await pumpApp(tester, size: size, fullscreen: FakeFullscreen(), pointer: PointerKind.mouse);
        expect(tester.takeException(), isNull, reason: 'rail or bar, $size');
        await pumpDesktop(tester, size);
        expect(tester.takeException(), isNull, reason: 'desktop, $size');
        expect(pill(), findsOneWidget, reason: '$size');
        // below the bar, less than the search field, the chips and the 4 px under them
        expect(
          find.byType(ChipRow).hitTestable(),
          size.height - topBarHeight < listHeadHeight ? findsNothing : findsOneWidget,
        );
      }
      // the filters come back when there is room
      await pumpDesktop(tester, const Size(1340, 56 + listHeadHeight));
      expect(tester.takeException(), isNull);
      expect(find.byType(ChipRow).hitTestable(), findsOneWidget);
    }, variant: windows);

    testWidgets('the keyboard focus shows on every control of every screen', (tester) async {
      await pumpDesktop(tester, const Size(1340, 830));
      await tester.tap(find.text('Song of Storms').first);
      await tester.pumpAndSettle();
      var stops = await expectFocusShows(tester, 'Highlights, a fiche in the pane');
      await goToTab(tester, 'Ong Log');
      await tester.tap(find.text('Lost Woods').first);
      await tester.pumpAndSettle();
      stops += await expectFocusShows(tester, 'Ong Log, a fiche in the pane');
      await goToTab(tester, 'About');
      // the segments of the theme selector among them
      stops += await expectFocusShows(tester, 'About');
      await openLicences(tester);
      stops += await expectFocusShows(tester, 'the licences page');
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(700, 800);
      await goToTab(tester, 'Highlights');
      await tester.tap(detailsButtons().first);
      await tester.pumpAndSettle();
      stops += await expectFocusShows(tester, 'a sheet');
      expect(stops, greaterThan(60));
    }, variant: windows);

    testWidgets('the licences page: the hover of a row in the first frame, the chosen package in its colour', (
      tester,
    ) async {
      await pumpDesktop(tester, const Size(1340, 830));
      await goToTab(tester, 'About');
      await openLicences(tester);
      final row = licensedRow();
      final layer = find.byType(InstantTileHover);
      CustomPainter? hover() => tester
          .widget<CustomPaint>(find.descendant(of: layer, matching: find.byType(CustomPaint)).first)
          .foregroundPainter;
      final mouse = await mouseAt(tester, const Offset(1300, 800));
      expect(hover(), isNull);
      await mouse.moveTo(tester.getCenter(row));
      await tester.pump();
      // the hover colour of the theme, at once, over the whole row; the row's own hover (which fades in) none
      final recorder = _RectCanvas();
      hover()!.paint(recorder, tester.getSize(layer));
      final theme = Theme.of(tester.element(layer));
      expect(recorder.rect, tester.getRect(row).shift(-tester.getTopLeft(layer)));
      expect(recorder.color, isSameColorAs(theme.hoverColor));
      expect(Theme.of(tester.element(row)).hoverColor.a, 0);
      await mouse.moveTo(const Offset(1300, 800));
      await tester.pump();
      expect(hover(), isNull);
      // chosen: the colour Material gives it, which the desktop theme's transparent highlight no longer is
      await tester.tap(row);
      await tester.pumpAndSettle();
      final chosen = tester.widget<ListTile>(row);
      expect(chosen.selected, isTrue);
      final ink = tester.widget<Ink>(find.descendant(of: row, matching: find.byType(Ink)).first);
      expect((ink.decoration! as ShapeDecoration).color!.a, greaterThan(0));
    }, variant: windows);
  });

  group('no ripple, instant feedback', () {
    testWidgets('desktop: no ripple anywhere, no highlight fading in or out', (tester) async {
      await pumpDesktop(tester, const Size(1340, 830));
      final seen = <String>{};
      await visitScreens(tester, (screen) {
        for (final ink in inkOf(tester)) {
          seen.add(ink.widget.split(' ').first);
          expect(
            ink.splash,
            anyOf(same(NoSplash.splashFactory), same(InstantInk.splashFactory)),
            reason: '$screen: ${ink.widget}',
          );
          expect(ink.pressed.a, 0, reason: '$screen: ${ink.widget}');
          expect(ink.hovered.a == 0 || ink.hover == Duration.zero, isTrue, reason: '$screen: ${ink.widget}');
        }
      });
      // the buttons, the chips, the segments, the ink wells of the app
      expect(seen, containsAll(['IconButton', 'InkWell']));
    }, variant: windows);

    testWidgets('phones and tablets: the ripples and the highlights of today', (tester) async {
      await pumpApp(tester, size: const Size(1340, 830), pointer: PointerKind.mouse);
      final ripple = ThemeData(useMaterial3: true).splashFactory;
      await visitScreens(tester, (screen) {
        for (final ink in inkOf(tester)) {
          // the destinations of the rail and the bar draw their own indicator, as they always did
          if (ink.widget.contains('_RailDestination') || ink.widget.contains('NavigationDestination')) continue;
          expect(ink.splash, same(ripple), reason: '$screen: ${ink.widget}');
          expect(ink.pressed.a, greaterThan(0), reason: '$screen: ${ink.widget}');
        }
      });
    }, variant: windows);

    testWidgets('a row: the hover tint in the first frame, the press tint in the next one, gone at release', (
      tester,
    ) async {
      await pumpDesktop(tester, const Size(1340, 830));
      final theme = Theme.of(tester.element(topBar()));
      final title = find.text('Song of Storms').first;
      final mouse = await mouseAt(tester, const Offset(260, 800));
      expect(layerColor(tester, title), isNull);
      await mouse.moveTo(tester.getCenter(title));
      await tester.pump();
      final hover = hoveredRowColor(tester.element(title));
      expect(layerColor(tester, title), isSameColorAs(hover));
      await mouse.down(tester.getCenter(title));
      await tester.pump();
      expect(
        layerColor(tester, title),
        isSameColorAs(Color.alphaBlend(theme.colorScheme.onSurface.withValues(alpha: pressStateOpacity), hover)),
      );
      await mouse.up();
      await tester.pump();
      expect(layerColor(tester, title), isSameColorAs(hover));
    }, variant: windows);

    testWidgets('a hover only repaints the row: nothing is built again, no frame after it', (tester) async {
      await pumpDesktop(tester, const Size(1340, 830));
      final title = find.text('I Will Survive').first;
      final layer = find.ancestor(of: title, matching: find.byType(StateLayer)).first;
      final paint = tester.renderObject<RenderCustomPaint>(
        find.descendant(of: layer, matching: find.byType(CustomPaint)).first,
      );
      final mouse = await mouseAt(tester, const Offset(260, 800));
      await mouse.moveTo(tester.getCenter(title));
      // the hover reached the row: its layer is to be painted again, not built again
      expect(paint.debugNeedsPaint, isTrue);
      final element = tester.element(layer);
      expect(element.dirty, isFalse);
      element.visitChildElements((child) => expect(child.dirty, isFalse));
      await tester.pump();
      expect(layerColor(tester, title), isSameColorAs(hoveredRowColor(tester.element(title))));
      // and no animation of an invisible highlight after it
      expect(tester.binding.hasScheduledFrame, isFalse);
      await mouse.moveTo(const Offset(260, 800));
      await tester.pump();
      expect(layerColor(tester, title), isNull);
      expect(tester.binding.hasScheduledFrame, isFalse);
    }, variant: windows);

    testWidgets('a press and a release: no frame after their own (no invisible highlight to fade)', (tester) async {
      await pumpDesktop(tester, const Size(1340, 830));
      final title = find.text('I Will Survive').first;
      // the row already chosen: its tap changes nothing else
      await tester.tap(title);
      await tester.pumpAndSettle();
      final mouse = await mouseAt(tester, tester.getCenter(title));
      await tester.pumpAndSettle();
      await mouse.down(tester.getCenter(title));
      await tester.pump();
      expect(layerColor(tester, title)!.a, greaterThan(hoveredRowColor(tester.element(title)).a));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await mouse.up();
      await tester.pump();
      expect(layerColor(tester, title), isSameColorAs(hoveredRowColor(tester.element(title))));
      expect(tester.binding.hasScheduledFrame, isFalse);
    }, variant: windows);

    testWidgets('the control of the desktop look without ink: Enter, Space and a screen reader activate it', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final app = await pumpDesktop(tester, const Size(1340, 830));
      // a screen reader's tap on a row chooses it
      final storms = find.text('Song of Storms').first;
      final row = find.ancestor(of: storms, matching: find.byType(HighlightRow)).first;
      expect(tester.getSemantics(row), isSemantics(hasTapAction: true, isSelected: false, isFocusable: true));
      final id = tester.getSemantics(row).id;
      tester.semantics.tap(find.semantics.byPredicate((node) => node.id == id));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(row), isSemantics(hasTapAction: true, isSelected: true, isFocusable: true));
      // Enter and Space on a tile of About, as on an ink well
      await goToTab(tester, 'About');
      final youTube = find.text('YouTube');
      await tester.ensureVisible(youTube);
      await tester.pumpAndSettle();
      for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
        Focus.of(tester.element(youTube)).requestFocus();
        await tester.pump();
        final opened = app.effects.opened.length;
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(app.effects.opened, hasLength(opened + 1), reason: '$key');
      }
      semantics.dispose();
    }, variant: windows);

    testWidgets('a disabled inner control leaves the press to the control around it', (tester) async {
      final outer = ValueNotifier<Set<WidgetState>>({});
      final inner = ValueNotifier<Set<WidgetState>>({WidgetState.disabled});
      addTearDown(outer.dispose);
      addTearDown(inner.dispose);
      const press = Color(0x33000000);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: StateLayer(
              states: outer,
              hover: Colors.transparent,
              focus: Colors.transparent,
              press: press,
              child: SizedBox.square(
                dimension: 200,
                child: Center(
                  child: StateLayer(
                    key: const Key('inner'),
                    states: inner,
                    hover: Colors.transparent,
                    focus: Colors.transparent,
                    press: press,
                    child: const SizedBox.square(dimension: 50),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: tester.getCenter(find.byKey(const Key('inner'))));
      await gesture.down(tester.getCenter(find.byKey(const Key('inner'))));
      await tester.pump();
      expect(layerColor(tester, find.byKey(const Key('inner'))), isSameColorAs(press));
      // (the layer around the inner one is the outer one)
      final inside = find.descendant(of: find.byKey(const Key('inner')), matching: find.byType(SizedBox));
      expect(layerColor(tester, inside), isNull);
      await gesture.up();
      await tester.pump();
      expect(layerColor(tester, find.byKey(const Key('inner'))), isNull);
    });

    testWidgets('a press an inner control takes never tints the control around it, until the pointer is up', (
      tester,
    ) async {
      /// Presses [inner] with [kind], and expects [outer] to show no press, at once and when the gesture arena
      /// gives up waiting (100 ms), while [inner] shows its own (with a mouse, at once).
      Future<void> expectInnerPress(
        Finder inner,
        Finder outer,
        PointerDeviceKind kind,
        String what, {
        bool innerLayer = true,
      }) async {
        Color? press(Finder finder) => layerColor(tester, finder);
        final gesture = await tester.createGesture(kind: kind);
        if (kind == PointerDeviceKind.mouse) {
          await gesture.addPointer(location: tester.getCenter(inner));
          await tester.pump();
        }
        final outerBefore = press(outer);
        final innerBefore = press(inner);
        await gesture.down(tester.getCenter(inner));
        await tester.pump();
        expect(press(outer), outerBefore, reason: '$what, $kind, at once');
        if (innerLayer && kind == PointerDeviceKind.mouse) {
          expect(press(inner), isNot(innerBefore), reason: '$what: its own press');
        }
        await tester.pump(const Duration(milliseconds: 150));
        expect(press(outer), outerBefore, reason: '$what, $kind, after the arena');
        if (innerLayer) expect(press(inner), isNot(innerBefore), reason: '$what, $kind: its own press after the arena');
        // away from the inner control: no tap, nothing opens
        await gesture.moveBy(const Offset(0, 300));
        await gesture.up();
        await tester.pumpAndSettle();
        if (kind == PointerDeviceKind.mouse) await gesture.removePointer();
        await tester.pump();
      }

      // the thumbnail of a row (expanded, with a mouse): not a state layer, it takes the press for itself
      await pumpDesktop(tester, const Size(1340, 830));
      final storms = find.ancestor(of: find.text('Song of Storms').first, matching: find.byType(HighlightRow)).first;
      final thumbnail = find.descendant(of: storms, matching: find.byType(Thumbnail)).first;
      await expectInnerPress(
        thumbnail,
        find.text('Song of Storms').first,
        PointerDeviceKind.mouse,
        'thumbnail',
        innerLayer: false,
      );
      // the video button of a play of the Ong Log
      await goToTab(tester, 'Ong Log');
      final pill = find.byType(VideoPill).first;
      final play = find.ancestor(of: pill, matching: find.byType(PlayRow)).first;
      final playText = find.descendant(of: play, matching: find.byType(Text)).first;
      for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
        await expectInnerPress(find.descendant(of: pill, matching: find.byType(Icon)), playText, kind, 'video button');
      }
      // the text and the clear button of a search field
      await goToTab(tester, 'Highlights');
      final field = find.byType(TextField).hitTestable().first;
      await expectInnerPress(
        field,
        find.byIcon(Icons.search).hitTestable(),
        PointerDeviceKind.mouse,
        'search text',
        innerLayer: false,
      );
      await tester.enterText(field, 'zelda');
      await tester.pumpAndSettle();
      final clear = find.byIcon(Icons.close).hitTestable();
      // (released away from it: the query stays)
      await expectInnerPress(clear, find.byIcon(Icons.search).hitTestable(), PointerDeviceKind.mouse, 'clear button');
      // the details button of a row (medium window)
      tester.view.physicalSize = const Size(700, 800);
      await tester.enterText(field, '');
      await tester.pumpAndSettle();
      final row = find.ancestor(of: find.text('Song of Storms').first, matching: find.byType(HighlightRow)).first;
      final more = find.descendant(of: row, matching: find.byIcon(Icons.more_vert));
      for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
        await expectInnerPress(more, find.text('Song of Storms').first, kind, 'details button');
      }
    }, variant: windows);

    testWidgets('the focus tint for the keyboard only: none for a control focused after a touch', (tester) async {
      await pumpDesktop(tester, const Size(1340, 830));
      final title = find.text('I Will Survive').first;
      // a touch: the focus no longer shows (as Material's focus highlight)
      await tester.tapAt(const Offset(1300, 820));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.highlightMode, FocusHighlightMode.touch);
      final layer = find.ancestor(of: title, matching: find.byType(StateLayer)).first;
      Focus.of(tester.element(layer)).requestFocus();
      await tester.pump();
      expect(Focus.of(tester.element(layer)).hasPrimaryFocus, isTrue);
      expect(layerColor(tester, title), isNull);
      // a key: the same focus shows, at once
      await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(FocusManager.instance.highlightMode, FocusHighlightMode.traditional);
      expect(layerColor(tester, title), isSameColorAs(Theme.of(tester.element(title)).focusColor));
      // the segments of the theme selector: the same rule, in their colour
      await goToTab(tester, 'About');
      final light = find.ancestor(of: find.text('Light'), matching: find.byType(TextButton)).first;
      Color? segment() =>
          tester.widget<Material>(find.descendant(of: light, matching: find.byType(Material)).first).color;
      await tester.tapAt(const Offset(1300, 820));
      await tester.pumpAndSettle();
      final unfocused = segment();
      Focus.of(tester.element(find.text('Light'))).requestFocus();
      await tester.pumpAndSettle();
      expect(FocusManager.instance.highlightMode, FocusHighlightMode.touch);
      expect(segment(), unfocused);
      // moved onto it by the keyboard: shown
      Focus.of(tester.element(find.text('System'))).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(Focus.of(tester.element(find.text('Light'))).hasPrimaryFocus, isTrue);
      expect(segment(), isNot(unfocused));
    }, variant: windows);

    testWidgets('a button on a row: its own press in the first frame, not the row', (tester) async {
      await pumpDesktop(tester, const Size(700, 800));
      final title = find.text('Song of Storms').first;
      final more = find.descendant(
        of: find.ancestor(of: title, matching: find.byType(HighlightRow)),
        matching: find.byIcon(Icons.more_vert),
      );
      final mouse = await mouseAt(tester, tester.getCenter(more));
      final hovered = layerColor(tester, more);
      final layer = find.ancestor(of: more, matching: find.byType(StateLayer)).first;
      final paint = tester.renderObject<RenderCustomPaint>(
        find.descendant(of: layer, matching: find.byType(CustomPaint)).first,
      );
      expect(paint.debugNeedsPaint, isFalse);
      await mouse.down(tester.getCenter(more));
      // the press itself asks for the layer to be painted again, before the tap gesture knows of it
      expect(paint.debugNeedsPaint, isTrue);
      expect(tester.element(layer).dirty, isFalse);
      await tester.pump();
      expect(layerColor(tester, more), isNot(hovered));
      expect(layerColor(tester, more)!.a, greaterThan(0));
      // the row under it is not pressed: only hovered
      expect(layerColor(tester, title), isSameColorAs(Theme.of(tester.element(title)).hoverColor));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
    }, variant: windows);

    testWidgets('a button: the press tint in the first frame (Watch on YouTube, in the brand colour)', (tester) async {
      await pumpDesktop(tester, const Size(1340, 830));
      await tester.tap(find.text('Song of Storms').first);
      await tester.pumpAndSettle();
      final watch = find.text('Watch on YouTube');
      final mouse = await mouseAt(tester, tester.getCenter(watch));
      final ong = OngColors.of(tester.element(watch));
      expect(layerColor(tester, watch), isSameColorAs(ong.onBrand.withValues(alpha: hoverStateOpacity)));
      await mouse.down(tester.getCenter(watch));
      await tester.pump();
      expect(
        layerColor(tester, watch),
        isSameColorAs(
          Color.alphaBlend(
            ong.onBrand.withValues(alpha: pressStateOpacity),
            ong.onBrand.withValues(alpha: hoverStateOpacity),
          ),
        ),
      );
      await mouse.up();
      await tester.pump();
    }, variant: windows);

    testWidgets('a chip: the hover tint in the first frame, a flat press tint in the next one, selected at once', (
      tester,
    ) async {
      await pumpDesktop(tester, const Size(700, 800));
      final scheme = Theme.of(tester.element(topBar())).colorScheme;
      Color? colorOf(String label) =>
          (tester.widget<Ink>(find.descendant(of: chip(label), matching: find.byType(Ink))).decoration!
                  as ShapeDecoration)
              .color;
      final ink = Material.of(tester.element(find.descendant(of: chip('Game OST'), matching: find.byType(InkWell))));
      final hover = scheme.onSurface.withValues(alpha: hoverStateOpacity);
      final mouse = await mouseAt(tester, const Offset(350, 790));
      await mouse.moveTo(tester.getCenter(chip('Game OST')));
      await tester.pump();
      expect(colorOf('Game OST'), isSameColorAs(hover));
      await mouse.down(tester.getCenter(chip('Game OST')));
      await tester.pump();
      final press = scheme.onSurface.withValues(alpha: pressStateOpacity);
      expect(ink as RenderObject, paintsPathOf(press));
      await mouse.up();
      await tester.pump();
      expect(ink as RenderObject, isNot(paintsPathOf(press)));
      // selected in that same frame
      expect(colorOf('Game OST'), isSameColorAs(Color.alphaBlend(hover, scheme.secondaryContainer)));
      expect(colorOf('All'), isSameColorAs(Colors.transparent));
    }, variant: windows);

    testWidgets('the selected row of the list changes in one frame', (tester) async {
      await pumpDesktop(tester, const Size(1340, 830));
      final title = find.text('I Will Survive').first;
      await tester.tap(title);
      await tester.pump();
      final row = find.ancestor(of: title, matching: find.byType(HighlightRow));
      final tint = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: row,
              matching: find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration is ShapeDecoration),
            )
            .first,
      );
      expect((tint.decoration as ShapeDecoration).color, selectedRowColor(tester.element(title)));
    }, variant: windows);
  });
}

bool _isUnder(BuildContext context, Type type) {
  var found = false;
  context.visitAncestorElements((element) {
    if (element.widget.runtimeType == type) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}
