/// What the two list tabs share: the loading and failure screens, the
/// refresh plumbing and the scroll view frame.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/parser.dart';
import '../data/sheets.dart';
import '../state/catalogue_state.dart';
import 'actions.dart';
import 'detail_pane.dart';
import 'layout.dart';
import 'theme.dart';
import 'top_bar.dart';
import 'view_state.dart';
import 'widgets.dart';

/// A download error in plain words.
String describeLoadError(Object? error) => switch (error) {
  SheetHttpException(:final statusCode) =>
    'Google Sheets answered with an error (HTTP $statusCode). Try again in a while.',
  SheetNotCsvException() =>
    'Got a web page instead of the songs. If this network asks you to sign in, do that and try again.',
  CatalogueFormatException() => 'The spreadsheets came back in an unexpected format. Try again in a while.',
  TimeoutException() => 'The download took too long. Check your connection and try again.',
  _ => 'Couldn’t reach Google Sheets. Check your connection and try again.',
};

/// Shown instead of a list while there is no catalogue: first download, or
/// its failure with a Retry button. With [songs], the same for the Songs sheet, which the Ong Log waits for once
/// the highlights are there.
class CatalogueStatusView extends ConsumerWidget {
  const CatalogueStatusView({super.key, this.songs = false, this.ongLog = false});

  /// The status of the Songs sheet ([CatalogueState.isSongsFailed], [CatalogueState.songsError]), whose Retry
  /// downloads it alone.
  final bool songs;

  /// Shown by the Ong Log: it says what the Ong Log waits for, with or without the highlights there.
  final bool ongLog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(catalogueProvider);
    final scheme = Theme.of(context).colorScheme;
    final on3 = OngColors.of(context).on3;
    final notifier = ref.read(catalogueProvider.notifier);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: (songs ? state.isSongsFailed : state.isFailed)
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off, size: 40, color: on3),
                  const SizedBox(height: 16),
                  Text(
                    'Couldn’t download the songs',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: scheme.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    describeLoadError(songs ? state.songsError : state.lastError),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: on3),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: songs ? notifier.retrySongs : notifier.refresh,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(
                    songs || ongLog ? 'Downloading the Ong Log…' : 'Downloading the highlights and the Ong Log…',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: on3),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Keeps the content of a list where it is on screen when its items move:
/// [newOffset] maps the current scroll offset to the offset showing the same
/// content in the list being built.
///
/// Call it from `build`, with the new list: the position is corrected at once,
/// without animation. A list at its top stays there.
void reanchorScroll(ScrollController controller, double Function(double offset) newOffset) {
  if (!controller.hasClients || controller.positions.length != 1) return;
  final position = controller.position;
  final offset = position.pixels;
  if (offset <= 0) return;
  final target = math.max(0.0, newOffset(offset));
  if (target != offset) position.correctBy(target - offset);
}

/// Scrolls [controller] just enough to show the extent from [top] to
/// `top + extent`, below [inset] px at the top of the viewport (a pinned
/// header): at once, without animation.
void revealExtent(ScrollController controller, double top, double extent, {double inset = 0}) {
  if (!controller.hasClients || controller.positions.length != 1) return;
  final position = controller.position;
  var target = position.pixels;
  if (top - inset < target) {
    target = top - inset;
  } else if (top + extent > target + position.viewportDimension) {
    target = top + extent - position.viewportDimension;
  }
  target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
  if (target != position.pixels) position.jumpTo(target);
}

// ------------------------------------------------------------------ keyboard

/// What a key asks of a list (see [listCommandOf]).
enum ListCommand {
  /// ↑.
  up,

  /// ↓.
  down,

  /// Page Up (Fn+↑ on a Mac keyboard).
  pageUp,

  /// Page Down (Fn+↓).
  pageDown,

  /// Home (Fn+←): the first row; in a text field, the start of its line.
  home,

  /// End (Fn+→): the last row; in a text field, the end of its line.
  end,

  /// ⌘↑ on Apple devices, Ctrl+Home elsewhere: the first row, from the
  /// search field too.
  top,

  /// ⌘↓, Ctrl+End: the last row, from the search field too.
  bottom,

  /// ←: the control of the row before the focused one, the row itself, or
  /// the header of its stream.
  left,

  /// →: the next control of the row; from a header, the play it was left
  /// for, or the play under it.
  right,

  /// Enter.
  enter,

  /// Space: the focused control's, but on a row out of view.
  space,

  /// The context-menu key, or Shift+F10: the details of the row (its ⋮).
  menu,
}

/// Whether the platform has Apple's shortcuts: ⌘↑ and ⌘↓ for the ends of a
/// list, where other systems have Ctrl+Home and Ctrl+End.
bool get _applePlatform => switch (defaultTargetPlatform) {
  TargetPlatform.macOS || TargetPlatform.iOS => true,
  _ => false,
};

/// The [ListCommand] of [event] (a key going down, or repeating), or null.
///
/// Enter, Space and the menu keys count when they go down only: held, they
/// would start or open the same thing again and again.
ListCommand? listCommandOf(KeyEvent event) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return null;
  final keyboard = HardwareKeyboard.instance;
  final shift = keyboard.isShiftPressed;
  final control = keyboard.isControlPressed;
  final meta = keyboard.isMetaPressed;
  final key = event.logicalKey;
  final down = event is KeyDownEvent;
  if (keyboard.isAltPressed) return null;
  if (shift) return !control && !meta && down && key == LogicalKeyboardKey.f10 ? ListCommand.menu : null;
  if (meta) {
    if (control || !_applePlatform) return null;
    return switch (key) {
      LogicalKeyboardKey.arrowUp => ListCommand.top,
      LogicalKeyboardKey.arrowDown => ListCommand.bottom,
      _ => null,
    };
  }
  if (control) {
    if (_applePlatform) return null;
    return switch (key) {
      LogicalKeyboardKey.home => ListCommand.top,
      LogicalKeyboardKey.end => ListCommand.bottom,
      _ => null,
    };
  }
  return switch (key) {
    LogicalKeyboardKey.arrowUp => ListCommand.up,
    LogicalKeyboardKey.arrowDown => ListCommand.down,
    LogicalKeyboardKey.pageUp => ListCommand.pageUp,
    LogicalKeyboardKey.pageDown => ListCommand.pageDown,
    LogicalKeyboardKey.home => ListCommand.home,
    LogicalKeyboardKey.end => ListCommand.end,
    LogicalKeyboardKey.arrowLeft => ListCommand.left,
    LogicalKeyboardKey.arrowRight => ListCommand.right,
    LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter when down => ListCommand.enter,
    LogicalKeyboardKey.space when down => ListCommand.space,
    LogicalKeyboardKey.contextMenu when down => ListCommand.menu,
    _ => null,
  };
}

/// What a list tab tells its [ListKeyboard]: the list as it was built last,
/// and what its items do. An item is a row or, in a grouped list, a header.
///
/// Items are counted as the list builds them: the index of an item is the one
/// the [SliverChildBuilderDelegate] of the list gives its child, which the
/// keyboard reads back from the [IndexedSemantics] the delegate puts around
/// it. That holds with the delegate's defaults (`addSemanticIndexes`, no
/// `semanticIndexCallback`, no `semanticIndexOffset`), one delegate per list,
/// and no [IndexedSemantics] inside a row: a list built otherwise must change
/// `ListKeyboard._placeOf`.
abstract interface class ListModel {
  /// The page (a [State]'s).
  BuildContext get context;
  WidgetRef get ref;
  bool get mounted;

  int get itemCount;
  double offsetOf(int item);
  double extentOf(int item);

  /// The item at scroll offset [offset], the later one on a boundary, within
  /// `[0, itemCount)`.
  int itemAt(double offset);

  /// Whether ↑ and ↓ stop at [item]: a row with something to show (not a
  /// header, not a play without fiche).
  bool stopsAt(int item);
  bool isHeader(int item);

  /// The header of the group of row [item]; null in a list without groups.
  int? headerOf(int item);

  /// The header drawn pinned over the top of the list now, or null.
  int? get pinnedHeader;

  /// How much of the top of the list the pinned header covers (0 without).
  double get inset;

  /// [item] whatever its place: the list may change under the cursor.
  Object keyOf(int item);

  /// The item of [key], or -1 when the list no longer holds it.
  int itemOf(Object key);

  /// The item chosen for the detail pane of an expanded window, or null.
  int? get selected;

  /// Shows [item] in the detail pane.
  void choose(int item);

  /// What the ⋮ of [item] does: its details, in a sheet or in the pane.
  void openDetails(int item);

  /// What Enter does with the selection (the video of the fiche of the pane,
  /// whether its row is in the list or not): false when nothing.
  bool start();
}

/// The keyboard of a list tab.
///
/// The list is one stop of the Tab key: Tab enters it on the row the keys
/// left (the selected one, in an expanded window) when it is in view, or on
/// the first row in full view, and the next Tab leaves it, as Shift+Tab does
/// backwards. Inside, ↑ and ↓ go from row to row (not to the headers of the
/// Ong Log, nor to a play without fiche), Page Up and Page Down by the height
/// of the list, Home, End (and ⌘↑, ⌘↓ or Ctrl+Home, Ctrl+End) to its ends,
/// → to the controls of a row (⋮, the video), ← back to the row and on to the
/// header of its stream, the context-menu key or Shift+F10 to its details.
///
/// Out of the list, on the tab: with nothing focused, from the search field
/// (but the keys of its line: Home, End, ←, →), from the chips (but those
/// moving between them) and from the top bar, in an expanded window the same
/// keys move the selected row and the detail pane follows, and Enter starts
/// its video; in a narrower window, ↓ (and ↑, but in the search field) brings
/// the focus to the list, and the other keys scroll it. A move starts from the
/// cursor (the focused row, or the selected one) when it is in view, from the
/// first row in full view otherwise: never far from what the list shows. The
/// keys that would act on a focused row out of view (Enter, Space, →, ←, the
/// menu keys) bring the focus to the first row in full view instead.
///
/// The focus stays in the list when its row goes: a row scrolled out of the
/// lazy list keeps itself alive while focused (its ink well does), a refresh
/// moves the rows instead of building new ones (the delegates find a row's new
/// index from its key), and when the row is built anew (another window mode)
/// or is gone, the list's own node takes the focus, unseen, and hands it back
/// to the row if it comes back in view; the keys then act as from outside the
/// list. Never the control focused before (the search field, a chip).
///
/// Nothing is added to the rows: the focus of a row is its own control's, the
/// cursor an id held here, the one stop a [FocusTraversalPolicy] of the list
/// (no rebuild when the focus moves), and the keys are heard before the
/// focused control (the search field would move its cursor with the arrows).
class ListKeyboard {
  ListKeyboard({required this.tab, required this.model, required this.scroll}) {
    FocusManager.instance.addListener(_onFocusChange);
  }

  final AppTab tab;
  final ListModel model;
  final ScrollController scroll;

  /// Above the focus nodes of the list (its rows, their controls, the pinned
  /// header): it has the focus when one of them does.
  final FocusNode node = FocusNode(debugLabel: 'list group', canRequestFocus: false, skipTraversal: true);

  /// The list's own node, under [node] and above the rows: it holds the focus,
  /// unseen and out of the order of the Tab key, when the focused row is gone.
  final FocusNode _holder = FocusNode(debugLabel: 'list', skipTraversal: true);

  late final FocusTraversalPolicy _policy = OneStopTraversalPolicy(_entryNode);

  /// The row the keys left the cursor on, whatever its place in the list.
  Object? _cursor;

  /// The row whose focus waits for it to be built.
  Object? _pending;

  /// The play ← left for the header of its stream: → comes back to it.
  Object? _leftFrom;

  /// The node of the list with the focus, while one has it.
  FocusNode? _focused;

  static const _overlay = ValueKey('list overlay');

  void dispose() {
    FocusManager.instance.removeListener(_onFocusChange);
    _holder.dispose();
    node.dispose();
  }

  /// The list as the keyboard needs it: [list], [overlay] drawn over it.
  Widget wrap({required Widget list, Widget? overlay}) => Focus(
    focusNode: node,
    canRequestFocus: false,
    skipTraversal: true,
    includeSemantics: false,
    onFocusChange: (focused) {
      // entered: in full view, below the pinned header (a Tab scrolls a row into view, as if nothing covered it);
      // not the pinned header, which is in view already, nor the list's own node
      final focus = FocusManager.instance.primaryFocus;
      final place = focused && focus != null ? _placeOf(focus) : null;
      if (place != null && !place.pinned) _reveal(place.item);
    },
    child: FocusTraversalGroup(
      policy: _policy,
      child: Focus(
        focusNode: _holder,
        includeSemantics: false,
        child: Listener(
          // a press in the list takes the keyboard focus out of it (no second cursor, no ring after a click) and
          // leaves the cursor where it was pressed
          onPointerDown: _onPointerDown,
          child: Stack(
            children: [
              list,
              if (overlay != null) KeyedSubtree(key: _overlay, child: overlay),
            ],
          ),
        ),
      ),
    ),
  );

  void _onPointerDown(PointerDownEvent event) {
    if (node.hasFocus) FocusManager.instance.primaryFocus?.unfocus();
    if (!_hasList || model.itemCount == 0) return;
    _cursor = model.keyOf(model.itemAt(scroll.position.pixels + event.localPosition.dy));
  }

  /// Follows the focus (on its changes only, not on frames): the cursor is the
  /// focused row; the row gone with the focus, the list's own node takes it.
  void _onFocusChange() {
    if (!model.mounted) return;
    final focus = FocusManager.instance.primaryFocus;
    final left = _focused;
    if (left != null && !identical(focus, left) && !(left.context?.mounted ?? false)) {
      // gone with its row: the focus went back to whatever had it before (the search field, a chip, another row,
      // a row out of view): the list's own node takes it, and gives it back to the same row if it comes again
      _focused = null;
      if (!identical(focus, _holder)) _holder.requestFocus();
      final tries = _restores > 0 ? _restores : 3;
      _restores = 0;
      _restore(tries);
      return;
    }
    if (focus != null && node.hasFocus && !identical(focus, _holder)) {
      _focused = focus;
      final place = _placeOf(focus);
      if (place != null) _cursor = model.keyOf(place.item);
    } else {
      // left for another control (Tab, a click, a sheet), or on the list's own node
      _focused = null;
    }
  }

  /// Gives the focus back to the cursor's row after the next frame, if that
  /// frame builds it in view (the same row in another window mode, which may
  /// take a frame more to settle: [tries] times at most).
  void _restore(int tries) {
    final key = _cursor;
    if (key == null || tries == 0) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!model.mounted || !_holder.hasPrimaryFocus || !_hasList) return;
      final item = model.itemOf(key);
      if (item < 0 || !_inView(item)) return;
      final row = _nodeOf(item);
      if (row == null) return _restore(tries - 1);
      _moveTo(item, focus: true, expanded: AppLayout.readModeOf(model.context) == WindowMode.expanded);
      _restores = tries - 1;
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// The restorations left when the row given the focus back goes again.
  int _restores = 0;

  bool get _hasList => scroll.hasClients && scroll.positions.length == 1;

  /// Whether nothing is over the page (a sheet, a dialog, another page): the
  /// focus is in its route, or nowhere (on a scope around it, the navigator's
  /// after an unfocus). Not from [ModalRoute.of], which would build the page
  /// again each time a sheet opens and closes.
  bool get _onTop {
    final route = Focus.maybeOf(model.context, scopeOk: true, createDependency: false)?.nearestScope;
    final focus = FocusManager.instance.primaryFocus;
    return route == null || focus == null || route.hasFocus || route.ancestors.contains(focus);
  }

  /// Set by [_inList] when the key only brought the cursor back into view.
  bool _landing = false;

  /// The key of such a press, until it is released or another key comes.
  LogicalKeyboardKey? _landedWith;

  /// Hears [event] before the focused control (an early key handler of the
  /// focus manager).
  KeyEventResult handle(KeyEvent event) {
    if (!model.mounted) return KeyEventResult.ignored;
    // a key whose press only brought the cursor back into view: held, it must not act on the row it landed on
    final landed = _landedWith;
    if (landed != null) {
      if (event.logicalKey == landed && event is KeyRepeatEvent) return KeyEventResult.handled;
      if (event.logicalKey != landed || event is! KeyRepeatEvent) _landedWith = null;
    }
    final command = listCommandOf(event);
    if (command == null) return KeyEventResult.ignored;
    final page = model.context;
    // the tab on screen, nothing over it, and its list (not its loading screen)
    if (model.ref.read(selectedTabProvider) != tab || !_onTop || !_hasList) return KeyEventResult.ignored;
    final expanded = AppLayout.readModeOf(page) == WindowMode.expanded;
    final focus = FocusManager.instance.primaryFocus;
    if (node.hasFocus) {
      _landing = false;
      final result = _inList(command, focus!, expanded);
      if (_landing) _landedWith = event.logicalKey;
      return result;
    }
    if (focus == null || focus is FocusScopeNode) return _onPage(command, expanded, control: false, chips: false);
    if (focus == model.ref.read(searchFocusProvider(tab))) {
      // a word being composed (an input method): its keys are the field's
      final editing = focus.context?.findAncestorStateOfType<EditableTextState>()?.textEditingValue;
      if (editing != null && editing.composing.isValid && !editing.composing.isCollapsed) {
        return KeyEventResult.ignored;
      }
      return _inSearch(command, expanded);
    }
    if (isEditingText()) return KeyEventResult.ignored;
    final focused = focus.context;
    if (focused == null) return KeyEventResult.ignored;
    // a control of the page or of the top bar; not one of the detail pane, of the rail or of the bottom bar,
    // whose arrows are their own
    var onPage = false;
    var chips = false;
    focused.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is ChipRow) chips = true;
      if (identical(element, page) || widget is AppTopBar) onPage = true;
      return !onPage && widget is! DetailPane;
    });
    if (!onPage) return KeyEventResult.ignored;
    return _onPage(command, expanded, control: true, chips: chips);
  }

  /// Keys with the focus elsewhere on the tab: nowhere ([control] false), or
  /// on a control, among the [chips] or not.
  KeyEventResult _onPage(ListCommand command, bool expanded, {required bool control, required bool chips}) {
    switch (command) {
      case ListCommand.left || ListCommand.right || ListCommand.menu || ListCommand.space:
        return KeyEventResult.ignored;
      case ListCommand.home || ListCommand.end when chips:
        // from chip to chip
        return KeyEventResult.ignored;
      case ListCommand.enter:
        // the focused control's
        if (control || !expanded) return KeyEventResult.ignored;
        return model.start() ? KeyEventResult.handled : KeyEventResult.ignored;
      case ListCommand.up || ListCommand.down:
        return expanded ? _move(command, model.selected, focus: false, expanded: true) : _enter();
      case _:
        return expanded ? _move(command, model.selected, focus: false, expanded: true) : _scrollBy(command);
    }
  }

  /// Keys in the search field of the list: those of its line are its own.
  KeyEventResult _inSearch(ListCommand command, bool expanded) {
    switch (command) {
      case ListCommand.home || ListCommand.end || ListCommand.left || ListCommand.right:
      case ListCommand.enter || ListCommand.menu || ListCommand.space:
        return KeyEventResult.ignored;
      case _ when expanded:
        return _move(command, model.selected, focus: false, expanded: true);
      case ListCommand.down:
        return _enter();
      case ListCommand.up:
        return KeyEventResult.ignored;
      case _:
        return _scrollBy(command);
    }
  }

  /// Keys with the focus on [focus], in the list.
  KeyEventResult _inList(ListCommand command, FocusNode focus, bool expanded) {
    final pending = _pending;
    final waiting = pending == null ? -1 : model.itemOf(pending);
    // the row the keys moved to, its focus still on the way; or the focused one
    final place = waiting >= 0 ? (item: waiting, pinned: false) : _placeOf(focus);
    final cursor = _cursor;
    // the list's own node (its row gone): the cursor, if it is still in the list
    final item = place?.item ?? (cursor == null ? -1 : model.itemOf(cursor));
    final known = item >= 0 && item < model.itemCount;
    final row = place == null ? null : _nodeOf(item);
    final inner = waiting < 0 && row != null && !identical(row, focus);
    switch (command) {
      case ListCommand.left || ListCommand.right || ListCommand.enter || ListCommand.menu || ListCommand.space
          when place == null || !_inView(item):
        // nothing focused in view: these keys would act on a row the user does not see; the cursor comes to what
        // the list shows instead (the focus with it), and nothing opens
        final entry = _entry();
        if (entry != null) _moveTo(entry, focus: true, expanded: expanded);
        _landing = true;
        return KeyEventResult.handled;
      case ListCommand.left:
        if (inner) {
          final controls = _controlsOf(row);
          final at = controls.indexWhere((c) => c.hasFocus);
          (at > 0 ? controls[at - 1] : row).requestFocus();
        } else if (!model.isHeader(item)) {
          final header = model.headerOf(item);
          if (header != null) {
            _moveTo(header, focus: true, expanded: expanded);
            _leftFrom = model.keyOf(item);
          }
        }
        return KeyEventResult.handled;
      case ListCommand.right:
        if (model.isHeader(item)) {
          // back to the play left for the header, if it still belongs to it
          final from = _leftFrom == null ? -1 : model.itemOf(_leftFrom!);
          if (from >= 0 && model.headerOf(from) == item) {
            _moveTo(from, focus: true, expanded: expanded);
            return KeyEventResult.handled;
          }
          return _fromHeader(item, place!.pinned, expanded);
        }
        if (row != null) {
          final controls = _controlsOf(row);
          final at = inner ? controls.indexWhere((c) => c.hasFocus) : -1;
          if (at + 1 < controls.length) controls[at + 1].requestFocus();
        }
        return KeyEventResult.handled;
      case ListCommand.down when place != null && place.pinned:
        return _fromHeader(item, true, expanded);
      case ListCommand.enter:
        // on the selected row of an expanded window, what Enter does with nothing focused; otherwise the focused
        // control's (the row chooses itself, or opens what it opens)
        if (!inner && expanded && model.selected == item && model.start()) return KeyEventResult.handled;
        return KeyEventResult.ignored;
      case ListCommand.space:
        return KeyEventResult.ignored;
      case ListCommand.menu:
        model.openDetails(item);
        return KeyEventResult.handled;
      case _:
        return _move(command, known ? item : null, focus: true, expanded: expanded);
    }
  }

  /// ↓ or → from header [item]: the play under it, which for the [pinned]
  /// header is the first one in full view below it (not the first of its
  /// stream, far above when the stream is long).
  KeyEventResult _fromHeader(int item, bool pinned, bool expanded) {
    if (!pinned) return _move(ListCommand.down, item, focus: true, expanded: expanded);
    final under = _firstInFullView(stops: true);
    if (under != null) _moveTo(under, focus: true, expanded: expanded);
    return KeyEventResult.handled;
  }

  /// Moves the cursor from [from] (null: none) as [command] asks: the focus
  /// with it when [focus], the selection in an [expanded] window.
  KeyEventResult _move(ListCommand command, int? from, {required bool focus, required bool expanded}) {
    final count = model.itemCount;
    if (count == 0) return focus ? KeyEventResult.handled : KeyEventResult.ignored;
    final inView = from != null && from >= 0 && from < count && _inView(from);
    final start = inView ? from : _firstInFullView();
    if (start == null) return KeyEventResult.ignored;
    final position = scroll.position;
    final int target;
    switch (command) {
      case ListCommand.up || ListCommand.down:
        target = inView ? (_step(from, command == ListCommand.down ? 1 : -1) ?? from) : start;
      case ListCommand.home || ListCommand.top:
        position.jumpTo(position.minScrollExtent);
        target = _step(-1, 1) ?? start;
      case ListCommand.end || ListCommand.bottom:
        position.jumpTo(position.maxScrollExtent);
        target = _step(count, -1) ?? start;
      case ListCommand.pageUp || ListCommand.pageDown:
        target = _page(start, command == ListCommand.pageDown ? 1 : -1);
      case _:
        return KeyEventResult.ignored;
    }
    _moveTo(target, focus: focus, expanded: expanded);
    return KeyEventResult.handled;
  }

  void _moveTo(int item, {required bool focus, required bool expanded}) {
    _leftFrom = null;
    // a header gone up is the pinned one, there already
    if (!model.isHeader(item) || model.pinnedHeader != item) _reveal(item);
    _cursor = model.keyOf(item);
    if (expanded && model.selected != item) model.choose(item);
    if (focus) _focus(item);
  }

  /// Scrolls the list a page further or back, or to an end, the cursor left
  /// where it is (it is not on screen).
  KeyEventResult _scrollBy(ListCommand command) {
    final position = scroll.position;
    final page = position.viewportDimension - (position.pixels > 0 ? model.inset : 0);
    final target = switch (command) {
      ListCommand.pageUp => position.pixels - page,
      ListCommand.pageDown => position.pixels + page,
      ListCommand.home || ListCommand.top => position.minScrollExtent,
      ListCommand.end || ListCommand.bottom => position.maxScrollExtent,
      _ => null,
    };
    if (target == null) return KeyEventResult.ignored;
    position.jumpTo(target.clamp(position.minScrollExtent, position.maxScrollExtent));
    return KeyEventResult.handled;
  }

  /// Brings the focus to the list, where Tab would.
  KeyEventResult _enter() {
    final item = _entry();
    if (item == null) return KeyEventResult.ignored;
    _cursor = model.keyOf(item);
    _focus(item);
    return KeyEventResult.handled;
  }

  /// A page down ([direction] 1) or up from [from]: the list scrolls by its
  /// height under the pinned header, and the cursor goes to the row at the
  /// same place on screen; to the last (first) row when the list is at its
  /// end already.
  int _page(int from, int direction) {
    final position = scroll.position;
    final pixels = position.pixels;
    final page = math.max(position.viewportDimension - model.inset, model.extentOf(from));
    final to = (pixels + direction * page).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((to - pixels).abs() < 0.5) return (direction > 0 ? _step(model.itemCount, -1) : _step(-1, 1)) ?? from;
    position.jumpTo(to);
    var item = model.itemAt(to + model.offsetOf(from) - pixels + 0.5);
    // not one cut by the top of the list: the page would be shorter by what shows it in full
    if (model.offsetOf(item) < to + (to > 0 ? model.inset : 0) - 0.5 && item + 1 < model.itemCount) item++;
    if (model.stopsAt(item)) return item;
    return _step(item, direction) ?? _step(item, -direction) ?? from;
  }

  /// The next item where the cursor stops after [from] in [direction], or
  /// null.
  int? _step(int from, int direction) {
    final count = model.itemCount;
    for (var i = from + direction; i >= 0 && i < count; i += direction) {
      if (model.stopsAt(i)) return i;
    }
    return null;
  }

  /// Whether some of [item] is on screen (not under the pinned header).
  bool _inView(int item) {
    final position = scroll.position;
    final pixels = position.pixels;
    if (model.isHeader(item) && pixels > 0 && model.pinnedHeader == item) return true;
    final top = model.offsetOf(item);
    final inset = model.isHeader(item) || pixels <= 0 ? 0 : model.inset;
    return top < pixels + position.viewportDimension && top + model.extentOf(item) > pixels + inset;
  }

  /// What shows first in the list, below the pinned header: the first row
  /// where the cursor stops in full view; without one, unless [stops], the
  /// first item in full view (a header, a play without fiche) or the pinned
  /// header. Only what is on screen, which the list has built: null when it
  /// shows nothing that takes the focus.
  int? _firstInFullView({bool stops = false}) {
    final count = model.itemCount;
    if (count == 0 || !_hasList) return null;
    final position = scroll.position;
    final pixels = position.pixels;
    final bottom = pixels + position.viewportDimension + 0.5;
    final top = pixels + (pixels > 0 ? model.inset : 0);
    var first = model.itemAt(top);
    if (model.offsetOf(first) < top - 0.5) first++;
    int? any;
    for (var i = first; i < count && model.offsetOf(i) < bottom; i++) {
      if (model.offsetOf(i) + model.extentOf(i) > bottom) break;
      if (model.stopsAt(i)) return i;
      any ??= i;
    }
    if (stops) return null;
    return any ?? model.pinnedHeader ?? (first < count && _inView(first) ? first : null);
  }

  /// Where Tab enters the list: the cursor when it is in view, what shows
  /// first otherwise.
  int? _entry() {
    final count = model.itemCount;
    if (count == 0 || !_hasList) return null;
    final cursor = _cursor;
    final candidate = AppLayout.readModeOf(model.context) == WindowMode.expanded
        ? model.selected
        : (cursor == null ? null : model.itemOf(cursor));
    if (candidate != null && candidate >= 0 && candidate < count && _inView(candidate)) return candidate;
    return _firstInFullView();
  }

  FocusNode? _entryNode() {
    final item = _entry();
    return item == null ? null : _nodeOf(item);
  }

  /// Scrolls just enough to show [item] in full, below the pinned header (a
  /// header goes to the top, where the pinned one shows it).
  void _reveal(int item) =>
      revealExtent(scroll, model.offsetOf(item), model.extentOf(item), inset: model.isHeader(item) ? 0 : model.inset);

  /// Gives the focus to [item], now if it is built, after the next frame
  /// otherwise (a page, an end of the list): that frame is asked for, and
  /// the focus waits for no other (a later frame, built for something else,
  /// would move it out of the blue).
  void _focus(int item) {
    final node = _nodeOf(item);
    if (node != null) {
      _pending = null;
      node.requestFocus();
      return;
    }
    final key = model.keyOf(item);
    _pending = key;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_pending != key) return;
      _pending = null;
      if (!model.mounted) return;
      final at = model.itemOf(key);
      if (at >= 0) _nodeOf(at)?.requestFocus();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// The item a focus node of the list belongs to, and whether it is the
  /// pinned header; null for a node of none (the list's own).
  ///
  /// The index comes from the [IndexedSemantics] the delegate of the list puts
  /// around each child: see [ListModel] for what that needs.
  ({int item, bool pinned})? _placeOf(FocusNode focus) {
    final context = focus.context;
    if (context == null || !context.mounted) return null;
    int? item;
    var pinned = false;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is IndexedSemantics) {
        item = widget.index;
        return false;
      }
      if (widget is KeyedSubtree && widget.key == _overlay) {
        pinned = true;
        return false;
      }
      return !(widget is Focus && widget.focusNode == node);
    });
    if (pinned) {
      final header = model.pinnedHeader;
      return header == null ? null : (item: header, pinned: true);
    }
    final found = item;
    if (found == null) return null;
    assert(
      found < model.itemCount,
      'the semantic index of a row ($found) is not its index in the list (${model.itemCount} items): see ListModel',
    );
    return (item: found, pinned: false);
  }

  /// The focus node of [item] itself (not of a control in it), if it is
  /// built: for a header at or above the top of the list, the pinned one,
  /// which covers it.
  FocusNode? _nodeOf(int item) {
    final pixels = _hasList ? scroll.position.pixels : 0.0;
    final pinned = model.isHeader(item) && pixels > 0 && model.offsetOf(item) <= pixels + 0.5;
    final nodes = [...node.children];
    for (var i = 0; i < nodes.length; i++) {
      final place = _placeOf(nodes[i]);
      if (place == null) {
        nodes.addAll(nodes[i].children);
      } else if (place.item == item && place.pinned == pinned) {
        return nodes[i];
      }
    }
    return null;
  }

  /// The controls inside [row] (⋮, the video), from left to right.
  static List<FocusNode> _controlsOf(FocusNode row) =>
      row.traversalDescendants.toList()..sort((a, b) => a.rect.left.compareTo(b.rect.left));
}

/// The scrolling part of a list tab: pull to refresh, scrollbar, a thin
/// progress bar while the data refreshes in the background, [overlay] (the
/// pinned header) above the list, and the [keyboard] of the list.
class ListFrame extends ConsumerStatefulWidget {
  const ListFrame({
    super.key,
    required this.controller,
    required this.slivers,
    this.overlay,
    this.keyboard,
    this.songs = false,
  });

  /// Whether the list shows the Songs sheet (the Ong Log): its refreshes show, a pull waits for it, and its failure
  /// is said. Otherwise only those of the Highlights sheet: the Songs sheet loaded in the background, or refreshed
  /// by the same pull, never shows over the Highlights list.
  final bool songs;

  final ScrollController controller;
  final List<Widget> slivers;
  final Widget? overlay;
  final ListKeyboard? keyboard;

  @override
  ConsumerState<ListFrame> createState() => _ListFrameState();
}

class _ListFrameState extends ConsumerState<ListFrame> {
  bool _pulling = false;

  Future<void> _pullToRefresh() async {
    setState(() => _pulling = true);
    final notifier = ref.read(catalogueProvider.notifier);
    await notifier.refresh(waitForSongs: widget.songs);
    if (!mounted) return;
    setState(() => _pulling = false);
    final state = ref.read(catalogueProvider);
    final error = widget.songs ? state.anyError : state.lastError;
    if (error != null) showMessage(context, 'Refresh failed. ${describeLoadError(error)}');
  }

  @override
  Widget build(BuildContext context) {
    final refreshing = ref.watch(
      catalogueProvider.select((s) => s.isRefreshing || (widget.songs && s.isRefreshingSongs)),
    );
    final overlay = widget.overlay;
    final list = CustomScrollView(
      controller: widget.controller,
      physics: const AlwaysScrollableScrollPhysics(),
      scrollBehavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      slivers: [
        ...widget.slivers,
        SliverPadding(padding: EdgeInsets.only(bottom: 8 + MediaQuery.paddingOf(context).bottom)),
      ],
    );
    final keyboard = widget.keyboard;
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _pullToRefresh,
          // the pinned header in the lane of the list too: nothing under the bar
          child: LaneScrollbar(
            controller: widget.controller,
            interactive: true,
            child: keyboard != null ? keyboard.wrap(list: list, overlay: overlay) : Stack(children: [list, ?overlay]),
          ),
        ),
        if (refreshing && !_pulling)
          const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
      ],
    );
  }
}
