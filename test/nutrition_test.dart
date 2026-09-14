import 'package:flutter_test/flutter_test.dart';
import 'package:hydrafuel/domain/nutrients.dart';
import 'package:hydrafuel/domain/nutrition.dart';

void main() {
  group('NutritionFacts scaling', () {
    const NutritionFacts chicken = NutritionFacts(<Nutrient, double>{
      Nutrient.energy: 120,
      Nutrient.protein: 22.5,
      Nutrient.fat: 2.62,
    });

    test('scales per-100g values by exact weight', () {
      final NutritionFacts f = chicken.scaledToGrams(150);
      expect(f[Nutrient.protein], closeTo(33.75, 1e-9));
      expect(f[Nutrient.energy], closeTo(180.0, 1e-9));
      expect(f[Nutrient.fat], closeTo(3.93, 1e-9));
    });

    test('scaling by a fractional weight keeps full precision', () {
      final NutritionFacts f = chicken.scaledToGrams(37.5);
      expect(f[Nutrient.protein], closeTo(8.4375, 1e-12));
    });

    test('zero grams yields zero, not a missing key', () {
      final NutritionFacts f = chicken.scaledToGrams(0);
      expect(f.has(Nutrient.protein), isTrue);
      expect(f[Nutrient.protein], 0.0);
    });
  });

  group('unknown vs zero', () {
    test('missing nutrient reads as 0 but reports as unknown', () {
      const NutritionFacts f =
          NutritionFacts(<Nutrient, double>{Nutrient.protein: 10});
      expect(f[Nutrient.iron], 0.0);
      expect(f.has(Nutrient.iron), isFalse);
      expect(f.lookup(Nutrient.iron), isNull);
    });
  });

  group('summation', () {
    test('sums are exact and take the union of keys', () {
      const NutritionFacts a = NutritionFacts(<Nutrient, double>{
        Nutrient.protein: 10.1,
        Nutrient.iron: 2.0,
      });
      const NutritionFacts b = NutritionFacts(<Nutrient, double>{
        Nutrient.protein: 5.4,
        Nutrient.calcium: 100.0,
      });

      final NutritionFacts total = a + b;
      expect(total[Nutrient.protein], closeTo(15.5, 1e-9));
      expect(total[Nutrient.iron], 2.0);
      expect(total[Nutrient.calcium], 100.0);
    });

    test('summing many small entries does not drift', () {
      final List<NutritionFacts> parts = List<NutritionFacts>.generate(
        100,
        (_) => const NutritionFacts(<Nutrient, double>{Nutrient.protein: 0.1}),
      );
      expect(NutritionFacts.sum(parts)[Nutrient.protein], closeTo(10.0, 1e-9));
    });

    test('empty sum is empty', () {
      expect(NutritionFacts.sum(<NutritionFacts>[]).isEmpty, isTrue);
    });
  });

  group('Atwater cross-check', () {
    test('charges fibre at 2 kcal/g and never double-counts it', () {
      // 10 g protein, 30 g carb of which 10 g fibre, 5 g fat.
      // 40 + (20 * 4) + (10 * 2) + 45 = 185 kcal
      const NutritionFacts f = NutritionFacts(<Nutrient, double>{
        Nutrient.protein: 10,
        Nutrient.carbs: 30,
        Nutrient.fiber: 10,
        Nutrient.fat: 5,
      });
      expect(f.atwaterEnergyKcal, closeTo(185.0, 1e-9));
    });

    test('counts alcohol at 7 kcal/g', () {
      const NutritionFacts f =
          NutritionFacts(<Nutrient, double>{Nutrient.alcohol: 10});
      expect(f.atwaterEnergyKcal, closeTo(70.0, 1e-9));
    });

    test('fibre larger than carbs does not produce negative energy', () {
      const NutritionFacts f = NutritionFacts(<Nutrient, double>{
        Nutrient.carbs: 2,
        Nutrient.fiber: 10,
      });
      expect(f.atwaterEnergyKcal, closeTo(20.0, 1e-9));
    });

    test('discrepancy ratio is signed and relative to the stated value', () {
      const NutritionFacts f = NutritionFacts(<Nutrient, double>{
        Nutrient.energy: 200,
        Nutrient.protein: 10,
        Nutrient.carbs: 10,
        Nutrient.fat: 10,
      });
      // Macros imply 40 + 40 + 90 = 170. (200 - 170) / 200 = 0.15
      expect(f.energyDiscrepancyRatio, closeTo(0.15, 1e-9));
    });

    test('discrepancy is null when there is nothing to compare', () {
      expect(NutritionFacts.empty.energyDiscrepancyRatio, isNull);
      expect(
        const NutritionFacts(<Nutrient, double>{Nutrient.energy: 100})
            .energyDiscrepancyRatio,
        isNull,
      );
    });
  });

  group('serialisation', () {
    test('round-trips through JSON without losing precision', () {
      const NutritionFacts f = NutritionFacts(<Nutrient, double>{
        Nutrient.protein: 22.53333,
        Nutrient.vitaminB12: 0.0001,
      });
      final NutritionFacts back = NutritionFacts.decode(f.encode());
      expect(back[Nutrient.protein], f[Nutrient.protein]);
      expect(back[Nutrient.vitaminB12], f[Nutrient.vitaminB12]);
    });

    test('ignores unknown keys from a future version', () {
      final NutritionFacts f = NutritionFacts.fromJson(
        <String, dynamic>{'protein': 5, 'unobtainium': 99},
      );
      expect(f[Nutrient.protein], 5.0);
      expect(f.values.length, 1);
    });

    test('decoding junk yields empty rather than throwing', () {
      expect(NutritionFacts.decode('').isEmpty, isTrue);
    });
  });

  test('every nutrient key is unique and resolvable', () {
    final Set<String> keys = <String>{};
    for (final Nutrient n in Nutrient.values) {
      expect(keys.add(n.key), isTrue, reason: 'duplicate key ${n.key}');
      expect(Nutrient.fromKey(n.key), n);
    }
  });
}
