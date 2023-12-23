import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/about.dart';
import 'src/entry.dart';
import 'src/entry_manager.dart';
import 'src/entry_list.dart';
import 'src/logger.dart';
import 'src/options.dart';
import 'src/search.dart';
import 'src/settings.dart';
import 'src/transient_state.dart';

void main(List<String> arguments) async {
  await configureLogger(arguments);
  logger.i('Initializing SQLite');
  await initializeSqlite();
  logger.i('Starting Ong Music App');
  try {
    runApp(
      const ProviderScope(
        child: MainApp(),
      ),
    );
  } catch (e, stackTrace) {
    logger.f('Unhandled exception: $e\n$stackTrace');
  }
}

class MainApp extends ConsumerWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future.microtask(() {
      ref.read(highlightEntriesProvider.notifier).initialize();
      ref.read(onglogEntriesProvider.notifier).initialize();
    });
    ThemeMode themeMode = ref.watch(themeProvider);
    if (themeMode == ThemeMode.system) {
      // initialize light or dark depending on platform brightness
      final Brightness platformBrightness = MediaQuery.of(context).platformBrightness;
      themeMode = platformBrightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
      Future.microtask(() => ref.read(themeProvider.notifier).themeMode = themeMode);
    }

    return MaterialApp(
      //debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      home: NavigationWidget(),
    );
  }
}

class NavigationWidget extends ConsumerWidget {
  NavigationWidget({super.key});

  final List<Widget> _pages = [
    EntriesPage(entriesProvider: highlightEntriesProvider, clickable: true, name: "Highlights"),
    EntriesPage(entriesProvider: onglogEntriesProvider, clickable: false, name: "Ong Log"),
    AboutPage()
  ];
  final List<String> _pageNames = ["Highlights", "Ong Log", "About"];
  final List<bool> _clickable = [true, false, false];
  final List<StateNotifierProvider<EntryManager, AsyncValue<List<Entry>>>?> _entriesProviders = [highlightEntriesProvider, onglogEntriesProvider, null];

  void _onDestinationSelected(int index, CurrentPageNotifier currentPageNotifier) {
    currentPageNotifier.value = index;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesProvider = _entriesProviders[ref.watch(currentPageProvider)];

    final currentPageNotifier = ref.read(currentPageProvider.notifier);
    final currentPage = ref.watch(currentPageProvider);

    List<Widget>? actions;
    if (entriesProvider != null) {
      actions = createActions(entriesProvider, currentPage, context, ref);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_pageNames[currentPage]),
        actions: actions,
      ),
      drawer: const SettingsDrawer(),
      body: _pages.elementAt(currentPage),
      bottomNavigationBar: NavigationBar(
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.star),
            label: 'Highlights',
          ),
          NavigationDestination(
            icon: Icon(Icons.all_inclusive),
            label: 'Ong Log',
          ),
          NavigationDestination(
            icon: Icon(Icons.info),
            label: 'About',
          ),
        ],
        onDestinationSelected: (index) => _onDestinationSelected(index, currentPageNotifier),
        selectedIndex: currentPage,
      ),
    );
  }

  List<Widget> createActions(
      StateNotifierProvider<EntryManager, AsyncValue<List<Entry>>> entriesProvider, int currentPage, BuildContext context, WidgetRef ref) {
    AsyncValue<List<Entry>> asyncEntries = ref.watch(entriesProvider);
    final EntryManager entryNotifier = ref.read(entriesProvider.notifier);
    bool expand = ref.watch(expandOptionProvider);
    final themeMode = ref.watch(themeProvider);
    double width = MediaQuery.of(context).size.width;
    return [
      IconButton(
        // Search
        icon: const Icon(Icons.search),
        onPressed: () => showSearch(
            context: context,
            delegate: EntrySearch(
              entries: asyncEntries.value!,
              clickable: _clickable[currentPage],
              name: _pageNames[currentPage],
            )),
      ),
      if (width > 320)
        IconButton(
          // Refresh
          icon: const Icon(Icons.refresh),
          onPressed: () {
            ref.read(entriesProvider.notifier).reloadEntries(cached: false);
          },
        ),
      if (width > 380)
        IconButton(
          icon: Icon(expand ? Icons.unfold_less : Icons.unfold_more),
          onPressed: () => ref.read(expandOptionProvider.notifier).toggle(),
        ),
      if (width > 420)
        IconButton(
          // Switch Theme
          icon: Icon(themeMode == ThemeMode.light ? Icons.dark_mode : Icons.light_mode),
          onPressed: () => ref.read(themeProvider.notifier).switchTheme(),
        ),
      if (width > 460)
        IconButton(
          // Clear Cache
          icon: const Icon(Icons.delete),
          onPressed: () async {
            await confirmAndClearEntries(context, entryNotifier);
          },
        ),
      PopupMenuButton<String>(
        onSelected: (String result) async {
          if (result == 'search') {
            await showSearch(
                context: context,
                delegate: EntrySearch(
                  entries: asyncEntries.value!,
                  clickable: _clickable[currentPage],
                  name: _pageNames[currentPage],
                ));
          } else if (result == 'clearCache') {
            await confirmAndClearEntries(context, entryNotifier);
          } else if (result == 'refresh') {
            await entryNotifier.reloadEntries(cached: false);
          }
        },
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(
            value: 'search',
            child: Text('Search'),
          ),
          const PopupMenuItem<String>(
            value: 'refresh',
            child: Text('Refresh'),
          ),
          const PopupMenuItem<String>(
            value: 'clearCache',
            child: Text('Clear Cache'),
          ),
        ],
      ),
    ];
  }
}

class EntriesPage extends ConsumerWidget {
  final StateNotifierProvider<EntryManager, AsyncValue<List<Entry>>> entriesProvider;

  const EntriesPage({super.key, required this.entriesProvider, required this.clickable, required this.name});
  final bool clickable;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AsyncValue<List<Entry>> asyncEntries = ref.watch(entriesProvider);

    return Scaffold(
      body: asyncEntries.when(
        data: (entries) => EntryList(entries: entries, clickable: clickable, name: name),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, stack) {
          logger.e('Error loading entries: $e\n$stack');
          return Center(child: Text('Error loading entries: $e'));
        },
      ),
    );
  }
}

Future<void> confirmAndClearEntries(BuildContext context, EntryManager entryNotifier) async {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Delete all cached entries?'),
        content: const SingleChildScrollView(
          child: ListBody(
            children: <Text>[
              Text('Are you sure you want to clear the cached data?\nThis will delete all cached SQlite entries from the local database.'),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            child: const Text('Cancel'),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
          TextButton(
            child: const Text('Delete'),
            onPressed: () {
              entryNotifier.clearEntries();
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}
