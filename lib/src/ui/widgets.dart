/// Small building blocks shared by the lists and the sheets.
library;

import 'dart:math' as math;
import 'dart:ui' show SemanticsInputType;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/model.dart';
import '../data/text.dart';
import '../data/thumbnail_cache.dart';
import 'format.dart';
import 'fullscreen_button.dart';
import 'instant_feedback.dart';
import 'layout.dart';
import 'theme.dart';

// ------------------------------------------------------------------ metrics

/// Text line heights and list item extents for the current text scale.
///
/// The lists give every item an exact extent (see `grouped_list.dart`), so
/// the extents are computed from the scaled font sizes of the texts they hold
/// instead of being measured.
@immutable
final class ListMetrics {
  ListMetrics._(TextScaler scaler)
    : title = _line(scaler, 15, 20),
      subtitle = _line(scaler, 13, 18),
      caption = _line(scaler, 12, 16),
      header = _line(scaler, 13, 20),
      time = scaler.scale(12) / 12;

  /// The metrics of [context]'s text scaler.
  factory ListMetrics.of(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final cached = _cache;
    if (cached != null && cached.$1 == scaler) return cached.$2;
    final metrics = ListMetrics._(scaler);
    _cache = (scaler, metrics);
    return metrics;
  }

  static (TextScaler, ListMetrics)? _cache;

  // Rounded up: text lays its lines out a fraction taller than the exact
  // product at some scales (0.2 px over two lines at 1.3), which would overflow
  // a row of exactly that height.
  static double _line(TextScaler scaler, double fontSize, double lineHeight) =>
      (scaler.scale(fontSize) * lineHeight / fontSize).ceilToDouble();

  /// Line height of a row title (15 px, 20 px line at 1x).
  final double title;

  /// Line height of a row subtitle (13 / 18).
  final double subtitle;

  /// Line height of the metadata line of a highlight (12 / 16).
  final double caption;

  /// Line height of a stream header (13 / 20).
  final double header;

  /// Width of a list thumbnail; its height follows 16:9.
  static const double thumbnailWidth = 124;
  static const double thumbnailHeight = thumbnailWidth * 9 / 16;

  /// Extent of a highlight row: a thumbnail, or up to four text lines.
  double get highlightRow => 16 + _max(thumbnailHeight, _max(2 * title, title + subtitle) + 2 + caption);

  /// Extent of an Ong Log row: two text lines, at least 56.
  double get playRow => _max(56, 16 + title + subtitle);

  /// Width of the time column of a play row (`22:15`).
  double get timeWidth => 36 * time;

  /// Scale of the 12 px time text.
  final double time;

  /// Extent of a stream header.
  double get streamHeader => 20 + header;

  /// Extent of a play row of the song sheet (two lines, at least 48).
  double get historyRow => _max(48, 16 + title + caption + 2);

  static double _max(double a, double b) => a > b ? a : b;
}

// ------------------------------------------------------------------ selection

/// The shape of the selection and hover states of a list row in an expanded
/// window: a rounded rectangle [insets] inside the row. Drawn inside the row,
/// it moves and resizes nothing.
class InsetRoundedBorder extends ShapeBorder {
  const InsetRoundedBorder({required this.insets, required this.radius});

  /// A row of a list: 8 px in from each side.
  static const row = InsetRoundedBorder(insets: EdgeInsets.symmetric(horizontal: 8), radius: 14);

  /// A stream header: 8 px in from each side, 4 from the top.
  static const header = InsetRoundedBorder(insets: EdgeInsets.fromLTRB(8, 4, 8, 0), radius: 10);

  final EdgeInsets insets;
  final double radius;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  RRect _rrect(Rect rect) => RRect.fromRectAndRadius(insets.deflateRect(rect), Radius.circular(radius));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => Path()..addRRect(_rrect(rect));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  bool get preferPaintInterior => true;

  @override
  void paintInterior(Canvas canvas, Rect rect, Paint paint, {TextDirection? textDirection}) =>
      canvas.drawRRect(_rrect(rect), paint);

  @override
  ShapeBorder scale(double t) => InsetRoundedBorder(insets: insets * t, radius: radius * t);

  @override
  bool operator ==(Object other) => other is InsetRoundedBorder && other.insets == insets && other.radius == radius;

  @override
  int get hashCode => Object.hash(insets, radius);
}

/// The tint of a selected row: `primary` at 16 % (the tint of the play a
/// setlist was opened from).
Color selectedRowColor(BuildContext context) => Theme.of(context).colorScheme.primary.withValues(alpha: 0.16);

/// The hover state of a row in an expanded window: `onSurface` at 6 %.
Color hoveredRowColor(BuildContext context) => Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06);

/// Whether the keyboard focus is in a text field: keys that type there are
/// not shortcuts then.
bool isEditingText() =>
    FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;

// ------------------------------------------------------------------ text

/// The spans of [text] with the hits of [tokens] (see `matchRanges`) marked:
/// on [mark], in [onMark], which the greys of the secondary texts are not
/// readable on.
List<InlineSpan> markedSpans(String text, List<String> tokens, Color mark, Color onMark) {
  final ranges = matchRanges(text, tokens);
  if (ranges.isEmpty) return [TextSpan(text: text)];
  final spans = <InlineSpan>[];
  var at = 0;
  for (final r in ranges) {
    if (r.start > at) spans.add(TextSpan(text: text.substring(at, r.start)));
    spans.add(
      TextSpan(
        text: text.substring(r.start, r.end),
        style: TextStyle(backgroundColor: mark, color: onMark),
      ),
    );
    at = r.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return spans;
}

/// [text] on one or [maxLines] lines with the hits of [tokens] marked.
class MarkedText extends StatelessWidget {
  /// Creates the text.
  const MarkedText(this.text, {super.key, required this.tokens, required this.style, this.maxLines = 1});

  final String text;
  final List<String> tokens;
  final TextStyle style;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(children: markedSpans(text, tokens, OngColors.of(context).mark, Theme.of(context).colorScheme.onSurface)),
    style: style,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    softWrap: maxLines > 1,
  );
}

// ------------------------------------------------------------------ inline marks

/// The coloured dot of a genre.
class GenreDot extends StatelessWidget {
  const GenreDot(this.genre, {super.key});

  final Genre genre;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    margin: const EdgeInsets.only(right: 5),
    decoration: BoxDecoration(color: genreColors[genre], shape: BoxShape.circle),
  );
}

/// A small uppercase label: `TIER 3`, `RAFFLE`.
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      // Capital letters only: nothing hangs under the baseline, for which the line keeps room. Left where the line
      // puts them, they sit half a pixel above the middle of the box (2.9 px over them, 4 px under).
      child: Transform.translate(
        offset: const Offset(0, 0.5),
        child: Text(
          label.toUpperCase(),
          // shown in a WidgetSpan, which already scales it with the text around it
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: 10,
            height: 1.4,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// A widget inside a line of text, centred on it.
WidgetSpan inlineWidget(Widget child) => WidgetSpan(alignment: PlaceholderAlignment.middle, child: child);

/// The small person icon before a requester name.
InlineSpan personIcon(Color color) => inlineWidget(
  Padding(
    padding: const EdgeInsets.only(right: 3),
    child: Icon(Icons.person, size: 13, color: color.withValues(alpha: 0.8)),
  ),
);

// ------------------------------------------------------------------ requesters

/// The padding of the user's own name inside its highlight: no-break spaces,
/// which never let the name wrap away from them. Not narrow ones (U+202F),
/// which the Roboto of the web app makes almost zero wide.
const _ownNamePad = '\u00A0';

/// A span with a rounded box of [box] behind it, drawn by [RequesterText]: the
/// user's own name, or a search hit in it.
class _BoxedSpan extends TextSpan {
  const _BoxedSpan({required this.box, super.text, super.style, super.children, super.semanticsLabel});

  final Color box;
}

/// The spans of requester [name] in a line of text, with the hits of [tokens]
/// marked (see [markedSpans]).
///
/// The user's own name ([own]) is highlighted instead, in [OngColors.onBrand]
/// on [OngColors.brand], when a [RequesterText] shows the spans: a search hit
/// in it keeps the [OngColors.mark] of the others, as a box inside the
/// highlight. Screen readers hear "name, you".
List<InlineSpan> requesterSpans(BuildContext context, String name, List<String> tokens, {required bool own}) {
  final ong = OngColors.of(context);
  if (!own) return markedSpans(name, tokens, ong.mark, Theme.of(context).colorScheme.onSurface);
  final ranges = matchRanges(name, tokens);
  final parts = <InlineSpan>[];
  var at = 0;
  for (final r in ranges) {
    if (r.start > at) parts.add(TextSpan(text: name.substring(at, r.start), semanticsLabel: ''));
    parts.add(
      _BoxedSpan(
        box: ong.mark,
        text: name.substring(r.start, r.end),
        // onBrand is too dark on the mark of the dark theme
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        semanticsLabel: '',
      ),
    );
    at = r.end;
  }
  if (at < name.length) parts.add(TextSpan(text: name.substring(at), semanticsLabel: ''));
  return [
    _BoxedSpan(
      box: ong.brand,
      style: TextStyle(color: ong.onBrand),
      children: [
        TextSpan(text: _ownNamePad, semanticsLabel: '$name, you'),
        ...parts,
        const TextSpan(text: _ownNamePad, semanticsLabel: ''),
      ],
    ),
  ];
}

/// A text holding a requester name (see [requesterSpans]), which draws the
/// highlight of the user's own name: a rounded box behind it, cut with the
/// text by the ellipsis. A span background would be square and as high as the
/// line.
class RequesterText extends StatelessWidget {
  /// Creates the text, on one line ending with an ellipsis, or on as many
  /// lines as needed without [maxLines].
  const RequesterText(this.span, {super.key, required this.style, this.maxLines});

  final InlineSpan span;
  final TextStyle style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final text = Text.rich(
      span,
      style: style,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
    final boxes = <_Box>[];
    _boxesOf(span, 0, boxes);
    return boxes.isEmpty ? text : _TextBoxes(boxes: boxes, child: text);
  }

  /// Adds the boxes of the [_BoxedSpan]s of [span], which starts at offset
  /// [at] of the text, to [boxes], a span before the spans inside it; returns
  /// the offset after [span].
  static int _boxesOf(InlineSpan span, int at, List<_Box> boxes) {
    if (span is! TextSpan) return at + 1; // a placeholder: one character
    final start = at;
    final index = boxes.length;
    at += span.text?.length ?? 0;
    for (final child in span.children ?? const <InlineSpan>[]) {
      at = _boxesOf(child, at, boxes);
    }
    if (span is _BoxedSpan) boxes.insert(index, (start: start, end: at, color: span.box));
    return at;
  }
}

/// A range of a text and the colour of the box behind it.
typedef _Box = ({int start, int end, Color color});

/// Paints rounded boxes behind ranges of the text of its child, one per line
/// of text, in order.
class _TextBoxes extends SingleChildRenderObjectWidget {
  const _TextBoxes({required this.boxes, required super.child});

  final List<_Box> boxes;

  @override
  _RenderTextBoxes createRenderObject(BuildContext context) => _RenderTextBoxes(boxes);

  @override
  void updateRenderObject(BuildContext context, _RenderTextBoxes renderObject) => renderObject.boxes = boxes;
}

class _RenderTextBoxes extends RenderProxyBox {
  _RenderTextBoxes(this._boxes);

  List<_Box> _boxes;
  set boxes(List<_Box> value) {
    if (listEquals(value, _boxes)) return;
    _boxes = value;
    markNeedsPaint();
  }

  static RenderParagraph? _paragraphIn(RenderObject object) {
    if (object is RenderParagraph) return object;
    RenderParagraph? found;
    object.visitChildren((child) => found ??= _paragraphIn(child));
    return found;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    final paragraph = child == null ? null : _paragraphIn(child);
    if (paragraph != null) {
      final transform = paragraph.getTransformTo(this);
      for (final box in _boxes) {
        final paint = Paint()..color = box.color;
        // On a line cut by the ellipsis, the last text box takes the ellipsis in. Cut right after its padding, the
        // user's name is a box around the ellipsis alone: still the sign that the request is theirs.
        final selection = TextSelection(baseOffset: box.start, extentOffset: box.end);
        for (final line in _lines(paragraph.getBoxesForSelection(selection))) {
          final rect = MatrixUtils.transformRect(transform, line);
          context.canvas.drawRRect(
            RRect.fromRectAndRadius(rect.shift(offset), Radius.circular(rect.height / 4)),
            paint,
          );
        }
      }
    }
    super.paint(context, offset);
  }

  /// One rectangle per line of text for [boxes], which come one per run of
  /// one font: a name written in a font other than its padding (Japanese,
  /// emoji) comes in several, of other heights.
  static List<Rect> _lines(List<TextBox> boxes) {
    final lines = <Rect>[];
    for (final box in boxes) {
      final rect = box.toRect();
      final index = lines.indexWhere((line) => _onOneLine(line, rect));
      if (index < 0) {
        lines.add(rect);
      } else {
        lines[index] = lines[index].expandToInclude(rect);
      }
    }
    return lines;
  }

  /// Whether [a] and [b] share more than half the height of the lower one.
  static bool _onOneLine(Rect a, Rect b) =>
      math.min(a.bottom, b.bottom) - math.max(a.top, b.top) > math.min(a.height, b.height) / 2;
}

/// The icon of a play type (piano, loop, improvisation), or null.
IconData? playTypeIcon(PlayType type) => switch (type) {
  PlayType.piano || PlayType.catPiano => Icons.piano,
  PlayType.loop => Icons.repeat,
  PlayType.improv => Icons.music_note,
  PlayType.unknown => null,
};

/// The play type icon column of a play row.
class PlayTypeIcon extends StatelessWidget {
  const PlayTypeIcon(this.type, {super.key});

  final PlayType type;

  @override
  Widget build(BuildContext context) {
    final icon = playTypeIcon(type);
    return SizedBox(
      width: 24,
      child: icon == null ? null : Icon(icon, size: 18, color: OngColors.of(context).on3, semanticLabel: type.label),
    );
  }
}

/// The round "play the video" button of a play row (36 × 28, 48 dp target).
class VideoPill extends StatelessWidget {
  const VideoPill({super.key, required this.onPressed});

  /// What screen readers call it.
  static const label = 'Watch the video';

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // a node of its own, with its own action: merged into its row, a screen reader would say it and open the row
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      // no tooltip: the label is for screen readers
      child: _PillInk(
        onTap: onPressed,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 36,
              height: 28,
              decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.play_arrow, size: 18, color: scheme.onPrimaryContainer),
            ),
          ),
        ),
      ),
    );
  }
}

/// The ink of a [VideoPill]: a circle 48 px across, Material's ink on phones
/// and tablets, an [AppInkWell] in the desktop look.
class _PillInk extends StatelessWidget {
  const _PillInk({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppLayout.desktopOf(context)
      ? AppInkWell(onTap: onTap, customBorder: const CircleBorder(), child: child)
      : InkResponse(onTap: onTap, radius: 24, containedInkWell: false, child: child);
}

// ------------------------------------------------------------------ thumbnails

/// Builds the image of a thumbnail URL: kept on disk in the native apps, a
/// plain [NetworkImage] on the web ([createThumbnailImages]); tests override
/// it (no network).
final thumbnailImageProvider = Provider<ImageProvider Function(String url)>((ref) {
  final images = createThumbnailImages();
  ref.onDispose(images.dispose);
  return images.image;
});

/// A YouTube thumbnail, decoded at its display size, with a neutral
/// placeholder while it loads and an icon without video or on error.
class Thumbnail extends ConsumerWidget {
  const Thumbnail({
    super.key,
    required this.youtubeId,
    required this.width,
    this.big = false,
    this.radius = 10,
    this.label,
    this.overlay,
  });

  final String? youtubeId;
  final double width;

  /// The 480 × 360 image (`hqdefault`) instead of the 320 × 180 one (`mqdefault`).
  final bool big;
  final double radius;

  /// Shown in the bottom left corner (`#1952`).
  final String? label;

  /// Drawn over the image, under [label].
  final Widget? overlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ong = OngColors.of(context);
    final height = width * 9 / 16;
    final id = youtubeId;
    Widget fallback() => Center(child: Icon(Icons.video_library, size: 22, color: ong.on3));
    Widget content;
    if (id == null) {
      content = fallback();
    } else {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final url = 'https://i.ytimg.com/vi/$id/${big ? 'hqdefault' : 'mqdefault'}.jpg';
      content = Image(
        image: ResizeImage(
          ref.watch(thumbnailImageProvider)(url),
          width: (width * dpr).round(),
          policy: ResizeImagePolicy.fit,
        ),
        width: width,
        height: height,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) => wasSynchronouslyLoaded
            ? child
            : AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 150),
                child: child,
              ),
        errorBuilder: (context, error, stackTrace) => fallback(),
      );
    }
    final label = this.label;
    final overlay = this.overlay;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: width,
        height: height,
        color: ong.thumbnail,
        child: label == null && overlay == null
            ? content
            : Stack(
                fit: StackFit.expand,
                children: [
                  content,
                  ?overlay,
                  if (label != null)
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xBB000000),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          label,
                          textScaler: TextScaler.noScaling,
                          style: const TextStyle(
                            fontSize: 10,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

// ------------------------------------------------------------------ list chrome

/// The search field at the top of a list: the look of a Material 3 search bar.
///
/// Not a [SearchBar]: that one leaves the keyboard's automatic correction on,
/// which replaces the titles, names and user names typed here with dictionary
/// words. Escape clears the field, or leaves it when it is empty.
///
/// In a browser that can show the page full screen, the [FullscreenButton] is
/// at its right, in the column of the ⋮ buttons of the highlight rows: the
/// field ends 48 px from the edge, where that column begins on a phone, and the
/// button is at the edge, like the ⋮ buttons (48 px on a phone, 40 on desktop).
/// Not in the desktop look, whose top bar has it: the field takes its place.
class ListSearchField extends ConsumerStatefulWidget {
  const ListSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.focusNode,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;

  @override
  ConsumerState<ListSearchField> createState() => _ListSearchFieldState();
}

class _ListSearchFieldState extends ConsumerState<ListSearchField> {
  FocusNode? _ownFocusNode;
  FocusNode get _focusNode => widget.focusNode ?? (_ownFocusNode ??= FocusNode());

  @override
  void dispose() {
    _ownFocusNode?.dispose();
    super.dispose();
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controller = widget.controller;
    final fullscreen = AppLayout.desktopOf(context) ? null : ref.watch(pageFullscreenProvider);
    final mouse = AppLayout.mouseOf(context);
    final field = Padding(
      padding: EdgeInsets.fromLTRB(16, 6, fullscreen == null ? 16 : 0, 2),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              controller.text.isEmpty ? FocusManager.instance.primaryFocus?.unfocus() : _clear(),
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Material(
            color: scheme.surfaceContainerHigh,
            surfaceTintColor: Colors.transparent,
            shape: const StadiumBorder(),
            child: AppInkWell(
              // the text field inside is the focus stop and the semantics node
              canRequestFocus: false,
              excludeFromSemantics: true,
              customBorder: const StadiumBorder(),
              overlayColor: WidgetStateProperty.resolveWith(
                (states) => switch (states) {
                  _ when states.contains(WidgetState.pressed) => scheme.onSurface.withValues(alpha: 0.1),
                  _ when states.contains(WidgetState.hovered) => scheme.onSurface.withValues(alpha: 0.08),
                  _ => Colors.transparent,
                },
              ),
              onTap: () {
                if (!_focusNode.hasFocus) _focusNode.requestFocus();
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 4),
                child: Row(
                  children: [
                    Icon(Icons.search, color: scheme.onSurfaceVariant),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16, right: 4),
                        child: _TakesPressOnDesktop(
                          child: Semantics(
                            inputType: SemanticsInputType.search,
                            child: TextField(
                              controller: controller,
                              focusNode: _focusNode,
                              onChanged: widget.onChanged,
                              onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                              textInputAction: TextInputAction.search,
                              autocorrect: false,
                              style: TextStyle(fontSize: 16, color: scheme.onSurface),
                              decoration: InputDecoration(
                                hintText: widget.hint,
                                hintStyle: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                // lets the text field be lower than 48 px
                                isDense: true,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    ListenableBuilder(
                      listenable: Listenable.merge([controller, _focusNode]),
                      builder: (context, _) => controller.text.isNotEmpty
                          ? IconButton(
                              tooltip: 'Clear',
                              icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
                              onPressed: _clear,
                            )
                          : mouse
                          // the place of the key cap stays while the field has the focus: nothing moves
                          ? Visibility(
                              visible: !_focusNode.hasFocus,
                              maintainSize: true,
                              maintainAnimation: true,
                              maintainState: true,
                              child: const _KeyCap('/'),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (fullscreen == null) return field;
    return Row(
      children: [
        Expanded(child: field),
        // the vertical padding of the field: centred on the pill; over the ⋮ buttons, which the lane of the
        // scroll bar keeps away from the edge with a mouse
        Padding(
          padding: EdgeInsets.only(top: 6, bottom: 2, right: mouse ? scrollbarLane : 0),
          child: SizedBox(
            width: 48,
            child: Align(
              alignment: Alignment.centerRight,
              child: FullscreenButton(fullscreen: fullscreen),
            ),
          ),
        ),
      ],
    );
  }
}

/// In the desktop look, a control that is not a [StateLayer] (the text of a
/// search field) whose press the state layer around it must not show: that
/// press is the control's own, the one around it does not get it.
class _TakesPressOnDesktop extends StatelessWidget {
  const _TakesPressOnDesktop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      AppLayout.desktopOf(context) ? Listener(onPointerDown: StateLayer.takePress, child: child) : child;
}

/// The key that puts the cursor in a search field, at its right end while it
/// is empty and has not the focus, with a mouse: a hint for the eye only.
class _KeyCap extends StatelessWidget {
  const _KeyCap(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        constraints: const BoxConstraints(minWidth: 22),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            height: 20 / 12,
            fontWeight: FontWeight.w500,
            color: OngColors.of(context).on3,
          ),
        ),
      ),
    ),
  );
}

/// A horizontal scroll view that a mouse wheel scrolls too.
///
/// A wheel turns vertically only, and a mouse cannot drag a scroll view on
/// desktop: without this, what is past the right edge (most genre chips) would
/// be out of reach of a mouse.
///
/// With [arrows] (labelled [previousLabel] and [nextLabel] for screen
/// readers), a mouse also gets a button at each end that can scroll further,
/// over a fade of the background: drawn over the row, they never move nor
/// resize what is in it.
class HorizontalScroll extends StatefulWidget {
  const HorizontalScroll({
    super.key,
    required this.padding,
    required this.child,
    this.arrows = false,
    this.previousLabel = 'Previous',
    this.nextLabel = 'Next',
  });

  final EdgeInsetsGeometry padding;
  final Widget child;
  final bool arrows;
  final String previousLabel;
  final String nextLabel;

  @override
  State<HorizontalScroll> createState() => _HorizontalScrollState();
}

class _HorizontalScrollState extends State<HorizontalScroll> {
  final _controller = ScrollController();

  /// Whether the row can scroll back, and further.
  bool _before = false;
  bool _after = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_follow);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _follow() {
    if (!widget.arrows || !mounted || !_controller.hasClients) return;
    final position = _controller.position;
    if (!position.hasContentDimensions || !position.hasPixels) return;
    // half a pixel of tolerance: a fractional end of the row does not show an arrow for nothing
    final before = position.pixels > position.minScrollExtent + 0.5;
    final after = position.pixels < position.maxScrollExtent - 0.5;
    if (before != _before || after != _after) {
      setState(() {
        _before = before;
        _after = after;
      });
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.kind != PointerDeviceKind.mouse || !_controller.hasClients) return;
    // a horizontal delta (trackpad, Shift + wheel) is the scroll view's own business
    final delta = event.scrollDelta;
    if (delta.dx != 0 || delta.dy == 0) return;
    final position = _controller.position;
    final target = (position.pixels + delta.dy).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target == position.pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) => position.pointerScroll(delta.dy));
  }

  /// Scrolls by seven tenths of the visible width, back or further.
  void _page(int direction) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target = (position.pixels + direction * 0.7 * position.viewportDimension).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      position.jumpTo(target);
    } else {
      position.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeInOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scroll = NotificationListener<ScrollMetricsNotification>(
      // the row or its content changed size: an end may come into view or go out of it
      onNotification: (_) {
        _follow();
        return false;
      },
      child: Listener(
        onPointerSignal: _onPointerSignal,
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: widget.padding,
          child: widget.child,
        ),
      ),
    );
    if (!widget.arrows) return scroll;
    final mouse = AppLayout.mouseOf(context);
    return Stack(
      children: [
        scroll,
        _ScrollArrow(
          forward: false,
          visible: mouse && _before,
          label: widget.previousLabel,
          onPressed: () => _page(-1),
        ),
        _ScrollArrow(forward: true, visible: mouse && _after, label: widget.nextLabel, onPressed: () => _page(1)),
      ],
    );
  }
}

/// A button at an end of a [HorizontalScroll], over a fade of the background
/// 64 px wide that lets the taps through to what is under it.
class _ScrollArrow extends StatelessWidget {
  const _ScrollArrow({required this.forward, required this.visible, required this.label, required this.onPressed});

  final bool forward;
  final bool visible;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final side = forward ? Alignment.centerRight : Alignment.centerLeft;
    return Positioned(
      top: 0,
      bottom: 0,
      left: forward ? null : 0,
      right: forward ? 0 : null,
      width: 64,
      child: Visibility(
        visible: visible,
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: side,
                    end: forward ? Alignment.centerLeft : Alignment.centerRight,
                    colors: [scheme.surface, scheme.surface, scheme.surface.withValues(alpha: 0)],
                    stops: const [0, 0.55, 1],
                  ),
                ),
              ),
            ),
            Align(
              alignment: side,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Semantics(
                  button: true,
                  label: label,
                  excludeSemantics: true,
                  onTap: onPressed,
                  child: Material(
                    type: MaterialType.transparency,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: AppInkWell(
                      onTap: onPressed,
                      // the keyboard has the chips themselves
                      canRequestFocus: false,
                      overlayColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.pressed) || states.contains(WidgetState.hovered)
                            ? scheme.onSurface.withValues(alpha: 0.1)
                            : Colors.transparent,
                      ),
                      child: SizedBox.square(
                        dimension: 32,
                        child: Icon(
                          forward ? Icons.chevron_right : Icons.chevron_left,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A traversal policy making a group one stop of the Tab key: the focused
/// node when the focus is in the group (the next Tab leaves it), the node of
/// [entry] when it comes in from elsewhere; nothing when [entry] has none.
class OneStopTraversalPolicy extends ReadingOrderTraversalPolicy {
  OneStopTraversalPolicy(this.entry);

  /// Where the focus enters the group.
  final FocusNode? Function() entry;

  @override
  Iterable<FocusNode> sortDescendants(Iterable<FocusNode> descendants, FocusNode currentNode) {
    if (descendants.contains(currentNode)) return [currentNode];
    final node = entry();
    return node != null && descendants.contains(node) ? [node] : const [];
  }
}

/// A horizontally scrolling row of filter chips, with arrows at its ends for
/// a mouse.
///
/// One stop of the Tab key, which enters it on the first selected chip; ← and
/// → go from chip to chip, Home and End to the first and the last, the chip
/// brought into view at once, clear of the arrows. Space and Enter select a
/// chip as a click does: going through the chips selects none of them (a
/// filter rebuilds the list, and the chips are toggles, not a choice of one).
class ChipRow extends StatefulWidget {
  const ChipRow({super.key, required this.children});

  final List<Widget> children;

  @override
  State<ChipRow> createState() => _ChipRowState();
}

class _ChipRowState extends State<ChipRow> {
  /// Above the focus nodes of the chips.
  final _chips = FocusNode(debugLabel: 'filters', canRequestFocus: false, skipTraversal: true);

  late final _policy = OneStopTraversalPolicy(() {
    final chips = _nodes();
    return chips.where(_isSelected).firstOrNull ?? chips.firstOrNull;
  });

  /// Room left between a chip brought into view and the edge of the row: the
  /// arrow and its fade, with a mouse, lie over 64 px at each end.
  static const double _clearance = 64;

  @override
  void dispose() {
    _chips.dispose();
    super.dispose();
  }

  /// The focus nodes of the chips, from left to right.
  List<FocusNode> _nodes() => _chips.traversalDescendants.toList()..sort((a, b) => a.rect.left.compareTo(b.rect.left));

  static bool _isSelected(FocusNode node) => node.context?.findAncestorWidgetOfExactType<ListChip>()?.selected ?? false;

  /// Focuses the chip [to] gives for the index of the focused one and the
  /// number of chips.
  void _go(int Function(int at, int count) to) {
    final chips = _nodes();
    if (chips.isEmpty) return;
    final at = chips.indexWhere((chip) => chip.hasFocus);
    final chip = chips[to(at, chips.length).clamp(0, chips.length - 1)];
    chip.requestFocus();
    _reveal(chip);
  }

  /// Scrolls the row, without animation, just enough to show [chip] clear of
  /// the ends.
  static void _reveal(FocusNode chip) {
    final context = chip.context;
    final box = context?.findRenderObject();
    if (context == null || box == null || !box.attached) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    final position = Scrollable.maybeOf(context)?.position;
    if (viewport == null || position == null || !position.hasContentDimensions) return;
    final before = viewport.getOffsetToReveal(box, 0).offset - _clearance;
    final after = viewport.getOffsetToReveal(box, 1).offset + _clearance;
    final pixels = position.pixels;
    final target = (pixels > before ? before : (pixels < after ? after : pixels)).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target != pixels) position.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _chips,
    canRequestFocus: false,
    skipTraversal: true,
    includeSemantics: false,
    onFocusChange: (focused) {
      // entered with Tab: the chip in view, clear of the arrow (the Tab key shows it, at the very edge)
      final focus = FocusManager.instance.primaryFocus;
      if (focused && focus != null) _reveal(focus);
    },
    child: FocusTraversalGroup(
      policy: _policy,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go((at, count) => at < 0 ? 0 : at - 1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go((at, count) => at + 1),
          const SingleActivator(LogicalKeyboardKey.home): () => _go((at, count) => 0),
          const SingleActivator(LogicalKeyboardKey.end): () => _go((at, count) => count - 1),
        },
        child: HorizontalScroll(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          arrows: true,
          previousLabel: 'Previous filters',
          nextLabel: 'More filters',
          child: Row(spacing: 8, children: widget.children),
        ),
      ),
    ),
  );
}

/// The height of the head of a list tab at the default text size: the search
/// field (52 px and 8 px around it), the chips (48) and the 4 px under them.
const double listHeadHeight = 112;

/// Whether the list tabs show their search field and their list alone, without
/// the filters, in a window too low for all three: a phone held sideways with
/// its keyboard up, which leaves little more than the height of the search
/// field (until the keyboard goes), or a window of the desktop look so low
/// that under the top bar there is less than [listHeadHeight] (the filters
/// come back when the window grows).
class FiltersOutOfRoom extends InheritedWidget {
  const FiltersOutOfRoom({super.key, required this.value, required super.child});

  final bool value;

  /// False without one above [context].
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FiltersOutOfRoom>()?.value ?? false;

  @override
  bool updateShouldNotify(FiltersOutOfRoom oldWidget) => oldWidget.value != value;
}

/// A filter chip of the design: label, optional icon and count.
///
/// Without [showLabel] it shows its [icon] (required then) and its count
/// alone, and [label] is only said to screen readers.
///
/// The chip keeps the width of [maxCount] (the largest count it can show) when
/// [count] is smaller: a count that follows the other filters moves nothing.
class ListChip extends StatelessWidget {
  const ListChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.count,
    this.maxCount,
    this.showLabel = true,
  }) : assert(showLabel || icon != null, 'a chip without label shows an icon');

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final int? count;
  final int? maxCount;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    final count = this.count;
    // tabular figures: a count never takes more room than a larger one
    final countStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w400,
      color: color.withValues(alpha: 0.75),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget withCount(int count) => showLabel
        ? Text.rich(
            TextSpan(
              text: label,
              children: [TextSpan(text: '  ${formatCount(count)}', style: countStyle)],
            ),
          )
        : Text(formatCount(count), style: countStyle);
    final Widget? text = count == null
        ? (showLabel ? Text(label) : null)
        // under the text shown, the same text with the largest count, unseen and unsaid, gives the width
        : Stack(
            alignment: AlignmentDirectional.centerStart,
            children: [
              Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: withCount(math.max(count, maxCount ?? count)),
              ),
              withCount(count),
            ],
          );
    final withIcon = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        Icon(icon, size: 16, color: color),
        ?text,
      ],
    );
    // The sizes of the design: 32 px high, 12 px on each side inside the border, the icon 6 px
    // from the label. The icon is part of the label: as an avatar, the chip
    // would give it a 32 px box.
    // merged: one node as high as the tap target, not as the chip
    return MergeSemantics(
      child: _ChipTapTarget(
        child: _ChipFocusRing(
          child: FilterChip(
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            // 32 px high with its border, not 34
            visualDensity: const VisualDensity(vertical: -1),
            selected: selected,
            onSelected: (_) => onTap(),
            labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color),
            label: icon == null ? text! : (showLabel ? withIcon : Semantics(label: label, child: withIcon)),
          ),
        ),
      ),
    );
  }
}

/// On a computer, a ring of the primary colour around the chip while the keyboard focus is on it (never a focus
/// given by a click): painted only, [focusRingWidth] outside the chip, which keeps its size and its place.
class _ChipFocusRing extends StatefulWidget {
  const _ChipFocusRing({required this.child});

  final Widget child;

  @override
  State<_ChipFocusRing> createState() => _ChipFocusRingState();
}

class _ChipFocusRingState extends State<_ChipFocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    includeSemantics: false,
    onFocusChange: (focused) => setState(() => _focused = focused),
    // the same widgets with and without the ring: the chip keeps its state, its focus among it
    child: ValueListenableBuilder(
      valueListenable: keyboardFocusShown,
      child: widget.child,
      builder: (context, shown, child) => CustomPaint(
        foregroundPainter: shown && _focused && AppLayout.desktopOf(context)
            ? _ChipRingPainter(Theme.of(context).colorScheme.primary)
            : null,
        child: child,
      ),
    ),
  );
}

class _ChipRingPainter extends CustomPainter {
  _ChipRingPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius((Offset.zero & size).inflate(focusRingWidth), const Radius.circular(10)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = focusRingWidth,
    );
  }

  @override
  bool shouldRepaint(_ChipRingPainter oldDelegate) => color != oldDelegate.color;
}

/// Gives a chip a tap target 48 px high on every platform, without the 48 px
/// of minimum width that come with [MaterialTapTargetSize.padded]: a chip
/// narrower than that ("All") would sit in the middle of them, out of line
/// with the search field and further from the next chip than the others are.
///
/// A tap above or below the chip counts as a tap on it.
class _ChipTapTarget extends SingleChildRenderObjectWidget {
  _ChipTapTarget({required Widget child}) : super(child: Center(widthFactor: 1, heightFactor: 1, child: child));

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderChipTapTarget();
}

class _RenderChipTapTarget extends RenderConstrainedBox {
  _RenderChipTapTarget() : super(additionalConstraints: const BoxConstraints(minHeight: kMinInteractiveDimension));

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    final onChip = Offset(position.dx, size.height / 2);
    return result.addWithRawTransform(
      transform: MatrixUtils.forceToPoint(onChip),
      position: position,
      hitTest: (result, position) => child!.hitTest(result, position: onChip),
    );
  }
}

/// The thin vertical line between chip groups.
class ChipSeparator extends StatelessWidget {
  const ChipSeparator({super.key});

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 24, color: Theme.of(context).colorScheme.outlineVariant);
}

/// The "N results" line under the chips, with an optional link on the right.
///
/// With [onLink], the line keeps the height of the link while [link] is null:
/// the list below does not move when the link comes and goes as the query
/// changes.
class CountLine extends StatelessWidget {
  const CountLine({super.key, required this.text, this.link, this.onLink});

  final String text;
  final String? link;
  final VoidCallback? onLink;

  static const double _linkHeight = 40;

  @override
  Widget build(BuildContext context) {
    final ong = OngColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final link = this.link;
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 4),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                text,
                style: TextStyle(fontSize: 12, color: ong.on3),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (link != null)
            TextButton(
              onPressed: onLink,
              style: platformButtonStyle(
                context,
                TextButton.styleFrom(
                  foregroundColor: scheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(48, _linkHeight),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
              child: Text('$link →'),
            )
          else
            SizedBox(height: onLink == null ? 28 : _linkHeight),
        ],
      ),
    );
  }
}

/// The centred message of an empty list.
class EmptyMessage extends StatelessWidget {
  const EmptyMessage({super.key, required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 56),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: scheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: OngColors.of(context).on3),
          ),
        ],
      ),
    );
  }
}

/// The vertical scroll bar of [child]: a scroll view, or a stack of one and
/// what is drawn over it (a pinned header).
///
/// With a mouse, which may drag it, the bar is always shown, in a lane of its
/// own: [child] ends [scrollbarLane] px before the right edge, so that nothing
/// lies under the bar. With touch, it shows while scrolling, over the content,
/// as it always has on phones. The pointer may change while the user scrolls:
/// the same widgets either way, the scroll position stays.
class LaneScrollbar extends StatelessWidget {
  const LaneScrollbar({super.key, this.controller, this.interactive, this.ends = 0, required this.child});

  /// The controller of the scroll view, or null for the primary one.
  final ScrollController? controller;
  final bool? interactive;

  /// Space kept free at both ends of the lane, with a mouse: clear of the
  /// rounded corners of a card.
  final double ends;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mouse = AppLayout.mouseOf(context);
    final theme = ScrollbarTheme.of(context);
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return ScrollbarTheme(
      // a thumb of 6 px in the middle of its lane, brighter under the mouse
      data: mouse
          ? theme.copyWith(
              thickness: const WidgetStatePropertyAll(6),
              crossAxisMargin: (scrollbarLane - 6) / 2,
              mainAxisMargin: ends,
              radius: const Radius.circular(3),
              minThumbLength: 48,
              thumbColor: WidgetStateProperty.resolveWith(
                (states) => color.withValues(
                  alpha: states.contains(WidgetState.hovered) || states.contains(WidgetState.dragged) ? 0.7 : 0.45,
                ),
              ),
            )
          : theme,
      child: Scrollbar(
        controller: controller,
        // a bar shown for a mouse can be dragged with it: on Android the Material bar is not draggable by default
        interactive: interactive ?? (mouse ? true : null),
        thumbVisibility: mouse,
        child: Padding(
          padding: EdgeInsets.only(right: mouse ? scrollbarLane : 0),
          child: child,
        ),
      ),
    );
  }
}
