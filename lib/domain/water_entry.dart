/// One drink, recorded in millilitres.
///
/// Volume is stored as a double so 1/3 of a 750 ml bottle stays exact rather
/// than being rounded to 250 ml on the way in.
class WaterEntry {
  const WaterEntry({
    this.id,
    required this.volumeMl,
    required this.loggedAt,
    this.label = '',
  });

  final int? id;
  final double volumeMl;
  final DateTime loggedAt;

  /// What it was drunk from, e.g. "Bottle". Cosmetic only.
  final String label;

  WaterEntry copyWith({
    int? id,
    double? volumeMl,
    DateTime? loggedAt,
    String? label,
  }) {
    return WaterEntry(
      id: id ?? this.id,
      volumeMl: volumeMl ?? this.volumeMl,
      loggedAt: loggedAt ?? this.loggedAt,
      label: label ?? this.label,
    );
  }
}

/// A quick-add button on the water screen.
class DrinkPreset {
  const DrinkPreset({required this.label, required this.volumeMl});

  final String label;
  final double volumeMl;

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'label': label, 'volumeMl': volumeMl};

  static DrinkPreset fromJson(Map<String, dynamic> json) => DrinkPreset(
        label: json['label'] as String? ?? 'Drink',
        volumeMl: (json['volumeMl'] as num?)?.toDouble() ?? 250.0,
      );

  static const List<DrinkPreset> defaults = <DrinkPreset>[
    DrinkPreset(label: 'Glass', volumeMl: 250),
    DrinkPreset(label: 'Large glass', volumeMl: 350),
    DrinkPreset(label: 'Bottle', volumeMl: 500),
    DrinkPreset(label: 'Big bottle', volumeMl: 1000),
  ];
}
