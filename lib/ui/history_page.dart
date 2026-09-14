import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dates.dart';
import '../core/formatting.dart';
import '../core/theme.dart';
import '../domain/daily_summary.dart';
import '../domain/nutrients.dart';
import '../state/providers.dart';
import 'widgets/section_card.dart';

/// The last 30 days at a glance.
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key, required this.onOpenDay});

  final VoidCallback onOpenDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<DaySummary>> async = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace st) => Center(child: Text('$e')),
        data: (List<DaySummary> days) {
          final List<DaySummary> withData = days
              .where((DaySummary d) =>
                  d.entries.isNotEmpty || d.waterEntries.isNotEmpty)
              .toList();

          if (withData.isEmpty) {
            return const _EmptyHistory();
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: <Widget>[
              _Averages(days: withData),
              const SizedBox(height: 14),
              SectionCard(
                title: 'Day by day',
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Column(
                  children: <Widget>[
                    for (final DaySummary d in withData)
                      _DayRow(
                        day: d,
                        onTap: () {
                          ref.read(selectedDateProvider.notifier).state =
                              startOfDay(d.date);
                          onOpenDay();
                        },
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.calendar_month_outlined,
                size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'Nothing logged in the last 30 days yet.',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Averages extends StatelessWidget {
  const _Averages({required this.days});

  final List<DaySummary> days;

  @override
  Widget build(BuildContext context) {
    // Averaged over days with data only — including untracked days would drag
    // every average towards zero and say nothing useful.
    final int n = days.length;
    double mean(double Function(DaySummary) pick) => n == 0
        ? 0
        : days.fold<double>(0, (double s, DaySummary d) => s + pick(d)) / n;

    final int daysOnTarget =
        days.where((DaySummary d) => d.waterGoalMet).length;

    return SectionCard(
      title: 'Averages',
      subtitle: 'Across $n logged ${n == 1 ? 'day' : 'days'}.',
      child: Column(
        children: <Widget>[
          StatRow(
            tiles: <Widget>[
              StatTile(
                label: 'Water',
                value: Fmt.volume(mean((DaySummary d) => d.waterDrunkMl)),
                color: AppTheme.water,
                caption: '$daysOnTarget / $n on target',
              ),
              StatTile(
                label: 'Energy',
                value: Fmt.energy(
                    mean((DaySummary d) => d.consumed(Nutrient.energy))),
              ),
              StatTile(
                label: 'Protein',
                value: Fmt.amount(Nutrient.protein,
                    mean((DaySummary d) => d.consumed(Nutrient.protein))),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.onTap});

  final DaySummary day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double waterProgress = day.waterProgress.clamp(0.0, 1.0);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 56,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    Fmt.weekday(day.date),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  Text(
                    Fmt.date(day.date),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: waterProgress,
                      minHeight: 6,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        day.waterGoalMet ? AppTheme.good : AppTheme.water,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${Fmt.volume(day.waterDrunkMl)} water · '
                    '${Fmt.energy(day.consumed(Nutrient.energy))} · '
                    '${Fmt.amount(Nutrient.protein, day.consumed(Nutrient.protein))} protein',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}
