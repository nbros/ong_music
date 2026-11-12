/// The navigation rail of the medium and expanded windows: the app picture,
/// then the three destinations of the bottom bar of the phone layout.
library;

import 'dart:ui' show SemanticsRole;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'layout.dart';

/// The largest text scale of the labels of the rail: the limit Material gives
/// the labels of its navigation bar.
const double maxRailLabelTextScale = 1.3;

/// A destination of the navigation: its icon and its label.
typedef NavDestination = ({IconData icon, String label});

/// The rail, [railWidth] wide plus the safe area on its left, as high as the
/// window.
///
/// The sizes of the design: the picture 40 × 40 at 16 px from the top, the
/// destinations 56 px high and 12 px apart from 82 px down, each one an
/// indicator of 56 × 32 over its label. No tooltip: the label is there.
class AppNavigationRail extends StatelessWidget {
  const AppNavigationRail({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: railWidth,
          // a window too low for the whole rail (large text in a phone held sideways) scrolls it
          child: SingleChildScrollView(
            primary: false,
            padding: const EdgeInsets.only(top: 16, bottom: 12),
            child: Semantics(
              role: SemanticsRole.tabBar,
              explicitChildNodes: true,
              container: true,
              child: Column(
                spacing: 12,
                children: [
                  // decoration: no action, nothing said
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Container(
                      width: 40,
                      height: 40,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3D2C3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Image.asset(
                        'assets/ongZoom.png',
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.medium,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                  for (var i = 0; i < destinations.length; i++)
                    _RailDestination(
                      destination: destinations[i],
                      selected: i == selectedIndex,
                      // what the bar tells too, but on the web, where the browser tells it by itself
                      tabLabel: kIsWeb ? null : localizations.tabLabel(tabIndex: i + 1, tabCount: destinations.length),
                      onTap: () => onDestinationSelected(i),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailDestination extends StatefulWidget {
  const _RailDestination({
    required this.destination,
    required this.selected,
    required this.tabLabel,
    required this.onTap,
  });

  final NavDestination destination;
  final bool selected;
  final String? tabLabel;
  final VoidCallback onTap;

  @override
  State<_RailDestination> createState() => _RailDestinationState();
}

class _RailDestinationState extends State<_RailDestination> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final mouse = AppLayout.mouseOf(context);
    // a colour, never a change of size or place: hover (with a mouse), keyboard focus, press
    final overlay = _pressed || _focused
        ? scheme.onSurface.withValues(alpha: 0.1)
        : (_hovered && mouse && !selected ? scheme.onSurface.withValues(alpha: 0.08) : null);
    final base = selected ? scheme.secondaryContainer : Colors.transparent;
    final indicator = overlay == null ? base : Color.alphaBlend(overlay, base);
    final tabLabel = widget.tabLabel;
    return MergeSemantics(
      child: Semantics(
        role: SemanticsRole.tab,
        selected: selected,
        button: true,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (value) => setState(() => _hovered = value),
          onFocusChange: (value) => setState(() => _focused = value),
          onHighlightChanged: (value) => setState(() => _pressed = value),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          // 56 px high at the default text size, more with a larger one
          child: Stack(
            alignment: Alignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: railWidth, minHeight: 56),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 56,
                      height: 32,
                      decoration: BoxDecoration(color: indicator, borderRadius: BorderRadius.circular(16)),
                      child: Icon(
                        widget.destination.icon,
                        size: 24,
                        color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
                      ),
                    ),
                    // As large as the labels of the bottom bar get, no more: at that size "Highlights" still
                    // fits in the rail; larger, it would be cut.
                    MediaQuery.withClampedTextScaling(
                      maxScaleFactor: maxRailLabelTextScale,
                      child: Text(
                        widget.destination.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 20 / 12,
                          fontWeight: FontWeight.w500,
                          color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (tabLabel != null) Semantics(label: tabLabel),
            ],
          ),
        ),
      ),
    );
  }
}
