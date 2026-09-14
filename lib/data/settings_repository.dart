import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/profile.dart';
import '../domain/water_entry.dart';
import 'database.dart';

/// Key-value store for the profile and app preferences.
class SettingsRepository {
  SettingsRepository(this._app);

  final AppDatabase _app;
  Database get _db => _app.db;

  static const String _profileKey = 'profile';
  static const String _presetsKey = 'drinkPresets';
  static const String _onboardedKey = 'onboarded';

  Future<String?> _raw(String key) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'settings',
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> _write(String key, String value) async {
    await _db.insert(
      'settings',
      <String, Object?>{'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<UserProfile> loadProfile() async {
    final String? raw = await _raw(_profileKey);
    if (raw == null || raw.isEmpty) return const UserProfile();
    final Object? decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return UserProfile.fromJson(decoded);
    return const UserProfile();
  }

  Future<void> saveProfile(UserProfile profile) =>
      _write(_profileKey, jsonEncode(profile.toJson()));

  Future<List<DrinkPreset>> loadPresets() async {
    final String? raw = await _raw(_presetsKey);
    if (raw == null || raw.isEmpty) return DrinkPreset.defaults;
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List) return DrinkPreset.defaults;
    final List<DrinkPreset> out = <DrinkPreset>[];
    for (final Object? item in decoded) {
      if (item is Map<String, dynamic>) out.add(DrinkPreset.fromJson(item));
    }
    return out.isEmpty ? DrinkPreset.defaults : out;
  }

  Future<void> savePresets(List<DrinkPreset> presets) => _write(
        _presetsKey,
        jsonEncode(presets.map((DrinkPreset p) => p.toJson()).toList()),
      );

  Future<bool> isOnboarded() async => (await _raw(_onboardedKey)) == 'true';

  Future<void> setOnboarded(bool value) =>
      _write(_onboardedKey, value ? 'true' : 'false');
}
