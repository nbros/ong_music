/// The feedback of the controls in the desktop look: no ink ripple, and the
/// hover, focus and press states as flat tints, there in the first frame
/// after the event and gone in the first frame after its end, as on a web
/// page. Phones and tablets keep Material's ink (ripples, highlights that fade
/// in and out).
///
/// Material's ink cannot be made instant by the theme: the highlight of a
/// press fades in and out over 200 ms whatever the theme says, and a control
/// on a row (a ⋮ button) only learns of its press 100 ms after it, when the
/// gesture arena gives up waiting for the row. So the controls of the desktop
/// look turn their ink off (no overlay, no splash) and paint their states
/// themselves, with a [StateLayer]:
/// - the app's own ink wells through [AppInkWell];
/// - the buttons through the theme ([instantButtonStyle]), and
///   [platformButtonStyle] for the styles that bring an overlay of their own;
/// - the chips and the segmented button through the colours of their theme,
///   which follow their states at once (see `theme.dart`);
/// - what the framework builds itself (the licences page) through
///   [InstantInk], a press without ripple.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import 'layout.dart';

/// Opacity of the hover state layer, over the colour of the content.
const double hoverStateOpacity = 0.08;

/// Opacity of the focus state layer (keyboard focus).
const double focusStateOpacity = 0.1;

/// Opacity of the press state layer, over the hover one.
const double pressStateOpacity = 0.1;

/// The tint of the states of a control: [hover] while [hovered], [focus]
/// while [focused] (by the keyboard), [press] while [pressed], each over the
/// ones before it; null for none. The state layers and the colours of the
/// chips and segments of the desktop theme (see `theme.dart`) all compose
/// their tints with it.
Color? stateTint({
  required bool hovered,
  required bool focused,
  required bool pressed,
  required Color hover,
  required Color focus,
  required Color press,
}) {
  Color? tint;
  void add(Color layer) => tint = tint == null ? layer : Color.alphaBlend(layer, tint!);
  if (hovered) add(hover);
  if (focused) add(focus);
  if (pressed) add(press);
  return tint;
}

/// The tints of the states of a control, painted behind [child] in [shape]
/// (the whole box when null): [hover] while [states] says hovered, [focus]
/// while it says focused and the keyboard moves the focus, [press] while it
/// says pressed or a mouse button is held down on it.
///
/// A mouse press shows in the frame after the button goes down, from the
/// pointer event itself: not from the tap gesture, which a control inside
/// another one (a button on a row) only gets 100 ms later. Other pointers
/// (touch, stylus) show their press when the tap gesture starts, as
/// Material's ink does.
///
/// The innermost state layer under the pointer takes the press, whatever the
/// pointer (see [takePress]): the layers around it show no press until the
/// pointer is up, even when their own tap gesture starts all the same (when
/// the gesture arena gives up waiting, 100 ms later): the row around a
/// pressed button or thumbnail is not tinted, as the press does not activate
/// it.
///
/// A change of state only repaints the layer and the control over it: the
/// painter follows [states], the press of the mouse and the way the focus
/// moves, and nothing is built again. Only a colour changes: nothing moves
/// or changes size.
class StateLayer extends StatefulWidget {
  const StateLayer({
    super.key,
    required this.states,
    required this.hover,
    required this.focus,
    required this.press,
    this.shape,
    required this.child,
  });

  final ValueListenable<Set<WidgetState>> states;
  final Color hover;
  final Color focus;
  final Color press;
  final ShapeBorder? shape;
  final Widget child;

  /// Takes the press of [event] for a control that is not a [StateLayer]
  /// (the thumbnail link of a row): the state layers around it leave it.
  static void takePress(PointerDownEvent event) => _StateLayerState._taken = event.original ?? event;

  @override
  State<StateLayer> createState() => _StateLayerState();
}

class _StateLayerState extends State<StateLayer> {
  /// The press the innermost state layer under the pointer took: a pointer
  /// event reaches the innermost listener first, and each press is a new
  /// event.
  static PointerEvent? _taken;

  /// The press of the pointer [_pointer]: this control's own press with the
  /// mouse, or one an inner control took.
  final _press = ValueNotifier(_Press.none);
  int? _pointer;

  /// Focused while the keyboard moves the focus (Material's focus highlight
  /// shows then only).
  final _keyboardFocus = ValueNotifier(false);

  /// Whether the way the focus moves is followed: only while focused.
  bool _followingMode = false;

  bool get _enabled => !widget.states.value.contains(WidgetState.disabled);

  @override
  void initState() {
    super.initState();
    widget.states.addListener(_onStates);
    _onStates();
  }

  @override
  void didUpdateWidget(StateLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.states != widget.states) {
      oldWidget.states.removeListener(_onStates);
      widget.states.addListener(_onStates);
      _onStates();
    }
  }

  @override
  void dispose() {
    widget.states.removeListener(_onStates);
    if (_followingMode) FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
    _press.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  void _onStates() {
    if (!_enabled && _press.value == _Press.mouse) _press.value = _Press.none;
    final focused = widget.states.value.contains(WidgetState.focused);
    if (focused != _followingMode) {
      _followingMode = focused;
      if (focused) {
        FocusManager.instance.addHighlightModeListener(_onHighlightMode);
      } else {
        FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
      }
    }
    _onHighlightMode(FocusManager.instance.highlightMode);
  }

  void _onHighlightMode(FocusHighlightMode mode) =>
      _keyboardFocus.value = _followingMode && mode == FocusHighlightMode.traditional;

  void _onDown(PointerDownEvent event) {
    final original = event.original ?? event;
    // the primary button of a mouse; any touch or stylus
    if (event.kind == PointerDeviceKind.mouse && event.buttons != kPrimaryMouseButton) return;
    if (identical(_taken, original)) {
      // an inner control took it: no press here until it ends, whatever this control's tap gesture says
      _pointer = event.pointer;
      _press.value = _Press.inner;
      return;
    }
    // a disabled control leaves the press to the control around it
    if (!_enabled) return;
    _taken = original;
    if (event.kind == PointerDeviceKind.mouse) {
      _pointer = event.pointer;
      _press.value = _Press.mouse;
    }
  }

  void _onUp(PointerEvent event) {
    // the control may be gone while its press lasts (a row scrolled out of a lazy list under a held mouse)
    if (!mounted || event.pointer != _pointer) return;
    _pointer = null;
    _press.value = _Press.none;
  }

  @override
  Widget build(BuildContext context) => Listener(
    // translucent: the whole control, its empty parts included
    behavior: HitTestBehavior.translucent,
    onPointerDown: _onDown,
    onPointerUp: _onUp,
    onPointerCancel: _onUp,
    child: CustomPaint(
      painter: _LayerPainter(
        states: widget.states,
        press: _press,
        keyboardFocus: _keyboardFocus,
        hover: widget.hover,
        focus: widget.focus,
        pressColor: widget.press,
        shape: widget.shape,
        textDirection: Directionality.maybeOf(context),
      ),
      child: widget.child,
    ),
  );
}

/// Where the press of a state layer stands.
enum _Press {
  none,

  /// The control's own press, with the mouse.
  mouse,

  /// A press an inner control took.
  inner,
}

class _LayerPainter extends CustomPainter {
  _LayerPainter({
    required this.states,
    required this.press,
    required this.keyboardFocus,
    required this.hover,
    required this.focus,
    required this.pressColor,
    required this.shape,
    required this.textDirection,
  }) : super(repaint: Listenable.merge([states, press, keyboardFocus]));

  final ValueListenable<Set<WidgetState>> states;
  final ValueListenable<_Press> press;
  final ValueListenable<bool> keyboardFocus;
  final Color hover;
  final Color focus;
  final Color pressColor;
  final ShapeBorder? shape;
  final TextDirection? textDirection;

  /// The tint of the states now; null for none.
  Color? get color {
    final states = this.states.value;
    if (states.contains(WidgetState.disabled)) return null;
    final press = this.press.value;
    return stateTint(
      hovered: states.contains(WidgetState.hovered),
      focused: keyboardFocus.value,
      pressed: press == _Press.mouse || (press == _Press.none && states.contains(WidgetState.pressed)),
      hover: hover,
      focus: focus,
      press: pressColor,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final color = this.color;
    if (color == null || color.a == 0) return;
    final paint = Paint()..color = color;
    final rect = Offset.zero & size;
    final shape = this.shape;
    if (shape == null) {
      canvas.drawRect(rect, paint);
    } else {
      canvas.drawPath(shape.getOuterPath(rect, textDirection: textDirection), paint);
    }
  }

  @override
  bool shouldRepaint(_LayerPainter oldDelegate) =>
      states != oldDelegate.states ||
      hover != oldDelegate.hover ||
      focus != oldDelegate.focus ||
      pressColor != oldDelegate.pressColor ||
      shape != oldDelegate.shape ||
      textDirection != oldDelegate.textDirection;
}

/// The states of a control that has no listenable of its own (a button, whose
/// background builder is given them at each build).
class _Fixed implements ValueListenable<Set<WidgetState>> {
  const _Fixed(this.value);

  @override
  final Set<WidgetState> value;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  bool operator ==(Object other) => other is _Fixed && setEquals(other.value, value);

  @override
  int get hashCode => Object.hashAllUnordered(value);
}

/// The app's [InkWell]: on phones and tablets, an [InkWell] with the given
/// arguments, as it always was; in the desktop look, the same control without
/// ink and a [StateLayer] in its shape instead.
///
/// Without ink, not even an invisible one: an [InkWell] fades the highlight
/// of a press in and out over 200 ms whatever its colour, a dozen frames or
/// more for every press and every release. The control of the desktop look is
/// made of what an [InkWell] is made of, but its ink: a tap gesture, the
/// keyboard's activation (Enter, Space), the focus, the hover and its mouse
/// cursor, the tap for screen readers.
///
/// The colours of the states are those of the ink well: [overlayColor], or
/// [hoverColor] and the theme's hover and focus colours, and `onSurface` at
/// [pressStateOpacity] for a press (where Material's ink has a grey highlight
/// and a ripple).
class AppInkWell extends StatefulWidget {
  const AppInkWell({
    super.key,
    required this.onTap,
    this.customBorder,
    this.borderRadius,
    this.hoverColor,
    this.overlayColor,
    this.canRequestFocus = true,
    this.excludeFromSemantics = false,
    required this.child,
  });

  final VoidCallback? onTap;
  final ShapeBorder? customBorder;
  final BorderRadius? borderRadius;
  final Color? hoverColor;
  final WidgetStateProperty<Color?>? overlayColor;
  final bool canRequestFocus;
  final bool excludeFromSemantics;
  final Widget child;

  @override
  State<AppInkWell> createState() => _AppInkWellState();
}

class _AppInkWellState extends State<AppInkWell> with AutomaticKeepAliveClientMixin {
  /// The states of the control of the desktop look.
  final _states = WidgetStatesController();

  /// Whether the control, or a control in it, has the keyboard focus (desktop
  /// look): it stays alive while it does, as Material's ink wells do, so that
  /// the focus of a row scrolled out of a lazy list stays on it instead of
  /// going back to the control focused before it (the search field).
  bool _focused = false;

  @override
  bool get wantKeepAlive => _focused;

  void _onFocusChange(bool focused) {
    _states.update(WidgetState.focused, focused);
    if (focused == _focused) return;
    _focused = focused;
    updateKeepAlive();
  }

  late final Map<Type, Action<Intent>> _actions = {
    ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _activate()),
    ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => _activate()),
  };

  bool get _enabled => widget.onTap != null;

  @override
  void initState() {
    super.initState();
    _states.update(WidgetState.disabled, !_enabled);
  }

  @override
  void didUpdateWidget(AppInkWell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _states.update(WidgetState.disabled, !_enabled);
    if (!_enabled) _states.update(WidgetState.pressed, false);
  }

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  void _activate() => widget.onTap?.call();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!AppLayout.desktopOf(context)) {
      return InkWell(
        onTap: widget.onTap,
        customBorder: widget.customBorder,
        borderRadius: widget.borderRadius,
        hoverColor: widget.hoverColor,
        overlayColor: widget.overlayColor,
        canRequestFocus: widget.canRequestFocus,
        excludeFromSemantics: widget.excludeFromSemantics,
        child: widget.child,
      );
    }
    final theme = Theme.of(context);
    final overlay = widget.overlayColor;
    final borderRadius = widget.borderRadius;
    final shape =
        widget.customBorder ?? (borderRadius == null ? null : RoundedRectangleBorder(borderRadius: borderRadius));
    final enabled = _enabled;
    final states = _states;
    return Actions(
      actions: _actions,
      child: Focus(
        canRequestFocus: enabled && widget.canRequestFocus,
        onFocusChange: _onFocusChange,
        child: MouseRegion(
          // as an InkWell: the hand on the web, the arrow in the Windows app
          cursor: WidgetStateMouseCursor.adaptiveClickable.resolve({if (!enabled) WidgetState.disabled}),
          onEnter: (_) => states.update(WidgetState.hovered, true),
          onExit: (_) => states.update(WidgetState.hovered, false),
          child: Semantics(
            onTap: enabled && !widget.excludeFromSemantics ? _activate : null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTapDown: enabled ? (_) => states.update(WidgetState.pressed, true) : null,
              onTapCancel: enabled ? () => states.update(WidgetState.pressed, false) : null,
              onTap: enabled
                  ? () {
                      states.update(WidgetState.pressed, false);
                      _activate();
                    }
                  : null,
              child: StateLayer(
                states: states,
                hover: overlay?.resolve(const {WidgetState.hovered}) ?? widget.hoverColor ?? theme.hoverColor,
                focus: overlay?.resolve(const {WidgetState.focused}) ?? theme.focusColor,
                press:
                    overlay?.resolve(const {WidgetState.pressed}) ??
                    theme.colorScheme.onSurface.withValues(alpha: pressStateOpacity),
                shape: shape,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The part of every button style of the desktop look (in the button themes,
/// see `theme.dart`): no overlay, whose highlights fade in and out, no ripple,
/// and a [StateLayer] of the foreground colour of the button behind its
/// content instead, at Material's opacities. The button clips it to its
/// shape (a button with a background builder clips its content).
final ButtonStyle instantButtonStyle = ButtonStyle(
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  splashFactory: NoSplash.splashFactory,
  backgroundBuilder: (context, states, child) => _ButtonStateLayer(states: states, child: child!),
);

class _ButtonStateLayer extends StatelessWidget {
  const _ButtonStateLayer({required this.states, required this.child});

  final Set<WidgetState> states;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // under the button's own theme and material: the colour of its icon and of its text
    final foreground =
        IconTheme.of(context).color ??
        DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.onSurface;
    return StateLayer(
      // a copy: the button changes its own set in place
      states: _Fixed(Set.of(states)),
      hover: foreground.withValues(alpha: hoverStateOpacity),
      focus: foreground.withValues(alpha: focusStateOpacity),
      press: foreground.withValues(alpha: pressStateOpacity),
      child: child,
    );
  }
}

/// [style] as the look of the platform needs it: unchanged on phones and
/// tablets; in the desktop look, without the overlay that a `styleFrom` with a
/// foreground colour brings (it would win over the theme's
/// [instantButtonStyle] and fade in and out).
ButtonStyle platformButtonStyle(BuildContext context, ButtonStyle style) => AppLayout.desktopOf(context)
    ? style.copyWith(overlayColor: const WidgetStatePropertyAll(Colors.transparent))
    : style;

/// The ink of a press in the desktop look, for the ink wells of the framework
/// that use the theme's ink (the chips, the rows of the licences page): a flat
/// tint over the whole control, in its shape, there as soon as the press
/// starts and gone as soon as it ends. No ripple, nothing that grows or fades.
class InstantInk extends InteractiveInkFeature {
  InstantInk({
    required super.controller,
    required super.referenceBox,
    required super.color,
    required TextDirection textDirection,
    super.customBorder,
    BorderRadius? borderRadius,
    RectCallback? rectCallback,
    super.onRemoved,
  }) : _textDirection = textDirection,
       _borderRadius = borderRadius ?? BorderRadius.zero,
       _rectCallback = rectCallback {
    controller.addInkFeature(this);
  }

  /// The factory of the theme of the desktop look.
  static const InteractiveInkFeatureFactory splashFactory = _InstantInkFactory();

  final TextDirection _textDirection;
  final BorderRadius _borderRadius;
  final RectCallback? _rectCallback;

  @override
  void confirm() => dispose();

  @override
  void cancel() => dispose();

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    final paint = Paint()..color = color;
    final rect = _rectCallback?.call() ?? Offset.zero & referenceBox.size;
    canvas.save();
    canvas.transform(transform.storage);
    final border = customBorder;
    if (border != null) {
      canvas.drawPath(border.getOuterPath(rect, textDirection: _textDirection), paint);
    } else if (_borderRadius != BorderRadius.zero) {
      canvas.drawRRect(_borderRadius.toRRect(rect), paint);
    } else {
      canvas.drawRect(rect, paint);
    }
    canvas.restore();
  }
}

class _InstantInkFactory extends InteractiveInkFeatureFactory {
  const _InstantInkFactory();

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) => InstantInk(
    controller: controller,
    referenceBox: referenceBox,
    color: color,
    textDirection: textDirection,
    customBorder: customBorder,
    borderRadius: borderRadius,
    rectCallback: rectCallback,
    onRemoved: onRemoved,
  );
}

/// The hover of the rows of a page that the framework builds itself (the
/// licences page), in the desktop look: Material's list tiles fade their
/// hover in over 50 ms, which no theme changes. Under this widget their own
/// hover is transparent, and the hover colour of the theme lies at once over
/// the tappable [ListTile] under the mouse (found by a hit test: not a row the
/// app bar covers), within its list, until the mouse leaves it or the list
/// scrolls it away.
class InstantTileHover extends StatefulWidget {
  const InstantTileHover({super.key, required this.child});

  final Widget child;

  @override
  State<InstantTileHover> createState() => _InstantTileHoverState();
}

class _InstantTileHoverState extends State<InstantTileHover> {
  /// Where the mouse is, in global coordinates; null when away.
  Offset? _pointer;

  /// The row under the mouse, in the coordinates of this widget.
  Rect? _row;

  void _update() {
    if (!mounted) return;
    final pointer = _pointer;
    final self = context.findRenderObject();
    Rect? found;
    if (pointer != null && self is RenderBox && self.attached) {
      // what is really under the mouse: not a row under the app bar, which a row scrolled up goes under
      final result = HitTestResult();
      WidgetsBinding.instance.hitTestInView(result, pointer, View.of(context).viewId);
      final hit = {for (final entry in result.path) entry.target};
      void visit(Element element) {
        if (found != null) return;
        final widget = element.widget;
        if (widget is ListTile) {
          final box = element.findRenderObject();
          if (widget.onTap != null && box is RenderBox && box.attached && box.hasSize && hit.contains(box)) {
            var row = MatrixUtils.transformRect(box.getTransformTo(self), Offset.zero & box.size);
            // the part of the row in its list, never over what lies around the list
            final list = Scrollable.maybeOf(element)?.context.findRenderObject();
            if (list is RenderBox && list.attached && list.hasSize) {
              row = row.intersect(MatrixUtils.transformRect(list.getTransformTo(self), Offset.zero & list.size));
            }
            if (!row.isEmpty) found = row;
          }
          return;
        }
        element.visitChildren(visit);
      }

      context.visitChildElements(visit);
    }
    if (found != _row) setState(() => _row = found);
  }

  void _onHover(PointerEvent event) {
    _pointer = event.position;
    _update();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = _row;
    return Theme(
      // the tiles' own hover, which fades in
      data: theme.copyWith(hoverColor: Colors.transparent),
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          // the rows moved under a mouse at rest: after the frame that lays them out
          WidgetsBinding.instance.addPostFrameCallback((_) => _update());
          return false;
        },
        child: MouseRegion(
          opaque: false,
          onHover: _onHover,
          onExit: (_) {
            _pointer = null;
            _update();
          },
          child: CustomPaint(
            foregroundPainter: row == null ? null : _RowPainter(row: row, color: theme.hoverColor),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _RowPainter extends CustomPainter {
  const _RowPainter({required this.row, required this.color});

  final Rect row;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(row, Paint()..color = color);

  @override
  bool shouldRepaint(_RowPainter oldDelegate) => row != oldDelegate.row || color != oldDelegate.color;
}
