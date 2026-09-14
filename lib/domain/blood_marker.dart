/// Blood test markers the app can record and act on.
///
/// Reference intervals follow the ones printed on Indian pathology reports
/// (Orange Health / Orchard Healthcare panels), so a value the lab flags is a
/// value this app flags too. Where guidelines differ from a lab's interval the
/// guideline figure is noted in [note].
library;

enum MarkerPanel {
  lipids('Lipids'),
  liver('Liver'),
  kidney('Kidney & electrolytes'),
  glucose('Blood sugar'),
  vitamins('Vitamins'),
  blood('Blood count'),
  thyroid('Thyroid');

  const MarkerPanel(this.label);
  final String label;
}

/// Where a value sits against its reference interval.
enum MarkerStatus {
  low('Low'),
  normal('In range'),
  high('High');

  const MarkerStatus(this.label);
  final String label;
}

enum BloodMarker {
  // --- Lipids ------------------------------------------------------------
  totalCholesterol(
      'totalCholesterol', 'Total cholesterol', 'mg/dL', MarkerPanel.lipids,
      max: 200),
  ldl('ldl', 'LDL cholesterol', 'mg/dL', MarkerPanel.lipids,
      max: 100,
      note: 'Optimal under 100. 100-129 above optimal, 130-159 borderline, '
          '160-189 high.'),
  hdl('hdl', 'HDL cholesterol', 'mg/dL', MarkerPanel.lipids,
      min: 50, note: 'Higher is protective. Under 40 is a clear risk factor.'),
  nonHdl('nonHdl', 'Non-HDL cholesterol', 'mg/dL', MarkerPanel.lipids,
      max: 130),
  triglycerides('triglycerides', 'Triglycerides', 'mg/dL', MarkerPanel.lipids,
      max: 150),

  // --- Liver -------------------------------------------------------------
  ast('ast', 'AST (SGOT)', 'U/L', MarkerPanel.liver, min: 17, max: 49),
  alt('alt', 'ALT (SGPT)', 'U/L', MarkerPanel.liver, max: 50),
  ggt('ggt', 'GGT', 'U/L', MarkerPanel.liver, min: 15, max: 73),
  alp('alp', 'Alkaline phosphatase', 'U/L', MarkerPanel.liver,
      min: 38, max: 126),
  bilirubinTotal(
      'bilirubinTotal', 'Bilirubin, total', 'mg/dL', MarkerPanel.liver,
      min: 0.2, max: 1.3),
  albumin('albumin', 'Albumin', 'g/dL', MarkerPanel.liver, min: 3.5, max: 5.0),

  // --- Kidney & electrolytes ---------------------------------------------
  creatinine('creatinine', 'Creatinine', 'mg/dL', MarkerPanel.kidney,
      min: 0.66, max: 1.25),
  egfr('egfr', 'eGFR', 'ml/min/1.73m²', MarkerPanel.kidney,
      min: 90, note: 'Under 90 is a mild decrease; under 60 needs follow-up.'),
  urea('urea', 'Urea', 'mg/dL', MarkerPanel.kidney, min: 19, max: 43),
  uricAcid('uricAcid', 'Uric acid', 'mg/dL', MarkerPanel.kidney,
      min: 3.5, max: 8.5, note: 'Gout risk rises above about 7.'),
  sodium('sodium', 'Sodium', 'mmol/L', MarkerPanel.kidney, min: 137, max: 145),
  potassium('potassium', 'Potassium', 'mmol/L', MarkerPanel.kidney,
      min: 3.5, max: 5.5),
  calcium('calcium', 'Calcium', 'mg/dL', MarkerPanel.kidney,
      min: 8.4, max: 10.2),
  phosphorus('phosphorus', 'Phosphorus', 'mg/dL', MarkerPanel.kidney,
      min: 2.5, max: 4.5),

  // --- Blood sugar --------------------------------------------------------
  hba1c('hba1c', 'HbA1c', '%', MarkerPanel.glucose,
      max: 5.7, note: '5.7-6.4 is pre-diabetes, 6.5 and over is diabetes.'),
  fastingGlucose(
      'fastingGlucose', 'Fasting glucose', 'mg/dL', MarkerPanel.glucose,
      min: 70, max: 99),

  // --- Vitamins -----------------------------------------------------------
  vitaminD('vitaminD', 'Vitamin D (25-OH)', 'ng/mL', MarkerPanel.vitamins,
      min: 30,
      max: 100,
      note: 'Under 20 is deficient, 20-30 insufficient, 30-100 sufficient.'),
  vitaminB12('vitaminB12', 'Vitamin B12', 'pg/mL', MarkerPanel.vitamins,
      min: 187,
      max: 883,
      note: 'Many clinicians aim above 400 even though labs accept less.'),

  // --- Blood count --------------------------------------------------------
  hemoglobin('hemoglobin', 'Haemoglobin', 'g/dL', MarkerPanel.blood,
      min: 13, max: 17),
  ferritin('ferritin', 'Ferritin', 'ng/mL', MarkerPanel.blood,
      min: 30, max: 400),

  // --- Thyroid ------------------------------------------------------------
  tsh('tsh', 'TSH', 'µIU/mL', MarkerPanel.thyroid, min: 0.35, max: 4.94);

  const BloodMarker(
    this.key,
    this.label,
    this.unit,
    this.panel, {
    this.min,
    this.max,
    this.note = '',
  });

  final String key;
  final String label;
  final String unit;
  final MarkerPanel panel;

  /// Lower bound of the healthy interval, if the marker has one.
  final double? min;

  /// Upper bound of the healthy interval, if the marker has one.
  final double? max;

  /// Extra context shown beside the value.
  final String note;

  MarkerStatus statusOf(double value) {
    final double? lo = min;
    final double? hi = max;
    if (lo != null && value < lo) return MarkerStatus.low;
    if (hi != null && value > hi) return MarkerStatus.high;
    return MarkerStatus.normal;
  }

  String get rangeLabel {
    final double? lo = min;
    final double? hi = max;
    if (lo != null && hi != null) return '$lo - $hi $unit';
    if (hi != null) return 'under $hi $unit';
    if (lo != null) return 'over $lo $unit';
    return unit;
  }

  static final Map<String, BloodMarker> _byKey = <String, BloodMarker>{
    for (final BloodMarker m in BloodMarker.values) m.key: m,
  };

  static BloodMarker? fromKey(String key) => _byKey[key];

  static List<BloodMarker> inPanel(MarkerPanel panel) => BloodMarker.values
      .where((BloodMarker m) => m.panel == panel)
      .toList(growable: false);
}

/// One recorded result.
class BloodResult {
  const BloodResult({
    this.id,
    required this.marker,
    required this.value,
    required this.takenOn,
    this.note = '',
  });

  final int? id;
  final BloodMarker marker;
  final double value;

  /// The date of the blood draw, not the date it was typed in.
  final DateTime takenOn;

  final String note;

  MarkerStatus get status => marker.statusOf(value);

  bool get isOutOfRange => status != MarkerStatus.normal;

  BloodResult copyWith({
    int? id,
    BloodMarker? marker,
    double? value,
    DateTime? takenOn,
    String? note,
  }) {
    return BloodResult(
      id: id ?? this.id,
      marker: marker ?? this.marker,
      value: value ?? this.value,
      takenOn: takenOn ?? this.takenOn,
      note: note ?? this.note,
    );
  }
}

/// The most recent value for each marker.
///
/// Targets are always derived from the latest draw, so re-testing in three
/// months moves them on its own rather than needing anything reconfigured.
class MarkerSnapshot {
  const MarkerSnapshot(this.latest);

  final Map<BloodMarker, BloodResult> latest;

  static const MarkerSnapshot empty =
      MarkerSnapshot(<BloodMarker, BloodResult>{});

  /// Build from an unordered history, keeping the newest result per marker.
  factory MarkerSnapshot.fromHistory(Iterable<BloodResult> history) {
    final Map<BloodMarker, BloodResult> out = <BloodMarker, BloodResult>{};
    for (final BloodResult r in history) {
      final BloodResult? existing = out[r.marker];
      if (existing == null || r.takenOn.isAfter(existing.takenOn)) {
        out[r.marker] = r;
      }
    }
    return MarkerSnapshot(out);
  }

  bool get isEmpty => latest.isEmpty;

  double? operator [](BloodMarker m) => latest[m]?.value;

  BloodResult? resultFor(BloodMarker m) => latest[m];

  bool has(BloodMarker m) => latest.containsKey(m);

  /// Date of the most recent draw across all markers.
  DateTime? get lastDrawDate {
    DateTime? newest;
    for (final BloodResult r in latest.values) {
      if (newest == null || r.takenOn.isAfter(newest)) newest = r.takenOn;
    }
    return newest;
  }

  List<BloodResult> get outOfRange {
    final List<BloodResult> out =
        latest.values.where((BloodResult r) => r.isOutOfRange).toList();
    out.sort((BloodResult a, BloodResult b) =>
        a.marker.panel.index.compareTo(b.marker.panel.index));
    return out;
  }
}
