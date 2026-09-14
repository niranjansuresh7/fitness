/// Day handling.
///
/// A "day" in this app is a **local calendar day**, stored as `yyyy-MM-dd`.
/// Every row carries that string alongside its timestamp so grouping a day's
/// entries never depends on timezone maths at query time.
library;

String dayKey(DateTime date) {
  final String m = date.month.toString().padLeft(2, '0');
  final String d = date.day.toString().padLeft(2, '0');
  return '${date.year}-$m-$d';
}

DateTime startOfDay(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime? parseDayKey(String key) {
  final List<String> parts = key.split('-');
  if (parts.length != 3) return null;
  final int? y = int.tryParse(parts[0]);
  final int? m = int.tryParse(parts[1]);
  final int? d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
