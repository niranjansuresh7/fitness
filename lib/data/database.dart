import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Opens and migrates the local SQLite database.
///
/// Everything lives on the device. There is no server, no account and no
/// network call anywhere in this app.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const int _version = 1;
  static AppDatabase? _instance;

  static Future<AppDatabase> open({String fileName = 'hydrafuel.db'}) async {
    final AppDatabase? existing = _instance;
    if (existing != null) return existing;

    final String dir = await getDatabasesPath();
    final String path = p.join(dir, fileName);

    final Database db = await openDatabase(
      path,
      version: _version,
      onConfigure: (Database d) async {
        await d.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (Database d, int version) async {
        await _createSchema(d);
      },
      onUpgrade: (Database d, int from, int to) async {
        // Version 1 is the initial schema; migrations land here as the
        // schema evolves. Never drop a table with logged history in it.
      },
    );

    final AppDatabase wrapper = AppDatabase._(db);
    _instance = wrapper;
    return wrapper;
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
  }

  Future<void> close() async {
    await db.close();
    _instance = null;
  }
}
