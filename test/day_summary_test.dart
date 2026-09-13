import 'package:flutter_test/flutter_test.dart';
import 'package:hydrafuel/domain/daily_summary.dart';
import 'package:hydrafuel/domain/log_entry.dart';
import 'package:hydrafuel/domain/nutrients.dart';
import 'package:hydrafuel/domain/nutrition.dart';
import 'package:hydrafuel/domain/profile.dart';
import 'package:hydrafuel/domain/water_entry.dart';

void main() {
  final DateTime today = DateTime(2026, 3, 14);

  // 80 kg, awake 07:00-23:00, so a 2800 ml goal across 960 minutes.
  const UserProfile profile = UserProfile(
    weightKg: 80,
    heightCm: 180,
    wakeMinuteOfDay: 7 * 60,
    sleepMinuteOfDay: 23 * 60,
  );

  LogEntry entry(String name, double grams, Map<Nutrient, double> per100g,
          {MealType meal = MealType.lunch}) =>
      LogEntry(
        foodName: name,
        grams: grams,
        per100gSnapshot: NutritionFacts(per100g),
        meal: meal,
        loggedAt: today.add(const Duration(hours: 13)),
      );

  WaterEntry water(double ml, int hour) => WaterEntry(
        volumeMl: ml,
        loggedAt: today.add(Duration(hours: hour)),
      );

  DaySummary summary({
    List<LogEntry> entries = const <LogEntry>[],
    List<WaterEntry> waters = const <WaterEntry>[],
  }) =>
      DaySummary(
        date: today,
        profile: profile,
        entries: entries,
        waterEntries: waters,
      );

  group('totals', () {
    test('an empty day totals to nothing', () {
      final DaySummary s = summary();
      expect(s.totals.isEmpty, isTrue);
      expect(s.waterDrunkMl, 0.0);
    });

    test('entries sum exactly across foods', () {
      final DaySummary s = summary(entries: <LogEntry>[
        // 150 g chicken: 33.75 g protein
        entry('Chicken', 150, <Nutrient, double>{Nutrient.protein: 22.5}),
        // 200 g rice: 14.26 g protein
        entry('Rice', 200, <Nutrient, double>{Nutrient.protein: 7.13}),
      ]);
      expect(s.consumed(Nutrient.protein), closeTo(48.01, 1e-9));
    });

    test('remaining is target minus consumed, floored at zero', () {
      final DaySummary s = summary(entries: <LogEntry>[
        entry('Protein', 100, <Nutrient, double>{Nutrient.protein: 1000}),
      ]);
      expect(s.remaining(Nutrient.protein), 0.0);
    });

    test('meal totals partition the day', () {
      final DaySummary s = summary(entries: <LogEntry>[
        entry('A', 100, <Nutrient, double>{Nutrient.protein: 10},
            meal: MealType.breakfast),
        entry('B', 100, <Nutrient, double>{Nutrient.protein: 20},
            meal: MealType.dinner),
      ]);
      expect(s.totalsFor(MealType.breakfast)[Nutrient.protein], 10.0);
      expect(s.totalsFor(MealType.dinner)[Nutrient.protein], 20.0);
      expect(s.totalsFor(MealType.lunch)[Nutrient.protein], 0.0);
      expect(s.consumed(Nutrient.protein), 30.0);
    });
  });

  group('water', () {
    test('adds up drinks and reports what is left', () {
      final DaySummary s =
          summary(waters: <WaterEntry>[water(500, 8), water(750, 11)]);
      expect(s.waterDrunkMl, 1250.0);
      expect(s.waterTargetMl, closeTo(2800.0, 0.01));
      expect(s.waterRemainingMl, closeTo(1550.0, 0.01));
      expect(s.waterGoalMet, isFalse);
    });

    test('goal met is inclusive and remaining stops at zero', () {
      final DaySummary s = summary(waters: <WaterEntry>[water(2800, 9)]);
      expect(s.waterGoalMet, isTrue);
      expect(s.waterRemainingMl, 0.0);

      final DaySummary over = summary(waters: <WaterEntry>[water(4000, 9)]);
      expect(over.waterRemainingMl, 0.0);
      expect(over.waterProgress, greaterThan(1.0));
    });

    test('fractional volumes are kept exactly', () {
      final DaySummary s = summary(
        waters: <WaterEntry>[water(333.33, 8), water(333.33, 9), water(333.34, 10)],
      );
      expect(s.waterDrunkMl, closeTo(1000.0, 1e-9));
    });
  });

  group('pacing', () {
    test('expected intake is zero at wake-up and full at bedtime', () {
      final DaySummary s = summary();
      expect(s.expectedWaterByMl(today.add(const Duration(hours: 7))), 0.0);
      expect(s.expectedWaterByMl(today.add(const Duration(hours: 23))),
          closeTo(2800.0, 0.01));
    });

    test('expected intake is linear across the waking window', () {
      final DaySummary s = summary();
      // 15:00 is 480 of 960 waking minutes: exactly half.
      expect(s.expectedWaterByMl(today.add(const Duration(hours: 15))),
          closeTo(1400.0, 0.01));
    });

    test('pace is negative when behind and positive when ahead', () {
      final DateTime threePm = today.add(const Duration(hours: 15));

      final DaySummary behind = summary(waters: <WaterEntry>[water(1000, 9)]);
      expect(behind.waterPaceMl(threePm), closeTo(-400.0, 0.01));

      final DaySummary ahead = summary(waters: <WaterEntry>[water(2000, 9)]);
      expect(ahead.waterPaceMl(threePm), closeTo(600.0, 0.01));
    });

    test('before waking, nothing is expected yet', () {
      final DaySummary s = summary();
      // 03:00 is before the 07:00 wake time.
      expect(s.expectedWaterByMl(today.add(const Duration(hours: 3))),
          closeTo(2800.0, 0.01),
          reason: 'past bedtime of the previous window, so the day is done');
    });

    test('per-remaining-hour rate closes out the day', () {
      final DaySummary s = summary(waters: <WaterEntry>[water(1000, 9)]);
      // At 15:00 there are 8 waking hours left and 1800 ml to go.
      expect(s.waterPerRemainingHour(today.add(const Duration(hours: 15))),
          closeTo(225.0, 0.01));
    });

    test('no rate is suggested once the goal is met', () {
      final DaySummary s = summary(waters: <WaterEntry>[water(3000, 9)]);
      expect(s.waterPerRemainingHour(today.add(const Duration(hours: 15))),
          isNull);
    });

    test('no rate is suggested after bedtime', () {
      final DaySummary s = summary(waters: <WaterEntry>[water(500, 9)]);
      expect(s.waterPerRemainingHour(today.add(const Duration(hours: 23, minutes: 30))),
          isNull);
    });
  });

  group('warnings', () {
    test('exceeded limits are reported', () {
      final DaySummary s = summary(entries: <LogEntry>[
        // 10 g of salt: 3875 mg sodium, well past the 2000 mg ceiling.
        entry('Salt', 10, <Nutrient, double>{Nutrient.sodium: 38758}),
      ]);
      expect(s.exceededLimits, contains(Nutrient.sodium));
    });

    test('a limit that is respected is not reported', () {
      final DaySummary s = summary(entries: <LogEntry>[
        entry('Salt', 1, <Nutrient, double>{Nutrient.sodium: 38758}),
      ]);
      expect(s.exceededLimits, isNot(contains(Nutrient.sodium)));
    });

    test('shortfalls are ordered worst first', () {
      final DaySummary s = summary(entries: <LogEntry>[
        entry('Protein', 100, <Nutrient, double>{Nutrient.protein: 100}),
      ]);
      final List<Nutrient> short = s.shortfalls();
      expect(short, contains(Nutrient.iron));
      for (int i = 1; i < short.length; i++) {
        expect(s.progress(short[i]),
            greaterThanOrEqualTo(s.progress(short[i - 1])));
      }
    });
  });

  test('food water credit only applies when opted in', () {
    final List<LogEntry> entries = <LogEntry>[
      // 1000 g of a food that is 90% water = 900 ml.
      entry('Soup', 1000, <Nutrient, double>{Nutrient.water: 90}),
    ];

    final DaySummary off = summary(entries: entries);
    expect(off.waterFromFoodMl, closeTo(900.0, 1e-9));
    expect(off.waterTargetMl, closeTo(2800.0, 0.01));

    final DaySummary on = DaySummary(
      date: today,
      profile: profile.copyWith(countFoodWaterTowardsTarget: true),
      entries: entries,
      waterEntries: const <WaterEntry>[],
    );
    expect(on.waterTargetMl, closeTo(1900.0, 0.01));
  });
}
