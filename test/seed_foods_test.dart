import 'package:flutter_test/flutter_test.dart';
import 'package:hydrafuel/data/seed_foods.dart';
import 'package:hydrafuel/domain/food_item.dart';
import 'package:hydrafuel/domain/nutrients.dart';
import 'package:hydrafuel/domain/nutrition.dart';

void main() {
  final List<FoodItem> foods = SeedFoods.build();

  test('the starter library is not empty', () {
    expect(foods.length, greaterThan(15));
  });

  test('every seeded food passes its own validation', () {
    for (final FoodItem f in foods) {
      expect(f.validate(), isEmpty,
          reason: '${f.name}: ${f.validate().join(' ')}');
    }
  });

  test('every seeded food has a name and an energy value', () {
    for (final FoodItem f in foods) {
      expect(f.name.trim(), isNotEmpty);
      expect(f.per100g.has(Nutrient.energy), isTrue, reason: f.name);
    }
  });

  test('every seeded food with calories states its macros', () {
    // Salt is the deliberate exception: it carries sodium and nothing else.
    for (final FoodItem f
        in foods.where((FoodItem f) => f.per100g[Nutrient.energy] > 0)) {
      expect(f.per100g.has(Nutrient.protein), isTrue, reason: f.name);
      expect(f.per100g.has(Nutrient.carbs), isTrue, reason: f.name);
      expect(f.per100g.has(Nutrient.fat), isTrue, reason: f.name);
    }
  });

  test('names are unique', () {
    final Set<String> seen = <String>{};
    for (final FoodItem f in foods) {
      expect(seen.add(f.displayName), isTrue, reason: 'duplicate ${f.name}');
    }
  });

  test('liquids carry a density so millilitres can be converted', () {
    for (final FoodItem f in foods.where((FoodItem f) => f.isLiquid)) {
      expect(f.densityGPerMl, isNotNull, reason: f.name);
      expect(f.densityGPerMl, greaterThan(0.5), reason: f.name);
      expect(f.densityGPerMl, lessThan(1.5), reason: f.name);
    }
  });

  test('named servings carry a weight', () {
    for (final FoodItem f in foods.where((FoodItem f) => f.servingName.isNotEmpty)) {
      expect(f.servingGrams, isNotNull, reason: f.name);
      expect(f.servingGrams, greaterThan(0), reason: f.name);
    }
  });

  test('no nutrient value is negative', () {
    for (final FoodItem f in foods) {
      f.per100g.values.forEach((Nutrient n, double v) {
        expect(v, greaterThanOrEqualTo(0.0), reason: '${f.name} ${n.key}');
      });
    }
  });

  group('portion maths', () {
    test('a named serving scales from its gram weight', () {
      final FoodItem egg =
          foods.firstWhere((FoodItem f) => f.name.startsWith('Egg'));
      // 50 g egg at 12.56 g protein per 100 g = 6.28 g
      expect(egg.forServings(1)![Nutrient.protein], closeTo(6.28, 1e-9));
      expect(egg.forServings(2)![Nutrient.protein], closeTo(12.56, 1e-9));
    });

    test('millilitres convert through density', () {
      final FoodItem milk =
          foods.firstWhere((FoodItem f) => f.name.startsWith('Milk'));
      // 200 ml at 1.03 g/ml = 206 g
      expect(milk.millilitresToGrams(200), closeTo(206.0, 1e-9));
    });

    test('a food without density refuses to guess a volume', () {
      final FoodItem rice =
          foods.firstWhere((FoodItem f) => f.name.startsWith('Rice'));
      expect(rice.millilitresToGrams(200), isNull);
    });

    test('a food without a serving weight returns null servings', () {
      final FoodItem spinach =
          foods.firstWhere((FoodItem f) => f.name.startsWith('Spinach'));
      expect(spinach.forServings(1), isNull);
    });
  });

  group('validation catches bad data', () {
    FoodItem bad(Map<Nutrient, double> v) =>
        FoodItem(name: 'test', per100g: NutritionFacts(v));

    test('impossible macro mass', () {
      final List<String> problems = bad(<Nutrient, double>{
        Nutrient.protein: 50,
        Nutrient.carbs: 50,
        Nutrient.fat: 50,
      }).validate();
      expect(problems.any((String p) => p.contains('impossible')), isTrue);
    });

    test('fat breakdown exceeding total fat', () {
      final List<String> problems = bad(<Nutrient, double>{
        Nutrient.fat: 10,
        Nutrient.satFat: 12,
      }).validate();
      expect(problems.any((String p) => p.contains('exceed total fat')), isTrue);
    });

    test('sugars plus fibre exceeding carbs', () {
      final List<String> problems = bad(<Nutrient, double>{
        Nutrient.carbs: 10,
        Nutrient.sugar: 8,
        Nutrient.fiber: 5,
      }).validate();
      expect(problems.any((String p) => p.contains('exceed total carbohydrate')),
          isTrue);
    });

    test('a mistyped energy value is caught', () {
      final List<String> problems = bad(<Nutrient, double>{
        Nutrient.energy: 1200, // typo: should be 120
        Nutrient.protein: 22.5,
        Nutrient.fat: 2.6,
      }).validate();
      expect(problems.any((String p) => p.contains('Stated energy')), isTrue);
    });

    test('very low calorie foods are not flagged for rounding noise', () {
      // Black coffee: 1 kcal stated, ~0.5 kcal from macros. A 100% relative
      // difference, but meaningless in absolute terms.
      final List<String> problems = bad(<Nutrient, double>{
        Nutrient.energy: 1,
        Nutrient.protein: 0.12,
        Nutrient.fat: 0.02,
      }).validate();
      expect(problems, isEmpty);
    });
  });
}
