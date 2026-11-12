/// Small building blocks shared by the lists and the sheets.
library;

import 'dart:ui' show SemanticsInputType;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/model.dart';
import '../data/text.dart';
import 'format.dart';
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

// ------------------------------------------------------------------ text

/// The spans of [text] with the hits of [tokens] (see `matchRanges`) marked.
List<InlineSpan> markedSpans(String text, List<String> tokens, Color mark) {
  final ranges = matchRanges(text, tokens);
  if (ranges.isEmpty) return [TextSpan(text: text)];
  final spans = <InlineSpan>[];
  var at = 0;
  for (final r in ranges) {
    if (r.start > at) spans.add(TextSpan(text: text.substring(at, r.start)));
    spans.add(
      TextSpan(
        text: text.substring(r.start, r.end),
        style: TextStyle(backgroundColor: mark),
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
    TextSpan(children: markedSpans(text, tokens, OngColors.of(context).mark)),
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

/// A small uppercase label: `TIER 3`, `RAFFLE`, or the "You" badge.
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.you = false});

  /// The "You" badge on the user's own requests.
  const Tag.you({super.key}) : label = 'You', you = true;

  final String label;
  final bool you;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ong = OngColors.of(context);
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: you ? ong.you : null,
        border: you ? null : Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label.toUpperCase(),
        // shown in a WidgetSpan, which already scales it with the text around it
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: 10,
          height: 1.4,
          fontWeight: you ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: you ? 0.4 : 0.3,
          color: you ? ong.onYou : scheme.onSurfaceVariant,
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

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Watch the video',
      excludeSemantics: true,
      child: Tooltip(
        message: 'Watch the video',
        child: InkResponse(
          onTap: onPressed,
          radius: 24,
          containedInkWell: false,
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
      ),
    );
  }
}

// ------------------------------------------------------------------ thumbnails

/// Builds the image of a thumbnail URL; tests override it (no network).
final thumbnailImageProvider = Provider<ImageProvider Function(String url)>((ref) => NetworkImage.new);

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
  });

  final String? youtubeId;
  final double width;

  /// The 480 × 360 image (`hqdefault`) instead of the 320 × 180 one (`mqdefault`).
  final bool big;
  final double radius;

  /// Shown in the bottom left corner (`#1952`).
  final String? label;

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
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: width,
        height: height,
        color: ong.thumbnail,
        child: label == null
            ? content
            : Stack(
                fit: StackFit.expand,
                children: [
                  content,
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(color: const Color(0xBB000000), borderRadius: BorderRadius.circular(4)),
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
class ListSearchField extends StatefulWidget {
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
  State<ListSearchField> createState() => _ListSearchFieldState();
}

class _ListSearchFieldState extends State<ListSearchField> {
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
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
            child: InkWell(
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
                    ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) => controller.text.isEmpty
                          ? const SizedBox.shrink()
                          : IconButton(
                              tooltip: 'Clear',
                              icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
                              onPressed: _clear,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A horizontal scroll view that a mouse wheel scrolls too.
///
/// A wheel turns vertically only, and a mouse cannot drag a scroll view on
/// desktop: without this, what is past the right edge (most genre chips) would
/// be out of reach of a mouse.
class HorizontalScroll extends StatefulWidget {
  const HorizontalScroll({super.key, required this.padding, required this.child});

  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  State<HorizontalScroll> createState() => _HorizontalScrollState();
}

class _HorizontalScrollState extends State<HorizontalScroll> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: _onPointerSignal,
    child: SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      padding: widget.padding,
      child: widget.child,
    ),
  );
}

/// A horizontally scrolling row of filter chips.
class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => HorizontalScroll(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(spacing: 8, children: children),
  );
}

/// A filter chip of the design: label, optional icon and count.
///
/// Without [showLabel] it shows its [icon] (required then) and its count
/// alone, and [label] is only said to screen readers.
class ListChip extends StatelessWidget {
  const ListChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.count,
    this.showLabel = true,
  }) : assert(showLabel || icon != null, 'a chip without label shows an icon');

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final int? count;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    final count = this.count;
    final countStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: color.withValues(alpha: 0.75));
    final Widget? text = !showLabel
        ? (count == null ? null : Text(formatCount(count), style: countStyle))
        : count == null
        ? Text(label)
        : Text.rich(
            TextSpan(
              text: label,
              children: [TextSpan(text: '  ${formatCount(count)}', style: countStyle)],
            ),
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
    return _ChipTapTarget(
      child: FilterChip(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        // 32 px high with its border, not 34
        visualDensity: const VisualDensity(vertical: -1),
        selected: selected,
        onSelected: (_) => onTap(),
        labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color),
        label: icon == null ? text! : (showLabel ? withIcon : Semantics(label: label, child: withIcon)),
      ),
    );
  }
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
              style: TextButton.styleFrom(
                foregroundColor: scheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(48, _linkHeight),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
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

/// Whether scrollbars are always shown: on desktop (Windows app and desktop
/// browsers), where a mouse may drag them. Phones, in the browser too, show
/// them only while scrolling, over the content.
bool alwaysShowScrollbars(BuildContext context) => switch (Theme.of(context).platform) {
  TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux => true,
  _ => false,
};
