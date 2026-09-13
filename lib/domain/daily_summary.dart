import 'log_entry.dart';
import 'nutrients.dart';
import 'nutrition.dart';
import 'profile.dart';
import 'targets.dart';
import 'water_entry.dart';

/// Everything that happened on one calendar day, with its targets attached.
class DaySummary {
  DaySummary({
    required this.date,
    required this.profile,
    required this.entries,
    required this.waterEntries,
  })  : totals = NutritionFacts.sum(entries.map((LogEntry e) => e.nutrition)),
        waterDrunkMl = waterEntries.fold<double>(
            0.0, (double sum, WaterEntry w) => sum + w.volumeMl);

  final DateTime date;
  final UserProfile profile;
  final List<LogEntry> entries;
  final List<WaterEntry> waterEntries;

  /// Sum of every logged entry. Exact — no intermediate rounding.
  final NutritionFacts totals;

  /// Total drunk today, millilitres.
  final double waterDrunkMl;

  /// Water obtained from food, millilitres. Food water content is stored in
  /// grams; at the densities involved 1 g is treated as 1 ml.
  double get waterFromFoodMl => totals[Nutrient.water];

  DailyTargets get targets => TargetCalculator.build(
        profile,
        date: date,
        foodWaterMl: waterFromFoodMl,
      );

  double consumed(Nutrient n) => totals[n];

  double remaining(Nutrient n) =>
      targets.nutrients[n]?.remainingFrom(totals[n]) ?? 0.0;

  double progress(Nutrient n) =>
      targets.nutrients[n]?.progressFrom(totals[n]) ?? 0.0;

  // --- Water ---------------------------------------------------------------

  double get waterTargetMl => targets.water.drinkingTargetMl;

  double get waterRemainingMl {
    final double left = waterTargetMl - waterDrunkMl;
    return left > 0 ? left : 0.0;
  }

  double get waterProgress =>
      waterTargetMl <= 0 ? 0.0 : waterDrunkMl / waterTargetMl;

  bool get waterGoalMet => waterDrunkMl >= waterTargetMl;

  /// How much you should have drunk by [now] if you were spreading the day's
  /// water evenly across your waking hours.
  ///
  /// Before you wake this is 0; after your bedtime it is the full target.
  double expectedWaterByMl(DateTime now) {
    final int minuteOfDay = now.hour * 60 + now.minute;
    final int wake = profile.wakeMinuteOfDay;
    final int waking = profile.wakingMinutes;
    if (waking <= 0) return waterTargetMl;

    int elapsed = minuteOfDay - wake;
    if (elapsed < 0) elapsed += 24 * 60;
    if (elapsed > waking) return waterTargetMl;

    return waterTargetMl * elapsed / waking;
  }

  /// Positive when you are ahead of pace, negative when behind.
  double waterPaceMl(DateTime now) => waterDrunkMl - expectedWaterByMl(now);

  /// Millilitres per remaining waking hour needed to finish the day on target.
  /// Returns null once the goal is met or the day is over.
  double? waterPerRemainingHour(DateTime now) {
    if (waterGoalMet) return null;
    final int minuteOfDay = now.hour * 60 + now.minute;
    final int wake = profile.wakeMinuteOfDay;
    int elapsed = minuteOfDay - wake;
    if (elapsed < 0) elapsed += 24 * 60;
    final int left = profile.wakingMinutes - elapsed;
    if (left <= 0) return null;
    return waterRemainingMl / (left / 60.0);
  }

  // --- Meals ---------------------------------------------------------------

  List<LogEntry> entriesFor(MealType meal) => entries
      .where((LogEntry e) => e.meal == meal)
      .toList(growable: false);

  NutritionFacts totalsFor(MealType meal) =>
      NutritionFacts.sum(entriesFor(meal).map((LogEntry e) => e.nutrition));

  /// Nutrients that are [TargetKind.limit] and have been exceeded today.
  List<Nutrient> get exceededLimits {
    final List<Nutrient> out = <Nutrient>[];
    targets.nutrients.forEach((Nutrient n, NutrientTarget t) {
      if (t.isExceededBy(totals[n])) out.add(n);
    });
    return out;
  }

  /// Goal nutrients still meaningfully short, worst first. Only counts
  /// nutrients you have actually logged data for today.
  List<Nutrient> shortfalls({double threshold = 0.8}) {
    final List<Nutrient> out = <Nutrient>[];
    targets.nutrients.forEach((Nutrient n, NutrientTarget t) {
      if (t.kind != TargetKind.goal) return;
      if (t.amount <= 0) return;
      if (totals[n] / t.amount < threshold) out.add(n);
    });
    out.sort((Nutrient a, Nutrient b) =>
        progress(a).compareTo(progress(b)));
    return out;
  }

  static DaySummary emptyFor(UserProfile profile, DateTime date) => DaySummary(
        date: DateTime(date.year, date.month, date.day),
        profile: profile,
        entries: const <LogEntry>[],
        waterEntries: const <WaterEntry>[],
      );
}
