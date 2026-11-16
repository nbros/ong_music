/// The small menu of a row of a list or of a fiche: more actions on its song
/// than its tap and its ⋮ button give, at hand. Opened by a long press with a
/// finger or a stylus, by a right click (in the web app, not on a link of the
/// page: the browser keeps its own menu there), and by the long press action
/// of screen readers.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/catalogue.dart';
import '../data/model.dart';
import '../state/settings_state.dart';
import '../state/vods_state.dart';
import '../web/context_menu.dart';
import '../web/web_platform.dart';
import 'actions.dart';
import 'instant_feedback.dart';
import 'widgets.dart';

/// Which menu a right click opens in the web app; null in the native apps, where it is always the row's. Overridden in
/// tests.
final contextMenusProvider = Provider<ContextMenus?>((ref) => contextMenus());

/// An item of the menu of a row: its icon, its label, and what it does.
typedef RowMenuItem = ({IconData icon, String label, VoidCallback onSelected});

/// The items of the menu of [highlight]'s row, in their order: copy its title, copy its link (with a video), share it
/// (where there is a share sheet), add it to the favourites or remove it. [context] is the row's.
List<RowMenuItem> highlightMenuItems(BuildContext context, WidgetRef ref, Highlight highlight) {
  final id = highlight.youtubeId;
  final favourite = ref.read(favouritesProvider).contains(highlight.key);
  return [
    (icon: Icons.copy, label: copyTitleText, onSelected: () => copyAndConfirm(context, songCopyText(highlight.title))),
    if (id != null)
      (icon: Icons.link, label: copyLinkText, onSelected: () => copyAndConfirm(context, shortVideoUrl(id))),
    if (id != null && ref.read(canShareProvider))
      (icon: Icons.share, label: shareText, onSelected: () => shareHighlight(context, ref, highlight)),
    favourite
        ? (
            icon: Icons.star,
            label: removeFromFavouritesText,
            onSelected: () => ref.read(favouritesProvider.notifier).toggle(highlight),
          )
        : (
            icon: Icons.star_border,
            label: addToFavouritesText,
            onSelected: () => ref.read(favouritesProvider.notifier).toggle(highlight),
          ),
  ];
}

/// The items of the menu of [play]'s row, in their order: copy its title; with a video, watch it on YouTube ([onVideo],
/// what the row's play button does); when its stream has a VOD that reaches it, watch it there ([watchInTheVodText]);
/// with a video, copy its link, share it (where there is a share sheet). [context] is the row's.
List<RowMenuItem> playMenuItems(
  BuildContext context,
  WidgetRef ref,
  Catalogue catalogue,
  Play play,
  void Function(Highlight video) onVideo,
) {
  final video = catalogue.highlightOf(play);
  final id = video?.youtubeId;
  final vod = vodLinksFor(catalogue, ref.read(vodFileProvider), ref.read(vodOffsetsProvider))?.linkOf(play);
  return [
    (icon: Icons.copy, label: copyTitleText, onSelected: () => copyAndConfirm(context, songCopyText(play.title))),
    if (video != null && id != null)
      (icon: Icons.play_arrow, label: watchOnYouTubeText, onSelected: () => onVideo(video)),
    if (vod != null) (icon: vodIcon, label: watchInTheVodText, onSelected: () => openVod(context, ref, vod)),
    if (video != null && id != null) ...[
      (icon: Icons.link, label: copyLinkText, onSelected: () => copyAndConfirm(context, shortVideoUrl(id))),
      if (ref.read(canShareProvider))
        (icon: Icons.share, label: shareText, onSelected: () => shareHighlight(context, ref, video)),
    ],
  ];
}

/// Gives [child], a row, its menu of [items] (built when it opens): a long press with a finger or a stylus (never a
/// mouse or a trackpad held down, which stays a click), with the haptic feedback of the platform; a right click; the
/// long press action of screen readers, named [moreActionsHint]. In the web app, a right click opens the browser's menu
/// or the row's, never both: the row claims it at the pointer down (see [ContextMenus]), which the browser refuses on a
/// link of the page (the link over a video button, a link of the semantics tree), whose menu stays the browser's; the
/// row's menu opens only for a click claimed, and while it is open no right click opens the browser's. The menu opens
/// where the finger or the pointer is (in the middle of the row for a screen reader). While it is open, the row keeps
/// the tint of a press, in [shape] (the whole box when null): only a colour changes, nothing moves.
class RowMenuArea extends ConsumerStatefulWidget {
  const RowMenuArea({super.key, required this.items, this.shape, required this.child});

  final List<RowMenuItem> Function(BuildContext context, WidgetRef ref) items;
  final ShapeBorder? shape;
  final Widget child;

  @override
  ConsumerState<RowMenuArea> createState() => _RowMenuAreaState();
}

class _RowMenuAreaState extends ConsumerState<RowMenuArea> {
  // read once: it never changes, and a list builds this for each row coming in
  late final ContextMenus? _menus = ref.read(contextMenusProvider);

  bool _open = false;

  /// Whether the right click of the last pointer down on the row is the row's: always in the native apps; in the web
  /// app, when the browser keeps its own menu closed for it.
  bool _rightClickClaimed = false;

  /// The pointers that may open the menu by a long press.
  static const _fingers = {PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus};

  Future<void> _show(Offset position, {bool haptic = false}) async {
    if (_open) return;
    final items = widget.items(context, ref);
    if (items.isEmpty) return;
    if (haptic) Feedback.forLongPress(context);
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final at = overlay.globalToLocal(position);
    setState(() => _open = true);
    _menus?.appMenuOpen = true;
    try {
      await showMenu<void>(
        context: context,
        position: RelativeRect.fromRect(Rect.fromLTWH(at.dx, at.dy, 0, 0), Offset.zero & overlay.size),
        items: [
          for (final item in items)
            PopupMenuItem<void>(
              // in the tap itself (a copy in a browser needs the user's gesture), before the menu closes
              onTap: item.onSelected,
              child: Row(
                children: [
                  Icon(item.icon, size: 20),
                  const SizedBox(width: 12),
                  Flexible(child: Text(item.label)),
                ],
              ),
            ),
        ],
      );
    } finally {
      // even when the row has gone meanwhile: the browser's menu must not stay closed
      _menus?.appMenuOpen = false;
    }
    if (mounted) setState(() => _open = false);
  }

  /// A pointer went down on the row: with the secondary button, the right click is the row's if the browser lets it
  /// have it (in the web app; now, before the browser's menu event, which comes before the pointer up on macOS).
  void _pointerDown(PointerDownEvent event) {
    if (event.buttons & kSecondaryButton == 0) return;
    _rightClickClaimed = _menus?.claimClick() ?? true;
  }

  /// The middle of the row: where a screen reader opens the menu.
  Offset _middle() {
    final box = context.findRenderObject()! as RenderBox;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget area = GestureDetector(
      // the action of screen readers is the Semantics below
      excludeFromSemantics: true,
      supportedDevices: _fingers,
      onLongPressStart: (details) => _show(details.globalPosition, haptic: true),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          color: _open ? scheme.onSurface.withValues(alpha: pressStateOpacity) : Colors.transparent,
          shape: widget.shape ?? const RoundedRectangleBorder(),
        ),
        child: widget.child,
      ),
    );
    area = Listener(
      onPointerDown: _pointerDown,
      child: GestureDetector(
        excludeFromSemantics: true,
        onSecondaryTapUp: (details) {
          // not when the browser opens its own menu for the click (a link of the page)
          if (_rightClickClaimed) _show(details.globalPosition);
        },
        child: area,
      ),
    );
    return Semantics(onLongPress: () => _show(_middle()), onLongPressHint: moreActionsHint, child: area);
  }
}
