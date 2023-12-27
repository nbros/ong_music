import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/main.dart';
import 'package:ong_music/src/entry.dart';
import 'package:ong_music/src/entry_manager.dart';
import 'package:ong_music/src/logger.dart';

void main() {
  setUp(() async {
    initializeSqlite();
    configureLogger([]);
  });

  testWidgets('MainApp widget should be created', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: MainApp(initialize: false)));

    // Verify that MainApp widget is created.
    expect(find.byType(MainApp), findsOneWidget);

    // Verify that MainApp contains NavigationWidget.
    expect(find.byType(NavigationWidget), findsOneWidget);
  });

  testWidgets('MainApp initializes providers', (WidgetTester tester) async {
    initializeSqlite();

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MainApp(initialize: false)));

    // Get the state of the providers.
    final highlightEntriesState = container.read(highlightEntriesProvider.notifier);
    final onglogEntriesState = container.read(onglogEntriesProvider.notifier);

    await highlightEntriesState.initialize();
    await onglogEntriesState.initialize();

    // Verify that providers are initialized.
    List<Entry> highlightEntries = highlightEntriesState.state.asData!.value;
    List<Entry> onglogEntries = onglogEntriesState.state.asData!.value;
    // check that there is at least one entry in each list
    expect(highlightEntries.length, greaterThan(0));
    expect(onglogEntries.length, greaterThan(0));
  });
}
