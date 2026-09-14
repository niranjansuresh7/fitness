import 'package:flutter_test/flutter_test.dart';
import 'package:hydrafuel/domain/blood_marker.dart';
import 'package:hydrafuel/domain/clinical_flags.dart';
import 'package:hydrafuel/domain/nutrients.dart';
import 'package:hydrafuel/domain/profile.dart';
import 'package:hydrafuel/domain/targets.dart';

/// Build a snapshot from marker values taken on one date.
MarkerSnapshot panel(Map<BloodMarker, double> values, {DateTime? takenOn}) {
  final DateTime date = takenOn ?? DateTime(2026, 9, 13);
  return MarkerSnapshot.fromHistory(<BloodResult>[
    for (final MapEntry<BloodMarker, double> e in values.entries)
      BloodResult(marker: e.key, value: e.value, takenOn: date),
  ]);
}

UserProfile profile() => UserProfile(
      sex: Sex.male,
      birthDate: DateTime(DateTime.now().year - 24, 1, 1),
      heightCm: 175,
      weightKg: 70,
      energyOverrideKcal: 2000,
    );

void main() {
  group('marker status', () {
    test('reads against the reference interval', () {
      expect(BloodMarker.ldl.statusOf(141), MarkerStatus.high);
      expect(BloodMarker.ldl.statusOf(90), MarkerStatus.normal);
      expect(BloodMarker.hdl.statusOf(36), MarkerStatus.low);
      expect(BloodMarker.vitaminD.statusOf(16.5), MarkerStatus.low);
      expect(BloodMarker.hba1c.statusOf(4.7), MarkerStatus.normal);
    });

    test('a marker with only an upper bound is never low', () {
      expect(BloodMarker.alt.statusOf(0), MarkerStatus.normal);
      expect(BloodMarker.alt.statusOf(133), MarkerStatus.high);
    });

    test('every marker key is unique and resolvable', () {
      final Set<String> keys = <String>{};
      for (final BloodMarker m in BloodMarker.values) {
        expect(keys.add(m.key), isTrue, reason: 'duplicate ${m.key}');
        expect(BloodMarker.fromKey(m.key), m);
      }
    });
  });

  group('snapshot', () {
    test('keeps the newest value per marker', () {
      final MarkerSnapshot snap = MarkerSnapshot.fromHistory(<BloodResult>[
        BloodResult(
            marker: BloodMarker.ldl,
            value: 141,
            takenOn: DateTime(2026, 9, 13)),
        BloodResult(
            marker: BloodMarker.ldl,
            value: 98,
            takenOn: DateTime(2026, 12, 20)),
      ]);
      expect(snap[BloodMarker.ldl], 98);
      expect(snap.lastDrawDate, DateTime(2026, 12, 20));
    });

    test('an unrecorded marker reads as null, not zero', () {
      final MarkerSnapshot snap = panel(<BloodMarker, double>{});
      expect(snap[BloodMarker.ldl], isNull);
      expect(snap.has(BloodMarker.ldl), isFalse);
    });

    test('lists what is out of range', () {
      final MarkerSnapshot snap = panel(<BloodMarker, double>{
        BloodMarker.ldl: 141,
        BloodMarker.hba1c: 4.7,
      });
      expect(snap.outOfRange.map((BloodResult r) => r.marker),
          <BloodMarker>[BloodMarker.ldl]);
    });
  });

  group('no results, no changes', () {
    test('an empty panel produces no findings', () {
      expect(
          ClinicalAssessment.fromMarkers(MarkerSnapshot.empty).isEmpty, isTrue);
    });

    test('a normal panel produces no findings', () {
      final ClinicalAssessment a =
          ClinicalAssessment.fromMarkers(panel(<BloodMarker, double>{
        BloodMarker.ldl: 90,
        BloodMarker.hdl: 60,
        BloodMarker.triglycerides: 100,
        BloodMarker.vitaminD: 45,
        BloodMarker.vitaminB12: 600,
        BloodMarker.hba1c: 5.0,
        BloodMarker.ast: 30,
        BloodMarker.alt: 25,
        BloodMarker.egfr: 110,
        BloodMarker.uricAcid: 5.0,
      }));
      expect(a.isEmpty, isTrue);
      expect(a.needsDoctor, isFalse);
    });

    test('targets are untouched when there are no findings', () {
      final DailyTargets plain =
          TargetCalculator.build(profile(), date: DateTime(2026, 9, 13));
      final DailyTargets same = TargetCalculator.build(
        profile(),
        date: DateTime(2026, 9, 13),
        assessment: ClinicalAssessment.none,
      );
      expect(same.amountFor(Nutrient.satFat),
          closeTo(plain.amountFor(Nutrient.satFat), 1e-9));
    });
  });

  group('individual flags', () {
    ClinicalAssessment assess(Map<BloodMarker, double> values) =>
        ClinicalAssessment.fromMarkers(panel(values));

    test('raised LDL', () {
      final ClinicalAssessment a =
          assess(<BloodMarker, double>{BloodMarker.ldl: 141});
      expect(a.has(ClinicalFlag.raisedLdl), isTrue);
      expect(a.findings.single.detail, contains('141'));
    });

    test('raised non-HDL alone also flags it', () {
      expect(
          assess(<BloodMarker, double>{BloodMarker.nonHdl: 155})
              .has(ClinicalFlag.raisedLdl),
          isTrue);
    });

    test('low HDL', () {
      expect(
          assess(<BloodMarker, double>{BloodMarker.hdl: 36})
              .has(ClinicalFlag.lowHdl),
          isTrue);
      expect(
          assess(<BloodMarker, double>{BloodMarker.hdl: 55})
              .has(ClinicalFlag.lowHdl),
          isFalse);
    });

    test('vitamin D splits deficient from insufficient', () {
      expect(
          assess(<BloodMarker, double>{BloodMarker.vitaminD: 16.5})
              .has(ClinicalFlag.vitaminDDeficient),
          isTrue);
      expect(
          assess(<BloodMarker, double>{BloodMarker.vitaminD: 25})
              .has(ClinicalFlag.vitaminDInsufficient),
          isTrue);
      expect(
          assess(<BloodMarker, double>{BloodMarker.vitaminD: 25})
              .has(ClinicalFlag.vitaminDDeficient),
          isFalse);
      expect(assess(<BloodMarker, double>{BloodMarker.vitaminD: 45}).isEmpty,
          isTrue);
    });

    test('B12 inside the lab range but below 400 is a nudge, not a deficiency',
        () {
      final ClinicalAssessment a =
          assess(<BloodMarker, double>{BloodMarker.vitaminB12: 306});
      expect(a.has(ClinicalFlag.b12BelowOptimal), isTrue);
      expect(a.has(ClinicalFlag.b12Deficient), isFalse);
      expect(a.needsDoctor, isFalse);
    });

    test('B12 below the lab range is a medical finding', () {
      final ClinicalAssessment a =
          assess(<BloodMarker, double>{BloodMarker.vitaminB12: 150});
      expect(a.has(ClinicalFlag.b12Deficient), isTrue);
      expect(a.needsDoctor, isTrue);
    });

    test('raised liver enzymes are medical and quote the multiple', () {
      final ClinicalAssessment a = assess(
          <BloodMarker, double>{BloodMarker.ast: 308, BloodMarker.alt: 133});
      expect(a.has(ClinicalFlag.raisedLiverEnzymes), isTrue);
      expect(a.needsDoctor, isTrue);
      expect(a.findings.single.detail, contains('6.3x'));
      expect(a.findings.single.detail, contains('2.7x'));
    });

    test('pre-diabetes and diabetes are separated', () {
      expect(
          assess(<BloodMarker, double>{BloodMarker.hba1c: 5.9})
              .has(ClinicalFlag.prediabetes),
          isTrue);
      expect(
          assess(<BloodMarker, double>{BloodMarker.hba1c: 6.8})
              .has(ClinicalFlag.diabetes),
          isTrue);
      expect(assess(<BloodMarker, double>{BloodMarker.hba1c: 5.0}).isEmpty,
          isTrue);
    });

    test('reduced kidney function', () {
      expect(
          assess(<BloodMarker, double>{BloodMarker.egfr: 70})
              .has(ClinicalFlag.reducedKidneyFunction),
          isTrue);
      expect(
          assess(<BloodMarker, double>{BloodMarker.egfr: 105}).isEmpty, isTrue);
    });

    test('uric acid flags above 7, not merely above the lab floor', () {
      expect(assess(<BloodMarker, double>{BloodMarker.uricAcid: 6.3}).isEmpty,
          isTrue);
      expect(
          assess(<BloodMarker, double>{BloodMarker.uricAcid: 7.6})
              .has(ClinicalFlag.raisedUricAcid),
          isTrue);
    });
  });

  group('target adjustments', () {
    DailyTargets withPanel(Map<BloodMarker, double> values) =>
        TargetCalculator.build(
          profile(),
          date: DateTime(2026, 9, 13),
          assessment: ClinicalAssessment.fromMarkers(panel(values)),
        );

    test('raised LDL tightens saturated fat from 10% to 7% of energy', () {
      final DailyTargets t = withPanel(<BloodMarker, double>{
        BloodMarker.ldl: 141,
      });
      // 2000 kcal * 0.07 / 9 = 15.56 g, down from 22.22 g.
      expect(t.amountFor(Nutrient.satFat), closeTo(15.56, 0.01));
      expect(t[Nutrient.satFat]!.isClinical, isTrue);
      expect(t[Nutrient.satFat]!.rationale, contains('LDL'));
    });

    test('raised LDL tightens cholesterol and raises the fibre floor', () {
      final DailyTargets t =
          withPanel(<BloodMarker, double>{BloodMarker.ldl: 141});
      expect(t.amountFor(Nutrient.cholesterol), 200);
      // 14 g/1000 kcal would be 28 g; the floor lifts it to 30 g.
      expect(t.amountFor(Nutrient.fiber), 30);
    });

    test('the fibre floor never lowers an already higher target', () {
      final DailyTargets t = TargetCalculator.build(
        profile().copyWith(energyOverrideKcal: 3000),
        date: DateTime(2026, 9, 13),
        assessment: ClinicalAssessment.fromMarkers(
            panel(<BloodMarker, double>{BloodMarker.ldl: 141})),
      );
      // 14 g/1000 kcal at 3000 kcal is 42 g, which already clears the floor.
      expect(t.amountFor(Nutrient.fiber), closeTo(42, 0.01));
    });

    test('low HDL halves the added-sugar ceiling and lifts omega-3', () {
      final DailyTargets t =
          withPanel(<BloodMarker, double>{BloodMarker.hdl: 36});
      // 2000 * 0.05 / 4 = 25 g, down from 50 g.
      expect(t.amountFor(Nutrient.addedSugar), closeTo(25, 0.01));
      expect(t.amountFor(Nutrient.omega3), 2.0);
    });

    test('vitamin D deficiency raises the dietary target to 25 mcg', () {
      final DailyTargets t =
          withPanel(<BloodMarker, double>{BloodMarker.vitaminD: 16.5});
      expect(t.amountFor(Nutrient.vitaminD), 25);
      expect(t[Nutrient.vitaminD]!.isClinical, isTrue);
    });

    test('a low-normal B12 raises the target without calling it a deficiency',
        () {
      final DailyTargets t =
          withPanel(<BloodMarker, double>{BloodMarker.vitaminB12: 306});
      expect(t.amountFor(Nutrient.vitaminB12), 4.0);
    });

    test('raised liver enzymes set the alcohol limit to zero', () {
      final DailyTargets t =
          withPanel(<BloodMarker, double>{BloodMarker.ast: 308});
      expect(t.amountFor(Nutrient.alcohol), 0);
      expect(t[Nutrient.alcohol]!.kind, TargetKind.limit);
      expect(t[Nutrient.alcohol]!.isExceededBy(0.1), isTrue);
    });

    test('raised uric acid adds 500 ml to the water target', () {
      final DailyTargets plain = withPanel(<BloodMarker, double>{});
      final DailyTargets t =
          withPanel(<BloodMarker, double>{BloodMarker.uricAcid: 7.6});
      expect(t.water.clinicalMl, 500);
      expect(t.water.drinkingTargetMl,
          closeTo(plain.water.drinkingTargetMl + 500, 0.01));
    });

    test('reduced kidney function only ever lowers protein', () {
      final DailyTargets t = withPanel(<BloodMarker, double>{
        BloodMarker.egfr: 55,
      });
      // Default 1.6 g/kg would be 112 g; the ceiling is 0.8 * 70 = 56 g.
      expect(t.amountFor(Nutrient.protein), closeTo(56, 0.01));
      expect(t[Nutrient.protein]!.kind, TargetKind.limit);
      expect(t.amountFor(Nutrient.sodium), 1500);
    });

    test('a low protein target is not raised by the kidney ceiling', () {
      final DailyTargets t = TargetCalculator.build(
        profile().copyWith(proteinGPerKg: 0.6),
        date: DateTime(2026, 9, 13),
        assessment: ClinicalAssessment.fromMarkers(
            panel(<BloodMarker, double>{BloodMarker.egfr: 55})),
      );
      expect(t.amountFor(Nutrient.protein), closeTo(42, 0.01));
    });

    test('a manual override still beats a clinical adjustment', () {
      final DailyTargets t = TargetCalculator.build(
        profile().copyWith(
          customTargets: <Nutrient, double>{Nutrient.cholesterol: 150},
        ),
        date: DateTime(2026, 9, 13),
        assessment: ClinicalAssessment.fromMarkers(
            panel(<BloodMarker, double>{BloodMarker.ldl: 141})),
      );
      expect(t.amountFor(Nutrient.cholesterol), 150);
      expect(t[Nutrient.cholesterol]!.isOverride, isTrue);
    });

    test('every clinical target still carries a rationale', () {
      final DailyTargets t = withPanel(<BloodMarker, double>{
        BloodMarker.ldl: 141,
        BloodMarker.hdl: 36,
        BloodMarker.vitaminD: 16.5,
      });
      for (final NutrientTarget target in t.nutrients.values) {
        expect(target.rationale.trim(), isNotEmpty,
            reason: '${target.nutrient.key} has no explanation');
      }
    });
  });

  group('the panel this app was built for', () {
    // 24-year-old male, drawn 13 September 2026.
    final MarkerSnapshot niranjan = panel(<BloodMarker, double>{
      BloodMarker.totalCholesterol: 191,
      BloodMarker.triglycerides: 72,
      BloodMarker.hdl: 36,
      BloodMarker.nonHdl: 155,
      BloodMarker.ldl: 141,
      BloodMarker.ast: 308,
      BloodMarker.alt: 133,
      BloodMarker.ggt: 24,
      BloodMarker.alp: 59,
      BloodMarker.bilirubinTotal: 1.06,
      BloodMarker.albumin: 4.09,
      BloodMarker.creatinine: 1.03,
      BloodMarker.egfr: 105,
      BloodMarker.urea: 28,
      BloodMarker.uricAcid: 6.3,
      BloodMarker.sodium: 137,
      BloodMarker.potassium: 4.6,
      BloodMarker.calcium: 8.6,
      BloodMarker.phosphorus: 4.6,
      BloodMarker.hba1c: 4.7,
      BloodMarker.vitaminD: 16.5,
      BloodMarker.vitaminB12: 306,
      BloodMarker.hemoglobin: 15.1,
      BloodMarker.tsh: 2.4754,
    });

    late ClinicalAssessment assessment;

    setUp(() => assessment = ClinicalAssessment.fromMarkers(niranjan));

    test('finds exactly the patterns that are there', () {
      expect(
        assessment.flags,
        <ClinicalFlag>{
          ClinicalFlag.raisedLdl,
          ClinicalFlag.lowHdl,
          ClinicalFlag.vitaminDDeficient,
          ClinicalFlag.b12BelowOptimal,
          ClinicalFlag.raisedLiverEnzymes,
        },
      );
    });

    test('does not invent problems from the normal results', () {
      expect(assessment.has(ClinicalFlag.prediabetes), isFalse);
      expect(assessment.has(ClinicalFlag.reducedKidneyFunction), isFalse);
      expect(assessment.has(ClinicalFlag.raisedUricAcid), isFalse);
      expect(assessment.has(ClinicalFlag.anaemia), isFalse);
      expect(assessment.has(ClinicalFlag.abnormalThyroid), isFalse);
      expect(assessment.has(ClinicalFlag.raisedTriglycerides), isFalse);
    });

    test('separates what food can move from what needs a doctor', () {
      expect(assessment.needsDoctor, isTrue);
      expect(
        assessment.medical.map((ClinicalFinding f) => f.flag),
        containsAll(<ClinicalFlag>[
          ClinicalFlag.raisedLiverEnzymes,
          ClinicalFlag.vitaminDDeficient,
        ]),
      );
      expect(
        assessment.nutritional.map((ClinicalFinding f) => f.flag),
        containsAll(<ClinicalFlag>[
          ClinicalFlag.raisedLdl,
          ClinicalFlag.lowHdl,
          ClinicalFlag.b12BelowOptimal,
        ]),
      );
    });

    test('produces the expected target set', () {
      final DailyTargets t = TargetCalculator.build(
        profile(),
        date: DateTime(2026, 9, 13),
        assessment: assessment,
      );
      expect(t.amountFor(Nutrient.satFat), closeTo(15.56, 0.01));
      expect(t.amountFor(Nutrient.cholesterol), 200);
      expect(t.amountFor(Nutrient.fiber), 30);
      expect(t.amountFor(Nutrient.addedSugar), closeTo(25, 0.01));
      expect(t.amountFor(Nutrient.omega3), 2.0);
      expect(t.amountFor(Nutrient.vitaminD), 25);
      expect(t.amountFor(Nutrient.vitaminB12), 4.0);
      expect(t.amountFor(Nutrient.alcohol), 0);

      // Untouched, because nothing in the panel justifies moving them.
      expect(t.amountFor(Nutrient.sodium), 2000);
      expect(t.amountFor(Nutrient.protein), closeTo(112, 0.01));
      expect(t.water.clinicalMl, 0);
    });

    test('a normal re-test drops the adjustments on its own', () {
      final MarkerSnapshot retest = MarkerSnapshot.fromHistory(<BloodResult>[
        ...niranjan.latest.values,
        BloodResult(
            marker: BloodMarker.ldl, value: 92, takenOn: DateTime(2027, 3, 20)),
        BloodResult(
            marker: BloodMarker.nonHdl,
            value: 120,
            takenOn: DateTime(2027, 3, 20)),
        BloodResult(
            marker: BloodMarker.hdl, value: 56, takenOn: DateTime(2027, 3, 20)),
        BloodResult(
            marker: BloodMarker.vitaminD,
            value: 42,
            takenOn: DateTime(2027, 3, 20)),
        BloodResult(
            marker: BloodMarker.ast, value: 31, takenOn: DateTime(2027, 3, 20)),
        BloodResult(
            marker: BloodMarker.alt, value: 24, takenOn: DateTime(2027, 3, 20)),
        BloodResult(
            marker: BloodMarker.vitaminB12,
            value: 520,
            takenOn: DateTime(2027, 3, 20)),
      ]);

      final ClinicalAssessment after = ClinicalAssessment.fromMarkers(retest);
      expect(after.isEmpty, isTrue);
      expect(after.needsDoctor, isFalse);

      final DailyTargets t = TargetCalculator.build(profile(),
          date: DateTime(2027, 3, 20), assessment: after);
      // Back to the 10%-of-energy default.
      expect(t.amountFor(Nutrient.satFat), closeTo(22.22, 0.01));
      expect(t.amountFor(Nutrient.cholesterol), 300);
    });
  });
}
