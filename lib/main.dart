import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final logger = Logger(printer: PrettyPrinter(methodCount: 0));

void main() {
  // WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  Logger.level = kDebugMode ? Level.all : Level.off;
  runApp(const MainApp());
}

List<List<dynamic>> parseCsvString(String csvString) {
  const csvParser = CsvToListConverter(eol: '\n');
  return csvParser.convert(csvString);
}

class VideoData {
  final String uploadDate;
  final int? seq;
  final String videoTitle;
  final String genre;
  final String videoLink;
  final String shortVideoOrRequestor;
  final String originalHighlight;
  final String additionalNotes;

  VideoData({
    required this.uploadDate,
    required this.seq,
    required this.videoTitle,
    required this.genre,
    required this.videoLink,
    required this.shortVideoOrRequestor,
    required this.originalHighlight,
    required this.additionalNotes,
  });

  @override
  String toString() {
    return 'VideoData{ '
        'uploadDate: $uploadDate, '
        'seq: $seq, '
        'videoTitle: $videoTitle, '
        'genre: $genre, '
        'videoLink: $videoLink, '
        'shortVideoOrRequestor: $shortVideoOrRequestor, '
        'originalHighlight: $originalHighlight, '
        'additionalNotes: $additionalNotes'
        ' }';
  }
}

// Query the CSV file from Google Sheets, parse it and save the data to a SQLite database
void query() async {
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

    // Format CSV into VideoData objects
    List<VideoData> videoDataList = [];
    for (int i = 1; i < csv.length; i++) {
      try {
        final row = csv[i];
        final videoData = VideoData(
          uploadDate: row[0],
          seq: int.tryParse(row[1]),
          videoTitle: row[2],
          genre: row[3],
          videoLink: row[4],
          shortVideoOrRequestor: row[5],
          originalHighlight: row[6],
          additionalNotes: row[7],
        );

        videoDataList.add(videoData);
      } catch (e) {
        logger.e('Error parsing row $i: $e');
      }
    }

    logger.d('First 10 VideoData entries:\n${videoDataList.take(10).map((videoData) => videoData.toString()).join('\n')}');

    // Save data to SQLite database
    await saveDataToDatabase(videoDataList);
  } else {
    logger.e('Failed to fetch CSV: HTTP ${response.statusCode}');
  }
}

Future<void> saveDataToDatabase(List<VideoData> videoDataList) async {
  final databasePath = await getDatabasesPath();
  final database = await openDatabase(
    join(databasePath, 'ongLog.db'),
    version: 1,
    onCreate: (db, version) async {
      await db.execute(
          'CREATE TABLE IF NOT EXISTS YoutubeCatalogue (uploadDate TEXT, seq INTEGER, videoTitle TEXT, genre TEXT, videoLink TEXT, shortVideoOrRequestor TEXT, originalHighlight TEXT, additionalNotes TEXT)');
    },
  );

  await database.transaction((txn) async {
    for (final videoData in videoDataList) {
      await txn.insert(
        'YoutubeCatalogue',
        {
          'uploadDate': videoData.uploadDate,
          'seq': videoData.seq,
          'videoTitle': videoData.videoTitle,
          'genre': videoData.genre,
          'videoLink': videoData.videoLink,
          'shortVideoOrRequestor': videoData.shortVideoOrRequestor,
          'originalHighlight': videoData.originalHighlight,
          'additionalNotes': videoData.additionalNotes,
        },
      );
    }
  });

  await database.close();
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              ElevatedButton(
                onPressed: query,
                child: Text('Query'),
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: deleteDatabase,
                child: Text('Delete Database'),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
