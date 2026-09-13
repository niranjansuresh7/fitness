import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dates.dart';
import '../core/formatting.dart';
import '../core/theme.dart';
import '../domain/daily_summary.dart';
import '../domain/food_item.dart';
import '../domain/log_entry.dart';
import '../domain/nutrients.dart';
import '../domain/targets.dart';
import '../state/providers.dart';
import 'log_food_page.dart';
import 'targets_page.dart';
import 'widgets/nutrient_bar.dart';
import 'widgets/progress_ring.dart';
import 'widgets/section_card.dart';

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key, required this.onOpenWater});

  final VoidCallback onOpenWater;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<DaySummary> async = ref.watch(todayProvider);
    final DateTime selected = ref.watch(selectedDateProvider);
    final DateTime today = startOfDay(DateTime.now());
    final bool canGoForward = selected.isBefore(today);

    return Scaffold(
      appBar: AppBar(
        title: Text(Fmt.relativeDate(selected, DateTime.now())),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous day',
            onPressed: () => ref.read(selectedDateProvider.notifier).state =
                selected.subtract(const Duration(days: 1)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next day',
            onPressed: canGoForward
                ? () => ref.read(selectedDateProvider.notifier).state =
                    selected.add(const Duration(days: 1))
                : null,
          ),
          if (!isSameDay(selected, today))
            TextButton(
              onPressed: () =>
                  ref.read(selectedDateProvider.notifier).state = today,
              child: const Text('Today'),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        // Every tab is built at once inside the shell's IndexedStack, so the
        // two floating action buttons coexist. Without distinct hero tags they
        // collide on the next route transition and throw.
        heroTag: 'fab-log-food',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const LogFoodPage()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Log food'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace st) => Center(child: Text('$e')),
        data: (DaySummary day) =>
            _TodayBody(day: day, onOpenWater: onOpenWater),
      ),
    );
  }
}

class _TodayBody extends ConsumerWidget {
  const _TodayBody({required this.day, required this.onOpenWater});

  final DaySummary day;
  final VoidCallback onOpenWater;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Nutrient> exceeded = day.exceededLimits;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[
        _WaterStrip(day: day, onTap: onOpenWater),
        const SizedBox(height: 14),
        _EnergyCard(day: day),
        const SizedBox(height: 14),
        _MacroCard(day: day),
        if (exceeded.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          _LimitWarnings(day: day, exceeded: exceeded),
        ],
        const SizedBox(height: 14),
        _MealsCard(day: day),
      ],
    );
  }
}

class _WaterStrip extends StatelessWidget {
  const _WaterStrip({required this.day, required this.onTap});

  final DaySummary day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime now = DateTime.now();
    final bool isToday = isSameDay(day.date, now);
    final double pace = day.waterPaceMl(now);
    final bool behind = isToday && !day.waterGoalMet && pace < -100;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              ProgressRing(
                progress: day.waterProgress,
                color: AppTheme.water,
                size: 78,
                strokeWidth: 8,
                child: Text(
                  Fmt.percent(day.waterProgress),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.water,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Water',
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${Fmt.volume(day.waterDrunkMl)} of '
                      '${Fmt.volume(day.waterTargetMl)}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      day.waterGoalMet
                          ? 'Goal met'
                          : behind
                              ? '${Fmt.volume(-pace)} behind schedule'
                              : '${Fmt.volume(day.waterRemainingMl)} to go',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: day.waterGoalMet
                            ? AppTheme.good
                            : behind
                                ? AppTheme.warning
                                : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnergyCard extends StatelessWidget {
  const _EnergyCard({required this.day});

  final DaySummary day;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DailyTargets t = day.targets;
    final double consumed = day.consumed(Nutrient.energy);
    final double remaining = day.remaining(Nutrient.energy);
    final bool over = consumed > t.energyKcal;

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        children: <Widget>[
          ProgressRing(
            progress: day.progress(Nutrient.energy),
            color: AppTheme.energy,
            size: 164,
            strokeWidth: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  over
                      ? Fmt.energy(consumed - t.energyKcal)
                      : Fmt.energy(remaining),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: over ? AppTheme.warning : null,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                Text(
                  over ? 'over budget' : 'left',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          StatRow(
            tiles: <Widget>[
              StatTile(label: 'Eaten', value: Fmt.energy(consumed)),
              StatTile(label: 'Budget', value: Fmt.energy(t.energyKcal)),
              StatTile(
                label: 'Burn',
                value: Fmt.energy(t.tdeeKcal),
                caption: 'TDEE',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MacroCard extends StatelessWidget {
  const _MacroCard({required this.day});

  final DaySummary day;

  static const List<Nutrient> _shown = <Nutrient>[
    Nutrient.protein,
    Nutrient.carbs,
    Nutrient.fat,
    Nutrient.fiber,
  ];

  @override
  Widget build(BuildContext context) {
    final DailyTargets t = day.targets;

    return SectionCard(
      title: 'Macros',
      trailing: TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const TargetsPage()),
        ),
        child: const Text('All nutrients'),
      ),
      child: Column(
        children: <Widget>[
          for (final Nutrient n in _shown)
            NutrientBar(
              nutrient: n,
              consumed: day.consumed(n),
              target: t[n],
              color: colorForNutrient(n, context),
            ),
          const SizedBox(height: 6),
          StatRow(
            tiles: <Widget>[
              for (final Nutrient n in Nutrient.macros)
                StatTile(
                  label: n.label,
                  value: Fmt.amount(n, day.remaining(n)),
                  caption: 'left',
                  color: colorForNutrient(n, context),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LimitWarnings extends StatelessWidget {
  const _LimitWarnings({required this.day, required this.exceeded});

  final DaySummary day;
  final List<Nutrient> exceeded;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      color: AppTheme.danger.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.warning_amber_rounded,
                    color: AppTheme.danger, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Over the limit',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.danger,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final Nutrient n in exceeded)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '${n.label}: ${Fmt.amount(n, day.consumed(n))} '
                  'against a ${Fmt.amount(n, day.targets.amountFor(n))} ceiling.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MealsCard extends ConsumerWidget {
  const _MealsCard({required this.day});

  final DaySummary day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    if (day.entries.isEmpty) {
      return SectionCard(
        title: 'Meals',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: <Widget>[
              Icon(Icons.restaurant_outlined,
                  size: 34, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 10),
              Text(
                'Nothing logged for this day.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: <Widget>[
        for (final MealType meal in MealType.values)
          if (day.entriesFor(meal).isNotEmpty) ...<Widget>[
            SectionCard(
              title: meal.label,
              trailing: Text(
                Fmt.energy(day.totalsFor(meal)[Nutrient.energy]),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                children: <Widget>[
                  for (final LogEntry e in day.entriesFor(meal))
                    _EntryRow(entry: e),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _EntryRow extends ConsumerWidget {
  const _EntryRow({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final int? id = entry.id;

    return Dismissible(
      key: ValueKey<Object>(id ?? entry.hashCode),
      direction:
          id == null ? DismissDirection.none : DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: AppTheme.danger,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) {
        if (id != null) ref.read(actionsProvider).deleteEntry(id);
      },
      child: InkWell(
        onTap: () => _edit(context),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.foodName,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${Fmt.grams(entry.grams)} · '
                      'P ${Fmt.bare(Nutrient.protein, entry.nutrition[Nutrient.protein])} · '
                      'C ${Fmt.bare(Nutrient.carbs, entry.nutrition[Nutrient.carbs])} · '
                      'F ${Fmt.bare(Nutrient.fat, entry.nutrition[Nutrient.fat])}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                Fmt.energy(entry.nutrition[Nutrient.energy]),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Reopen the amount screen for this entry.
  ///
  /// The food is rebuilt from the entry's own snapshot rather than looked up
  /// in the library. That keeps the correction anchored to what was actually
  /// recorded — and works just as well for an entry whose food has since been
  /// edited or deleted.
  void _edit(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LogAmountPage(
          food: FoodItem(
            id: entry.foodId,
            name: entry.foodName,
            per100g: entry.per100gSnapshot,
          ),
          editing: entry,
        ),
      ),
    );
  }
}
