import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'entry.dart';
import 'logger.dart';

const String dbFileName = 'ongLog3.db';

final highlightEntriesProvider = StateNotifierProvider<EntryManager, AsyncValue<List<Entry>>>((ref) => HighlightEntryManager());
final onglogEntriesProvider = StateNotifierProvider<EntryManager, AsyncValue<List<Entry>>>((ref) => OngLogEntryManager());

Future<void> initializeSqlite() async {
  if (!kIsWeb && Platform.isWindows) {
    // check that sqlite3.dll is in the same directory as the executable
    if (!kDebugMode) {
      final dir = dirname(Platform.resolvedExecutable);
      if (!await File(join(dir, 'sqlite3.dll')).exists()) {
        logger.e('sqlite3.dll not found in $dir');
      }
    }
    sqfliteFfiInit();
  }
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  } else if (!Platform.isAndroid && !Platform.isIOS) {
    databaseFactory = databaseFactoryFfi;
  }
}

abstract class EntryManager extends StateNotifier<AsyncValue<List<Entry>>> {
  EntryManager() : super(const AsyncValue.loading());

  bool _initialized = false;
  late final String dbFilePath;

  String get tableName;

  Future<void> initialize() async {
    if (!_initialized) {
      _initialized = true;
      final databasePath = await getDatabasesPath();
      dbFilePath = join(databasePath, dbFileName);
      logger.d('Database file path: $dbFilePath');
      await reloadEntries(cached: true);
    }
  }

  Future<void> reloadEntries({@required cached}) async {
    state = const AsyncValue.loading();
    List<Entry>? entries;
    try {
      if (cached && await tableExists(tableName, File(dbFilePath))) {
        logger.i('Loading entries from db table $tableName');
        entries = await loadEntriesFromDatabase();
      }
      if (entries == null || entries.isEmpty) {
        logger.i('Loading entries from Google Sheet');
        entries = await loadEntriesFromGoogleSheets();
      }
      entries = entries.where((entry) => entry.title.isNotEmpty).toList();
      entries.sort((e1, e2) => e2.seq.compareTo(e1.seq));
      logger.d('Latest 10 entries:\n${entries.take(10).map((entry) => entry.toString()).join('\n')}');
      state = AsyncValue.data(entries);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<Database> openEntriesDatabase() async {
    final database = await openDatabase(
      dbFilePath,
      version: 1,
    );
    return database;
  }

  void clearEntries() async {
    Database? db;
    try {
      db = await openEntriesDatabase();
      await db.delete(tableName);
    } finally {
      await db?.close();
    }
    state = const AsyncValue.data([]);
    logger.d('Entries cleared');
  }

  Future<List<Entry>> loadEntriesFromDatabase() async {
    Database? db;
    try {
      try {
        db = await openEntriesDatabase();
        final List<Map<String, dynamic>> maps = await db.query(tableName);
        List<Entry> entries = [];
        for (final map in maps) {
          final entry = Entry(
            seq: map['seq'],
            title: map['title'],
            subtitle: map['subtitle'],
            url: map['url'],
          );
          entries.add(entry);
        }
        return entries;
      } catch (e) {
        logger.e('Error loading entries from database: $e');
        return [];
      }
    } finally {
      await db?.close();
    }
  }

  Future<List<Entry>> loadEntriesFromGoogleSheets();
}

class HighlightEntryManager extends EntryManager {
  @override
  get tableName => 'YoutubeCatalogue';

  @override
  Future<List<Entry>> loadEntriesFromGoogleSheets() async {
    const url = "https://docs.google.com/spreadsheets/d/14ARzE_zSMNhp0ZQV34ti2741PbA-5wAjsXRAW8EgJ-4/gviz/tq?tqx=out:csv&sheet=Youtube%20Catalogue";

    final csv = await fetchCsv(url);

    // Format CSV into Entry objects
    List<Entry> entries = [];
    int seq = 1;
    final requesterPattern = RegExp(r'requested by "?([^"\s,.;]+)"?', caseSensitive: false);
    for (int i = 1; i < csv.length; i++) {
      try {
        final row = csv[i];
        int? maybeSeq = int.tryParse(row[1]);
        // if seq is not a number, use previous seq
        seq = maybeSeq ?? seq;
        final String uploadDate = row[0].trim();
        final String title = row[2].trim();
        final String genre = row[3].trim();
        final String videoLink = row[4].trim();
        final String requester = row[5].trim();
        final String date = row[6].trim();

        // skip empty rows and highlights not yet officially uploaded ("Premiere")
        if (title.isEmpty || uploadDate.isEmpty || uploadDate == 'Premiere') {
          continue;
        }

        final additionalNotes = row[7].trim();

        final genreStr = genre.isEmpty ? '' : ' • $genre';
        final dateStr = date.isEmpty ? '' : ' - $date';
        final notes = additionalNotes.isEmpty ? '' : additionalNotes;
        final uploadDateStr = uploadDate.isEmpty ? '' : ' (uploaded on $uploadDate)';
        var requesterStr = requester.isNotEmpty && !requester.startsWith('http') && requester != '-' ? " [$requester]" : '';
        // if requester is empty, try to parse it from additional notes
        if (requesterStr.isEmpty) {
          final match = requesterPattern.firstMatch(additionalNotes);
          if (match != null) {
            requesterStr = " [${match.group(1)}]";
          }
        }

        final entry = Entry(
          seq: seq,
          title: "$seq$dateStr - $title$genreStr$requesterStr",
          subtitle: "$notes$uploadDateStr",
          url: videoLink,
        );
        entries.add(entry);
      } catch (e) {
        logger.e('Error parsing row $i: $e');
      }
    }
    await saveDataToDatabase(entries, "YoutubeCatalogue");
    return entries;
  }
}

class OngLogEntryManager extends EntryManager {
  @override
  get tableName => 'OngLog';

  @override
  Future<List<Entry>> loadEntriesFromGoogleSheets() async {
    const url = "https://docs.google.com/spreadsheets/d/14ARzE_zSMNhp0ZQV34ti2741PbA-5wAjsXRAW8EgJ-4/gviz/tq?tqx=out:csv&sheet=Songs";

    final csv = await fetchCsv(url);

    // Format CSV into Entry objects
    List<Entry> entries = [];
    int seq = 1;
    for (int i = 1; i < csv.length; i++) {
      try {
        final row = csv[i];
        final String date = row[0].trim();
        //final uptime = row[1].trim();
        final String order = row[2].trim();
        final String requester = row[3].trim();
        final String titleUrl = row[4].trim();
        final String genre = row[5].trim();
        final String type = row[6].trim();

        if (date.isEmpty || order == '0') {
          // 0 is for stream start
          continue;
        }

        bool hasRequester = requester.isNotEmpty && requester != "-";
        final genreStr = genre.isEmpty ? '' : ' • $genre';
        final typeStr = type.isEmpty ? '' : ' • $type';
        final dateStr = date.isEmpty ? '' : ' - $date';
        final requesterStr = hasRequester ? " [$requester]" : '';

        final entry = Entry(
          seq: seq++,
          title: "$seq$dateStr - $titleUrl$genreStr$typeStr$requesterStr",
          subtitle: "",
        );
        entries.add(entry);
      } catch (e) {
        logger.e('Error parsing row $i: $e');
      }
    }
    await saveDataToDatabase(entries, "OngLog");
    return entries;
  }
}

Future<bool> tableExists(String tableName, File databaseFile) async {
  bool databaseExists = kIsWeb || await databaseFile.exists();
  if (databaseExists) {
    Database? db;
    try {
      db = await openDatabase(databaseFile.path);
      List<Map<String, dynamic>> tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='$tableName'");

      //var sqliteVersion = (await db.rawQuery('select sqlite_version()')).first.values.first;
      //logger.d("SQlite version $sqliteVersion"); // should print 3.39.3

      return tables.isNotEmpty;
    } finally {
      await db?.close();
    }
  }
  return false;
}

Future<List<List>> fetchCsv(String url) async {
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

    final csv = const CsvToListConverter(eol: '\n').convert(csvString);
    logger.i('Parsed CSV: ${csv.length} rows');
    return csv;
  } else {
    logger.e('Failed to fetch CSV: HTTP ${response.statusCode} ${response.body}');
    return [];
  }
}

// Save loaded entries to a local SQLite database
Future<void> saveDataToDatabase(List<Entry> entries, String tableName) async {
  // open database and create table if it doesn't exist
  final databasePath = await getDatabasesPath();
  Database? db;
  try {
    db = await openDatabase(
      join(databasePath, dbFileName),
      version: 1,
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        seq INTEGER,
        title TEXT,
        subtitle TEXT,
        url TEXT
      )
    ''');
    // replace all entries
    final batch = db.batch();
    batch.delete(tableName);
    for (final entry in entries) {
      batch.insert(
        tableName,
        {
          'seq': entry.seq,
          'title': entry.title,
          'subtitle': entry.subtitle,
          'url': entry.url,
        },
      );
    }
    await batch.commit(noResult: true);
  } finally {
    await db?.close();
  }
}
