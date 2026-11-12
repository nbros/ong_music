/// What the two list tabs share: the loading and failure screens, the
/// refresh plumbing and the scroll view frame.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/parser.dart';
import '../data/sheets.dart';
import '../state/catalogue_state.dart';
import 'actions.dart';
import 'theme.dart';
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
/// its failure with a Retry button.
class CatalogueStatusView extends ConsumerWidget {
  const CatalogueStatusView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(catalogueProvider);
    final scheme = Theme.of(context).colorScheme;
    final on3 = OngColors.of(context).on3;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: state.isFailed
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
                    describeLoadError(state.lastError),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: on3),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => ref.read(catalogueProvider.notifier).refresh(),
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
                    'Downloading the highlights and the Ong Log…',
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

/// The scrolling part of a list tab: pull to refresh, scrollbar, a thin
/// progress bar while the data refreshes in the background, and [overlay]
/// (the pinned header) above the list.
class ListFrame extends ConsumerStatefulWidget {
  const ListFrame({super.key, required this.controller, required this.slivers, this.overlay});

  final ScrollController controller;
  final List<Widget> slivers;
  final Widget? overlay;

  @override
  ConsumerState<ListFrame> createState() => _ListFrameState();
}

class _ListFrameState extends ConsumerState<ListFrame> {
  bool _pulling = false;

  Future<void> _pullToRefresh() async {
    setState(() => _pulling = true);
    final notifier = ref.read(catalogueProvider.notifier);
    await notifier.refresh();
    if (!mounted) return;
    setState(() => _pulling = false);
    final error = ref.read(catalogueProvider).lastError;
    if (error != null) showMessage(context, 'Refresh failed. ${describeLoadError(error)}');
  }

  @override
  Widget build(BuildContext context) {
    final refreshing = ref.watch(catalogueProvider.select((s) => s.isRefreshing));
    final overlay = widget.overlay;
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _pullToRefresh,
          child: Scrollbar(
            controller: widget.controller,
            interactive: true,
            thumbVisibility: alwaysShowScrollbars(context),
            child: Stack(
              children: [
                CustomScrollView(
                  controller: widget.controller,
                  physics: const AlwaysScrollableScrollPhysics(),
                  scrollBehavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                  slivers: [
                    ...widget.slivers,
                    SliverPadding(padding: EdgeInsets.only(bottom: 8 + MediaQuery.paddingOf(context).bottom)),
                  ],
                ),
                ?overlay,
              ],
            ),
          ),
        ),
        if (refreshing && !_pulling)
          const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
      ],
    );
  }
}
