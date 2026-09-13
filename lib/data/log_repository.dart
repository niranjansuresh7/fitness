import 'package:sqflite/sqflite.dart';

import '../core/dates.dart';
import '../domain/log_entry.dart';
import '../domain/nutrition.dart';
import 'database.dart';

class LogRepository {
  LogRepository(this._app);

  final AppDatabase _app;
  Database get _db => _app.db;

  static LogEntry _fromRow(Map<String, Object?> row) => LogEntry(
        id: row['id'] as int?,
        foodId: row['food_id'] as int?,
        foodName: row['food_name'] as String? ?? '',
        grams: (row['grams'] as num?)?.toDouble() ?? 0.0,
        per100gSnapshot: NutritionFacts.decode(row['nutrients'] as String? ?? ''),
        meal: MealType.fromName(row['meal'] as String?),
        loggedAt: DateTime.tryParse(row['logged_at'] as String? ?? '') ??
            DateTime.now(),
        note: row['note'] as String? ?? '',
      );

  static Map<String, Object?> _toRow(LogEntry e) => <String, Object?>{
        'food_id': e.foodId,
        'food_name': e.foodName,
        'grams': e.grams,
        'nutrients': e.per100gSnapshot.encode(),
        'meal': e.meal.name,
        'logged_at': e.loggedAt.toIso8601String(),
        'day': dayKey(e.loggedAt),
        'note': e.note,
      };

  Future<List<LogEntry>> forDay(DateTime date) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'log_entries',
      where: 'day = ?',
      whereArgs: <Object?>[dayKey(date)],
      orderBy: 'logged_at ASC',
    );
    final List<LogEntry> entries = rows.map(_fromRow).toList();
    entries.sort((LogEntry a, LogEntry b) {
      final int byMeal = a.meal.order.compareTo(b.meal.order);
      return byMeal != 0 ? byMeal : a.loggedAt.compareTo(b.loggedAt);
    });
    return entries;
  }

  Future<List<LogEntry>> between(DateTime from, DateTime to) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'log_entries',
      where: 'day >= ? AND day <= ?',
      whereArgs: <Object?>[dayKey(from), dayKey(to)],
      orderBy: 'logged_at ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<int> insert(LogEntry entry) => _db.insert('log_entries', _toRow(entry));

  Future<void> update(LogEntry entry) async {
    final int? id = entry.id;
    if (id == null) throw ArgumentError('Cannot update an entry with no id.');
    await _db.update('log_entries', _toRow(entry),
        where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<void> delete(int id) async {
    await _db.delete('log_entries', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  /// Distinct days that have at least one food entry, newest first.
  Future<List<String>> loggedDays({int limit = 120}) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT DISTINCT day FROM log_entries ORDER BY day DESC LIMIT ?',
      <Object?>[limit],
    );
    return rows
        .map((Map<String, Object?> r) => r['day'] as String? ?? '')
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);
  }
}
