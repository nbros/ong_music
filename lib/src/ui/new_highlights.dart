/// The marks of the highlights new since the last visit (see
/// `new_highlights_state.dart`): the `New` mark of their rows, and the count
/// on the Highlights destination of the navigation.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state/new_highlights_state.dart';
import 'format.dart';
import 'theme.dart';

/// The word of the mark of a new highlight's row, and of the chip that keeps
/// only the new highlights.
const String newLabel = 'New';

/// What a screen reader says of the count of new highlights: `1 new
/// highlight`, `3 new highlights`.
String newHighlightsLabel(int count) => plural(count, 'new highlight');

/// The `New` mark of a highlight row, over the top left corner of its
/// thumbnail (see `HighlightRow`): it takes no room in the row. The colours
/// of the brand, the same in both themes, as the picture under it.
class NewMark extends StatelessWidget {
  const NewMark({super.key});

  @override
  Widget build(BuildContext context) {
    final ong = OngColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(color: ong.brand, borderRadius: BorderRadius.circular(4)),
      child: Text(
        newLabel,
        // in the thumbnail, which keeps its size whatever the text size
        textScaler: TextScaler.noScaling,
        style: TextStyle(fontSize: 10, height: 1.4, fontWeight: FontWeight.w600, color: ong.onBrand),
      ),
    );
  }
}

/// [child], the icon or the label of the Highlights destination of the
/// navigation, with the count of the new highlights over its top end corner
/// while there are any: drawn over what is around it, it moves nothing. Said
/// as [newHighlightsLabel], with the destination.
class NewHighlightsBadge extends ConsumerWidget {
  const NewHighlightsBadge({super.key, required this.child, this.offset});

  final Widget child;

  /// [Badge.offset]: where the count is from the top end corner of [child]
  /// (the default of [Badge] when null).
  final Offset? offset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(newHighlightCountProvider);
    final ong = OngColors.of(context);
    return Badge(
      isLabelVisible: count > 0,
      offset: offset,
      backgroundColor: ong.brand,
      textColor: ong.onBrand,
      label: Semantics(
        label: newHighlightsLabel(count),
        excludeSemantics: true,
        child: Text(
          count > 99 ? '99+' : formatCount(count),
          // as the label it stands by, which keeps its size up to the limit of the navigation
          textScaler: TextScaler.noScaling,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      child: child,
    );
  }
}
