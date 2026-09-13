import 'package:flutter_test/flutter_test.dart';
import 'package:hydrafuel/domain/nutrients.dart';
import 'package:hydrafuel/domain/profile.dart';
import 'package:hydrafuel/domain/targets.dart';

/// 30-year-old male, 80 kg, 180 cm. Every expected number below is worked out
/// by hand in the comments so the test doubles as documentation.
UserProfile baseProfile() => UserProfile(
      sex: Sex.male,
      birthDate: DateTime(DateTime.now().year - 30, 1, 1),
      heightCm: 180,
      weightKg: 80,
      activityLevel: ActivityLevel.light,
    );

void main() {
  group('BMR', () {
    test('Mifflin-St Jeor, male', () {
      // 10*80 + 6.25*180 - 5*30 + 5 = 800 + 1125 - 150 + 5 = 1780
      expect(TargetCalculator.bmr(baseProfile()), closeTo(1780.0, 0.5));
    });

    test('Mifflin-St Jeor, female is 166 kcal lower', () {
      final UserProfile f = baseProfile().copyWith(sex: Sex.female);
      // 800 + 1125 - 150 - 161 = 1614
      expect(TargetCalculator.bmr(f), closeTo(1614.0, 0.5));
    });

    test('Katch-McArdle uses lean mass', () {
      final UserProfile p = baseProfile().copyWith(
        bmrFormula: BmrFormula.katchMcArdle,
        bodyFatPercent: 20,
      );
      // LBM = 80 * 0.8 = 64 kg; 370 + 21.6 * 64 = 1752.4
      expect(TargetCalculator.bmr(p), closeTo(1752.4, 0.1));
    });

    test('Katch-McArdle falls back to Mifflin without a body-fat figure', () {
      final UserProfile p =
          baseProfile().copyWith(bmrFormula: BmrFormula.katchMcArdle);
      expect(TargetCalculator.bmr(p), closeTo(1780.0, 0.5));
    });

    test('an implausible body-fat figure is rejected, not used', () {
      final UserProfile p = baseProfile().copyWith(
        bmrFormula: BmrFormula.katchMcArdle,
        bodyFatPercent: 95,
      );
      expect(p.leanBodyMassKg, isNull);
      expect(TargetCalculator.bmr(p), closeTo(1780.0, 0.5));
    });
  });

  group('TDEE and the energy budget', () {
    test('applies the activity multiplier', () {
      // 1780 * 1.375 = 2447.5
      expect(TargetCalculator.tdee(baseProfile()), closeTo(2447.5, 1.0));
    });

    test('0.5 kg/week of fat loss is a 550 kcal daily deficit', () {
      final UserProfile p = baseProfile()
          .copyWith(goal: WeightGoal.lose, rateKgPerWeek: 0.5);
      // 0.5 * 7700 / 7 = 550
      expect(TargetCalculator.energyAdjustment(p), closeTo(-550.0, 0.5));
      expect(TargetCalculator.energyBudget(p), closeTo(1897.5, 1.0));
    });

    test('a surplus is applied in the other direction', () {
      final UserProfile p = baseProfile()
          .copyWith(goal: WeightGoal.gain, rateKgPerWeek: 0.25);
      expect(TargetCalculator.energyAdjustment(p), closeTo(275.0, 0.5));
    });

    test('the deficit is clamped so the budget never drops below BMR', () {
      final UserProfile p = baseProfile().copyWith(
        activityLevel: ActivityLevel.sedentary,
        goal: WeightGoal.lose,
        rateKgPerWeek: 1.5, // would be a 1650 kcal/day deficit
      );
      // BMR 1780, TDEE 2136, so the largest allowed deficit is 356.
      expect(TargetCalculator.energyBudget(p),
          closeTo(TargetCalculator.bmr(p), 1.0));
    });

    test('maintain ignores any rate that happens to be set', () {
      final UserProfile p = baseProfile()
          .copyWith(goal: WeightGoal.maintain, rateKgPerWeek: 1.0);
      expect(TargetCalculator.energyAdjustment(p), 0.0);
    });

    test('a manual override wins outright', () {
      final UserProfile p = baseProfile().copyWith(energyOverrideKcal: 2000);
      expect(TargetCalculator.energyBudget(p), 2000.0);
    });
  });

  group('macro split', () {
    late DailyTargets t;

    setUp(() {
      t = TargetCalculator.build(
        baseProfile().copyWith(goal: WeightGoal.lose, rateKgPerWeek: 0.5),
        date: DateTime(2026, 1, 1),
      );
    });

    test('protein is g/kg of body weight', () {
      // 1.6 * 80 = 128
      expect(t.amountFor(Nutrient.protein), closeTo(128.0, 0.01));
    });

    test('fat is a percentage of energy at 9 kcal/g', () {
      // 1897.5 * 0.28 / 9 = 59.03
      expect(t.amountFor(Nutrient.fat), closeTo(59.03, 0.05));
    });

    test('carbs take whatever energy is left', () {
      // (1897.5 - 128*4 - 59.03*9) / 4 = 213.56
      expect(t.amountFor(Nutrient.carbs), closeTo(213.56, 0.1));
    });

    test('the three macros reconstruct the calorie budget exactly', () {
      final double kcal = t.amountFor(Nutrient.protein) * 4 +
          t.amountFor(Nutrient.carbs) * 4 +
          t.amountFor(Nutrient.fat) * 9;
      expect(kcal, closeTo(t.energyKcal, 0.01));
    });

    test('fibre follows 14 g per 1000 kcal', () {
      expect(t.amountFor(Nutrient.fiber),
          closeTo(14.0 * t.energyKcal / 1000.0, 0.001));
    });

    test('protein can be based on lean mass instead', () {
      final DailyTargets lean = TargetCalculator.build(
        baseProfile().copyWith(
          bodyFatPercent: 20,
          proteinBasis: ProteinBasis.leanMass,
          proteinGPerKg: 2.2,
        ),
        date: DateTime(2026, 1, 1),
      );
      // 2.2 * 64 = 140.8
      expect(lean.amountFor(Nutrient.protein), closeTo(140.8, 0.01));
    });

    test('fat never falls below the 0.5 g/kg essential floor', () {
      final DailyTargets low = TargetCalculator.build(
        baseProfile().copyWith(fatPercentOfEnergy: 0.05),
        date: DateTime(2026, 1, 1),
      );
      expect(low.amountFor(Nutrient.fat), closeTo(40.0, 0.01));
    });

    test('carbs floor at zero rather than going negative', () {
      final DailyTargets extreme = TargetCalculator.build(
        baseProfile().copyWith(
          energyOverrideKcal: 600,
          proteinGPerKg: 2.0,
          fatPercentOfEnergy: 0.6,
        ),
        date: DateTime(2026, 1, 1),
      );
      expect(extreme.amountFor(Nutrient.carbs), greaterThanOrEqualTo(0.0));
    });
  });

  group('limits', () {
    test('saturated fat is 10% of energy', () {
      final DailyTargets t = TargetCalculator.build(
        baseProfile().copyWith(energyOverrideKcal: 2000),
        date: DateTime(2026, 1, 1),
      );
      // 2000 * 0.10 / 9 = 22.2 g
      expect(t.amountFor(Nutrient.satFat), closeTo(22.22, 0.01));
      expect(t[Nutrient.satFat]!.kind, TargetKind.limit);
    });

    test('a limit reports as exceeded only when over', () {
      final DailyTargets t = TargetCalculator.build(
        baseProfile().copyWith(energyOverrideKcal: 2000),
        date: DateTime(2026, 1, 1),
      );
      expect(t[Nutrient.sodium]!.isExceededBy(1999), isFalse);
      expect(t[Nutrient.sodium]!.isExceededBy(2001), isTrue);
    });

    test('a goal is never reported as exceeded', () {
      final DailyTargets t =
          TargetCalculator.build(baseProfile(), date: DateTime(2026, 1, 1));
      expect(t[Nutrient.protein]!.isExceededBy(999), isFalse);
    });

    test('remaining never goes negative', () {
      final DailyTargets t =
          TargetCalculator.build(baseProfile(), date: DateTime(2026, 1, 1));
      expect(t[Nutrient.protein]!.remainingFrom(9999), 0.0);
    });
  });

  group('overrides', () {
    test('a custom target replaces the calculated one and keeps its kind', () {
      final DailyTargets t = TargetCalculator.build(
        baseProfile()
            .copyWith(customTargets: <Nutrient, double>{Nutrient.sodium: 1500}),
        date: DateTime(2026, 1, 1),
      );
      expect(t.amountFor(Nutrient.sodium), 1500.0);
      expect(t[Nutrient.sodium]!.kind, TargetKind.limit);
      expect(t[Nutrient.sodium]!.isOverride, isTrue);
    });
  });

  group('water', () {
    test('baseline is body weight times ml/kg', () {
      final WaterTarget w = TargetCalculator.water(baseProfile());
      expect(w.baselineMl, closeTo(2800.0, 0.01)); // 80 * 35
      expect(w.drinkingTargetMl, closeTo(2800.0, 0.01));
    });

    test('exercise and climate are added on top', () {
      final WaterTarget w = TargetCalculator.water(baseProfile().copyWith(
        dailyExerciseMinutes: 60,
        climate: Climate.hot,
      ));
      // 2800 + 60*12 + 1000 = 4520
      expect(w.totalWaterMl, closeTo(4520.0, 0.01));
    });

    test('food water is ignored unless you opt in', () {
      final WaterTarget off =
          TargetCalculator.water(baseProfile(), foodWaterMl: 900);
      expect(off.foodWaterCreditMl, 0.0);
      expect(off.drinkingTargetMl, closeTo(2800.0, 0.01));

      final WaterTarget on = TargetCalculator.water(
        baseProfile().copyWith(countFoodWaterTowardsTarget: true),
        foodWaterMl: 900,
      );
      expect(on.drinkingTargetMl, closeTo(1900.0, 0.01));
    });

    test('a huge food-water credit cannot push the goal below 1 litre', () {
      final WaterTarget w = TargetCalculator.water(
        baseProfile().copyWith(countFoodWaterTowardsTarget: true),
        foodWaterMl: 9000,
      );
      expect(w.drinkingTargetMl, 1000.0);
    });
  });

  test('every target carries a rationale', () {
    final DailyTargets t =
        TargetCalculator.build(baseProfile(), date: DateTime(2026, 1, 1));
    for (final NutrientTarget target in t.nutrients.values) {
      expect(target.rationale, isNotEmpty,
          reason: '${target.nutrient.key} has no explanation');
    }
  });
}
