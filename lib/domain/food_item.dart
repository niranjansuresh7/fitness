import 'nutrients.dart';
import 'nutrition.dart';

/// A food in your personal library.
///
/// Nutrition is always stored **per 100 g**, whatever units the packet used.
/// Converting on the way in (once, when you add the food) rather than on the
/// way out (every time you log it) keeps rounding error from compounding.
class FoodItem {
  const FoodItem({
    this.id,
    required this.name,
    this.brand = '',
    this.note = '',
    required this.per100g,
    this.servingName = '',
    this.servingGrams,
    this.densityGPerMl,
    this.isLiquid = false,
    this.tags = const <String>[],
    this.favorite = false,
    this.useCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final String name;
  final String brand;
  final String note;

  /// Composition per 100 g.
  final NutritionFacts per100g;

  /// Optional named portion, e.g. "1 roti".
  final String servingName;

  /// Weight of one [servingName], in grams. Lets you log "2 rotis" and still
  /// have the maths run on exact grams underneath.
  final double? servingGrams;

  /// Grams per millilitre, for foods you measure by volume.
  /// Water is 1.0, milk about 1.03, most cooking oils about 0.92.
  final double? densityGPerMl;

  final bool isLiquid;
  final List<String> tags;
  final bool favorite;

  /// Incremented on every log, used to float your real foods to the top.
  final int useCount;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayName => brand.isEmpty ? name : '$name ($brand)';

  /// Convert a volume in millilitres to grams using [densityGPerMl].
  /// Returns null when no density is recorded, because guessing would be worse
  /// than refusing.
  double? millilitresToGrams(double ml) {
    final double? d = densityGPerMl;
    return d == null ? null : ml * d;
  }

  /// Nutrition for an exact weight.
  NutritionFacts forGrams(double grams) => per100g.scaledToGrams(grams);

  /// Nutrition for a number of [servingName] portions, null if no serving
  /// weight is recorded.
  NutritionFacts? forServings(double servings) {
    final double? g = servingGrams;
    return g == null ? null : per100g.scaledToGrams(g * servings);
  }

  /// Below this, the Atwater cross-check is not worth running: for a food with
  /// a handful of calories per 100 g (black coffee, cucumber, stock) a rounding
  /// difference of 1 kcal is a huge *percentage* but a meaningless absolute.
  static const double _energyCheckFloorKcal = 20.0;

  /// True when the stated energy disagrees with its own macros by more than
  /// [tolerance]. Surfaced as a warning when you save a food, so a mistyped
  /// value gets caught at entry rather than after a month of bad totals.
  bool hasEnergyMismatch({double tolerance = 0.10}) {
    if (per100g[Nutrient.energy] < _energyCheckFloorKcal) return false;
    final double? ratio = per100g.energyDiscrepancyRatio;
    return ratio != null && ratio.abs() > tolerance;
  }

  /// True when the fat breakdown adds up to more than total fat, or the sugar
  /// and fibre exceed total carbohydrate — both are impossible.
  List<String> validate() {
    final List<String> problems = <String>[];
    final NutritionFacts f = per100g;

    if (f[Nutrient.protein] + f[Nutrient.carbs] + f[Nutrient.fat] > 100.5) {
      problems.add(
          'Protein + carbs + fat exceed 100 g per 100 g, which is impossible.');
    }
    final double fatParts = f[Nutrient.satFat] +
        f[Nutrient.monoFat] +
        f[Nutrient.polyFat] +
        f[Nutrient.transFat];
    if (f.has(Nutrient.fat) && fatParts > f[Nutrient.fat] + 0.5) {
      problems.add('Saturated + mono + poly + trans fat exceed total fat.');
    }
    if (f.has(Nutrient.carbs) &&
        f[Nutrient.sugar] + f[Nutrient.fiber] > f[Nutrient.carbs] + 0.5) {
      problems.add('Sugars + fibre exceed total carbohydrate.');
    }
    if (f[Nutrient.addedSugar] > f[Nutrient.sugar] + 0.5 &&
        f.has(Nutrient.sugar)) {
      problems.add('Added sugar exceeds total sugars.');
    }
    if (f[Nutrient.water] > 100.5) {
      problems.add('Water content exceeds 100 g per 100 g.');
    }
    final double? ratio = f[Nutrient.energy] < _energyCheckFloorKcal
        ? null
        : f.energyDiscrepancyRatio;
    if (ratio != null && ratio.abs() > 0.10) {
      problems
          .add('Stated energy is ${(ratio * 100).abs().toStringAsFixed(0)}% '
              '${ratio > 0 ? 'higher' : 'lower'} than its macros imply '
              '(${f.atwaterEnergyKcal.round()} kcal). Check for a typo.');
    }
    return problems;
  }

  FoodItem copyWith({
    int? id,
    String? name,
    String? brand,
    String? note,
    NutritionFacts? per100g,
    String? servingName,
    double? servingGrams,
    bool clearServingGrams = false,
    double? densityGPerMl,
    bool clearDensity = false,
    bool? isLiquid,
    List<String>? tags,
    bool? favorite,
    int? useCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FoodItem(
      id: id ?? this.id,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      note: note ?? this.note,
      per100g: per100g ?? this.per100g,
      servingName: servingName ?? this.servingName,
      servingGrams:
          clearServingGrams ? null : (servingGrams ?? this.servingGrams),
      densityGPerMl:
          clearDensity ? null : (densityGPerMl ?? this.densityGPerMl),
      isLiquid: isLiquid ?? this.isLiquid,
      tags: tags ?? this.tags,
      favorite: favorite ?? this.favorite,
      useCount: useCount ?? this.useCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
