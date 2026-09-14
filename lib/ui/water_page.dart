import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dates.dart';
import '../core/formatting.dart';
import '../core/theme.dart';
import '../domain/daily_summary.dart';
import '../domain/targets.dart';
import '../domain/water_entry.dart';
import '../services/notification_service.dart';
import '../state/providers.dart';
import 'widgets/progress_ring.dart';
import 'widgets/section_card.dart';

class WaterPage extends ConsumerWidget {
  const WaterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<DaySummary> async = ref.watch(todayProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Water')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace st) => Center(child: Text('$e')),
        data: (DaySummary day) => _WaterBody(day: day),
      ),
    );
  }
}

class _WaterBody extends ConsumerWidget {
  const _WaterBody({required this.day});

  final DaySummary day;

  /// Water is logged at the current time when you are looking at today, and at
  /// midday when back-filling an earlier date.
  DateTime _logTime() {
    final DateTime now = DateTime.now();
    if (isSameDay(day.date, now)) return now;
    return DateTime(day.date.year, day.date.month, day.date.day, 12);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DateTime now = DateTime.now();
    final bool isToday = isSameDay(day.date, now);

    final AsyncValue<List<DrinkPreset>> presets =
        ref.watch(drinkPresetsProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: <Widget>[
        _RingCard(
          day: day,
          isToday: isToday,
          now: now,
          // Kept in the same card as the ring: on a phone these would not
          // otherwise share a screen, and checking your progress should not
          // mean scrolling away from the button that changes it.
          actions: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              presets.when(
                loading: () => const SizedBox(height: 86),
                error: (Object e, StackTrace st) => Text('$e'),
                data: (List<DrinkPreset> list) => Row(
                  children: <Widget>[
                    for (int i = 0; i < list.length; i++) ...<Widget>[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _PresetChip(
                          preset: list[i],
                          onTap: () => ref.read(actionsProvider).addWater(
                                list[i].volumeMl,
                                label: list[i].label,
                                at: _logTime(),
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _askCustomAmount(context, ref),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Custom amount'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 46),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _TargetBreakdown(day: day),
        const SizedBox(height: 14),
        if (isToday) ...<Widget>[
          _NextReminderCard(day: day),
          const SizedBox(height: 14),
        ],
        SectionCard(
          title: 'Logged today',
          subtitle: day.waterEntries.isEmpty
              ? null
              : '${day.waterEntries.length} '
                  '${day.waterEntries.length == 1 ? 'drink' : 'drinks'}',
          child: day.waterEntries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Nothing logged yet.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              : Column(
                  children: <Widget>[
                    for (final WaterEntry w in day.waterEntries.reversed)
                      _WaterRow(entry: w),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _askCustomAmount(BuildContext context, WidgetRef ref) async {
    final double? ml = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) => const _CustomAmountSheet(),
    );
    if (ml != null && ml > 0) {
      await ref.read(actionsProvider).addWater(ml, at: _logTime());
    }
  }
}

class _RingCard extends StatelessWidget {
  const _RingCard({
    required this.day,
    required this.isToday,
    required this.now,
    required this.actions,
  });

  final DaySummary day;
  final bool isToday;
  final DateTime now;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double pace = day.waterPaceMl(now);
    final double? perHour = day.waterPerRemainingHour(now);

    // Only meaningful while the day is actually in progress.
    final bool showPace = isToday && !day.waterGoalMet;
    final bool behind = pace < -100;

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        children: <Widget>[
          ProgressRing(
            progress: day.waterProgress,
            color: AppTheme.water,
            size: 176,
            strokeWidth: 15,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  Fmt.volume(day.waterDrunkMl),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                Text(
                  'of ${Fmt.volume(day.waterTargetMl)}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Text(
                  Fmt.percent(day.waterProgress),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppTheme.water,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (day.waterGoalMet)
            _Banner(
              icon: Icons.check_circle,
              color: AppTheme.good,
              text: 'Goal met. '
                  '${day.waterDrunkMl > day.waterTargetMl ? '${Fmt.volume(day.waterDrunkMl - day.waterTargetMl)} over.' : ''}',
            )
          else
            Column(
              children: <Widget>[
                Text(
                  '${Fmt.volume(day.waterRemainingMl)} to go',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (showPace) ...<Widget>[
                  const SizedBox(height: 10),
                  _Banner(
                    icon: behind ? Icons.trending_down : Icons.trending_up,
                    color: behind ? AppTheme.warning : AppTheme.good,
                    text: behind
                        ? '${Fmt.volume(-pace)} behind schedule'
                        : 'On track (${Fmt.signedVolume(pace)})',
                  ),
                  if (perHour != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      '${Fmt.millilitres(perHour)} per hour until '
                      '${Fmt.timeOfDay(day.profile.sleepMinuteOfDay)} '
                      'finishes the day.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          actions,
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.preset, required this.onTap});

  final DrinkPreset preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
        decoration: BoxDecoration(
          color: AppTheme.water.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.water.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.local_drink_outlined,
                color: AppTheme.water, size: 22),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                Fmt.millilitres(preset.volumeMl),
                maxLines: 1,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.water,
                ),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                preset.label,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TargetBreakdown extends StatelessWidget {
  const _TargetBreakdown({required this.day});

  final DaySummary day;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final WaterTarget w = day.targets.water;

    Widget row(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
        );

    return SectionCard(
      title: 'How this target is built',
      child: Column(
        children: <Widget>[
          row(
            '${day.profile.weightKg.toStringAsFixed(1)} kg × '
            '${day.profile.waterMlPerKg.toStringAsFixed(0)} ml/kg',
            Fmt.millilitres(w.baselineMl),
          ),
          if (w.exerciseMl > 0)
            row(
              '${day.profile.dailyExerciseMinutes} min exercise × '
                  '${day.profile.waterMlPerExerciseMinute.toStringAsFixed(0)} ml/min',
              '+${Fmt.millilitres(w.exerciseMl)}',
            ),
          if (w.climateMl > 0)
            row(day.profile.climate.label, '+${Fmt.millilitres(w.climateMl)}'),
          if (w.foodWaterCreditMl > 0)
            row('Water from food logged today',
                '−${Fmt.millilitres(w.foodWaterCreditMl)}'),
          const Divider(height: 18),
          row('Drink today', Fmt.volume(w.drinkingTargetMl), bold: true),
          const SizedBox(height: 8),
          Text(
            'Change any of these inputs in Profile, under Water.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _NextReminderCard extends StatelessWidget {
  const _NextReminderCard({required this.day});

  final DaySummary day;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (!day.profile.remindersEnabled) {
      return SectionCard(
        title: 'Reminders are off',
        child: Text(
          'Turn them on in Profile, under Water reminders, so the phone '
          'nudges you through the day.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }

    final List<ReminderSlot> slots =
        NotificationService.buildSlots(day.profile);
    final DateTime now = DateTime.now();
    final int minuteNow = now.hour * 60 + now.minute;

    ReminderSlot? next;
    for (final ReminderSlot s in slots) {
      if (s.minuteOfDay > minuteNow) {
        next = s;
        break;
      }
    }

    return SectionCard(
      title: 'Next reminder',
      child: next == null
          ? Text(
              'No more reminders today. The next one is at '
              '${slots.isEmpty ? '—' : slots.first.timeLabel} tomorrow.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          : Row(
              children: <Widget>[
                const Icon(Icons.notifications_active_outlined,
                    color: AppTheme.water, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        next.timeLabel,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Drink about ${Fmt.millilitres(next.perSlotMl)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _WaterRow extends ConsumerWidget {
  const _WaterRow({required this.entry});

  final WaterEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final int? id = entry.id;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.water_drop_outlined, color: AppTheme.water),
      title: Text(
        Fmt.millilitres(entry.volumeMl),
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        entry.label.isEmpty
            ? Fmt.clock(entry.loggedAt)
            : '${entry.label} · ${Fmt.clock(entry.loggedAt)}',
      ),
      trailing: id == null
          ? null
          : IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Remove',
              onPressed: () => ref.read(actionsProvider).deleteWater(id),
            ),
    );
  }
}

/// Bottom sheet for entering an exact volume.
class _CustomAmountSheet extends StatefulWidget {
  const _CustomAmountSheet();

  @override
  State<_CustomAmountSheet> createState() => _CustomAmountSheetState();
}

class _CustomAmountSheetState extends State<_CustomAmountSheet> {
  final TextEditingController _controller = TextEditingController(text: '250');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final double? ml = double.tryParse(_controller.text.trim());
    Navigator.of(context).pop(ml);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'How much did you drink?',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              suffixText: 'ml',
              hintText: '250',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _submit, child: const Text('Add')),
        ],
      ),
    );
  }
}
