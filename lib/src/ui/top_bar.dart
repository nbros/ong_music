/// The top bar of the desktop look, in place of the rail and of the bottom
/// bar, in a window of any size: the app picture and its name, the three
/// destinations as text links, the full screen button at the right end.
library;

import 'dart:ui' show SemanticsRole;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state/settings_state.dart';
import 'fullscreen_button.dart';
import 'nav_rail.dart';
import 'outside_link.dart';
import 'theme.dart';
import 'widgets.dart';

/// Height of the top bar, its line included.
const double topBarHeight = 56;

/// The sizes of the bar at its full width: the picture 20 px from the left
/// edge, the name 10 px after it, the first link 20 px after the name, the
/// links 4 px apart with 14 px of padding on each side, the full screen
/// button 16 px from the right edge.
const double _edge = 20, _picture = 32, _nameGap = 10, _linksGap = 20, _linkSpacing = 4, _linkPadding = 14;
const double _endEdge = 16, _buttonWidth = 40, _buttonGap = 4;

/// The narrowest a window may be for the name; and, without the name, for
/// links with their full padding: below, the edges and the paddings shrink
/// down to these.
const double _narrowEdge = 16, _narrowLinksGap = 12, _minLinkPadding = 4;

/// Whether the bar has the room for the light/dark button, before the full screen [button]: only when everything
/// else is there at the sizes of the design, the name included.
@visibleForTesting
bool topBarHasThemeButton({
  required double width,
  required double nameWidth,
  required List<double> labelWidths,
  required bool button,
}) => topBarLayout(
  width: width - _buttonWidth - (button ? _buttonGap : 0),
  nameWidth: nameWidth,
  labelWidths: labelWidths,
  button: button,
).name;

/// What the bar shows in a window [width] wide whose name and labels are
/// [nameWidth] and [labelWidths] wide, with or without the full screen
/// [button]: the name only when everything fits at the sizes of the design;
/// without it, the paddings of the links, then the edges, shrink as needed.
/// [scale] is below 1 when nothing fits even then (text much larger than
/// usual): the links are scaled down, never cut.
@visibleForTesting
({bool name, double edge, double linksGap, double linkPadding, double scale}) topBarLayout({
  required double width,
  required double nameWidth,
  required List<double> labelWidths,
  required bool button,
}) {
  final labels = labelWidths.fold(0.0, (a, b) => a + b) + _linkSpacing * (labelWidths.length - 1);
  final end = _endEdge + (button ? _buttonWidth : 0);
  double fixed(double edge, double gap) => edge + _picture + gap + labels + end;
  final pads = 2.0 * labelWidths.length;
  final full = fixed(_edge, _linksGap) + _nameGap + nameWidth + pads * _linkPadding;
  if (full <= width) return (name: true, edge: _edge, linksGap: _linksGap, linkPadding: _linkPadding, scale: 1);
  if (fixed(_edge, _linksGap) + pads * _linkPadding <= width) {
    return (name: false, edge: _edge, linksGap: _linksGap, linkPadding: _linkPadding, scale: 1);
  }
  final narrow = fixed(_narrowEdge, _narrowLinksGap);
  final padding = ((width - narrow) / pads).clamp(_minLinkPadding, _linkPadding);
  final links = labels + pads * padding;
  final room = width - (narrow - labels);
  return (
    name: false,
    edge: _narrowEdge,
    linksGap: _narrowLinksGap,
    linkPadding: padding,
    scale: links <= room ? 1 : (room / links).clamp(0.1, 1),
  );
}

/// The top bar: [topBarHeight] high across the window, on the page
/// background, with a line under it. [destinations] are text links (their
/// icons are not shown), the one at [selectedIndex] in `onSurface` with a
/// line of the brand colour under it; [addresses] are their addresses, which
/// the web app makes links of the page (the browser shows them, a Ctrl/⌘ or
/// middle click opens them in another tab).
///
/// For screen readers and the keyboard, the links are the tabs of a tab bar,
/// as the destinations of the rail are; the picture and the name are not
/// controls.
class AppTopBar extends ConsumerWidget {
  const AppTopBar({
    super.key,
    required this.destinations,
    required this.addresses,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<NavDestination> destinations;
  final List<Uri> addresses;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const _nameStyle = TextStyle(fontSize: 17, fontWeight: FontWeight.w500);
  static const _linkStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w500);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final fullscreen = ref.watch(pageFullscreenProvider);
    final localizations = MaterialLocalizations.of(context);
    return Material(
      color: scheme.surface,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: topBarHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            // As large as the labels of the rail get, no more: the bar keeps its height, and the line under the
            // current link stays under its label.
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: maxRailLabelTextScale,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // measured as drawn: in the style the texts inherit here (the family of the platform), at the
                  // clamped scale
                  final inherited = DefaultTextStyle.of(context).style;
                  final scaler = MediaQuery.textScalerOf(context);
                  double widthOf(String text, TextStyle style) {
                    final painter = TextPainter(
                      text: TextSpan(text: text, style: inherited.merge(style)),
                      textDirection: Directionality.of(context),
                      textScaler: scaler,
                      maxLines: 1,
                    )..layout();
                    final width = painter.width;
                    painter.dispose();
                    return width.ceilToDouble();
                  }

                  final labelWidths = [for (final d in destinations) widthOf(d.label, _linkStyle)];
                  final nameWidth = widthOf('Ong Music', _nameStyle);
                  final layout = topBarLayout(
                    width: constraints.maxWidth,
                    nameWidth: nameWidth,
                    labelWidths: labelWidths,
                    button: fullscreen != null,
                  );
                  final themeButton = topBarHasThemeButton(
                    width: constraints.maxWidth,
                    nameWidth: nameWidth,
                    labelWidths: labelWidths,
                    button: fullscreen != null,
                  );
                  Widget links = Semantics(
                    role: SemanticsRole.tabBar,
                    explicitChildNodes: true,
                    container: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: _linkSpacing,
                      children: [
                        for (var i = 0; i < destinations.length; i++)
                          OutsideLink(
                            url: addresses[i].toString(),
                            label: destinations[i].label,
                            onOpen: () => onDestinationSelected(i),
                            // a tab for screen readers, not a link
                            linkSemantics: false,
                            builder: (context, open) => _TopBarLink(
                              label: destinations[i].label,
                              labelWidth: labelWidths[i],
                              padding: layout.linkPadding,
                              selected: i == selectedIndex,
                              // what the rail tells too, but on the web, where the browser tells it by itself
                              tabLabel: kIsWeb
                                  ? null
                                  : localizations.tabLabel(tabIndex: i + 1, tabCount: destinations.length),
                              onTap: open,
                            ),
                          ),
                      ],
                    ),
                  );
                  if (layout.scale < 1) {
                    links = FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(height: topBarHeight, child: links),
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: layout.edge),
                      Center(
                        child: Container(
                          width: _picture,
                          height: _picture,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3D2C3),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          // decoration: no action, nothing said
                          child: Image.asset(
                            'assets/ongZoom.png',
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.medium,
                            excludeFromSemantics: true,
                          ),
                        ),
                      ),
                      if (layout.name) ...[
                        const SizedBox(width: _nameGap),
                        Center(
                          child: Text(
                            'Ong Music',
                            maxLines: 1,
                            softWrap: false,
                            style: _nameStyle.copyWith(color: scheme.onSurface),
                          ),
                        ),
                      ],
                      SizedBox(width: layout.linksGap),
                      if (layout.scale < 1) Expanded(child: links) else links,
                      if (layout.scale >= 1) const Spacer(),
                      if (themeButton) const Center(child: ThemeButton()),
                      if (themeButton && fullscreen != null) const SizedBox(width: _buttonGap),
                      if (fullscreen != null) Center(child: FullscreenButton(fullscreen: fullscreen)),
                      const SizedBox(width: _endEdge),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Switches between the light and the dark theme, from the one on screen (the system's while the setting follows
/// it) to the other, which becomes the setting; the About tab keeps the three choices. The icon is that of the
/// theme the button gives, at one size: nothing moves.
class ThemeButton extends ConsumerWidget {
  const ThemeButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return IconButton(
      tooltip: dark ? 'Light theme' : 'Dark theme',
      onPressed: () =>
          ref.read(themePreferenceProvider.notifier).set(dark ? ThemePreference.light : ThemePreference.dark),
      icon: Icon(dark ? Icons.light_mode : Icons.dark_mode, color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

/// A destination of the top bar: its label in the secondary text colour, in
/// `onSurface` when hovered or current; the current one with a line 3 px high
/// of the brand colour under its label, at the bottom edge of the bar. A press
/// dims the label at once; the keyboard focus shows as a tint behind it.
/// Only colours change: nothing moves or changes size.
class _TopBarLink extends StatefulWidget {
  const _TopBarLink({
    required this.label,
    required this.labelWidth,
    required this.padding,
    required this.selected,
    required this.tabLabel,
    required this.onTap,
  });

  final String label;
  final double labelWidth;
  final double padding;
  final bool selected;
  final String? tabLabel;
  final VoidCallback onTap;

  @override
  State<_TopBarLink> createState() => _TopBarLinkState();
}

class _TopBarLinkState extends State<_TopBarLink> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final tabLabel = widget.tabLabel;
    final color = selected || _hovered ? scheme.onSurface : scheme.onSurfaceVariant;
    return MergeSemantics(
      child: Semantics(
        role: SemanticsRole.tab,
        selected: selected,
        button: true,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (value) => setState(() => _hovered = value),
          onHighlightChanged: (value) => setState(() => _pressed = value),
          // the keyboard focus only, at once, in a rounded rectangle 36 px high around the label
          overlayColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.focused) ? scheme.onSurface.withValues(alpha: 0.1) : Colors.transparent,
          ),
          hoverDuration: Duration.zero,
          customBorder: const InsetRoundedBorder(insets: EdgeInsets.symmetric(vertical: 10), radius: 8),
          splashFactory: NoSplash.splashFactory,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.padding),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: widget.labelWidth,
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: AppTopBar._linkStyle.copyWith(
                      color: _pressed ? color.withValues(alpha: color.a * 0.7) : color,
                    ),
                  ),
                ),
                if (selected)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: OngColors.of(context).brand,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ),
                  ),
                if (tabLabel != null) Semantics(label: tabLabel),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
