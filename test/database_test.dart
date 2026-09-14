import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrafuel/data/database.dart';
import 'package:hydrafuel/data/marker_repository.dart';
import 'package:hydrafuel/domain/blood_marker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hydrafuel_db_test');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  String pathFor(String name) => '${dir.path}/$name';

  group('schema', () {
    test('a fresh database has every table', () async {
      final AppDatabase app = await AppDatabase.open(path: pathFor('new.db'));
      addTearDown(app.close);

      final List<Map<String, Object?>> tables = await app.db
          .rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      final Set<String> names =
          tables.map((Map<String, Object?> r) => r['name'] as String).toSet();

      expect(
        names,
        containsAll(<String>[
          'foods',
          'log_entries',
          'water_entries',
          'settings',
          'blood_results',
        ]),
      );
    });
  });

  group('migration from version 1', () {
    /// The exact version 1 schema, before blood results existed.
    Future<void> createV1(String path) async {
      final Database db = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (Database d, int v) async {
            await d.execute('''
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
            await d.execute('''
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
            await d.execute('''
              CREATE TABLE water_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                volume_ml REAL NOT NULL,
                logged_at TEXT NOT NULL,
                day TEXT NOT NULL,
                label TEXT NOT NULL DEFAULT ''
              )
            ''');
            await d.execute('''
              CREATE TABLE settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
              )
            ''');
          },
        ),
      );

      // Some history worth not losing.
      await db.insert('water_entries', <String, Object?>{
        'volume_ml': 500,
        'logged_at': '2026-09-13T08:00:00.000',
        'day': '2026-09-13',
        'label': 'Bottle',
      });
      await db.insert(
          'settings', <String, Object?>{'key': 'onboarded', 'value': 'true'});
      await db.close();
    }

    test('upgrading adds blood results and keeps existing data', () async {
      final String path = pathFor('upgrade.db');
      await createV1(path);

      final AppDatabase app = await AppDatabase.open(path: path);
      addTearDown(app.close);

      expect(await app.db.getVersion(), 2);

      // Pre-existing rows survived.
      final List<Map<String, Object?>> water =
          await app.db.query('water_entries');
      expect(water, hasLength(1));
      expect(water.single['label'], 'Bottle');

      final List<Map<String, Object?>> settings =
          await app.db.query('settings');
      expect(settings.single['value'], 'true');

      // And the new table is usable.
      final MarkerRepository markers = MarkerRepository(app);
      await markers.save(BloodResult(
        marker: BloodMarker.ldl,
        value: 141,
        takenOn: DateTime(2026, 9, 13),
      ));
      expect((await markers.snapshot())[BloodMarker.ldl], 141);
    });
  });

  group('marker repository', () {
    late AppDatabase app;
    late MarkerRepository markers;

    setUp(() async {
      app = await AppDatabase.open(path: pathFor('markers.db'));
      markers = MarkerRepository(app);
      addTearDown(app.close);
    });

    test('saves and reads back a draw', () async {
      await markers.saveDraw(DateTime(2026, 9, 13), <BloodMarker, double>{
        BloodMarker.ldl: 141,
        BloodMarker.hdl: 36,
        BloodMarker.vitaminD: 16.5,
      });

      final MarkerSnapshot snap = await markers.snapshot();
      expect(snap.latest, hasLength(3));
      expect(snap[BloodMarker.vitaminD], 16.5);
      expect(snap.lastDrawDate, DateTime(2026, 9, 13));
    });

    test('re-saving the same marker on the same date replaces, not duplicates',
        () async {
      await markers.saveDraw(
          DateTime(2026, 9, 13), <BloodMarker, double>{BloodMarker.ldl: 141});
      await markers.saveDraw(
          DateTime(2026, 9, 13), <BloodMarker, double>{BloodMarker.ldl: 138});

      expect(await markers.all(), hasLength(1));
      expect((await markers.snapshot())[BloodMarker.ldl], 138);
    });

    test('a later draw becomes the current value but keeps the history',
        () async {
      await markers.saveDraw(
          DateTime(2026, 9, 13), <BloodMarker, double>{BloodMarker.ldl: 141});
      await markers.saveDraw(
          DateTime(2027, 3, 20), <BloodMarker, double>{BloodMarker.ldl: 95});

      expect((await markers.snapshot())[BloodMarker.ldl], 95);

      final List<BloodResult> history = await markers.history(BloodMarker.ldl);
      expect(history.map((BloodResult r) => r.value), <double>[141, 95]);
    });

    test('draw dates list newest first', () async {
      await markers.saveDraw(
          DateTime(2026, 9, 13), <BloodMarker, double>{BloodMarker.ldl: 141});
      await markers.saveDraw(
          DateTime(2027, 3, 20), <BloodMarker, double>{BloodMarker.ldl: 95});

      final List<DateTime> dates = await markers.drawDates();
      expect(dates.first.year, 2027);
      expect(dates.last.year, 2026);
    });

    test('deleting removes only that result', () async {
      await markers.saveDraw(DateTime(2026, 9, 13), <BloodMarker, double>{
        BloodMarker.ldl: 141,
        BloodMarker.hdl: 36,
      });
      final List<BloodResult> all = await markers.all();
      await markers.delete(all.first.id!);
      expect(await markers.all(), hasLength(1));
    });

    test('a row for a marker this version does not know is skipped, not fatal',
        () async {
      await app.db.insert('blood_results', <String, Object?>{
        'marker': 'unobtainium',
        'value': 42,
        'taken_on': DateTime(2026, 9, 13).toIso8601String(),
        'note': '',
      });
      await markers.saveDraw(
          DateTime(2026, 9, 13), <BloodMarker, double>{BloodMarker.ldl: 141});

      final List<BloodResult> all = await markers.all();
      expect(all, hasLength(1));
      expect(all.single.marker, BloodMarker.ldl);
    });
  });
}
