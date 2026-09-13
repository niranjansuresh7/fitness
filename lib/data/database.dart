import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Opens and migrates the local SQLite database.
///
/// Everything lives on the device. There is no server, no account and no
/// network call anywhere in this app.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const int _version = 2;

  /// Opens the database, creating it on first run.
  ///
  /// [path] is only for tests, which pass an in-memory path so each case
  /// starts from a clean schema.
  static Future<AppDatabase> open({
    String fileName = 'hydrafuel.db',
    String? path,
  }) async {
    final String location = path ?? p.join(await getDatabasesPath(), fileName);

    final Database db = await openDatabase(
      location,
      version: _version,
      onConfigure: (Database d) async {
        await d.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (Database d, int version) async {
        await _createSchema(d);
      },
      onUpgrade: (Database d, int from, int to) async {
        // Migrations are additive and run in order. Never drop a table with
        // logged history in it.
        if (from < 2) {
          await _createBloodResults(d);
        }
      },
    );

    return AppDatabase._(db);
  }

  static Future<void> _createSchema(Database d) async {
    final Batch batch = d.batch();

    batch.execute('''
      CREATE TABLE foods (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        brand TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        nutrients TEXT NOT NULL,
        serving_name TEXT NOT NULL DEFAULT '',
        serving_grams REAL,
        density_g_per_ml REAL,
        is_liquid INTEGER NOT NULL DEFAULT 0,
        tags TEXT NOT NULL DEFAULT '',
        favorite INTEGER NOT NULL DEFAULT 0,
        use_count INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    batch.execute('CREATE INDEX idx_foods_name ON foods(name)');

    // food_id is intentionally NOT a foreign key: deleting a food from the
    // library must never delete or invalidate what you already ate.
    batch.execute('''
      CREATE TABLE log_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        food_id INTEGER,
        food_name TEXT NOT NULL,
        grams REAL NOT NULL,
        nutrients TEXT NOT NULL,
        meal TEXT NOT NULL,
        logged_at TEXT NOT NULL,
        day TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT ''
      )
    ''');
    batch.execute('CREATE INDEX idx_log_day ON log_entries(day)');

    batch.execute('''
      CREATE TABLE water_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        volume_ml REAL NOT NULL,
        logged_at TEXT NOT NULL,
        day TEXT NOT NULL,
        label TEXT NOT NULL DEFAULT ''
      )
    ''');
    batch.execute('CREATE INDEX idx_water_day ON water_entries(day)');

    batch.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await batch.commit(noResult: true);
    await _createBloodResults(d);
  }

  /// Blood test results, one row per marker per draw.
  ///
  /// Kept as a history rather than a single current value so a re-test shows
  /// movement, and so targets always follow the most recent draw on their own.
  static Future<void> _createBloodResults(Database d) async {
    await d.execute('''
      CREATE TABLE blood_results (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        marker TEXT NOT NULL,
        value REAL NOT NULL,
        taken_on TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT ''
      )
    ''');
    await d.execute(
        'CREATE INDEX idx_blood_marker ON blood_results(marker, taken_on)');
  }

  Future<void> close() => db.close();
}
