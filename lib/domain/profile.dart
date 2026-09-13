import 'nutrients.dart';

enum Sex {
  male('Male'),
  female('Female');

  const Sex(this.label);
  final String label;
}

/// Physical activity level multipliers applied to BMR to reach TDEE.
///
/// These are the standard Harris-Benedict/WHO activity factors. They describe
/// *everything* you do in a day including workouts, so do not also log exercise
/// calories on top unless you drop to a lower band.
enum ActivityLevel {
  sedentary('Sedentary', 'Desk job, little or no exercise', 1.200),
  light('Lightly active', 'Light exercise 1-3 days/week', 1.375),
  moderate('Moderately active', 'Moderate exercise 3-5 days/week', 1.550),
  high('Very active', 'Hard exercise 6-7 days/week', 1.725),
  athlete('Extremely active', 'Physical job or twice-daily training', 1.900);

  const ActivityLevel(this.label, this.description, this.multiplier);
  final String label;
  final String description;
  final double multiplier;
}

enum WeightGoal {
  lose('Lose fat'),
  maintain('Maintain'),
  gain('Gain weight');

  const WeightGoal(this.label);
  final String label;
}

enum BmrFormula {
  mifflinStJeor('Mifflin-St Jeor',
      'Most accurate for the general population. Needs height, weight, age, sex.'),
  katchMcArdle('Katch-McArdle',
      'More accurate if you know your body-fat %. Based on lean mass only.'),
  harrisBenedict(
      'Harris-Benedict (revised)', 'Older formula, kept for comparison.');

  const BmrFormula(this.label, this.description);
  final String label;
  final String description;
}

enum ProteinBasis {
  bodyWeight('Total body weight'),
  leanMass('Lean body mass');

  const ProteinBasis(this.label);
  final String label;
}

/// Extra fluid needed for heat and humidity, in millilitres per day.
enum Climate {
  temperate('Temperate', 0),
  warm('Warm', 500),
  hot('Hot / humid', 1000);

  const Climate(this.label, this.extraWaterMl);
  final String label;
  final int extraWaterMl;
}

/// Everything the target calculations need, plus reminder preferences.
///
/// Times of day are stored as minutes since midnight so this file stays pure
/// Dart and remains unit-testable without a Flutter binding.
class UserProfile {
  const UserProfile({
    this.name = '',
    this.sex = Sex.male,
    this.birthDate,
    this.heightCm = 175.0,
    this.weightKg = 70.0,
    this.bodyFatPercent,
    this.activityLevel = ActivityLevel.light,
    this.goal = WeightGoal.maintain,
    this.rateKgPerWeek = 0.0,
    this.bmrFormula = BmrFormula.mifflinStJeor,
    this.proteinGPerKg = 1.6,
    this.proteinBasis = ProteinBasis.bodyWeight,
    this.fatPercentOfEnergy = 0.28,
    this.waterMlPerKg = 35.0,
    this.climate = Climate.temperate,
    this.dailyExerciseMinutes = 0,
    this.waterMlPerExerciseMinute = 12.0,
    this.countFoodWaterTowardsTarget = false,
    this.wakeMinuteOfDay = 7 * 60,
    this.sleepMinuteOfDay = 23 * 60,
    this.remindersEnabled = true,
    this.reminderIntervalMinutes = 90,
    this.energyOverrideKcal,
    this.customTargets = const <Nutrient, double>{},
  });

  final String name;
  final Sex sex;
  final DateTime? birthDate;
  final double heightCm;
  final double weightKg;

  /// Optional. Unlocks the Katch-McArdle BMR formula and lean-mass protein.
  final double? bodyFatPercent;

  final ActivityLevel activityLevel;
  final WeightGoal goal;

  /// Intended rate of weight change. Always stored positive; [goal] gives the
  /// direction. 0.5 kg/week is the usual safe ceiling for fat loss.
  final double rateKgPerWeek;

  final BmrFormula bmrFormula;
  final double proteinGPerKg;
  final ProteinBasis proteinBasis;

  /// Fraction of total energy from fat, e.g. 0.28 for 28%.
  final double fatPercentOfEnergy;

  final double waterMlPerKg;
  final Climate climate;
  final int dailyExerciseMinutes;
  final double waterMlPerExerciseMinute;

  /// When true the water you get from food counts towards the daily goal, so
  /// the amount you must *drink* drops accordingly.
  final bool countFoodWaterTowardsTarget;

  final int wakeMinuteOfDay;
  final int sleepMinuteOfDay;
  final bool remindersEnabled;
  final int reminderIntervalMinutes;

  /// Overrides the calculated calorie budget when set.
  final double? energyOverrideKcal;

  /// Hard overrides for any nutrient, e.g. a sodium ceiling from a doctor.
  /// These always win over the calculated value.
  final Map<Nutrient, double> customTargets;

  int get ageYears {
    final DateTime? dob = birthDate;
    if (dob == null) return 30;
    final DateTime now = DateTime.now();
    int age = now.year - dob.year;
    final bool beforeBirthday =
        now.month < dob.month || (now.month == dob.month && now.day < dob.day);
    if (beforeBirthday) age -= 1;
    return age.clamp(1, 120);
  }

  double? get leanBodyMassKg {
    final double? bf = bodyFatPercent;
    if (bf == null || bf <= 0 || bf >= 70) return null;
    return weightKg * (1.0 - bf / 100.0);
  }

  /// Number of waking minutes, handling a sleep time past midnight.
  int get wakingMinutes {
    final int span = sleepMinuteOfDay - wakeMinuteOfDay;
    return span > 0 ? span : span + 24 * 60;
  }

  UserProfile copyWith({
    String? name,
    Sex? sex,
    DateTime? birthDate,
    bool clearBirthDate = false,
    double? heightCm,
    double? weightKg,
    double? bodyFatPercent,
    bool clearBodyFat = false,
    ActivityLevel? activityLevel,
    WeightGoal? goal,
    double? rateKgPerWeek,
    BmrFormula? bmrFormula,
    double? proteinGPerKg,
    ProteinBasis? proteinBasis,
    double? fatPercentOfEnergy,
    double? waterMlPerKg,
    Climate? climate,
    int? dailyExerciseMinutes,
    double? waterMlPerExerciseMinute,
    bool? countFoodWaterTowardsTarget,
    int? wakeMinuteOfDay,
    int? sleepMinuteOfDay,
    bool? remindersEnabled,
    int? reminderIntervalMinutes,
    double? energyOverrideKcal,
    bool clearEnergyOverride = false,
    Map<Nutrient, double>? customTargets,
  }) {
    return UserProfile(
      name: name ?? this.name,
      sex: sex ?? this.sex,
      birthDate: clearBirthDate ? null : (birthDate ?? this.birthDate),
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      bodyFatPercent:
          clearBodyFat ? null : (bodyFatPercent ?? this.bodyFatPercent),
      activityLevel: activityLevel ?? this.activityLevel,
      goal: goal ?? this.goal,
      rateKgPerWeek: rateKgPerWeek ?? this.rateKgPerWeek,
      bmrFormula: bmrFormula ?? this.bmrFormula,
      proteinGPerKg: proteinGPerKg ?? this.proteinGPerKg,
      proteinBasis: proteinBasis ?? this.proteinBasis,
      fatPercentOfEnergy: fatPercentOfEnergy ?? this.fatPercentOfEnergy,
      waterMlPerKg: waterMlPerKg ?? this.waterMlPerKg,
      climate: climate ?? this.climate,
      dailyExerciseMinutes: dailyExerciseMinutes ?? this.dailyExerciseMinutes,
      waterMlPerExerciseMinute:
          waterMlPerExerciseMinute ?? this.waterMlPerExerciseMinute,
      countFoodWaterTowardsTarget:
          countFoodWaterTowardsTarget ?? this.countFoodWaterTowardsTarget,
      wakeMinuteOfDay: wakeMinuteOfDay ?? this.wakeMinuteOfDay,
      sleepMinuteOfDay: sleepMinuteOfDay ?? this.sleepMinuteOfDay,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      reminderIntervalMinutes:
          reminderIntervalMinutes ?? this.reminderIntervalMinutes,
      energyOverrideKcal: clearEnergyOverride
          ? null
          : (energyOverrideKcal ?? this.energyOverrideKcal),
      customTargets: customTargets ?? this.customTargets,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'sex': sex.name,
        'birthDate': birthDate?.toIso8601String(),
        'heightCm': heightCm,
        'weightKg': weightKg,
        'bodyFatPercent': bodyFatPercent,
        'activityLevel': activityLevel.name,
        'goal': goal.name,
        'rateKgPerWeek': rateKgPerWeek,
        'bmrFormula': bmrFormula.name,
        'proteinGPerKg': proteinGPerKg,
        'proteinBasis': proteinBasis.name,
        'fatPercentOfEnergy': fatPercentOfEnergy,
        'waterMlPerKg': waterMlPerKg,
        'climate': climate.name,
        'dailyExerciseMinutes': dailyExerciseMinutes,
        'waterMlPerExerciseMinute': waterMlPerExerciseMinute,
        'countFoodWaterTowardsTarget': countFoodWaterTowardsTarget,
        'wakeMinuteOfDay': wakeMinuteOfDay,
        'sleepMinuteOfDay': sleepMinuteOfDay,
        'remindersEnabled': remindersEnabled,
        'reminderIntervalMinutes': reminderIntervalMinutes,
        'energyOverrideKcal': energyOverrideKcal,
        'customTargets': <String, double>{
          for (final MapEntry<Nutrient, double> e in customTargets.entries)
            e.key.key: e.value,
        },
      };

  static UserProfile fromJson(Map<String, dynamic> json) {
    T pick<T extends Enum>(List<T> values, Object? raw, T fallback) {
      if (raw is String) {
        for (final T v in values) {
          if (v.name == raw) return v;
        }
      }
      return fallback;
    }

    double? optDouble(Object? v) => v is num ? v.toDouble() : null;

    final Map<Nutrient, double> custom = <Nutrient, double>{};
    final Object? rawCustom = json['customTargets'];
    if (rawCustom is Map) {
      rawCustom.forEach((Object? k, Object? v) {
        final Nutrient? n = k is String ? Nutrient.fromKey(k) : null;
        if (n != null && v is num) custom[n] = v.toDouble();
      });
    }

    final Object? rawDob = json['birthDate'];

    return UserProfile(
      name: json['name'] as String? ?? '',
      sex: pick(Sex.values, json['sex'], Sex.male),
      birthDate: rawDob is String ? DateTime.tryParse(rawDob) : null,
      heightCm: optDouble(json['heightCm']) ?? 175.0,
      weightKg: optDouble(json['weightKg']) ?? 70.0,
      bodyFatPercent: optDouble(json['bodyFatPercent']),
      activityLevel: pick(
          ActivityLevel.values, json['activityLevel'], ActivityLevel.light),
      goal: pick(WeightGoal.values, json['goal'], WeightGoal.maintain),
      rateKgPerWeek: optDouble(json['rateKgPerWeek']) ?? 0.0,
      bmrFormula:
          pick(BmrFormula.values, json['bmrFormula'], BmrFormula.mifflinStJeor),
      proteinGPerKg: optDouble(json['proteinGPerKg']) ?? 1.6,
      proteinBasis: pick(
          ProteinBasis.values, json['proteinBasis'], ProteinBasis.bodyWeight),
      fatPercentOfEnergy: optDouble(json['fatPercentOfEnergy']) ?? 0.28,
      waterMlPerKg: optDouble(json['waterMlPerKg']) ?? 35.0,
      climate: pick(Climate.values, json['climate'], Climate.temperate),
      dailyExerciseMinutes:
          (json['dailyExerciseMinutes'] as num?)?.toInt() ?? 0,
      waterMlPerExerciseMinute:
          optDouble(json['waterMlPerExerciseMinute']) ?? 12.0,
      countFoodWaterTowardsTarget:
          json['countFoodWaterTowardsTarget'] as bool? ?? false,
      wakeMinuteOfDay: (json['wakeMinuteOfDay'] as num?)?.toInt() ?? 7 * 60,
      sleepMinuteOfDay: (json['sleepMinuteOfDay'] as num?)?.toInt() ?? 23 * 60,
      remindersEnabled: json['remindersEnabled'] as bool? ?? true,
      reminderIntervalMinutes:
          (json['reminderIntervalMinutes'] as num?)?.toInt() ?? 90,
      energyOverrideKcal: optDouble(json['energyOverrideKcal']),
      customTargets: custom,
    );
  }
}
