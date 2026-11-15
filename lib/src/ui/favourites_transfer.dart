/// Moving the favourites between the app on a phone, the web app and another
/// device: the `Favourites` section of the About tab, its export as a text,
/// and the import of such a text.
///
/// (Android's own backup carries the favourites to a new phone by itself.)
library;

import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoColors, cupertinoDesktopTextSelectionHandleControls, cupertinoTextSelectionHandleControls;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/catalogue.dart';
import '../data/model.dart';
import '../data/parser.dart';
import '../data/text.dart';
import '../state/catalogue_state.dart';
import '../state/settings_state.dart';
import 'actions.dart';
import 'format.dart';

/// The title of the section of the About tab.
const String favouritesSectionTitle = 'Favourites';

/// The button of the section that opens the import dialog, and the one of the dialog that imports.
const String _importLabel = 'Import';

/// A `Highlight.key` that is the id of a YouTube video (the key of a highlight without video holds a space).
final _youtubeKey = RegExp(r'^[\w-]{11}$');

/// The highlight of each key of [catalogue]: the newest one of the highlights sharing a video. Made once per list
/// of highlights.
final _byKey = Expando<Map<String, Highlight>>('highlights by key');

Map<String, Highlight> _highlightsByKey(Catalogue catalogue) =>
    _byKey[catalogue.highlights] ??= {for (final h in catalogue.highlights) h.key: h};

/// The lines of the export of [favourites] (in the order they were added), one per favourite, as "Share" gives
/// its highlight (`highlightShareText`): its title and its link, its title alone without video. A favourite whose
/// highlight is not in [catalogue] (or without catalogue) is its link alone when its key is a YouTube video, and
/// is left out otherwise (nothing would find it again).
List<String> favouriteLines(Set<String> favourites, Catalogue? catalogue) {
  final byKey = catalogue == null ? const <String, Highlight>{} : _highlightsByKey(catalogue);
  return [
    for (final key in favourites)
      if (byKey[key] case final highlight?)
        highlightShareText(highlight)
      else if (_youtubeKey.hasMatch(key))
        shortVideoUrl(key),
  ];
}

/// The lines of the export of the favourites, on the current catalogue: their number is the count of the
/// section.
final favouriteLinesProvider = Provider<List<String>>(
  (ref) => favouriteLines(ref.watch(favouritesProvider), ref.watch(currentCatalogueProvider)),
);

/// The text of an export: a first line with the number of [lines], then the lines.
String favouritesExportText(List<String> lines) => ['My Ong Music favourites (${lines.length})', ...lines].join('\n');

/// The keys of the highlights of [catalogue] that [text] names, in the order of the text, each once: every YouTube
/// link in it, wherever it is (a forwarded message, lines wrapped, words around the list); and a line without
/// link, by its title, a highlight without video. A highlight not in [catalogue] is not named.
///
/// Highlights without video sharing a title are named one per line naming it: first those among [favourites] (an
/// export read back on the same device adds nothing), then the newest. The text cannot tell them apart otherwise:
/// on another device, the newest is the guess.
List<String> favouriteKeysIn(String text, Catalogue catalogue, {Set<String> favourites = const {}}) {
  final byKey = _highlightsByKey(catalogue);
  final keys = <String>{};
  // the highlights without video by title, newest first: made only when a line has no link
  Map<String, List<Highlight>>? untitled;
  for (final line in text.split('\n')) {
    final ids = youtubeIdsIn(line);
    if (ids.isNotEmpty) {
      for (final id in ids) {
        if (byKey.containsKey(id)) keys.add(id);
      }
      continue;
    }
    final title = songKey(line);
    if (title.isEmpty) continue;
    untitled ??= () {
      final map = <String, List<Highlight>>{};
      for (final h in catalogue.highlights.reversed) {
        if (h.youtubeId == null && h.songKey.isNotEmpty) (map[h.songKey] ??= []).add(h);
      }
      return map;
    }();
    final candidates = untitled[title] ?? const <Highlight>[];
    final pick =
        candidates.where((h) => favourites.contains(h.key) && !keys.contains(h.key)).firstOrNull ??
        candidates.where((h) => !keys.contains(h.key)).firstOrNull;
    if (pick != null) keys.add(pick.key);
  }
  return keys.toList();
}

/// The widest count the section can show: four digits (the catalogue holds about 2,000 highlights).
const _widestCount = 8888;

/// What the section says of the favourites: `12 favourites`.
String favouriteCountText(int count) => plural(count, 'favourite');

/// The `Favourites` section of the About tab, under its title: the number of favourites, `Export` and `Import`.
///
/// The number is that of the lines an export writes. Its text changes in the room left of the buttons, which
/// stay at the right edge: nothing moves.
class FavouritesSection extends ConsumerWidget {
  const FavouritesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(favouriteLinesProvider);
    final loaded = ref.watch(currentCatalogueProvider.select((c) => c != null));
    final scheme = Theme.of(context).colorScheme;
    // tabular figures: every count of as many digits is as wide
    final countStyle = TextStyle(
      fontSize: 14,
      color: scheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final buttonStyle = TextButton.styleFrom(textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
      // the count at the left, the buttons at the right; under it when they do not fit beside it (large text)
      child: OverflowBar(
        alignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            // its line as high as the buttons, in either layout
            padding: const EdgeInsets.symmetric(vertical: 12),
            // In the room of the widest count it can show, unseen and unsaid under it: whether the buttons stand
            // beside the count or under it never changes with the count (a star more, the highlights coming).
            child: Stack(
              children: [
                Visibility(
                  visible: false,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: Text(favouriteCountText(math.max(lines.length, _widestCount)), style: countStyle),
                ),
                Text(favouriteCountText(lines.length), style: countStyle),
              ],
            ),
          ),
          // one under the other when even a line of their own is too narrow
          OverflowBar(
            children: [
              TextButton(
                onPressed: lines.isEmpty ? null : () => _export(context, ref, lines),
                style: buttonStyle,
                child: const Text('Export'),
              ),
              TextButton(
                // the text is read against the highlights
                onPressed: loaded ? () => showImportFavouritesDialog(context) : null,
                style: buttonStyle,
                child: const Text(_importLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Gives the export to the share sheet, or copies it where there is none (or it failed).
Future<void> _export(BuildContext context, WidgetRef ref, List<String> lines) async {
  final text = favouritesExportText(lines);
  if (ref.read(canShareProvider) && await ref.read(textSharerProvider)(text)) return;
  // confirmed as every other copy is: no message where the system shows what is copied by itself
  if (context.mounted) await copyAndConfirm(context, text);
}

/// The import dialog: the exported text pasted, its favourites added to the user's.
Future<void> showImportFavouritesDialog(BuildContext context) async {
  final added = await showDialog<int>(context: context, builder: (context) => const _ImportDialog());
  if (added == null || !context.mounted) return;
  showMessage(context, added == 0 ? 'Already in your favourites' : '${favouriteCountText(added)} added');
}

class _ImportDialog extends ConsumerStatefulWidget {
  const _ImportDialog();

  @override
  ConsumerState<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<_ImportDialog> {
  final _text = TextEditingController();
  bool _nothing = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _import() {
    final catalogue = ref.read(currentCatalogueProvider);
    final keys = catalogue == null
        ? const <String>[]
        : favouriteKeysIn(_text.text, catalogue, favourites: ref.read(favouritesProvider));
    if (keys.isEmpty) {
      setState(() => _nothing = true);
      return;
    }
    // the number added, 0 when all were favourites already
    Navigator.of(context).pop(ref.read(favouritesProvider.notifier).addAll(keys));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    // with the keyboard up on a small phone, the field scrolls and the buttons stay in reach
    scrollable: true,
    title: const Text('Import favourites'),
    // the line kept for the error is the room between the field and the buttons
    contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
    content: SizedBox(
      width: 400,
      child: UnwrappedTextField(
        controller: _text,
        autofocus: true,
        lines: 5,
        hintText: 'Paste the exported text',
        errorText: _nothing ? 'That text holds no favourites.' : null,
        // the error goes when the text changes
        onChanged: (_) {
          if (_nothing) setState(() => _nothing = false);
        },
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      TextButton(onPressed: _import, child: const Text(_importLabel)),
    ],
  );
}

/// A text field of several lines that never wraps them: one title per line however long, the text scrolling both
/// ways, by a finger, the mouse wheel (with Shift, or a trackpad, sideways), and following the caret as it moves.
///
/// The box keeps its size, [lines] high and as wide as it is given, whatever the text: the outline, the hint, the
/// focus and the error ([errorText], under the box, in a line kept for it) are those of a [TextField], drawn
/// around the scrolling text, which stays inside them.
///
/// Built as a [TextField] builds itself, but for the order: the gestures of the text, then the outline, then the
/// sideways scroll, then the text with its own upright scroll. A [TextField] in a sideways scroll would take every
/// sideways drag of a finger for itself (on Android, to move the caret), the scroll none.
///
/// A paste of several lines shows the start of the text: the caret goes there, the view with it.
class UnwrappedTextField extends StatefulWidget {
  const UnwrappedTextField({
    super.key,
    required this.controller,
    required this.lines,
    required this.hintText,
    this.errorText,
    this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController controller;

  /// The height of the box, in lines of text.
  final int lines;
  final String hintText;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  State<UnwrappedTextField> createState() => _UnwrappedTextFieldState();
}

class _UnwrappedTextFieldState extends State<UnwrappedTextField>
    implements TextSelectionGestureDetectorBuilderDelegate {
  final _focus = FocusNode(debugLabel: 'unwrapped field');
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  late final _gestures = TextSelectionGestureDetectorBuilder(delegate: this);
  bool _hovered = false;
  bool _showHandles = false;
  late String _text = widget.controller.text;

  @override
  final GlobalKey<EditableTextState> editableTextKey = GlobalKey<EditableTextState>();

  @override
  bool get forcePressEnabled => Theme.of(context).platform == TargetPlatform.iOS;

  @override
  bool get selectionEnabled => true;

  EditableTextState? get _editable => editableTextKey.currentState;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
    widget.controller.addListener(_changed);
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    widget.controller.removeListener(_changed);
    _focus.dispose();
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  /// A font came (the web app fetches those of rare characters, a Hebrew title among them, once they show): the
  /// lines are measured again, as the text lays them out again.
  void _fontsChanged() => setState(() => _measured = null);

  void _changed() {
    final previous = _text;
    final text = widget.controller.text;
    if (text == previous) return;
    _text = text;
    // A paste of several lines (not a key, nor a word of the keyboard): the caret goes to the start of the text,
    // and the view with it. The text brings the caret at the end of the paste into view after this frame, from
    // the place of the caret it last painted (the end): the view goes to the start the frame after, which stops it.
    if (text.length > previous.length + 1 && '\n'.allMatches(text).length > '\n'.allMatches(previous).length) {
      final binding = WidgetsBinding.instance;
      binding.addPostFrameCallback((_) {
        if (!mounted || widget.controller.text != text) return;
        widget.controller.selection = const TextSelection.collapsed(offset: 0);
        binding.addPostFrameCallback((_) {
          if (!mounted) return;
          for (final scroll in [_vertical, _horizontal]) {
            if (scroll.hasClients) scroll.jumpTo(scroll.position.minScrollExtent);
          }
        });
        binding.scheduleFrame();
      });
    }
    // the width of the lines, and the hint, which shows on an empty field only
    _refresh();
  }

  /// When the handles of the selection show: as in a [TextField].
  void _selectionChanged(TextSelection selection, SelectionChangedCause? cause) {
    final show =
        _gestures.shouldShowSelectionToolbar &&
        cause != SelectionChangedCause.keyboard &&
        (cause == SelectionChangedCause.longPress || widget.controller.text.isNotEmpty);
    if (show != _showHandles) setState(() => _showHandles = show);
    if (cause == SelectionChangedCause.longPress) _editable?.bringIntoView(selection.extent);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge;
    final selectionTheme = DefaultSelectionStyle.of(context);
    final error = widget.errorText != null;
    final cursorColor = error ? theme.colorScheme.error : selectionTheme.cursorColor ?? theme.colorScheme.primary;
    final selectionColor = selectionTheme.selectionColor ?? theme.colorScheme.primary.withValues(alpha: 0.40);
    final apple = theme.platform == TargetPlatform.iOS || theme.platform == TargetPlatform.macOS;
    final controls = switch (theme.platform) {
      TargetPlatform.iOS => cupertinoTextSelectionHandleControls,
      TargetPlatform.macOS => cupertinoDesktopTextSelectionHandleControls,
      TargetPlatform.android || TargetPlatform.fuchsia => materialTextSelectionHandleControls,
      TargetPlatform.linux || TargetPlatform.windows => desktopTextSelectionHandleControls,
    };
    final editable = RepaintBoundary(
      child: EditableText(
        key: editableTextKey,
        controller: widget.controller,
        focusNode: _focus,
        autofocus: widget.autofocus,
        style: style!,
        minLines: widget.lines,
        maxLines: widget.lines,
        keyboardType: TextInputType.multiline,
        autocorrect: false,
        enableSuggestions: false,
        showSelectionHandles: _showHandles,
        selectionColor: _focus.hasFocus ? selectionColor : null,
        selectionControls: controls,
        contextMenuBuilder: (context, state) => AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
        magnifierConfiguration: TextMagnifier.adaptiveMagnifierConfiguration,
        onChanged: widget.onChanged,
        onSelectionChanged: _selectionChanged,
        // the gestures are those of the field around
        rendererIgnoresPointer: true,
        mouseCursor: MouseCursor.defer,
        cursorColor: cursorColor,
        backgroundCursorColor: CupertinoColors.inactiveGray,
        cursorWidth: 2,
        cursorRadius: apple ? const Radius.circular(2) : null,
        cursorOpacityAnimates: theme.platform == TargetPlatform.iOS,
        paintCursorAboveText: apple,
        cursorOffset: apple ? Offset(iOSHorizontalOffset / MediaQuery.devicePixelRatioOf(context), 0) : null,
        scrollController: _vertical,
        // Shift held: the wheel is for the sideways scroll
        scrollPhysics: const _NotWithShift(),
      ),
    );
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: TextFieldTapRegion(
        child: Semantics(
          onTap: () {
            if (!widget.controller.selection.isValid) {
              widget.controller.selection = TextSelection.collapsed(offset: widget.controller.text.length);
            }
            _editable?.requestKeyboard();
          },
          child: _gestures.buildGestureDetector(
            behavior: HitTestBehavior.translucent,
            child: InputDecorator(
              baseStyle: style,
              isFocused: _focus.hasFocus,
              isHovering: _hovered,
              isEmpty: widget.controller.text.isEmpty,
              decoration: InputDecoration(
                // the line of the error is there before it: nothing moves when it comes
                helperText: ' ',
                errorText: widget.errorText,
              ),
              // the text scrolls inside the outline; at least as wide as the box, and as its longest line
              child: _FixedIntrinsics(
                height: _height(context, style),
                child: LayoutBuilder(
                  builder: (context, constraints) => Listener(
                    onPointerSignal: _shiftWheel,
                    // The mouse wheel goes to the text's own (upright) scroll; sideways (a trackpad, or Shift with
                    // the wheel where the system makes it sideways itself, as macOS does) to this one; Shift with an
                    // upright wheel (Windows, Linux) to this one by [_shiftWheel]. No axis is flipped by the
                    // framework: with two scrolls one in the other, the inner one would take the flipped wheel.
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(pointerAxisModifiers: const {}),
                      child: SingleChildScrollView(
                        controller: _horizontal,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: math.max(constraints.maxWidth, _width(context, style)),
                          // the hint on the first line, where the caret is: the decoration would put it on the last
                          // one (it knows no first line of a box that scrolls its text)
                          child: Stack(
                            children: [
                              if (widget.controller.text.isEmpty)
                                IgnorePointer(
                                  child: ExcludeSemantics(
                                    child: Text(
                                      widget.hintText,
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.clip,
                                      style: style.merge(
                                        theme.inputDecorationTheme.hintStyle ??
                                            TextStyle(color: theme.colorScheme.onSurfaceVariant),
                                      ),
                                    ),
                                  ),
                                ),
                              editable,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Shift with an upright mouse wheel scrolls the lines sideways, as in other apps.
  void _shiftWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.kind != PointerDeviceKind.mouse) return;
    final delta = event.scrollDelta;
    if (!HardwareKeyboard.instance.isShiftPressed || delta.dx != 0 || delta.dy == 0 || !_horizontal.hasClients) {
      return;
    }
    final position = _horizontal.position;
    // as the framework does it: a scroll laid out from the right (right-to-left) goes the other way
    final step = Directionality.of(context) == TextDirection.rtl ? -delta.dy : delta.dy;
    final target = (position.pixels + step).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target == position.pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) => position.jumpTo(target));
  }

  /// The width the text needs for each of its lines to stay one line, the room of the caret at their end
  /// included: its widest line. Remembered for the text, style and text size it was measured for, until a font
  /// comes.
  double _width(BuildContext context, TextStyle? style) {
    final text = widget.controller.text;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final measured = _measured;
    if (measured != null &&
        measured.text == text &&
        measured.style == style &&
        measured.scaler == scaler &&
        measured.direction == direction) {
      return measured.width;
    }
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
    )..layout();
    // rounded up, and the caret after the last character with the gap before it
    final width = painter.maxIntrinsicWidth.ceilToDouble() + _caretRoom;
    painter.dispose();
    _measured = (text: text, style: style, scaler: scaler, direction: direction, width: width);
    return width;
  }

  ({String text, TextStyle? style, TextScaler scaler, TextDirection direction, double width})? _measured;

  /// The room of the caret after the end of a line: its width (2) and the gap before it (1), and a pixel to spare.
  static const double _caretRoom = 4;

  /// The height of [UnwrappedTextField.lines] lines of [style], as the text lays them out.
  double _height(BuildContext context, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: ' ', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final line = painter.preferredLineHeight;
    painter.dispose();
    return line * widget.lines;
  }
}

/// [child] for the questions asked of its size before it is laid out: no width of its own (it takes the width it
/// is given) and [height]. A [LayoutBuilder] cannot answer them, and the outline around the field asks.
class _FixedIntrinsics extends SingleChildRenderObjectWidget {
  const _FixedIntrinsics({required this.height, required super.child});

  final double height;

  @override
  _RenderFixedIntrinsics createRenderObject(BuildContext context) => _RenderFixedIntrinsics(height);

  @override
  void updateRenderObject(BuildContext context, _RenderFixedIntrinsics renderObject) => renderObject.height = height;
}

class _RenderFixedIntrinsics extends RenderProxyBox {
  _RenderFixedIntrinsics(this._height);

  double _height;
  set height(double value) {
    if (value == _height) return;
    _height = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  double computeMinIntrinsicHeight(double width) => _height;

  @override
  double computeMaxIntrinsicHeight(double width) => _height;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(Size(constraints.hasBoundedWidth ? constraints.maxWidth : 0, _height));

  @override
  double? computeDryBaseline(BoxConstraints constraints, TextBaseline baseline) => null;
}

/// The physics of the text's own (vertical) scroll, which leaves the mouse wheel alone while Shift is held: it is
/// then for the sideways scroll around it.
class _NotWithShift extends ScrollPhysics {
  const _NotWithShift({super.parent});

  @override
  _NotWithShift applyTo(ScrollPhysics? ancestor) => _NotWithShift(parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) =>
      !HardwareKeyboard.instance.isShiftPressed && super.shouldAcceptUserOffset(position);
}
