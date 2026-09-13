import 'blood_marker.dart';

/// What a flag is for.
enum FlagKind {
  /// Something eating differently can move.
  nutrition,

  /// Something that needs a doctor. The app will still adjust what it sensibly
  /// can, but it must never present these as a diet problem.
  medical,
}

/// A pattern in a blood panel that the app knows how to respond to.
///
/// Thresholds are stated on each entry rather than buried in the derivation so
/// they can be checked against a guideline without reading the logic.
enum ClinicalFlag {
  raisedLdl(
    'Raised LDL cholesterol',
    FlagKind.nutrition,
    'Tightens saturated fat and dietary cholesterol, and raises the fibre '
        'target. Soluble fibre and replacing saturated fat with unsaturated '
        'fat are the two dietary levers with the best evidence behind them.',
  ),
  lowHdl(
    'Low HDL cholesterol',
    FlagKind.nutrition,
    'Tightens added sugar and raises the omega-3 target. HDL responds more to '
        'exercise, refined-carbohydrate intake and body composition than to '
        'any single nutrient.',
  ),
  raisedTriglycerides(
    'Raised triglycerides',
    FlagKind.nutrition,
    'Tightens added sugar and alcohol, and raises omega-3.',
  ),
  vitaminDDeficient(
    'Vitamin D deficiency',
    FlagKind.medical,
    'Raises the dietary vitamin D target, but food alone will not correct a '
        'deficiency — that needs a supplement dose a doctor prescribes.',
  ),
  vitaminDInsufficient(
    'Vitamin D insufficiency',
    FlagKind.nutrition,
    'Raises the dietary vitamin D target.',
  ),
  b12BelowOptimal(
    'Vitamin B12 in the lower part of range',
    FlagKind.nutrition,
    'Raises the B12 target. Still inside the laboratory range, so this is a '
        'nudge rather than a correction. B12 has no established upper limit.',
  ),
  b12Deficient(
    'Vitamin B12 deficiency',
    FlagKind.medical,
    'Raises the B12 target, but a deficiency usually needs supplementation or '
        'injections rather than food.',
  ),
  raisedLiverEnzymes(
    'Raised liver enzymes',
    FlagKind.medical,
    'Sets the alcohol limit to zero. Beyond that this is not a nutrition '
        'finding and needs a doctor to interpret.',
  ),
  reducedKidneyFunction(
    'Reduced kidney function',
    FlagKind.medical,
    'Caps protein at a safer level and tightens sodium, potassium and '
        'phosphorus. Protein targets must be set by a doctor at this point.',
  ),
  raisedUricAcid(
    'Raised uric acid',
    FlagKind.nutrition,
    'Adds fluid to the daily water target and sets alcohol to zero. '
        'Purine-heavy foods are worth limiting.',
  ),
  prediabetes(
    'Pre-diabetes range HbA1c',
    FlagKind.nutrition,
    'Tightens added sugar and raises fibre.',
  ),
  diabetes(
    'Diabetes range HbA1c',
    FlagKind.medical,
    'Tightens added sugar and raises fibre, but the target range is a '
        'clinical decision.',
  ),
  anaemia(
    'Low haemoglobin',
    FlagKind.medical,
    'Raises the iron and vitamin C targets. The cause needs investigating.',
  ),
  lowFerritin(
    'Low iron stores',
    FlagKind.nutrition,
    'Raises the iron target and pairs it with vitamin C, which improves '
        'absorption of iron from plant foods several-fold.',
  ),
  abnormalThyroid(
    'TSH outside range',
    FlagKind.medical,
    'No nutrition change. Thyroid results need a doctor.',
  );

  const ClinicalFlag(this.label, this.kind, this.effect);

  final String label;
  final FlagKind kind;

  /// What the app does about it, in plain words.
  final String effect;

  static ClinicalFlag? fromName(String name) {
    for (final ClinicalFlag f in ClinicalFlag.values) {
      if (f.name == name) return f;
    }
    return null;
  }
}

/// One flag together with the numbers that raised it.
class ClinicalFinding {
  const ClinicalFinding({required this.flag, required this.detail});

  final ClinicalFlag flag;

  /// The evidence, e.g. "LDL 141 mg/dL against a target under 100 mg/dL."
  final String detail;
}

/// Everything the app concluded from the latest blood results.
class ClinicalAssessment {
  const ClinicalAssessment(this.findings);

  final List<ClinicalFinding> findings;

  static const ClinicalAssessment none =
      ClinicalAssessment(<ClinicalFinding>[]);

  Set<ClinicalFlag> get flags =>
      findings.map((ClinicalFinding f) => f.flag).toSet();

  bool has(ClinicalFlag flag) => flags.contains(flag);

  bool get isEmpty => findings.isEmpty;

  List<ClinicalFinding> get medical => findings
      .where((ClinicalFinding f) => f.flag.kind == FlagKind.medical)
      .toList(growable: false);

  List<ClinicalFinding> get nutritional => findings
      .where((ClinicalFinding f) => f.flag.kind == FlagKind.nutrition)
      .toList(growable: false);

  bool get needsDoctor => medical.isNotEmpty;

  /// Read a blood panel and decide what, if anything, to change.
  ///
  /// Only markers that were actually recorded are considered; a missing marker
  /// never produces a flag. Every threshold here is the one printed on the
  /// marker definition, so the app and the lab report agree.
  static ClinicalAssessment fromMarkers(MarkerSnapshot snapshot) {
    if (snapshot.isEmpty) return none;

    final List<ClinicalFinding> out = <ClinicalFinding>[];
    void add(ClinicalFlag flag, String detail) =>
        out.add(ClinicalFinding(flag: flag, detail: detail));

    String fmt(BloodMarker m, double v) => '${_trim(v)} ${m.unit}';

    // --- Lipids ----------------------------------------------------------
    final double? ldl = snapshot[BloodMarker.ldl];
    final double? nonHdl = snapshot[BloodMarker.nonHdl];
    if ((ldl != null && ldl > 100) || (nonHdl != null && nonHdl > 130)) {
      final List<String> parts = <String>[
        if (ldl != null && ldl > 100)
          'LDL ${fmt(BloodMarker.ldl, ldl)} against a target under 100',
        if (nonHdl != null && nonHdl > 130)
          'non-HDL ${fmt(BloodMarker.nonHdl, nonHdl)} against a target '
              'under 130',
      ];
      add(ClinicalFlag.raisedLdl, '${parts.join('; ')}.');
    }

    final double? hdl = snapshot[BloodMarker.hdl];
    if (hdl != null && hdl < 50) {
      add(ClinicalFlag.lowHdl,
          'HDL ${fmt(BloodMarker.hdl, hdl)} against a target above 50.');
    }

    final double? tg = snapshot[BloodMarker.triglycerides];
    if (tg != null && tg > 150) {
      add(
          ClinicalFlag.raisedTriglycerides,
          'Triglycerides ${fmt(BloodMarker.triglycerides, tg)} against a '
          'target under 150.');
    }

    // --- Vitamins ---------------------------------------------------------
    final double? vitD = snapshot[BloodMarker.vitaminD];
    if (vitD != null) {
      if (vitD < 20) {
        add(
            ClinicalFlag.vitaminDDeficient,
            'Vitamin D ${fmt(BloodMarker.vitaminD, vitD)}, below the '
            'deficiency threshold of 20.');
      } else if (vitD < 30) {
        add(
            ClinicalFlag.vitaminDInsufficient,
            'Vitamin D ${fmt(BloodMarker.vitaminD, vitD)}, below the '
            'sufficiency threshold of 30.');
      }
    }

    final double? b12 = snapshot[BloodMarker.vitaminB12];
    if (b12 != null) {
      if (b12 < 187) {
        add(
            ClinicalFlag.b12Deficient,
            'B12 ${fmt(BloodMarker.vitaminB12, b12)}, below the laboratory '
            'range.');
      } else if (b12 < 400) {
        add(
            ClinicalFlag.b12BelowOptimal,
            'B12 ${fmt(BloodMarker.vitaminB12, b12)} — inside the laboratory '
            'range but below the 400 many clinicians aim for.');
      }
    }

    // --- Liver -------------------------------------------------------------
    final double? ast = snapshot[BloodMarker.ast];
    final double? alt = snapshot[BloodMarker.alt];
    final bool astHigh = ast != null && ast > 49;
    final bool altHigh = alt != null && alt > 50;
    if (astHigh || altHigh) {
      final List<String> parts = <String>[
        if (astHigh)
          'AST ${fmt(BloodMarker.ast, ast)} '
              '(${(ast / 49).toStringAsFixed(1)}x the upper limit)',
        if (altHigh)
          'ALT ${fmt(BloodMarker.alt, alt)} '
              '(${(alt / 50).toStringAsFixed(1)}x the upper limit)',
      ];
      add(ClinicalFlag.raisedLiverEnzymes, '${parts.join('; ')}.');
    }

    // --- Kidney -------------------------------------------------------------
    final double? egfr = snapshot[BloodMarker.egfr];
    final double? creatinine = snapshot[BloodMarker.creatinine];
    if ((egfr != null && egfr < 90) ||
        (creatinine != null && creatinine > 1.25)) {
      add(
          ClinicalFlag.reducedKidneyFunction,
          egfr != null
              ? 'eGFR ${fmt(BloodMarker.egfr, egfr)}, below the normal '
                  'threshold of 90.'
              : 'Creatinine ${fmt(BloodMarker.creatinine, creatinine!)}, '
                  'above the reference range.');
    }

    final double? uric = snapshot[BloodMarker.uricAcid];
    if (uric != null && uric > 7.0) {
      add(
          ClinicalFlag.raisedUricAcid,
          'Uric acid ${fmt(BloodMarker.uricAcid, uric)}, above the 7.0 at '
          'which gout risk climbs.');
    }

    // --- Blood sugar --------------------------------------------------------
    final double? hba1c = snapshot[BloodMarker.hba1c];
    if (hba1c != null) {
      if (hba1c >= 6.5) {
        add(ClinicalFlag.diabetes,
            'HbA1c ${fmt(BloodMarker.hba1c, hba1c)}, in the diabetes range.');
      } else if (hba1c >= 5.7) {
        add(
            ClinicalFlag.prediabetes,
            'HbA1c ${fmt(BloodMarker.hba1c, hba1c)}, in the pre-diabetes '
            'range.');
      }
    }

    // --- Blood count --------------------------------------------------------
    final double? hb = snapshot[BloodMarker.hemoglobin];
    if (hb != null && hb < 13) {
      add(
          ClinicalFlag.anaemia,
          'Haemoglobin ${fmt(BloodMarker.hemoglobin, hb)}, below the '
          'reference range.');
    }

    final double? ferritin = snapshot[BloodMarker.ferritin];
    if (ferritin != null && ferritin < 30) {
      add(
          ClinicalFlag.lowFerritin,
          'Ferritin ${fmt(BloodMarker.ferritin, ferritin)}, indicating '
          'depleted iron stores.');
    }

    // --- Thyroid ------------------------------------------------------------
    final double? tsh = snapshot[BloodMarker.tsh];
    if (tsh != null && (tsh < 0.35 || tsh > 4.94)) {
      add(ClinicalFlag.abnormalThyroid,
          'TSH ${fmt(BloodMarker.tsh, tsh)}, outside the reference range.');
    }

    return ClinicalAssessment(out);
  }

  static String _trim(double v) {
    final String s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }
}
