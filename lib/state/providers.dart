import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dates.dart';
import '../data/database.dart';
import '../data/food_repository.dart';
import '../data/log_repository.dart';
import '../data/marker_repository.dart';
import '../data/settings_repository.dart';
import '../data/water_repository.dart';
import '../domain/blood_marker.dart';
import '../domain/clinical_flags.dart';
import '../domain/daily_summary.dart';
import '../domain/food_item.dart';
import '../domain/log_entry.dart';
import '../domain/profile.dart';
import '../domain/water_entry.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';

/// Providers whose value is supplied by `main()` before the app starts.
///
/// Overriding them at the root keeps the whole widget tree free of async
/// bootstrapping: by the time anything renders, the database is open and the
/// profile is loaded.
final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>(
  (Ref ref) =>
      throw UnimplementedError('appDatabaseProvider must be overridden'),
);

final Provider<NotificationService> notificationServiceProvider =
    Provider<NotificationService>(
  (Ref ref) => throw UnimplementedError(
      'notificationServiceProvider must be overridden'),
);

final Provider<UserProfile> initialProfileProvider = Provider<UserProfile>(
  (Ref ref) =>
      throw UnimplementedError('initialProfileProvider must be overridden'),
);

// --- Repositories ----------------------------------------------------------

final Provider<FoodRepository> foodRepositoryProvider =
    Provider<FoodRepository>(
        (Ref ref) => FoodRepository(ref.watch(appDatabaseProvider)));

final Provider<LogRepository> logRepositoryProvider = Provider<LogRepository>(
    (Ref ref) => LogRepository(ref.watch(appDatabaseProvider)));

final Provider<WaterRepository> waterRepositoryProvider =
    Provider<WaterRepository>(
        (Ref ref) => WaterRepository(ref.watch(appDatabaseProvider)));

final Provider<MarkerRepository> markerRepositoryProvider =
    Provider<MarkerRepository>(
        (Ref ref) => MarkerRepository(ref.watch(appDatabaseProvider)));

final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>(
        (Ref ref) => SettingsRepository(ref.watch(appDatabaseProvider)));

// --- Profile ---------------------------------------------------------------

class ProfileNotifier extends Notifier<UserProfile> {
  @override
  UserProfile build() => ref.watch(initialProfileProvider);

  /// Persist the profile and rebuild the reminder schedule to match.
  ///
  /// Reminders are rescheduled on every save because almost every field can
  /// change them: weight and climate change the target, wake and sleep change
  /// the window, and the interval changes the spacing.
  ///
  /// Nothing is invalidated here on purpose. [daySummaryProvider] and
  /// [historyProvider] already watch this provider, so they recompute on their
  /// own when [state] changes; invalidating them from inside the provider they
  /// depend on is a circular dependency and throws.
  Future<void> save(UserProfile profile) async {
    state = profile;
    await ref.read(settingsRepositoryProvider).saveProfile(profile);
    await ref
        .read(notificationServiceProvider)
        .rescheduleWaterReminders(profile);
  }

  /// Re-read the stored profile and adopt it.
  ///
  /// Needed after a backup restore, which writes straight to the database:
  /// without this the screen would keep showing the profile from before the
  /// restore until the app was relaunched.
  Future<void> reload() async {
    final UserProfile stored =
        await ref.read(settingsRepositoryProvider).loadProfile();
    state = stored;
    await ref
        .read(notificationServiceProvider)
        .rescheduleWaterReminders(stored);
  }
}

final NotifierProvider<ProfileNotifier, UserProfile> profileProvider =
    NotifierProvider<ProfileNotifier, UserProfile>(ProfileNotifier.new);

// --- Selected day ----------------------------------------------------------

final StateProvider<DateTime> selectedDateProvider =
    StateProvider<DateTime>((Ref ref) => startOfDay(DateTime.now()));

/// The day being viewed, as a `yyyy-MM-dd` key.
final Provider<String> selectedDayKeyProvider =
    Provider<String>((Ref ref) => dayKey(ref.watch(selectedDateProvider)));

// --- Blood markers ---------------------------------------------------------

/// Every recorded result, newest draw first.
final FutureProvider<List<BloodResult>> bloodResultsProvider =
    FutureProvider<List<BloodResult>>(
  (Ref ref) => ref.watch(markerRepositoryProvider).all(),
);

/// The latest value for each marker.
final FutureProvider<MarkerSnapshot> markerSnapshotProvider =
    FutureProvider<MarkerSnapshot>((Ref ref) async {
  final List<BloodResult> all = await ref.watch(bloodResultsProvider.future);
  return MarkerSnapshot.fromHistory(all);
});

/// What those results mean for the daily targets.
final FutureProvider<ClinicalAssessment> assessmentProvider =
    FutureProvider<ClinicalAssessment>((Ref ref) async {
  final MarkerSnapshot snapshot =
      await ref.watch(markerSnapshotProvider.future);
  return ClinicalAssessment.fromMarkers(snapshot);
});

// --- Day summary -----------------------------------------------------------

/// Everything logged on one day, keyed by its `yyyy-MM-dd` string.
///
/// Keyed by String rather than DateTime so the family identity is stable —
/// two DateTime objects for the same day are not equal if their times differ.
final FutureProviderFamily<DaySummary, String> daySummaryProvider =
    FutureProvider.family<DaySummary, String>((Ref ref, String key) async {
  final DateTime date = parseDayKey(key) ?? startOfDay(DateTime.now());
  final UserProfile profile = ref.watch(profileProvider);

  final List<LogEntry> entries =
      await ref.watch(logRepositoryProvider).forDay(date);
  final List<WaterEntry> waters =
      await ref.watch(waterRepositoryProvider).forDay(date);
  final ClinicalAssessment assessment =
      await ref.watch(assessmentProvider.future);

  return DaySummary(
    date: date,
    profile: profile,
    entries: entries,
    waterEntries: waters,
    assessment: assessment,
  );
});

/// The day currently selected in the UI.
final Provider<AsyncValue<DaySummary>> todayProvider =
    Provider<AsyncValue<DaySummary>>(
  (Ref ref) => ref.watch(daySummaryProvider(ref.watch(selectedDayKeyProvider))),
);

// --- Food library ----------------------------------------------------------

final StateProvider<String> foodSearchProvider =
    StateProvider<String>((Ref ref) => '');

final FutureProviderFamily<List<FoodItem>, String> foodListProvider =
    FutureProvider.family<List<FoodItem>, String>(
  (Ref ref, String query) =>
      ref.watch(foodRepositoryProvider).all(query: query),
);

final FutureProvider<List<DrinkPreset>> drinkPresetsProvider =
    FutureProvider<List<DrinkPreset>>(
  (Ref ref) => ref.watch(settingsRepositoryProvider).loadPresets(),
);

final FutureProvider<List<String>> loggedDaysProvider =
    FutureProvider<List<String>>(
  (Ref ref) => ref.watch(logRepositoryProvider).loggedDays(),
);

// --- Actions ---------------------------------------------------------------

/// Mutations, grouped so widgets never talk to a repository directly and
/// invalidation is handled in exactly one place.
class TrackerActions {
  TrackerActions(this._ref);

  final Ref _ref;

  void _refreshDays() {
    _ref.invalidate(daySummaryProvider);
    _ref.invalidate(loggedDaysProvider);
    _ref.invalidate(historyProvider);
  }

  void _refreshFoods() {
    _ref.invalidate(foodListProvider);
  }

  Future<void> addWater(double volumeMl,
      {String label = '', DateTime? at}) async {
    if (volumeMl <= 0) return;
    await _ref.read(waterRepositoryProvider).add(WaterEntry(
          volumeMl: volumeMl,
          loggedAt: at ?? DateTime.now(),
          label: label,
        ));
    _refreshDays();
  }

  Future<void> deleteWater(int id) async {
    await _ref.read(waterRepositoryProvider).delete(id);
    _refreshDays();
  }

  Future<void> logFood(LogEntry entry) async {
    await _ref.read(logRepositoryProvider).insert(entry);
    final int? foodId = entry.foodId;
    if (foodId != null) {
      await _ref.read(foodRepositoryProvider).recordUse(foodId);
      _refreshFoods();
    }
    _refreshDays();
  }

  Future<void> updateEntry(LogEntry entry) async {
    await _ref.read(logRepositoryProvider).update(entry);
    _refreshDays();
  }

  Future<void> deleteEntry(int id) async {
    await _ref.read(logRepositoryProvider).delete(id);
    _refreshDays();
  }

  Future<int> saveFood(FoodItem food) async {
    final int id = await _ref.read(foodRepositoryProvider).save(food);
    _refreshFoods();
    return id;
  }

  Future<void> deleteFood(int id) async {
    await _ref.read(foodRepositoryProvider).delete(id);
    _refreshFoods();
  }

  Future<void> toggleFavorite(FoodItem food) async {
    final int? id = food.id;
    if (id == null) return;
    await _ref.read(foodRepositoryProvider).setFavorite(id, !food.favorite);
    _refreshFoods();
  }

  void _refreshMarkers() {
    _ref.invalidate(bloodResultsProvider);
    // The day summaries read the assessment, so they follow automatically once
    // the results provider is rebuilt.
  }

  Future<void> saveBloodResult(BloodResult result) async {
    await _ref.read(markerRepositoryProvider).save(result);
    _refreshMarkers();
  }

  Future<void> saveBloodDraw(
      DateTime takenOn, Map<BloodMarker, double> values) async {
    if (values.isEmpty) return;
    await _ref.read(markerRepositoryProvider).saveDraw(takenOn, values);
    _refreshMarkers();
  }

  Future<void> deleteBloodResult(int id) async {
    await _ref.read(markerRepositoryProvider).delete(id);
    _refreshMarkers();
  }

  Future<void> savePresets(List<DrinkPreset> presets) async {
    await _ref.read(settingsRepositoryProvider).savePresets(presets);
    _ref.invalidate(drinkPresetsProvider);
  }
}

final Provider<TrackerActions> actionsProvider =
    Provider<TrackerActions>((Ref ref) => TrackerActions(ref));

final Provider<BackupService> backupServiceProvider = Provider<BackupService>(
  (Ref ref) => BackupService(
    ref.watch(appDatabaseProvider),
    ref.watch(settingsRepositoryProvider),
  ),
);

/// Summaries for the last [historyDayCount] days, newest first.
///
/// Loaded with two range queries rather than one pair per day, so opening the
/// history screen is a constant number of round trips.
const int historyDayCount = 30;

final FutureProvider<List<DaySummary>> historyProvider =
    FutureProvider<List<DaySummary>>((Ref ref) async {
  final UserProfile profile = ref.watch(profileProvider);
  final DateTime today = startOfDay(DateTime.now());
  final DateTime from =
      today.subtract(const Duration(days: historyDayCount - 1));

  final List<LogEntry> entries =
      await ref.watch(logRepositoryProvider).between(from, today);
  final List<WaterEntry> waters =
      await ref.watch(waterRepositoryProvider).between(from, today);
  final ClinicalAssessment assessment =
      await ref.watch(assessmentProvider.future);

  final Map<String, List<LogEntry>> entriesByDay = <String, List<LogEntry>>{};
  for (final LogEntry e in entries) {
    entriesByDay.putIfAbsent(dayKey(e.loggedAt), () => <LogEntry>[]).add(e);
  }

  final Map<String, List<WaterEntry>> watersByDay =
      <String, List<WaterEntry>>{};
  for (final WaterEntry w in waters) {
    watersByDay.putIfAbsent(dayKey(w.loggedAt), () => <WaterEntry>[]).add(w);
  }

  return List<DaySummary>.generate(historyDayCount, (int i) {
    final DateTime date = today.subtract(Duration(days: i));
    final String key = dayKey(date);
    return DaySummary(
      date: date,
      profile: profile,
      entries: entriesByDay[key] ?? const <LogEntry>[],
      waterEntries: watersByDay[key] ?? const <WaterEntry>[],
      assessment: assessment,
    );
  });
});
