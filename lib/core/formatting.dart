import '../domain/nutrients.dart';

/// Display helpers.
///
/// Nothing here ever feeds back into a calculation — rounding happens at the
/// last possible moment, on its way to the screen.
class Fmt {
  const Fmt._();

  /// A nutrient amount with its unit, e.g. "22.5 g".
  static String amount(Nutrient n, double value) =>
      '${number(value, n.decimals)} ${n.unit.symbol}';

  /// A nutrient amount without its unit.
  static String bare(Nutrient n, double value) => number(value, n.decimals);

  static String number(double value, int decimals) {
    if (value.isNaN || value.isInfinite) return '—';
    final String s = value.toStringAsFixed(decimals);
    // Strip a trailing ".0" so "22.0 g" reads as "22 g".
    if (decimals > 0 && s.endsWith('.${'0' * decimals}')) {
      return s.substring(0, s.length - decimals - 1);
    }
    return s;
  }

  /// Millilitres, switching to litres once it is easier to read that way.
  static String volume(double ml) {
    if (ml.abs() >= 1000) return '${number(ml / 1000, 2)} L';
    return '${ml.round()} ml';
  }

  /// Always millilitres, for compact places like a list row.
  static String millilitres(double ml) => '${ml.round()} ml';

  static String energy(double kcal) => '${kcal.round()} kcal';

  static String percent(double fraction) => '${(fraction * 100).round()}%';

  static String grams(double g) => '${number(g, g >= 100 ? 0 : 1)} g';

  /// "7:30 AM" from minutes since midnight.
  static String timeOfDay(int minuteOfDay) {
    final int h = (minuteOfDay ~/ 60) % 24;
    final int m = minuteOfDay % 60;
    final int h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
  }

  static String clock(DateTime t) => timeOfDay(t.hour * 60 + t.minute);

  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const List<String> _weekdays = <String>[
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  static String date(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  static String weekday(DateTime d) => _weekdays[d.weekday - 1];

  static String longDate(DateTime d) =>
      '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]} ${d.year}';

  /// "Today" / "Yesterday" / a date.
  static String relativeDate(DateTime d, DateTime now) {
    final DateTime a = DateTime(d.year, d.month, d.day);
    final DateTime b = DateTime(now.year, now.month, now.day);
    final int diff = a.difference(b).inDays;
    if (diff == 0) return 'Today';
    if (diff == -1) return 'Yesterday';
    if (diff == 1) return 'Tomorrow';
    return longDate(d);
  }

  /// Signed value for the pace readout, e.g. "+320 ml" or "-150 ml".
  static String signedVolume(double ml) {
    final String sign = ml >= 0 ? '+' : '-';
    return '$sign${volume(ml.abs())}';
  }
}
