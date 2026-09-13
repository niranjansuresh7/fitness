import 'package:sqflite/sqflite.dart';

import '../core/dates.dart';
import '../domain/water_entry.dart';
import 'database.dart';

class WaterRepository {
  WaterRepository(this._app);

  final AppDatabase _app;
  Database get _db => _app.db;

  static WaterEntry _fromRow(Map<String, Object?> row) => WaterEntry(
        id: row['id'] as int?,
        volumeMl: (row['volume_ml'] as num?)?.toDouble() ?? 0.0,
        loggedAt: DateTime.tryParse(row['logged_at'] as String? ?? '') ??
            DateTime.now(),
        label: row['label'] as String? ?? '',
      );

  Future<List<WaterEntry>> forDay(DateTime date) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'water_entries',
      where: 'day = ?',
      whereArgs: <Object?>[dayKey(date)],
      orderBy: 'logged_at ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<List<WaterEntry>> between(DateTime from, DateTime to) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'water_entries',
      where: 'day >= ? AND day <= ?',
      whereArgs: <Object?>[dayKey(from), dayKey(to)],
      orderBy: 'logged_at ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<int> add(WaterEntry entry) =>
      _db.insert('water_entries', <String, Object?>{
        'volume_ml': entry.volumeMl,
        'logged_at': entry.loggedAt.toIso8601String(),
        'day': dayKey(entry.loggedAt),
        'label': entry.label,
      });

  Future<void> delete(int id) async {
    await _db
        .delete('water_entries', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  /// Total millilitres for a day, computed in SQL for the widget/summary path.
  Future<double> totalForDay(DateTime date) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(volume_ml), 0) AS total FROM water_entries WHERE day = ?',
      <Object?>[dayKey(date)],
    );
    return (rows.first['total'] as num?)?.toDouble() ?? 0.0;
  }
}
