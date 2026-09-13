import 'nutrients.dart';
import 'nutrition.dart';
import 'profile.dart';

/// How a target should be read.
enum TargetKind {
  /// Hit this number (protein, fibre, water).
  goal,

  /// Stay at or below (sodium, saturated fat, added sugar).
  limit,

  /// Never go below (essential fat floor).
  floor,
}

/// A single nutrient target plus the reasoning that produced it.
///
/// [rationale] is surfaced in the UI so every number on screen can be traced
/// back to the formula that made it. Nothing here is a magic constant.
class NutrientTarget {
  const NutrientTarget({
    required this.nutrient,
    required this.amount,
    required this.kind,
    required this.rationale,
    this.isOverride = false,
  });

  final Nutrient nutrient;
  final double amount;
  final TargetKind kind;
  final String rationale;

  /// True when this came from the user's own override rather than a formula.
  final bool isOverride;

  /// Progress towards this target as a fraction (may exceed 1.0).
  double progressFrom(double consumed) => amount <= 0 ? 0.0 : consumed / amount;

  /// What is still allowed or still owed. Never negative.
  double remainingFrom(double consumed) {
    final double left = amount - consumed;
    return left > 0 ? left : 0.0;
  }

  /// True when a [TargetKind.limit] has been breached.
  bool isExceededBy(double consumed) =>
      kind == TargetKind.limit && consumed > amount;
}

/// The water plan for a day, broken into its parts so the arithmetic is visible.
class WaterTarget {
  const WaterTarget({
    required this.baselineMl,
    required this.exerciseMl,
    required this.climateMl,
    required this.foodWaterCreditMl,
  });

  /// Body-mass baseline: `weightKg * mlPerKg`.
  final double baselineMl;

  /// `exerciseMinutes * mlPerExerciseMinute`.
  final double exerciseMl;

  /// Heat and humidity allowance.
  final double climateMl;

  /// Water obtained from food that is deducted from the drinking goal.
  /// Zero unless the user opted in.
  final double foodWaterCreditMl;

  /// Total water the body needs from all sources.
  double get totalWaterMl => baselineMl + exerciseMl + climateMl;

  /// What must actually be drunk. Floored at 1000 ml so a food-water credit can
  /// never drive the goal down to something unsafe.
  double get drinkingTargetMl {
    final double net = totalWaterMl - foodWaterCreditMl;
    return net < 1000.0 ? 1000.0 : net;
  }
}

/// A complete, dated set of targets.
///
/// A snapshot is stored per day so that changing your weight next month does
/// not silently rewrite what "100% of goal" meant last week.
class DailyTargets {
  const DailyTargets({
    required this.date,
    required this.bmrKcal,
    required this.tdeeKcal,
    required this.energyKcal,
    required this.energyAdjustmentKcal,
    required this.water,
    required this.nutrients,
  });

  final DateTime date;

  /// Basal metabolic rate — energy at complete rest.
  final double bmrKcal;

  /// Total daily energy expenditure — BMR times the activity factor.
  final double tdeeKcal;

  /// The actual calorie budget after the goal adjustment.
  final double energyKcal;

  /// Signed deficit (negative) or surplus (positive) applied to TDEE.
  final double energyAdjustmentKcal;

  final WaterTarget water;

  final Map<Nutrient, NutrientTarget> nutrients;

  NutrientTarget? operator [](Nutrient n) => nutrients[n];

  double amountFor(Nutrient n) => nutrients[n]?.amount ?? 0.0;
}

/// Pure functions that turn a [UserProfile] into numbers.
///
/// Every method here is deterministic and side-effect free so the whole target
/// engine can be unit-tested against published reference values.
class TargetCalculator {
  const TargetCalculator._();

  /// Energy density of body fat, kcal per kg. The classic 7700 kcal/kg figure
  /// (3500 kcal/lb) used to convert a weekly rate into a daily adjustment.
  static const double kcalPerKgBodyFat = 7700.0;

  /// Basal metabolic rate in kcal/day.
  ///
  /// Falls back from Katch-McArdle to Mifflin-St Jeor when body fat is unknown,
  /// because Katch-McArdle without lean mass is not defined.
  static double bmr(UserProfile p) {
    switch (p.bmrFormula) {
      case BmrFormula.katchMcArdle:
        final double? lbm = p.leanBodyMassKg;
        if (lbm != null) return 370.0 + 21.6 * lbm;
        return _mifflin(p);
      case BmrFormula.harrisBenedict:
        return p.sex == Sex.male
            ? 88.362 +
                13.397 * p.weightKg +
                4.799 * p.heightCm -
                5.677 * p.ageYears
            : 447.593 +
                9.247 * p.weightKg +
                3.098 * p.heightCm -
                4.330 * p.ageYears;
      case BmrFormula.mifflinStJeor:
        return _mifflin(p);
    }
  }

  static double _mifflin(UserProfile p) {
    final double base =
        10.0 * p.weightKg + 6.25 * p.heightCm - 5.0 * p.ageYears;
    return p.sex == Sex.male ? base + 5.0 : base - 161.0;
  }

  /// Total daily energy expenditure.
  static double tdee(UserProfile p) => bmr(p) * p.activityLevel.multiplier;

  /// Daily calorie change implied by the goal and rate.
  ///
  /// Negative for fat loss, positive for gain. Clamped so the resulting budget
  /// can never fall below BMR — eating under your basal rate is not a target
  /// this app will ever hand you.
  static double energyAdjustment(UserProfile p) {
    if (p.goal == WeightGoal.maintain || p.rateKgPerWeek <= 0) return 0.0;
    final double perDay = p.rateKgPerWeek.abs() * kcalPerKgBodyFat / 7.0;
    if (p.goal == WeightGoal.gain) return perDay;

    final double maxDeficit = tdee(p) - bmr(p);
    return -(perDay > maxDeficit ? maxDeficit : perDay);
  }

  static double energyBudget(UserProfile p) {
    final double? override = p.energyOverrideKcal;
    if (override != null && override > 0) return override;
    return tdee(p) + energyAdjustment(p);
  }

  static WaterTarget water(UserProfile p, {double foodWaterMl = 0.0}) {
    return WaterTarget(
      baselineMl: p.weightKg * p.waterMlPerKg,
      exerciseMl: p.dailyExerciseMinutes * p.waterMlPerExerciseMinute,
      climateMl: p.climate.extraWaterMl.toDouble(),
      foodWaterCreditMl: p.countFoodWaterTowardsTarget ? foodWaterMl : 0.0,
    );
  }

  /// Build the full target set for [date].
  ///
  /// [foodWaterMl] is the water already obtained from logged food; it only
  /// affects the result when the profile opts into food-water crediting.
  static DailyTargets build(
    UserProfile p, {
    required DateTime date,
    double foodWaterMl = 0.0,
  }) {
    final double bmrKcal = bmr(p);
    final double tdeeKcal = tdee(p);
    final double adjustment = energyAdjustment(p);
    final double energy = energyBudget(p);

    final Map<Nutrient, NutrientTarget> targets = <Nutrient, NutrientTarget>{};

    void put(Nutrient n, double amount, TargetKind kind, String why) {
      targets[n] = NutrientTarget(
        nutrient: n,
        amount: amount,
        kind: kind,
        rationale: why,
      );
    }

    put(
      Nutrient.energy,
      energy,
      TargetKind.goal,
      p.energyOverrideKcal != null
          ? 'Manual override.'
          : 'BMR ${bmrKcal.round()} kcal (${p.bmrFormula.label}) '
              'x ${p.activityLevel.multiplier} activity = ${tdeeKcal.round()} kcal TDEE, '
              '${adjustment == 0 ? 'no adjustment' : '${adjustment > 0 ? '+' : ''}${adjustment.round()} kcal for ${p.rateKgPerWeek} kg/week'}.',
    );

    // --- Protein -----------------------------------------------------------
    final double? lbm = p.leanBodyMassKg;
    final bool useLean = p.proteinBasis == ProteinBasis.leanMass && lbm != null;
    final double proteinRefKg = useLean ? lbm : p.weightKg;
    final double proteinG = proteinRefKg * p.proteinGPerKg;
    put(
      Nutrient.protein,
      proteinG,
      TargetKind.goal,
      '${p.proteinGPerKg} g per kg of '
      '${useLean ? 'lean mass' : 'body weight'} '
      '(${proteinRefKg.toStringAsFixed(1)} kg).',
    );

    // --- Fat ---------------------------------------------------------------
    // Percentage of energy, but never below the essential-fat floor of
    // 0.5 g/kg body weight, which is the low end of what is needed for
    // hormone production and fat-soluble vitamin absorption.
    final double fatFromPercent =
        energy * p.fatPercentOfEnergy / AtwaterFactors.fat;
    final double fatFloor = 0.5 * p.weightKg;
    final double fatG = fatFromPercent < fatFloor ? fatFloor : fatFromPercent;
    put(
      Nutrient.fat,
      fatG,
      TargetKind.goal,
      fatG > fatFromPercent
          ? 'Raised to the 0.5 g/kg essential-fat floor (${fatFloor.toStringAsFixed(0)} g).'
          : '${(p.fatPercentOfEnergy * 100).toStringAsFixed(0)}% of ${energy.round()} kcal at 9 kcal/g.',
    );

    // --- Carbohydrate ------------------------------------------------------
    // Whatever energy is left once protein and fat are paid for.
    final double carbKcal =
        energy - proteinG * AtwaterFactors.protein - fatG * AtwaterFactors.fat;
    final double carbG =
        (carbKcal / AtwaterFactors.digestibleCarb).clamp(0.0, double.infinity);
    put(
      Nutrient.carbs,
      carbG,
      TargetKind.goal,
      'Remaining energy after protein and fat, at 4 kcal/g.',
    );

    // --- Fibre: Institute of Medicine, 14 g per 1000 kcal ------------------
    put(
      Nutrient.fiber,
      14.0 * energy / 1000.0,
      TargetKind.goal,
      '14 g per 1000 kcal (Institute of Medicine).',
    );

    // --- Limits ------------------------------------------------------------
    put(
      Nutrient.satFat,
      energy * 0.10 / AtwaterFactors.fat,
      TargetKind.limit,
      'Under 10% of energy (WHO). Drop to 7% if LDL is raised.',
    );
    put(
      Nutrient.transFat,
      energy * 0.01 / AtwaterFactors.fat,
      TargetKind.limit,
      'Under 1% of energy (WHO). Ideally zero.',
    );
    put(
      Nutrient.addedSugar,
      energy * 0.10 / AtwaterFactors.digestibleCarb,
      TargetKind.limit,
      'Under 10% of energy (WHO); under 5% gives additional benefit.',
    );
    put(Nutrient.sodium, 2000.0, TargetKind.limit,
        'WHO ceiling of 2000 mg/day (5 g of salt).');
    put(Nutrient.cholesterol, 300.0, TargetKind.limit,
        'Under 300 mg/day; under 200 mg if LDL is raised.');

    // --- Micronutrients: adult RDA / adequate intake -----------------------
    final bool male = p.sex == Sex.male;
    final int age = p.ageYears;

    put(Nutrient.potassium, male ? 3400.0 : 2600.0, TargetKind.goal,
        'Adequate intake for adults.');
    put(Nutrient.calcium, age > 50 ? 1200.0 : 1000.0, TargetKind.goal,
        'RDA for your age band.');
    put(Nutrient.iron, male || age > 50 ? 8.0 : 18.0, TargetKind.goal,
        'RDA; higher for menstruating women.');
    put(Nutrient.magnesium, male ? 420.0 : 320.0, TargetKind.goal, 'RDA.');
    put(Nutrient.zinc, male ? 11.0 : 8.0, TargetKind.goal, 'RDA.');
    put(Nutrient.phosphorus, 700.0, TargetKind.goal, 'RDA.');
    put(Nutrient.vitaminA, male ? 900.0 : 700.0, TargetKind.goal,
        'RDA in mcg retinol activity equivalents.');
    put(Nutrient.vitaminC, male ? 90.0 : 75.0, TargetKind.goal, 'RDA.');
    put(Nutrient.vitaminD, age > 70 ? 20.0 : 15.0, TargetKind.goal,
        'RDA in mcg (15 mcg = 600 IU).');
    put(Nutrient.vitaminB12, 2.4, TargetKind.goal, 'RDA.');
    put(Nutrient.folate, 400.0, TargetKind.goal,
        'RDA in mcg dietary folate equivalents.');
    put(Nutrient.omega3, male ? 1.6 : 1.1, TargetKind.goal,
        'Adequate intake for alpha-linolenic acid.');
    put(Nutrient.caffeine, 400.0, TargetKind.limit,
        'Generally recognised safe ceiling for healthy adults.');

    // --- User overrides win -------------------------------------------------
    for (final MapEntry<Nutrient, double> e in p.customTargets.entries) {
      final NutrientTarget? existing = targets[e.key];
      targets[e.key] = NutrientTarget(
        nutrient: e.key,
        amount: e.value,
        kind: existing?.kind ?? TargetKind.goal,
        rationale: 'Your override.',
        isOverride: true,
      );
    }

    return DailyTargets(
      date: DateTime(date.year, date.month, date.day),
      bmrKcal: bmrKcal,
      tdeeKcal: tdeeKcal,
      energyKcal: targets[Nutrient.energy]?.amount ?? energy,
      energyAdjustmentKcal: adjustment,
      water: water(p, foodWaterMl: foodWaterMl),
      nutrients: targets,
    );
  }

  /// Convenience: how much of [n] is left for the day.
  static double remaining(
          DailyTargets t, NutritionFacts consumed, Nutrient n) =>
      t.nutrients[n]?.remainingFrom(consumed[n]) ?? 0.0;
}
