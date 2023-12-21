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
      logger.d('First 10 entries:\n${entries.take(10).map((entry) => entry.toString()).join('\n')}');
      state = AsyncValue.data(entries);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }
}

final entryProvider = StateNotifierProvider<EntryNotifier, AsyncValue<List<Entry>>>((ref) => EntryNotifier());

class MainApp extends ConsumerWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future.microtask(() => ref.read(entryProvider.notifier).loadEntries());
    final asyncEntries = ref.watch(entryProvider);
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Ong Log'),
        ),
        body: asyncEntries.when(
          data: (entries) => EntryList(entries: entries),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, stack) {
            logger.e('Error loading entries: $e\n$stack');
            return Center(child: Text('Error loading entries: $e'));
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            ref.read(entryProvider.notifier).reloadEntries(cached: false);
          },
          child: const Icon(Icons.refresh),
        ),
      ),
    );
  }
}

class EntryList extends StatelessWidget {
  final List<Entry> entries;

  const EntryList({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return ListTile(
          title: Text(entry.videoTitle),
          subtitle: Text(entry.additionalNotes),
        );
      },
    );
  }
}

Future<bool> isDatabaseInitialized() async {
  File databaseFile = File(await getDatabaseFilePath());
  logger.d('Database file: $databaseFile');
  bool databaseExists = await databaseFile.exists();
  if (databaseExists) {
    Database database = await openDatabase(databaseFile.path);
    List<Map<String, dynamic>> tables = await database.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='YoutubeCatalogue'");
    await database.close();
    return tables.isNotEmpty;
  }
  return false;
}

Future<String> getDatabaseFilePath() async {
  final databasePath = await getDatabasesPath();
  return join(databasePath, databaseFileName);
}

Future<List<Entry>> loadEntriesFromDatabase() async {
  try {
    Database database = await openOngLogDatabase();
    final List<Map<String, dynamic>> maps = await database.query('YoutubeCatalogue', orderBy: 'seq');
    await database.close();

    return List.generate(maps.length, (i) {
      return Entry(
        uploadDate: maps[i]['uploadDate'],
        seq: maps[i]['seq'],
        videoTitle: maps[i]['videoTitle'],
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
  final response = await http.get(Uri.parse(url));
  if (response.statusCode == 200) {
    final csvString = response.body;
    final bytes = response.bodyBytes.lengthInBytes;
    final mib = bytes / (1024 * 1024);
    logger.i('Fetched ${mib.toStringAsFixed(2)} MiB');

    final csv = parseCsvString(csvString);
    logger.i('Parsed CSV: ${csv.length} rows');

    // Format CSV into Entry objects
    List<Entry> entries = [];
    for (int i = 1; i < csv.length; i++) {
      try {
        final row = csv[i];
        final entry = Entry(
          uploadDate: row[0],
          seq: int.tryParse(row[1]),
          videoTitle: row[2],
          genre: row[3],
          videoLink: row[4],
          shortVideoOrRequestor: row[5],
          originalHighlight: row[6],
          additionalNotes: row[7],
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
  final database = await openDatabase(
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
  final batch = database.batch();
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
  await database.close();
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
