/// The controls that open an outside address (a video, a page of the
/// artist, the privacy policy) as links of the browser, in the web app.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/model.dart';
import '../web/link_anchor.dart';
import '../web/web_platform.dart';
import 'actions.dart';
import 'video_preview.dart';

/// The links of the page; null in the native apps. Overridden in tests.
final linkAnchorsProvider = Provider<LinkAnchors?>((ref) => linkAnchors());

/// How long a mouse stays on a control before the link of the page comes
/// over it: long enough that the controls only passing under the mouse (a
/// list scrolled by the wheel goes by a row in less) get none, short enough
/// that the address the browser shows seems to come with the mouse.
const Duration linkAnchorDelay = Duration(milliseconds: 100);

/// Whether a click with the keys held now is one the browser handles itself
/// on a link: Ctrl, ⌘, Shift or Alt (another tab, a window, a download).
bool browserHandlesClick() {
  final keyboard = HardwareKeyboard.instance;
  return keyboard.isControlPressed || keyboard.isMetaPressed || keyboard.isShiftPressed || keyboard.isAltPressed;
}

/// The control [builder] makes, opening [url] with [onOpen], as a link of the
/// browser in the web app:
/// - with a mouse resting on it ([linkAnchorDelay]), an invisible link of the
///   page lies over it (one at a time in the whole app, see
///   `link_anchor_web.dart`): the browser shows the address, a Ctrl/⌘-click
///   or a middle click opens it in another tab, its context menu offers to
///   copy it; a plain click is the control's, as before;
/// - screen readers have one node, said as a link to [url], named [label]
///   (the control's own name) with the control's action, in place of the
///   control's own node.
///
/// For a [video], a click the browser opens in front (Shift: a window, a tab
/// in front) stops the video playing in the app first, as [onOpen] does
/// (never two sounds); a Ctrl/⌘ or middle click, which opens a tab behind,
/// leaves it playing.
///
/// In the native apps, and without [url], only the control: as it always was.
class OutsideLink extends ConsumerStatefulWidget {
  const OutsideLink({
    super.key,
    required this.url,
    required this.label,
    required this.onOpen,
    this.video = false,
    required this.builder,
  });

  final String? url;

  /// What screen readers call the link: the control's own name.
  final String label;

  /// What activating the control does: a tap, a plain click, Enter, a screen
  /// reader.
  final VoidCallback onOpen;

  final bool video;

  /// The control, which calls the given callback when activated.
  final Widget Function(BuildContext context, VoidCallback open) builder;

  @override
  ConsumerState<OutsideLink> createState() => _OutsideLinkState();
}

class _OutsideLinkState extends ConsumerState<OutsideLink> {
  // read once: it never changes, and a list builds this for each row coming in
  late final LinkAnchors? _anchors = ref.read(linkAnchorsProvider);

  /// Whether the link of the page lies over the control: the mouse moved over
  /// it and stayed, and has not left. Not when the control only passes under
  /// a mouse at rest or moving (a list scrolled by the wheel): no element
  /// made and dropped per row going by.
  bool _anchored = false;

  Timer? _delay;

  void _open() {
    if (_anchored && browserHandlesClick()) {
      // the browser opens it, from the link under the mouse
      if (widget.video && HardwareKeyboard.instance.isShiftPressed) ref.read(inPlaceVideosProvider).stop();
      return;
    }
    widget.onOpen();
  }

  /// The mouse moved over the control (not the control under the mouse).
  void _hovered() {
    if (_anchored || _delay != null) return;
    _delay = Timer(linkAnchorDelay, () {
      _delay = null;
      if (mounted) setState(() => _anchored = true);
    });
  }

  void _left() {
    _delay?.cancel();
    _delay = null;
    if (_anchored) setState(() => _anchored = false);
  }

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anchors = _anchors;
    final url = widget.url;
    final uri = url == null ? null : Uri.tryParse(url);
    if (anchors == null || uri == null) return widget.builder(context, widget.onOpen);
    // one node: a node of the control under a node of the link would be two for screen readers
    return Semantics(
      container: true,
      link: true,
      linkUrl: uri,
      label: widget.label,
      onTap: _open,
      excludeSemantics: true,
      child: MouseRegion(
        // the hover states of the control and of what is behind it stay as they are
        opaque: false,
        onHover: (_) => _hovered(),
        onExit: (_) => _left(),
        child: Stack(
          // exactly the size and place of the control: nothing moves when the link comes and goes
          fit: StackFit.passthrough,
          children: [
            widget.builder(context, _open),
            if (_anchored) Positioned.fill(child: anchors.anchor(uri)),
          ],
        ),
      ),
    );
  }
}

/// [OutsideLink] to the video of [highlight] (it must have one), opened with
/// [openVideo], or with [onOpen] when given.
class VideoLink extends ConsumerWidget {
  const VideoLink({super.key, required this.highlight, required this.label, this.onOpen, required this.builder});

  final Highlight highlight;

  /// What screen readers call the link: the control's own name.
  final String label;
  final VoidCallback? onOpen;
  final Widget Function(BuildContext context, VoidCallback open) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) => OutsideLink(
    url: highlight.youtubeId == null ? null : highlight.url,
    label: label,
    video: true,
    onOpen: onOpen ?? () => openVideo(context, ref, highlight),
    builder: builder,
  );
}
