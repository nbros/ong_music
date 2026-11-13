/// What the layout adapts to: the window mode (from the size of the window)
/// and the pointer (from the latest pointer event), both followed live, and
/// the look of the platform (desktop, or phone and tablet), decided once.
///
/// Neither the window mode nor the pointer is derived from the platform once
/// and for all: a window is resized, a phone turned, a mouse plugged into a
/// tablet, a touch screen laptop touched. The look is: a computer keeps the
/// look of a computer in a narrow window or under a finger, a tablet keeps the
/// look of a tablet with a mouse. [AppLayout] (above the navigator, so the
/// sheets see it too) gives all three to the whole UI.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../web/install_hint.dart';
import '../web/web_platform.dart';

/// The layout of the window, from its logical size.
enum WindowMode {
  /// Narrower than [mediumMinWidth]: the phone layout, bottom navigation bar.
  compact,

  /// Navigation rail, one column, details in a bottom sheet: up to
  /// [expandedMinWidth], or any window lower than [expandedMinHeight] (a phone
  /// held sideways).
  medium,

  /// Navigation rail and room for a list and a detail pane side by side.
  expanded;

  /// Windows at least this wide have a navigation rail.
  static const double mediumMinWidth = 600;

  /// Windows at least this wide, and at least [expandedMinHeight] high, are
  /// [expanded].
  static const double expandedMinWidth = 840;

  /// Lower windows stay [medium] whatever their width.
  static const double expandedMinHeight = 480;

  /// The mode of a window of [size].
  static WindowMode of(Size size) {
    if (size.width < mediumMinWidth) return compact;
    if (size.width < expandedMinWidth || size.height < expandedMinHeight) return medium;
    return expanded;
  }

  /// Whether the navigation is a rail on the left instead of a bar at the
  /// bottom, in the phone and tablet look (the desktop look has a bar at the
  /// top in every mode, see [AppNavigation]).
  bool get hasRail => this != compact;
}

/// Where the navigation between the three tabs is.
enum AppNavigation {
  /// The phone and tablet look in a [WindowMode.compact] window.
  bottomBar,

  /// The phone and tablet look in a [WindowMode.medium] or
  /// [WindowMode.expanded] window.
  rail,

  /// The desktop look, in a window of any size: text links in a bar across
  /// the top of the window.
  topBar,
}

/// Whether [platform] gets the desktop look: the browsers of macOS, Windows,
/// Linux and ChromeOS (which Flutter reports as Linux), and the Windows app.
/// Android and iOS keep the phone and tablet look in their apps and in their
/// browsers, installed or not, whatever the size of the device.
///
/// [browser] (null outside a browser) tells the tablets and phones whose
/// browser asks for desktop sites, which Flutter reports as computers: an
/// iPad that claims to be a Mac (Flutter already reports it as iOS when it has
/// more than two touch points, [isIPad] from more than one), an Android device
/// that claims to be a Linux computer ([isAndroid]).
bool isDesktopPlatform(TargetPlatform platform, BrowserEnvironment? browser) => switch (platform) {
  TargetPlatform.windows ||
  TargetPlatform.macOS ||
  TargetPlatform.linux => browser == null || !(isIPad(browser) || isAndroid(browser)),
  TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => false,
};

/// Whether the app has the desktop look: a top bar of text links instead of
/// the rail and the bottom bar, no ink ripple, hover and press states shown at
/// once. Decided once, from the platform (see [isDesktopPlatform]): not from
/// the size of the window, nor from the pointer. Overridden in tests.
final desktopLookProvider = Provider<bool>((ref) => isDesktopPlatform(defaultTargetPlatform, currentBrowser()));

/// What the user points with.
///
/// [mouse] (a trackpad too) brings what only makes sense with a pointer that
/// hovers and does not cover what it points at: scroll bars always shown, in a
/// lane of their own, the `/` hint of the search fields, arrows at the ends of
/// the chip rows, hover states. [touch] (a stylus too) brings none of them.
/// Tap targets and density do not depend on it.
enum PointerKind {
  mouse,
  touch;

  /// The pointer of [kind] of device, or null when it says nothing.
  static PointerKind? ofDevice(PointerDeviceKind kind) => switch (kind) {
    PointerDeviceKind.mouse || PointerDeviceKind.trackpad => mouse,
    PointerDeviceKind.touch || PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus => touch,
    PointerDeviceKind.unknown => null,
  };

  /// The guess before any pointer event: a mouse on desktop platforms (the
  /// Windows app, desktop browsers), touch on phones and tablets, in their
  /// browsers too.
  static PointerKind get guess => switch (defaultTargetPlatform) {
    TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux => mouse,
    TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => touch,
  };
}

/// The pointer before any pointer event (see [PointerKind.guess]).
final initialPointerProvider = Provider<PointerKind>((ref) => PointerKind.guess);

/// The pointer of the latest pointer event.
final pointerProvider = NotifierProvider<PointerNotifier, PointerKind>(PointerNotifier.new);

/// Holds the [PointerKind] of the latest pointer event; tests replace it with
/// one that ignores the events, to keep a pointer whatever they tap with.
class PointerNotifier extends Notifier<PointerKind> {
  @override
  PointerKind build() => ref.watch(initialPointerProvider);

  /// A pointer event of [kind] of device came.
  void saw(PointerDeviceKind kind) {
    final pointer = PointerKind.ofDevice(kind);
    if (pointer != null && pointer != state) state = pointer;
  }
}

/// Width of the navigation rail, without the safe area on its left.
const double railWidth = 80;

/// Width of the lane of an always-visible scroll bar: the scrolled content
/// ends this far from the right edge, so that nothing lies under the bar.
const double scrollbarLane = 12;

/// Gives the window mode and the pointer to the whole UI, and follows the
/// pointer events of the whole window to keep the pointer up to date.
///
/// Placed above the navigator (`MaterialApp.builder`): sheets and dialogs are
/// under it too.
class AppLayout extends ConsumerWidget {
  const AppLayout({super.key, required this.child});

  final Widget child;

  /// The mode of the window of [context] (from its media query without an
  /// [AppLayout] above).
  static WindowMode modeOf(BuildContext context) =>
      InheritedModel.inheritFrom<_LayoutScope>(context, aspect: _Aspect.mode)?.mode ??
      WindowMode.of(MediaQuery.sizeOf(context));

  /// [modeOf] without making [context] depend on it: for event handlers.
  static WindowMode readModeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_LayoutScope>()?.mode ??
      WindowMode.of(MediaQuery.maybeSizeOf(context) ?? Size.zero);

  /// Whether the app has the desktop look (see [desktopLookProvider]); false
  /// without an [AppLayout] above.
  static bool desktopOf(BuildContext context) =>
      InheritedModel.inheritFrom<_LayoutScope>(context, aspect: _Aspect.desktop)?.desktop ?? false;

  /// Where the navigation is in the window of [context].
  static AppNavigation navigationOf(BuildContext context) => desktopOf(context)
      ? AppNavigation.topBar
      : (modeOf(context).hasRail ? AppNavigation.rail : AppNavigation.bottomBar);

  /// The pointer ([PointerKind.guess] without an [AppLayout] above).
  static PointerKind pointerOf(BuildContext context) =>
      InheritedModel.inheritFrom<_LayoutScope>(context, aspect: _Aspect.pointer)?.pointer ?? PointerKind.guess;

  /// Whether the pointer is a mouse.
  static bool mouseOf(BuildContext context) => pointerOf(context) == PointerKind.mouse;

  /// How far from the left edge of the window the content begins: the rail
  /// and the safe area on its left (a phone held sideways with its camera on
  /// that side), or nothing without a rail (a bottom bar, or the top bar of
  /// the desktop look).
  static double contentLeftOf(BuildContext context) =>
      navigationOf(context) == AppNavigation.rail ? MediaQuery.paddingOf(context).left + railWidth : 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(pointerProvider.notifier);
    return Listener(
      // translucent: hears the events that reach anything in the window, empty space included
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => notifier.saw(event.kind),
      onPointerHover: (event) => notifier.saw(event.kind),
      onPointerSignal: (event) => notifier.saw(event.kind),
      onPointerPanZoomStart: (event) => notifier.saw(event.kind),
      child: _LayoutScope(
        mode: WindowMode.of(MediaQuery.sizeOf(context)),
        pointer: ref.watch(pointerProvider),
        desktop: ref.watch(desktopLookProvider),
        child: child,
      ),
    );
  }
}

enum _Aspect { mode, pointer, desktop }

class _LayoutScope extends InheritedModel<_Aspect> {
  const _LayoutScope({required this.mode, required this.pointer, required this.desktop, required super.child});

  final WindowMode mode;
  final PointerKind pointer;
  final bool desktop;

  @override
  bool updateShouldNotify(_LayoutScope oldWidget) =>
      mode != oldWidget.mode || pointer != oldWidget.pointer || desktop != oldWidget.desktop;

  @override
  bool updateShouldNotifyDependent(_LayoutScope oldWidget, Set<_Aspect> dependencies) =>
      (dependencies.contains(_Aspect.mode) && mode != oldWidget.mode) ||
      (dependencies.contains(_Aspect.pointer) && pointer != oldWidget.pointer) ||
      (dependencies.contains(_Aspect.desktop) && desktop != oldWidget.desktop);
}
