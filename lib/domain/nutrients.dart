/// Canonical nutrient catalogue.
///
/// Every nutrient value in this app is stored as a `double` in the nutrient's
/// [NutrientUnit]. Rounding happens *only* at display time, never during
/// storage or arithmetic, so a day's total is the exact sum of its entries.
library;

enum NutrientUnit {
  kcal('kcal'),
  gram('g'),
  milligram('mg'),
  microgram('mcg');

  const NutrientUnit(this.symbol);
  final String symbol;
}

enum NutrientGroup {
  energy('Energy'),
  macro('Macronutrients'),
  lipid('Fats & cholesterol'),
  carbQuality('Carb quality'),
  mineral('Minerals & electrolytes'),
  vitamin('Vitamins'),
  other('Other');

  const NutrientGroup(this.label);
  final String label;
}

/// Every nutrient the app can track.
///
/// `key` is the stable serialisation name — never rename one without a
/// database migration, because it is written into every logged entry.
enum Nutrient {
  energy('energy', 'Energy', NutrientUnit.kcal, NutrientGroup.energy, 0),

  protein('protein', 'Protein', NutrientUnit.gram, NutrientGroup.macro, 1),
  carbs('carbs', 'Carbohydrate', NutrientUnit.gram, NutrientGroup.macro, 1,
      short: 'Carbs'),
  fat('fat', 'Fat', NutrientUnit.gram, NutrientGroup.macro, 1),

  fiber('fiber', 'Fibre', NutrientUnit.gram, NutrientGroup.carbQuality, 1),
  sugar(
      'sugar', 'Total sugars', NutrientUnit.gram, NutrientGroup.carbQuality, 1),
  addedSugar('addedSugar', 'Added sugar', NutrientUnit.gram,
      NutrientGroup.carbQuality, 1),

  satFat('satFat', 'Saturated fat', NutrientUnit.gram, NutrientGroup.lipid, 1),
  monoFat('monoFat', 'Monounsaturated fat', NutrientUnit.gram,
      NutrientGroup.lipid, 1),
  polyFat('polyFat', 'Polyunsaturated fat', NutrientUnit.gram,
      NutrientGroup.lipid, 1),
  transFat('transFat', 'Trans fat', NutrientUnit.gram, NutrientGroup.lipid, 2),
  omega3('omega3', 'Omega-3', NutrientUnit.gram, NutrientGroup.lipid, 2),
  cholesterol('cholesterol', 'Cholesterol', NutrientUnit.milligram,
      NutrientGroup.lipid, 0),

  sodium('sodium', 'Sodium', NutrientUnit.milligram, NutrientGroup.mineral, 0),
  potassium('potassium', 'Potassium', NutrientUnit.milligram,
      NutrientGroup.mineral, 0),
  calcium(
      'calcium', 'Calcium', NutrientUnit.milligram, NutrientGroup.mineral, 0),
  iron('iron', 'Iron', NutrientUnit.milligram, NutrientGroup.mineral, 1),
  magnesium('magnesium', 'Magnesium', NutrientUnit.milligram,
      NutrientGroup.mineral, 0),
  zinc('zinc', 'Zinc', NutrientUnit.milligram, NutrientGroup.mineral, 1),
  phosphorus('phosphorus', 'Phosphorus', NutrientUnit.milligram,
      NutrientGroup.mineral, 0),

  vitaminA('vitaminA', 'Vitamin A', NutrientUnit.microgram,
      NutrientGroup.vitamin, 0),
  vitaminC('vitaminC', 'Vitamin C', NutrientUnit.milligram,
      NutrientGroup.vitamin, 1),
  vitaminD('vitaminD', 'Vitamin D', NutrientUnit.microgram,
      NutrientGroup.vitamin, 1),
  vitaminB12('vitaminB12', 'Vitamin B12', NutrientUnit.microgram,
      NutrientGroup.vitamin, 2),
  folate('folate', 'Folate', NutrientUnit.microgram, NutrientGroup.vitamin, 0),

  water('water', 'Water content', NutrientUnit.gram, NutrientGroup.other, 0),
  caffeine(
      'caffeine', 'Caffeine', NutrientUnit.milligram, NutrientGroup.other, 0),
  alcohol('alcohol', 'Alcohol', NutrientUnit.gram, NutrientGroup.other, 1);

  const Nutrient(
    this.key,
    this.label,
    this.unit,
    this.group,
    this.decimals, {
    String? short,
  }) : _short = short;

  final String key;
  final String label;

  final String? _short;

  /// A compact name, for the stat rows where three or four of these share a
  /// phone's width. Falls back to [label] when no shorter form is needed.
  String get shortLabel => _short ?? label;
  final NutrientUnit unit;
  final NutrientGroup group;

  /// Decimal places used for *display only*.
  final int decimals;

  static final Map<String, Nutrient> _byKey = {
    for (final n in Nutrient.values) n.key: n,
  };

  static Nutrient? fromKey(String key) => _byKey[key];

  /// The three nutrients that make up the energy budget.
  static const List<Nutrient> macros = [protein, carbs, fat];

  /// Nutrients shown on the main dashboard rings.
  static const List<Nutrient> dashboard = [energy, protein, carbs, fat, fiber];

  static List<Nutrient> inGroup(NutrientGroup group) =>
      Nutrient.values.where((n) => n.group == group).toList(growable: false);
}

/// Atwater energy factors, kcal per gram.
///
/// Fibre is given 2 kcal/g (the EU/Codex figure for fermentable fibre) rather
/// than 4, and is therefore subtracted out of the carbohydrate term so it is
/// never counted twice.
class AtwaterFactors {
  const AtwaterFactors._();

  static const double protein = 4.0;
  static const double digestibleCarb = 4.0;
  static const double fiber = 2.0;
  static const double fat = 9.0;
  static const double alcohol = 7.0;
}
