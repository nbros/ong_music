/// The detail pane of an expanded window, beside the list of a tab: the fiche
/// of the row chosen in the list, or of a link followed from a fiche, with a
/// back bar to return to the fiche under it.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state/catalogue_state.dart';
import 'sheets.dart';
import 'view_state.dart';
import 'widgets.dart';

/// Height of the back bar.
const double backBarHeight = 56;

/// The detail pane of [tab] ([AppTab.highlights] or [AppTab.ongLog]): a card
/// beside the list, showing the last fiche of [detailPaneProvider].
///
/// Escape, outside a text field, goes back to the fiche under the one on
/// screen.
class DetailPane extends ConsumerStatefulWidget {
  const DetailPane({super.key, required this.tab});

  final AppTab tab;

  @override
  ConsumerState<DetailPane> createState() => _DetailPaneState();
}

class _DetailPaneState extends ConsumerState<DetailPane> {
  @override
  void initState() {
    super.initState();
    // before the focused widget: Escape would otherwise reach nothing, or a button of the fiche
    FocusManager.instance.addEarlyKeyEventHandler(_onKey);
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_onKey);
    super.dispose();
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape || !mounted) {
      return KeyEventResult.ignored;
    }
    // the pane on screen, not under a sheet or a dialog, and not the Escape of a search field
    if (ref.read(selectedTabProvider) != widget.tab ||
        !(ModalRoute.of(context)?.isCurrent ?? true) ||
        isEditingText()) {
      return KeyEventResult.ignored;
    }
    return ref.read(detailPaneProvider(widget.tab).notifier).pop() ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final stack = ref.watch(detailPaneProvider(widget.tab));
    final scheme = Theme.of(context).colorScheme;
    // without catalogue (being downloaded again) the card waits, as the list does
    final top = ref.watch(currentCatalogueProvider.select((c) => c != null)) ? stack.lastOrNull : null;
    final under = stack.length > 1 ? stack[stack.length - 2] : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(4, 12, 12, 12 + MediaQuery.paddingOf(context).bottom),
      child: Material(
        color: scheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: top == null
            ? null
            : MediaQuery.removePadding(
                context: context,
                removeBottom: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (under != null)
                      _BackBar(
                        title: ficheTitle(under),
                        onBack: () => ref.read(detailPaneProvider(widget.tab).notifier).pop(),
                      ),
                    Expanded(
                      child: DetailPaneScope(
                        tab: widget.tab,
                        top: under == null ? 24 : 0,
                        // a fiche of its own (scroll position, state) for each place in the stack: another fiche
                        // starts at its top, the same one after a refresh stays where it was
                        child: _FicheHost(key: ValueKey((stack.length, top.identity)), fiche: top),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// A fiche in the pane, with a scroll controller of its own: the primary one
/// of the window belongs to the About tab.
class _FicheHost extends StatefulWidget {
  const _FicheHost({super.key, required this.fiche});

  final Fiche fiche;

  @override
  State<_FicheHost> createState() => _FicheHostState();
}

class _FicheHostState extends State<_FicheHost> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      PrimaryScrollController(controller: _controller, child: ficheContent(widget.fiche));
}

/// The bar over a fiche stacked on another one: an arrow back, and the title
/// of the fiche it returns to.
class _BackBar extends StatelessWidget {
  const _BackBar({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: backBarHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          spacing: 2,
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: onBack,
              icon: Icon(Icons.arrow_back, color: scheme.onSurfaceVariant),
            ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, height: 18 / 13, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
