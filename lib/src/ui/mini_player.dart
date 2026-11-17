/// The mini player of the web app: the video playing inside the app, over
/// every page, while the preview of its fiche is not on screen (another
/// fiche, the sheet closed, another tab). It is moved by its title and
/// resized by its corner, and keeps its place and size from one visit to the
/// next.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state/catalogue_state.dart';
import '../state/settings_state.dart';
import '../web/embedded_video.dart';
import 'layout.dart';
import 'sheets.dart';
import 'video_preview.dart';
import 'view_state.dart';

// The words of the mini player: the tooltips of its buttons, which screen readers say too.

/// The button that stops the video.
const String closeVideoText = 'Close';

/// The button that shows the fiche of the video again (the video then plays in it).
const String showVideoDetailsText = 'Show details';

/// The distance of the mini player to the right and bottom edges of its room,
/// where it first appears.
const double miniPlayerMargin = 16;

/// The closest the mini player comes to the edges of its room.
const double miniPlayerEdge = 8;

/// The width of the mini player where it first appears, in a window wide
/// enough.
const double miniPlayerWidth = 320;

/// The narrowest the mini player is resized, in a room wide enough.
const double miniPlayerMinWidth = 200;

/// The height of the bar over the video: the title, by which it is moved, the
/// corner by which it is resized, the buttons.
const double miniPlayerBarHeight = 40;

/// Where the mini player is in its room: its distances to the right and bottom
/// edges, and its width (the height follows: the bar, and the video in 16:9).
/// Taken from the bottom right corner, where it first appears: it stays there
/// when the window is resized.
typedef MiniPlayerPlace = ({double right, double bottom, double width});

/// Where the user put the mini player; null until they move or resize it.
final miniPlayerPlaceProvider = NotifierProvider<MiniPlayerPlaceNotifier, MiniPlayerPlace?>(
  MiniPlayerPlaceNotifier.new,
);

/// Persists [MiniPlayerPlace] under [key], as `right,bottom,width`.
class MiniPlayerPlaceNotifier extends Notifier<MiniPlayerPlace?> {
  /// Preference key.
  static const key = 'miniPlayer';

  @override
  MiniPlayerPlace? build() {
    final parts = ref.watch(sharedPreferencesProvider).getString(key)?.split(',').map(double.tryParse).toList();
    if (parts == null || parts.length != 3 || parts.any((p) => p == null || !p.isFinite)) return null;
    return (right: parts[0]!, bottom: parts[1]!, width: parts[2]!);
  }

  /// Changes and persists the place.
  void set(MiniPlayerPlace place) {
    state = place;
    final value = [place.right, place.bottom, place.width].map((v) => v.toStringAsFixed(1)).join(',');
    unawaited(ref.read(sharedPreferencesProvider).setString(key, value));
  }
}

/// The room of the mini player in a window of [size]: all of it but the
/// system's bars and cutouts, and the navigation bar at the bottom of a
/// compact window (phones and tablets), which it leaves free.
Rect miniPlayerRoom(BuildContext context, Size size) {
  final padding = MediaQuery.paddingOf(context);
  final bar = AppLayout.navigationOf(context) == AppNavigation.bottomBar
      ? NavigationBarTheme.of(context).height ?? 80
      : 0.0;
  return Rect.fromLTRB(padding.left, padding.top, size.width - padding.right, size.height - padding.bottom - bar);
}

/// The rectangle of the mini player at [place] (where it first appears when
/// null) in [room]: inside it, [miniPlayerEdge] from its edges, the video in
/// 16:9 under the bar, no narrower than [miniPlayerMinWidth] unless the room
/// is.
Rect miniPlayerRect(Rect room, MiniPlayerPlace? place) {
  final maxWidth = math.max(
    0.0,
    math.min(room.width - 2 * miniPlayerEdge, (room.height - 2 * miniPlayerEdge - miniPlayerBarHeight) * 16 / 9),
  );
  // narrower in a narrow window: a third of a phone's width stays free beside it
  final p =
      place ??
      (
        right: miniPlayerMargin,
        bottom: miniPlayerMargin,
        width: math.min(miniPlayerWidth, (room.width - 2 * miniPlayerMargin) * 2 / 3),
      );
  final width = p.width.clamp(math.min(miniPlayerMinWidth, maxWidth), maxWidth).toDouble();
  final height = miniPlayerBarHeight + width * 9 / 16;
  final right = p.right.clamp(miniPlayerEdge, math.max(miniPlayerEdge, room.width - miniPlayerEdge - width)).toDouble();
  final bottom = p.bottom
      .clamp(miniPlayerEdge, math.max(miniPlayerEdge, room.height - miniPlayerEdge - height))
      .toDouble();
  return Rect.fromLTWH(room.right - right - width, room.bottom - bottom - height, width, height);
}

MiniPlayerPlace _placeOf(Rect room, Rect rect) =>
    (right: room.right - rect.right, bottom: room.bottom - rect.bottom, width: rect.width);

/// [child] (the app, under its router) with the mini player over it, in the
/// web app.
///
/// Over the navigator, so over everything it opens: a sheet of another fiche
/// does not hide the video listened to, nor do dialogs and menus (which it
/// seldom meets in its corner, and can be moved off). Its own overlay holds
/// the tooltips of its buttons.
class MiniPlayerLayer extends ConsumerStatefulWidget {
  const MiniPlayerLayer({super.key, required this.navigatorKey, required this.child});

  /// The navigator of the app, which shows the fiche of the video again.
  final GlobalKey<NavigatorState> navigatorKey;

  final Widget child;

  @override
  ConsumerState<MiniPlayerLayer> createState() => _MiniPlayerLayerState();
}

class _MiniPlayerLayerState extends ConsumerState<MiniPlayerLayer> {
  /// The mini player in the overlay; none in the native apps.
  OverlayEntry? _entry;

  @override
  void dispose() {
    _entry
      ?..remove()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // the native apps play no video inside the app
    if (!ref.watch(inPlaceVideosProvider).available) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Overlay(
          initialEntries: [_entry ??= OverlayEntry(builder: (_) => _MiniPlayer(navigatorKey: widget.navigatorKey))],
        ),
      ],
    );
  }
}

/// The mini player, where its place says, when the video is there
/// ([InPlaceVideos.inMiniPlayer]); nothing otherwise (the app under it gets
/// the pointer everywhere).
class _MiniPlayer extends ConsumerStatefulWidget {
  const _MiniPlayer({required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  ConsumerState<_MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<_MiniPlayer> {
  late final InPlaceVideos _videos = ref.read(inPlaceVideosProvider);

  /// Where it is during a move or a resize: saved at the end.
  MiniPlayerPlace? _live;

  /// The room and the rectangle at the start of the move or resize, and how far the pointer went since.
  Rect _room = Rect.zero;
  Rect _from = Rect.zero;
  Offset _moved = Offset.zero;

  /// The player whose pointer goes through during a move or a resize.
  EmbeddedVideo? _through;

  @override
  void initState() {
    super.initState();
    _videos.addListener(_changed);
  }

  @override
  void dispose() {
    _videos.removeListener(_changed);
    super.dispose();
  }

  /// The video started, showed, stopped or changed places.
  void _changed() {
    if (mounted) setState(() {});
  }

  void _start(Rect room, Rect rect) {
    _room = room;
    _from = rect;
    _moved = Offset.zero;
    // the pointer must reach the app all the way, over the player too
    _through = _videos.playing?.video?..letPointerThrough(true);
  }

  void _move(DragUpdateDetails details) {
    _moved += details.delta;
    setState(() => _live = _placeOf(_room, miniPlayerRect(_room, _placeOf(_room, _from.shift(_moved)))));
  }

  /// A resize by the top left corner: the bottom right one stays, the video in 16:9.
  void _resize(DragUpdateDetails details) {
    _moved += details.delta;
    final from = _placeOf(_room, _from);
    final width = _from.width - (_moved.dx + _moved.dy * 16 / 9) / 2;
    setState(
      () => _live = _placeOf(_room, miniPlayerRect(_room, (right: from.right, bottom: from.bottom, width: width))),
    );
  }

  void _end([Object? _]) {
    _through?.letPointerThrough(false);
    _through = null;
    final live = _live;
    if (live == null) return;
    ref.read(miniPlayerPlaceProvider.notifier).set(live);
    setState(() => _live = null);
  }

  /// Shows the fiche of the video, where it then plays: in the detail pane of an expanded window, in a sheet
  /// otherwise, instead of what is open over the app.
  void _showDetails(HighlightFiche fiche) {
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) return;
    navigator.popUntil((route) => route.isFirst);
    unawaited(showFiche(navigator.context, fiche));
  }

  /// Escape while a button of the mini player has the focus: what is open over the app closes, as it does
  /// with the focus inside it. The mini player is in no route, so the route's own action is out of its reach.
  void _dismiss() {
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) return;
    Route<void>? top;
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    final route = top;
    if (route is ModalRoute && !route.isFirst && route.barrierDismissible) unawaited(navigator.maybePop());
  }

  @override
  Widget build(BuildContext context) {
    // (asked at each build: a place that does not show the video lets it go)
    final view = _videos.miniPlayerView();
    final playing = _videos.playing;
    if (playing == null || !_videos.inMiniPlayer) return const SizedBox.shrink();
    final room = miniPlayerRoom(context, MediaQuery.sizeOf(context));
    final rect = miniPlayerRect(room, _live ?? ref.watch(miniPlayerPlaceProvider));
    final scheme = Theme.of(context).colorScheme;
    final catalogue = ref.watch(currentCatalogueProvider);
    final fiche = catalogue == null ? null : highlightFicheOn(catalogue, playing.highlight);
    final loading = playing.video.state.value != EmbeddedVideoState.playing;
    final moving = _through != null;
    return Stack(
      children: [
        Positioned.fromRect(
          rect: rect,
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            // In the focus tree of the navigator, out of reach for the Tab key otherwise: each route keeps the key
            // inside it, and the mini player is in none. After the last button of the page (or of a sheet).
            child: Focus(
              parentNode: widget.navigatorKey.currentState?.focusNode,
              canRequestFocus: false,
              skipTraversal: true,
              child: Actions(
                actions: {DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) => _dismiss())},
                child: FocusTraversalGroup(
                  child: Material(
                    color: scheme.surfaceContainerHigh,
                    elevation: 6,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // the bar: nothing of it over the player, which would take the pointer
                        SizedBox(
                          height: miniPlayerBarHeight,
                          child: Row(
                            children: [
                              // for the pointer only, as the place is; in a window too low for the whole bar (the
                              // width follows the height), Close stays, then the title by which it is moved
                              if (rect.width >= 4 * miniPlayerBarHeight)
                                ExcludeSemantics(
                                  child: _Handle(
                                    cursor: SystemMouseCursors.resizeUpLeftDownRight,
                                    onStart: () => _start(room, rect),
                                    onUpdate: _resize,
                                    onEnd: _end,
                                    child: SizedBox.square(
                                      dimension: miniPlayerBarHeight,
                                      child: RotatedBox(
                                        quarterTurns: 1,
                                        child: Icon(Icons.open_in_full, size: 16, color: scheme.onSurfaceVariant),
                                      ),
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: _Handle(
                                  cursor: moving ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
                                  onStart: () => _start(room, rect),
                                  onUpdate: _move,
                                  onEnd: _end,
                                  child: Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Text(
                                      playing.highlight.track,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 18 / 13,
                                        fontWeight: FontWeight.w500,
                                        color: scheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (rect.width >= 3 * miniPlayerBarHeight)
                                _BarButton(
                                  tooltip: showVideoDetailsText,
                                  icon: Icons.info_outline,
                                  onPressed: fiche == null ? null : () => _showDetails(fiche),
                                ),
                              _BarButton(tooltip: closeVideoText, icon: Icons.close, onPressed: _videos.stop),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              const ColoredBox(color: Colors.black),
                              // the player is transparent while it loads
                              if (loading)
                                const Center(
                                  child: SizedBox.square(
                                    dimension: 24,
                                    child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                                  ),
                                ),
                              ?view,
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A part of the bar that moves or resizes the mini player under the pointer.
class _Handle extends StatelessWidget {
  const _Handle({
    required this.cursor,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.child,
  });

  final MouseCursor cursor;
  final VoidCallback onStart;
  final GestureDragUpdateCallback onUpdate;
  final void Function([Object?]) onEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: cursor,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => onStart(),
      onPanUpdate: onUpdate,
      onPanEnd: onEnd,
      onPanCancel: onEnd,
      child: child,
    ),
  );
}

/// A button of the bar: an icon, its [tooltip] for its name.
class _BarButton extends StatelessWidget {
  const _BarButton({required this.tooltip, required this.icon, required this.onPressed});

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    iconSize: 20,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: miniPlayerBarHeight, height: miniPlayerBarHeight),
    style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    icon: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
  );
}
