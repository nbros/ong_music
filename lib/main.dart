import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'src/entry.dart';
import 'src/entry_list.dart';
import 'src/search.dart';
import 'src/options.dart';

final logger = Logger(printer: PrettyPrinter(methodCount: 0));
const String databaseFileName = 'ongLog.db';

void main() {
  // WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  Logger.level = kDebugMode ? Level.all : Level.off;
  runApp(
    const ProviderScope(
      child: MainApp(),
    ),
  );
}

class EntryNotifier extends StateNotifier<AsyncValue<List<Entry>>> {
  EntryNotifier() : super(const AsyncValue.loading());

  bool _initialized = false;

  Future<void> loadEntries() async {
    if (!_initialized) {
      _initialized = true;
      return reloadEntries(cached: true);
    }
  }

  Future<void> reloadEntries({@required cached}) async {
    state = const AsyncValue.loading();
    try {
      // await Future.delayed(const Duration(milliseconds: 500));
      List<Entry>? entries;
      if (cached && await isDatabaseInitialized()) {
        logger.i('Database exists, loading entries from database');
        entries = await loadEntriesFromDatabase();
      }
      if (entries == null || entries.isEmpty) {
        logger.i('Loading entries from Google Sheet');
        entries = await loadEntriesFromGoogleSheets();
      }
      entries = entries.where((entry) => entry.videoTitle.isNotEmpty && entry.seq != null).toList();
      entries.sort((e1, e2) => e2.seq!.compareTo(e1.seq!));
      logger.d('First 10 entries:\n${entries.take(10).map((entry) => entry.toString()).join('\n')}');
      state = AsyncValue.data(entries);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  void clearEntries() {
    state = const AsyncValue.data([]);
  }
}

final entryProvider = StateNotifierProvider<EntryNotifier, AsyncValue<List<Entry>>>((ref) => EntryNotifier());

class MainApp extends ConsumerWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future.microtask(() => ref.read(entryProvider.notifier).loadEntries());
    final Brightness platformBrightness = MediaQuery.of(context).platformBrightness;
    ThemeMode themeMode = ref.watch(themeProvider);
    if (themeMode == ThemeMode.system) {
      // initialize light or dark depending on platform brightness
      themeMode = platformBrightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
      Future.microtask(() => ref.read(themeProvider.notifier).themeMode = themeMode);
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      home: const MainPage(),
    );
  }
}

class MainPage extends ConsumerWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AsyncValue<List<Entry>> asyncEntries = ref.watch(entryProvider);
    bool expand = ref.watch(expandOptionProvider);
    ThemeMode themeMode = ref.watch(themeProvider);
    final entryNotifier = ref.read(entryProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ong Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => showSearch(context: context, delegate: EntrySearch(asyncEntries.value!)),
          ),
          IconButton(
            icon: Icon(expand ? Icons.unfold_less : Icons.unfold_more),
            onPressed: () => ref.read(expandOptionProvider.notifier).toggle(),
          ),
          IconButton(
            icon: Icon(themeMode == ThemeMode.light ? Icons.dark_mode : Icons.light_mode),
            onPressed: () => ref.read(themeProvider.notifier).switchTheme(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.read(entryProvider.notifier).reloadEntries(cached: false);
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              await confirmAndDeleteDatabase(context, entryNotifier);
            },
          ),
        ],
      ),
      body: asyncEntries.when(
        data: (entries) => EntryList(entries: entries),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, stack) {
          logger.e('Error loading entries: $e\n$stack');
          return Center(child: Text('Error loading entries: $e'));
        },
      ),
    );
  }
}

Future<bool> isDatabaseInitialized() async {
  File databaseFile = File(await getDatabaseFilePath());
  logger.d('Database file: $databaseFile');
  bool databaseExists = await databaseFile.exists();
  if (databaseExists) {
    Database? db;
    try {
      db = await openDatabase(databaseFile.path);
      List<Map<String, dynamic>> tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='YoutubeCatalogue'");
      return tables.isNotEmpty;
    } finally {
      await db?.close();
    }
  }
  return false;
}

Future<String> getDatabaseFilePath() async {
  final databasePath = await getDatabasesPath();
  return join(databasePath, databaseFileName);
}

Future<List<Entry>> loadEntriesFromDatabase() async {
  Database? db;
  try {
    try {
      db = await openOngLogDatabase();
      final List<Map<String, dynamic>> maps = await db.query('YoutubeCatalogue');
      return List.generate(maps.length, (i) {
        var title = maps[i]['videoTitle'];
        return Entry(
          uploadDate: maps[i]['uploadDate'],
          seq: maps[i]['seq'],
          videoTitle: title,
          genre: maps[i]['genre'],
          videoLink: maps[i]['videoLink'],
          shortVideoOrRequestor: maps[i]['shortVideoOrRequestor'],
          originalHighlight: maps[i]['originalHighlight'],
          additionalNotes: maps[i]['additionalNotes'],
        );
      });
    } catch (e) {
      logger.e('Error loading entries from database: $e');
      return [];
    }
  } finally {
    await db?.close();
  }
}

Future<Database> openOngLogDatabase() async {
  final databaseFilePath = await getDatabaseFilePath();
  final database = await openDatabase(
    databaseFilePath,
    version: 1,
  );
  return database;
}

// Query the CSV file from Google Sheets, parse it and save the data to a SQLite database
Future<List<Entry>> loadEntriesFromGoogleSheets() async {
  const url = "https://docs.google.com/spreadsheets/d/14ARzE_zSMNhp0ZQV34ti2741PbA-5wAjsXRAW8EgJ-4/gviz/tq?tqx=out:csv&sheet=Youtube%20Catalogue";
  logger.d('Fetching CSV from $url');
  final stopwatch = Stopwatch()..start();
  final response = await http.get(Uri.parse(url));
  stopwatch.stop();
  if (response.statusCode == 200) {
    final csvString = response.body;
    final bytes = response.bodyBytes.lengthInBytes;
    final mib = bytes / (1024 * 1024);
    final mibPerSecond = mib * 1E6 / stopwatch.elapsed.inMicroseconds;
    logger.i('Fetched ${mib.toStringAsFixed(2)} MiB in ${stopwatch.elapsed} (${mibPerSecond.toStringAsFixed(2)} MiB/s)');

    final csv = parseCsvString(csvString);
    logger.i('Parsed CSV: ${csv.length} rows');

    // Format CSV into Entry objects
    List<Entry> entries = [];
    for (int i = 1; i < csv.length; i++) {
      try {
        final row = csv[i];
        final entry = Entry(
          uploadDate: row[0].trim(),
          seq: int.tryParse(row[1]),
          videoTitle: row[2].trim(),
          genre: row[3].trim(),
          videoLink: row[4].trim(),
          shortVideoOrRequestor: row[5].trim(),
          originalHighlight: row[6].trim(),
          additionalNotes: row[7].trim(),
        );

        entries.add(entry);
      } catch (e) {
        logger.e('Error parsing row $i: $e');
      }
    }
    await saveDataToDatabase(entries);
    return entries;
  } else {
    logger.e('Failed to fetch CSV: HTTP ${response.statusCode}');
    return [];
  }
}

List<List<dynamic>> parseCsvString(String csvString) {
  const csvParser = CsvToListConverter(eol: '\n');
  return csvParser.convert(csvString);
}

// Save loaded entries to a local SQLite database
Future<void> saveDataToDatabase(List<Entry> entries) async {
  // open database and create table if it doesn't exist
  final databasePath = await getDatabasesPath();
  Database? db;
  try {
    db = await openDatabase(
      join(databasePath, 'ongLog.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
            CREATE TABLE IF NOT EXISTS YoutubeCatalogue (
              uploadDate TEXT,
              seq INTEGER,
              videoTitle TEXT,
              genre TEXT,
              videoLink TEXT,
              shortVideoOrRequestor TEXT,
              originalHighlight TEXT,
              additionalNotes TEXT
            )
          ''');
      },
    );
    // replace all entries
    final batch = db.batch();
    batch.delete('YoutubeCatalogue');
    for (final entry in entries) {
      batch.insert(
        'YoutubeCatalogue',
        {
          'uploadDate': entry.uploadDate,
          'seq': entry.seq,
          'videoTitle': entry.videoTitle,
          'genre': entry.genre,
          'videoLink': entry.videoLink,
          'shortVideoOrRequestor': entry.shortVideoOrRequestor,
          'originalHighlight': entry.originalHighlight,
          'additionalNotes': entry.additionalNotes,
        },
      );
    }
    await batch.commit(noResult: true);
  } finally {
    await db?.close();
  }
}

Future<void> confirmAndDeleteDatabase(BuildContext context, EntryNotifier entryNotifier) async {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Confirm Delete'),
        content: const SingleChildScrollView(
          child: ListBody(
            children: <Text>[
              Text('Are you sure you want to reset the cached data (delete the local database)?'),
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
              deleteDatabase();
              entryNotifier.clearEntries();
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}

Future<void> deleteDatabase() async {
  final databasePath = await getDatabasesPath();
  final databaseFile = File(join(databasePath, 'ongLog.db'));
  logger.d('Deleting database at $databaseFile');
  if (!await databaseFile.exists()) {
    logger.d('Database does not exist');
    return;
  }
  await databaseFile.delete();
  logger.d('Database deleted');
}
