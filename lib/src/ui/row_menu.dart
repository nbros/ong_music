/// The small menu of a row of a list or of a fiche: more actions on its song
/// than its tap and its ⋮ button give, at hand. Opened by a long press with a
/// finger or a stylus, by a right click (in the web app, not on a link of the
/// page: the browser keeps its own menu there), and by the long press action
/// of screen readers.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/catalogue.dart';
import '../data/model.dart';
import '../data/song_links.dart';
import '../state/settings_state.dart';
import '../state/song_links_state.dart';
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

/// The items of the menu of [highlight]'s row, in their order: copy its title; when its song has a link to its
/// original, listen to it; with a video, copy its link; copy the link of the original; with a video, share it (where
/// there is a share sheet); add it to the favourites or remove it. [context] is the row's.
List<RowMenuItem> highlightMenuItems(BuildContext context, WidgetRef ref, Highlight highlight) {
  final id = highlight.youtubeId;
  final favourite = ref.read(favouritesProvider).contains(highlight.key);
  final original = ref.read(songLinksProvider)?.of(highlight.songKey);
  return [
    (icon: Icons.copy, label: copyTitleText, onSelected: () => copyAndConfirm(context, songCopyText(highlight.title))),
    if (original != null) _listenItem(context, ref, original),
    if (id != null)
      (icon: Icons.link, label: copyVideoLinkText, onSelected: () => copyAndConfirm(context, shortVideoUrl(id))),
    if (original != null) _copyOriginalItem(context, original),
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
/// when its song has a link to its original, listen to it ([listenToTheOriginalText]); with a video, copy its link;
/// copy the link of the original; with a video, share it (where there is a share sheet). [context] is the row's.
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
  final original = ref.read(songLinksProvider)?.of(play.songKey);
  return [
    (icon: Icons.copy, label: copyTitleText, onSelected: () => copyAndConfirm(context, songCopyText(play.title))),
    if (video != null && id != null)
      (icon: Icons.play_arrow, label: watchOnYouTubeText, onSelected: () => onVideo(video)),
    if (vod != null) (icon: vodIcon, label: watchInTheVodText, onSelected: () => openVod(context, ref, vod)),
    if (original != null) _listenItem(context, ref, original),
    if (video != null && id != null)
      (icon: Icons.link, label: copyVideoLinkText, onSelected: () => copyAndConfirm(context, shortVideoUrl(id))),
    if (original != null) _copyOriginalItem(context, original),
    if (video != null && id != null && ref.read(canShareProvider))
      (icon: Icons.share, label: shareText, onSelected: () => shareHighlight(context, ref, video)),
  ];
}

/// The icon of the original of a song: the line of the fiches, the items of the menus.
const IconData originalIcon = Icons.music_note;

RowMenuItem _listenItem(BuildContext context, WidgetRef ref, SongLink original) =>
    (icon: originalIcon, label: listenToTheOriginalText, onSelected: () => openOriginal(context, ref, original));

RowMenuItem _copyOriginalItem(BuildContext context, SongLink original) =>
    (icon: Icons.link, label: copyOriginalLinkText, onSelected: () => copyAndConfirm(context, original.url));

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
  /// Read once (it never changes, and a list builds this for each row coming in), as the row comes in and not at its
  /// first right click: the browser's side must be listening already at that pointer down, to know whether it is on
  /// a link of the page.
  late final ContextMenus? _menus;

  bool _open = false;

  /// Whether the right click of the last pointer down on the row is the row's: always in the native apps; in the web
  /// app, when the browser keeps its own menu closed for it.
  bool _rightClickClaimed = false;

  /// The pointers that may open the menu by a long press.
  static const _fingers = {PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus};

  @override
  void initState() {
    super.initState();
    _menus = ref.read(contextMenusProvider);
  }

  Future<void> _show(Offset position, {bool haptic = false}) async {
    if (_open) return;
    final items = widget.items(context, ref);
    if (items.isEmpty) return;
    if (haptic) Feedback.forLongPress(context);
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final at = overlay.globalToLocal(position);
    final navigator = Navigator.of(context);
    final localizations = MaterialLocalizations.of(context);
    setState(() => _open = true);
    _menus?.appMenuOpen = true;
    try {
      await navigator.push(
        _RowMenuRoute(
          at: at,
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
          // the name screen readers give the menu, as Material's: none on Apple's platforms, which name it themselves
          semanticLabel: switch (defaultTargetPlatform) {
            TargetPlatform.iOS || TargetPlatform.macOS => null,
            _ => localizations.popupMenuLabel,
          },
          barrierLabel: localizations.menuDismissLabel,
          capturedThemes: InheritedTheme.capture(from: context, to: navigator.context),
          animated: !MediaQuery.disableAnimationsOf(context),
        ),
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

/// How long the menu of a row takes to appear: a fade, with a gentle ease-out, of the whole menu at its full size and
/// in its place from the first frame (as the menus of Samsung's phones), not Material's unrolling from the top, whose
/// width and height grow and whose items come one after the other over 300 ms.
const rowMenuFadeIn = Duration(milliseconds: 120);

/// How long the menu of a row takes to go once closed: a shorter fade, what comes after it not kept waiting.
const rowMenuFadeOut = Duration(milliseconds: 90);

/// The menu of a row over the page, at [at] (in the navigator's overlay): Material's menu of [showMenu] (its surface,
/// its place, its barrier, its focus kept among its items, what screen readers get) with a fade of its own, which
/// [showMenu] cannot give (its fade, its growth and its items' fades are one animation). Nothing moves when the system
/// asks for less motion ([animated] false): it is there, and then gone, from one frame to the next.
class _RowMenuRoute extends PopupRoute<void> {
  _RowMenuRoute({
    required this.at,
    required this.items,
    required this.semanticLabel,
    required this.barrierLabel,
    required this.capturedThemes,
    required this.animated,
  }) : super(traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop); // as Material's: focus stays in the menu

  final Offset at;
  final List<PopupMenuItem<void>> items;
  final String? semanticLabel;

  /// The themes of the row's context, which apply inside the menu as they would in the row.
  final CapturedThemes capturedThemes;

  final bool animated;

  @override
  final String barrierLabel;

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => null;

  @override
  Duration get transitionDuration => animated ? rowMenuFadeIn : Duration.zero;

  @override
  Duration get reverseTransitionDuration => animated ? rowMenuFadeOut : Duration.zero;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final padding = MediaQuery.paddingOf(context);
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      removeLeft: true,
      removeRight: true,
      child: CustomSingleChildLayout(
        delegate: _RowMenuLayout(at, padding, Directionality.of(context)),
        child: capturedThemes.wrap(_RowMenu(items: items, semanticLabel: semanticLabel)),
      ),
    );
  }

  /// The whole menu fades, its surface, its shadow and its items together; the same curve backwards makes the fade
  /// out speed up as it goes.
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(
    opacity: animation.drive(CurveTween(curve: Curves.easeOut)),
    child: child,
  );
}

/// The surface of the menu of a row, with [items]: Material's for [showMenu] (the app is Material 3), its look from
/// the [PopupMenuTheme] when one is set, and otherwise from Material 3's defaults, private to Material and so written
/// again here. Its width is a step of 56 px between two and five steps; taller than the window, it scrolls.
class _RowMenu extends StatelessWidget {
  const _RowMenu({required this.items, required this.semanticLabel});

  final List<PopupMenuItem<void>> items;
  final String? semanticLabel;

  static const _widthStep = 56.0;

  @override
  Widget build(BuildContext context) {
    final theme = PopupMenuTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.card,
      shape: theme.shape ?? const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4))),
      color: theme.color ?? scheme.surfaceContainer,
      elevation: theme.elevation ?? 3,
      shadowColor: theme.shadowColor ?? scheme.shadow,
      surfaceTintColor: theme.surfaceTintColor ?? Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 2 * _widthStep, maxWidth: 5 * _widthStep),
        child: IntrinsicWidth(
          stepWidth: _widthStep,
          // what screen readers get from Material's menu: a menu, a route of its own, named
          child: Semantics(
            role: SemanticsRole.menu,
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: semanticLabel,
            child: SingleChildScrollView(
              padding: theme.menuPadding ?? const EdgeInsets.symmetric(vertical: 8),
              child: ListBody(children: items),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the menu of a row goes: Material's rules for a menu of [showMenu] at a point. Its corner at [at]: to the right
/// of the pointer in the left half of the window, to its left in the right half (in the reading direction in the
/// middle); kept inside the window, 8 px clear of its edges and of the system bars ([padding]). (Material's menu also
/// keeps to one side of the hinge of a folding screen: left out here, a row's menu opening at a finger on one side.)
class _RowMenuLayout extends SingleChildLayoutDelegate {
  const _RowMenuLayout(this.at, this.padding, this.textDirection);

  final Offset at;
  final EdgeInsets padding;
  final TextDirection textDirection;

  static const _margin = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest).deflate(const EdgeInsets.all(_margin) + padding);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final toTheLeft = switch (at.dx.compareTo(size.width - at.dx)) {
      > 0 => true,
      < 0 => false,
      _ => textDirection == TextDirection.rtl,
    };
    var x = toTheLeft ? at.dx - childSize.width : at.dx;
    var y = at.dy;
    if (x < _margin + padding.left) {
      x = _margin + padding.left;
    } else if (x + childSize.width > size.width - _margin - padding.right) {
      x = size.width - childSize.width - _margin - padding.right;
    }
    if (y < _margin + padding.top) {
      y = _margin + padding.top;
    } else if (y + childSize.height > size.height - _margin - padding.bottom) {
      y = size.height - childSize.height - _margin - padding.bottom;
    }
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_RowMenuLayout oldDelegate) =>
      at != oldDelegate.at || padding != oldDelegate.padding || textDirection != oldDelegate.textDirection;
}
