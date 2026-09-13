import 'package:sqflite/sqflite.dart';

import '../domain/food_item.dart';
import '../domain/nutrition.dart';
import 'database.dart';

/// CRUD for your personal food library.
class FoodRepository {
  FoodRepository(this._app);

  final AppDatabase _app;
  Database get _db => _app.db;

  static FoodItem _fromRow(Map<String, Object?> row) {
    final String rawTags = row['tags'] as String? ?? '';
    return FoodItem(
      id: row['id'] as int?,
      name: row['name'] as String? ?? '',
      brand: row['brand'] as String? ?? '',
      note: row['note'] as String? ?? '',
      per100g: NutritionFacts.decode(row['nutrients'] as String? ?? ''),
      servingName: row['serving_name'] as String? ?? '',
      servingGrams: (row['serving_grams'] as num?)?.toDouble(),
      densityGPerMl: (row['density_g_per_ml'] as num?)?.toDouble(),
      isLiquid: (row['is_liquid'] as int? ?? 0) == 1,
      tags: rawTags.isEmpty ? const <String>[] : rawTags.split('|'),
      favorite: (row['favorite'] as int? ?? 0) == 1,
      useCount: row['use_count'] as int? ?? 0,
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? ''),
    );
  }

  static Map<String, Object?> _toRow(FoodItem f) => <String, Object?>{
        'name': f.name,
        'brand': f.brand,
        'note': f.note,
        'nutrients': f.per100g.encode(),
        'serving_name': f.servingName,
        'serving_grams': f.servingGrams,
        'density_g_per_ml': f.densityGPerMl,
        'is_liquid': f.isLiquid ? 1 : 0,
        'tags': f.tags.join('|'),
        'favorite': f.favorite ? 1 : 0,
        'use_count': f.useCount,
        'created_at': (f.createdAt ?? DateTime.now()).toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

  /// Most-used first, then favourites, then alphabetical — so the foods you
  /// actually eat rise to the top of the list on their own.
  Future<List<FoodItem>> all({String query = ''}) async {
    final String trimmed = query.trim();
    final List<Map<String, Object?>> rows = await _db.query(
      'foods',
      where: trimmed.isEmpty ? null : 'name LIKE ? OR brand LIKE ?',
      whereArgs: trimmed.isEmpty ? null : <Object?>['%$trimmed%', '%$trimmed%'],
      orderBy: 'favorite DESC, use_count DESC, name COLLATE NOCASE ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<FoodItem?> byId(int id) async {
    final List<Map<String, Object?>> rows =
        await _db.query('foods', where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<int> insert(FoodItem food) =>
      _db.insert('foods', _toRow(food));

  Future<void> update(FoodItem food) async {
    final int? id = food.id;
    if (id == null) throw ArgumentError('Cannot update a food with no id.');
    await _db.update('foods', _toRow(food),
        where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<int> save(FoodItem food) async {
    if (food.id == null) return insert(food);
    await update(food);
    return food.id!;
  }

  /// Removes the food from the library. Entries already logged from it keep
  /// their own nutrition snapshot and are left untouched.
  Future<void> delete(int id) async {
    await _db.delete('foods', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<void> recordUse(int id) async {
    await _db.rawUpdate(
      'UPDATE foods SET use_count = use_count + 1 WHERE id = ?',
      <Object?>[id],
    );
  }

  Future<void> setFavorite(int id, bool value) async {
    await _db.update('foods', <String, Object?>{'favorite': value ? 1 : 0},
        where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<int> count() async {
    final List<Map<String, Object?>> rows =
        await _db.rawQuery('SELECT COUNT(*) AS c FROM foods');
    return (rows.first['c'] as int?) ?? 0;
  }
}
