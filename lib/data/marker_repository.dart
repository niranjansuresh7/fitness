import 'package:sqflite/sqflite.dart';

import '../core/dates.dart';
import '../domain/blood_marker.dart';
import 'database.dart';

/// Storage for blood test results.
class MarkerRepository {
  MarkerRepository(this._app);

  final AppDatabase _app;
  Database get _db => _app.db;

  static BloodResult? _fromRow(Map<String, Object?> row) {
    final BloodMarker? marker =
        BloodMarker.fromKey(row['marker'] as String? ?? '');
    if (marker == null) return null; // A marker this version no longer knows.
    return BloodResult(
      id: row['id'] as int?,
      marker: marker,
      value: (row['value'] as num?)?.toDouble() ?? 0.0,
      takenOn:
          DateTime.tryParse(row['taken_on'] as String? ?? '') ?? DateTime.now(),
      note: row['note'] as String? ?? '',
    );
  }

  Future<List<BloodResult>> all() async {
    final List<Map<String, Object?>> rows =
        await _db.query('blood_results', orderBy: 'taken_on DESC, id DESC');
    return rows.map(_fromRow).whereType<BloodResult>().toList(growable: false);
  }

  /// Every recorded value for one marker, oldest first, for a trend view.
  Future<List<BloodResult>> history(BloodMarker marker) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'blood_results',
      where: 'marker = ?',
      whereArgs: <Object?>[marker.key],
      orderBy: 'taken_on ASC',
    );
    return rows.map(_fromRow).whereType<BloodResult>().toList(growable: false);
  }

  Future<MarkerSnapshot> snapshot() async =>
      MarkerSnapshot.fromHistory(await all());

  /// Insert or update. A marker recorded twice for the same draw date replaces
  /// the earlier value rather than adding a duplicate.
  Future<int> save(BloodResult result) async {
    final Map<String, Object?> row = <String, Object?>{
      'marker': result.marker.key,
      'value': result.value,
      'taken_on': result.takenOn.toIso8601String(),
      'note': result.note,
    };

    final int? id = result.id;
    if (id != null) {
      await _db.update('blood_results', row,
          where: 'id = ?', whereArgs: <Object?>[id]);
      return id;
    }

    final List<Map<String, Object?>> existing = await _db.query(
      'blood_results',
      where: 'marker = ? AND taken_on LIKE ?',
      whereArgs: <Object?>[result.marker.key, '${dayKey(result.takenOn)}%'],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final int existingId = existing.first['id']! as int;
      await _db.update('blood_results', row,
          where: 'id = ?', whereArgs: <Object?>[existingId]);
      return existingId;
    }

    return _db.insert('blood_results', row);
  }

  /// Save a whole panel from one draw in a single transaction.
  Future<void> saveDraw(
      DateTime takenOn, Map<BloodMarker, double> values) async {
    await _db.transaction((Transaction txn) async {
      for (final MapEntry<BloodMarker, double> e in values.entries) {
        final List<Map<String, Object?>> existing = await txn.query(
          'blood_results',
          where: 'marker = ? AND taken_on LIKE ?',
          whereArgs: <Object?>[e.key.key, '${dayKey(takenOn)}%'],
          limit: 1,
        );
        final Map<String, Object?> row = <String, Object?>{
          'marker': e.key.key,
          'value': e.value,
          'taken_on': takenOn.toIso8601String(),
          'note': '',
        };
        if (existing.isEmpty) {
          await txn.insert('blood_results', row);
        } else {
          await txn.update('blood_results', row,
              where: 'id = ?', whereArgs: <Object?>[existing.first['id']]);
        }
      }
    });
  }

  Future<void> delete(int id) async {
    await _db
        .delete('blood_results', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  /// Distinct draw dates, newest first.
  Future<List<DateTime>> drawDates() async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT DISTINCT taken_on FROM blood_results ORDER BY taken_on DESC',
    );
    return rows
        .map((Map<String, Object?> r) =>
            DateTime.tryParse(r['taken_on'] as String? ?? ''))
        .whereType<DateTime>()
        .toList(growable: false);
  }
}
