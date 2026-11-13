/// What the layout adapts to: the window mode (from the size of the window)
/// and the pointer (from the latest pointer event), both followed live.
///
/// Neither is derived from the platform once and for all: a window is resized,
/// a phone turned, a mouse plugged into a tablet, a touch screen laptop
/// touched. [AppLayout] (above the navigator, so the sheets see it too) gives
/// both to the whole UI.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

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

  /// Whether the navigation is a rail on the left instead of a bar at the bottom.
  bool get hasRail => this != compact;
}

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

  /// The pointer ([PointerKind.guess] without an [AppLayout] above).
  static PointerKind pointerOf(BuildContext context) =>
      InheritedModel.inheritFrom<_LayoutScope>(context, aspect: _Aspect.pointer)?.pointer ?? PointerKind.guess;

  /// Whether the pointer is a mouse.
  static bool mouseOf(BuildContext context) => pointerOf(context) == PointerKind.mouse;

  /// How far from the left edge of the window the content begins: the rail
  /// and the safe area on its left (a phone held sideways with its camera on
  /// that side), or nothing in [WindowMode.compact].
  static double contentLeftOf(BuildContext context) =>
      modeOf(context).hasRail ? MediaQuery.paddingOf(context).left + railWidth : 0;

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
        child: child,
      ),
    );
  }
}

enum _Aspect { mode, pointer }

class _LayoutScope extends InheritedModel<_Aspect> {
  const _LayoutScope({required this.mode, required this.pointer, required super.child});

  final WindowMode mode;
  final PointerKind pointer;

  @override
  bool updateShouldNotify(_LayoutScope oldWidget) => mode != oldWidget.mode || pointer != oldWidget.pointer;

  @override
  bool updateShouldNotifyDependent(_LayoutScope oldWidget, Set<_Aspect> dependencies) =>
      (dependencies.contains(_Aspect.mode) && mode != oldWidget.mode) ||
      (dependencies.contains(_Aspect.pointer) && pointer != oldWidget.pointer);
}
