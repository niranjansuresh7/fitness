import 'dart:convert';

import 'nutrients.dart';

/// An immutable bundle of nutrient amounts.
///
/// The same type is used for two things, distinguished only by context:
///  * a food's composition **per 100 g** ([FoodItem.per100g]), and
///  * an **absolute** amount actually eaten ([scaledToGrams]) or a daily total.
///
/// A missing key means "not known", which is deliberately different from zero:
/// [has] lets the UI show "—" instead of claiming a food contains no iron when
/// the label simply did not print it. For summing purposes an unknown value
/// contributes nothing, which is the only honest choice available.
class NutritionFacts {
  const NutritionFacts(this.values);

  final Map<Nutrient, double> values;

  static const NutritionFacts empty = NutritionFacts(<Nutrient, double>{});

  double operator [](Nutrient n) => values[n] ?? 0.0;

  bool has(Nutrient n) => values.containsKey(n);

  double? lookup(Nutrient n) => values[n];

  bool get isEmpty => values.isEmpty;

  /// Scale a per-100 g composition to the amount actually eaten.
  ///
  /// This is the single multiplication the whole app's accuracy rests on:
  /// `amount = per100g * grams / 100`.
  NutritionFacts scaledToGrams(double grams) {
    final double factor = grams / 100.0;
    return NutritionFacts(<Nutrient, double>{
      for (final MapEntry<Nutrient, double> e in values.entries)
        e.key: e.value * factor,
    });
  }

  NutritionFacts scaledBy(double factor) => NutritionFacts(<Nutrient, double>{
        for (final MapEntry<Nutrient, double> e in values.entries)
          e.key: e.value * factor,
      });

  /// Union-sum: a nutrient known in either operand appears in the result.
  NutritionFacts operator +(NutritionFacts other) {
    final Map<Nutrient, double> out = Map<Nutrient, double>.of(values);
    for (final MapEntry<Nutrient, double> e in other.values.entries) {
      out[e.key] = (out[e.key] ?? 0.0) + e.value;
    }
    return NutritionFacts(out);
  }

  NutritionFacts withValue(Nutrient n, double? value) {
    final Map<Nutrient, double> out = Map<Nutrient, double>.of(values);
    if (value == null) {
      out.remove(n);
    } else {
      out[n] = value;
    }
    return NutritionFacts(out);
  }

  static NutritionFacts sum(Iterable<NutritionFacts> parts) {
    final Map<Nutrient, double> out = <Nutrient, double>{};
    for (final NutritionFacts p in parts) {
      for (final MapEntry<Nutrient, double> e in p.values.entries) {
        out[e.key] = (out[e.key] ?? 0.0) + e.value;
      }
    }
    return NutritionFacts(out);
  }

  /// Energy recomputed from the macros using [AtwaterFactors].
  ///
  /// Used to sanity-check hand-entered foods — see [energyDiscrepancyRatio].
  double get atwaterEnergyKcal {
    final double fiberG = this[Nutrient.fiber];
    // Most labels include fibre inside total carbohydrate. Subtract it so it is
    // charged at 2 kcal/g rather than 4, and never allow a negative term when a
    // user types fibre larger than carbs by mistake.
    final double digestibleCarbG =
        (this[Nutrient.carbs] - fiberG).clamp(0.0, double.infinity);
    return this[Nutrient.protein] * AtwaterFactors.protein +
        digestibleCarbG * AtwaterFactors.digestibleCarb +
        fiberG * AtwaterFactors.fiber +
        this[Nutrient.fat] * AtwaterFactors.fat +
        this[Nutrient.alcohol] * AtwaterFactors.alcohol;
  }

  /// How far the stated energy is from the energy implied by the macros,
  /// as a signed fraction of the stated value. `null` when either side is
  /// unknown or zero, so there is nothing meaningful to compare.
  ///
  /// A result of `0.08` means the label claims 8% more kcal than its own macros
  /// account for. Anything beyond ~10% is usually a typo or a unit mix-up.
  double? get energyDiscrepancyRatio {
    final double? stated = values[Nutrient.energy];
    if (stated == null || stated <= 0) return null;
    final double computed = atwaterEnergyKcal;
    if (computed <= 0) return null;
    return (stated - computed) / stated;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        for (final MapEntry<Nutrient, double> e in values.entries)
          e.key.key: e.value,
      };

  static NutritionFacts fromJson(Map<String, dynamic> json) {
    final Map<Nutrient, double> out = <Nutrient, double>{};
    for (final MapEntry<String, dynamic> e in json.entries) {
      final Nutrient? n = Nutrient.fromKey(e.key);
      final Object? v = e.value;
      if (n != null && v is num) out[n] = v.toDouble();
    }
    return NutritionFacts(out);
  }

  String encode() => jsonEncode(toJson());

  static NutritionFacts decode(String source) {
    if (source.isEmpty) return empty;
    final Object? decoded = jsonDecode(source);
    if (decoded is Map<String, dynamic>) return fromJson(decoded);
    return empty;
  }

  @override
  String toString() => 'NutritionFacts(${toJson()})';
}
