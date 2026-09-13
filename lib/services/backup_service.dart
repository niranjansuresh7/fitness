import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../data/database.dart';
import '../data/settings_repository.dart';
import '../domain/profile.dart';
import '../domain/water_entry.dart';

/// Export and restore the whole database as a single JSON document.
///
/// With everything stored on one phone and no account behind it, an export is
/// the only thing standing between you and losing months of logs to a dropped
/// handset. Keep one somewhere safe.
class BackupService {
  BackupService(this._app, this._settings);

  final AppDatabase _app;
  final SettingsRepository _settings;

  static const int formatVersion = 1;

  Database get _db => _app.db;

  Future<String> export() async {
    final UserProfile profile = await _settings.loadProfile();
    final List<DrinkPreset> presets = await _settings.loadPresets();

    final Map<String, dynamic> payload = <String, dynamic>{
      'formatVersion': formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'profile': profile.toJson(),
      'drinkPresets':
          presets.map((DrinkPreset p) => p.toJson()).toList(growable: false),
      'foods': await _db.query('foods'),
      'logEntries': await _db.query('log_entries'),
      'waterEntries': await _db.query('water_entries'),
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Replace everything with the contents of [source].
  ///
  /// All-or-nothing: it runs in a transaction, so a malformed file leaves the
  /// existing data untouched rather than half-overwritten.
  Future<BackupRestoreResult> restore(String source) async {
    final Object? decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('That file is not a HydraFuel backup.');
    }

    final Object? version = decoded['formatVersion'];
    if (version is! int || version > formatVersion) {
      throw FormatException(
        'This backup was written by a newer version of the app '
        '(format $version). Update the app first.',
      );
    }

    final List<Map<String, Object?>> foods = _rows(decoded['foods']);
    final List<Map<String, Object?>> entries = _rows(decoded['logEntries']);
    final List<Map<String, Object?>> waters = _rows(decoded['waterEntries']);

    await _db.transaction((Transaction txn) async {
      await txn.delete('foods');
      await txn.delete('log_entries');
      await txn.delete('water_entries');

      for (final Map<String, Object?> row in foods) {
        await txn.insert('foods', row);
      }
      for (final Map<String, Object?> row in entries) {
        await txn.insert('log_entries', row);
      }
      for (final Map<String, Object?> row in waters) {
        await txn.insert('water_entries', row);
      }
    });

    final Object? rawProfile = decoded['profile'];
    if (rawProfile is Map<String, dynamic>) {
      await _settings.saveProfile(UserProfile.fromJson(rawProfile));
    }

    final Object? rawPresets = decoded['drinkPresets'];
    if (rawPresets is List) {
      final List<DrinkPreset> presets = <DrinkPreset>[];
      for (final Object? p in rawPresets) {
        if (p is Map<String, dynamic>) presets.add(DrinkPreset.fromJson(p));
      }
      if (presets.isNotEmpty) await _settings.savePresets(presets);
    }

    return BackupRestoreResult(
      foods: foods.length,
      entries: entries.length,
      waterEntries: waters.length,
    );
  }

  static List<Map<String, Object?>> _rows(Object? raw) {
    if (raw is! List) return const <Map<String, Object?>>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> m) => Map<String, Object?>.of(m))
        .toList(growable: false);
  }
}

class BackupRestoreResult {
  const BackupRestoreResult({
    required this.foods,
    required this.entries,
    required this.waterEntries,
  });

  final int foods;
  final int entries;
  final int waterEntries;

  @override
  String toString() =>
      '$foods foods, $entries food entries and $waterEntries drinks restored.';
}
