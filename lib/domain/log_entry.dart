import 'nutrition.dart';

enum MealType {
  breakfast('Breakfast', 0),
  lunch('Lunch', 1),
  snack('Snack', 2),
  dinner('Dinner', 3);

  const MealType(this.label, this.order);
  final String label;
  final int order;

  static MealType fromName(String? name) {
    for (final MealType m in MealType.values) {
      if (m.name == name) return m;
    }
    return MealType.snack;
  }

  /// Best guess from the clock, used to preselect the meal when logging.
  static MealType forHour(int hour) {
    if (hour < 11) return MealType.breakfast;
    if (hour < 16) return MealType.lunch;
    if (hour < 19) return MealType.snack;
    return MealType.dinner;
  }
}

/// One logged food.
///
/// The per-100 g composition is **copied into the entry** at log time rather
/// than looked up through [foodId]. Correcting a food's nutrition tomorrow
/// therefore leaves yesterday's totals exactly as they were recorded, which is
/// the only way a history can be trusted.
class LogEntry {
  const LogEntry({
    this.id,
    this.foodId,
    required this.foodName,
    required this.grams,
    required this.per100gSnapshot,
    required this.meal,
    required this.loggedAt,
    this.note = '',
  });

  final int? id;

  /// Null when the source food has since been deleted from the library.
  final int? foodId;

  final String foodName;
  final double grams;
  final NutritionFacts per100gSnapshot;
  final MealType meal;
  final DateTime loggedAt;
  final String note;

  /// What this entry actually contributed.
  NutritionFacts get nutrition => per100gSnapshot.scaledToGrams(grams);

  LogEntry copyWith({
    int? id,
    int? foodId,
    String? foodName,
    double? grams,
    NutritionFacts? per100gSnapshot,
    MealType? meal,
    DateTime? loggedAt,
    String? note,
  }) {
    return LogEntry(
      id: id ?? this.id,
      foodId: foodId ?? this.foodId,
      foodName: foodName ?? this.foodName,
      grams: grams ?? this.grams,
      per100gSnapshot: per100gSnapshot ?? this.per100gSnapshot,
      meal: meal ?? this.meal,
      loggedAt: loggedAt ?? this.loggedAt,
      note: note ?? this.note,
    );
  }
}
