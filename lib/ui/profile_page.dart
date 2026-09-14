import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../core/formatting.dart';
import '../core/theme.dart';
import '../domain/blood_marker.dart';
import '../domain/clinical_flags.dart';
import '../domain/nutrients.dart';
import '../domain/profile.dart';
import '../domain/targets.dart';
import '../services/notification_service.dart';
import '../state/providers.dart';
import 'blood_report_page.dart';
import 'reminder_schedule_page.dart';
import 'targets_page.dart';
import 'widgets/number_field.dart';
import 'widgets/section_card.dart';

/// Body stats, goals and reminder settings.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserProfile p = ref.watch(profileProvider);

    Future<void> save(UserProfile next) =>
        ref.read(profileProvider.notifier).save(next);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          _BodySection(profile: p, save: save),
          const SizedBox(height: 14),
          const _BloodReportLink(),
          const SizedBox(height: 14),
          _GoalSection(profile: p, save: save),
          const SizedBox(height: 14),
          _ResultsCard(profile: p),
          const SizedBox(height: 14),
          _MacroSection(profile: p, save: save),
          const SizedBox(height: 14),
          _WaterSection(profile: p, save: save),
          const SizedBox(height: 14),
          _ReminderSection(profile: p, save: save),
          const SizedBox(height: 14),
          const _DataSection(),
        ],
      ),
    );
  }
}

class _BodySection extends StatelessWidget {
  const _BodySection({required this.profile, required this.save});

  final UserProfile profile;
  final Future<void> Function(UserProfile) save;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'You',
      subtitle: 'These drive every calculation in the app.',
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: NumberField(
                  label: 'Weight',
                  suffix: 'kg',
                  value: profile.weightKg,
                  onChanged: (double v) => save(profile.copyWith(weightKg: v)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NumberField(
                  label: 'Height',
                  suffix: 'cm',
                  decimals: 0,
                  value: profile.heightCm,
                  onChanged: (double v) => save(profile.copyWith(heightCm: v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          NumberField(
            label: 'Body fat (optional)',
            suffix: '%',
            value: profile.bodyFatPercent,
            allowEmpty: true,
            helper: 'Unlocks the Katch-McArdle formula and lean-mass protein '
                'targets, both more accurate than the body-weight versions.',
            onChanged: (double v) => save(profile.copyWith(bodyFatPercent: v)),
            onCleared: () => save(profile.copyWith(clearBodyFat: true)),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Sex>(
            initialValue: profile.sex,
            decoration: const InputDecoration(labelText: 'Sex'),
            items: <DropdownMenuItem<Sex>>[
              for (final Sex s in Sex.values)
                DropdownMenuItem<Sex>(value: s, child: Text(s.label)),
            ],
            onChanged: (Sex? s) {
              if (s != null) save(profile.copyWith(sex: s));
            },
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date of birth'),
            subtitle: Text(profile.birthDate == null
                ? 'Not set — age defaults to 30'
                : '${Fmt.longDate(profile.birthDate!)} '
                    '(${profile.ageYears} years)'),
            trailing: const Icon(Icons.calendar_today_outlined, size: 20),
            onTap: () async {
              final DateTime now = DateTime.now();
              final DateTime? picked = await showDatePicker(
                context: context,
                initialDate: profile.birthDate ??
                    DateTime(now.year - 30, now.month, now.day),
                firstDate: DateTime(now.year - 110),
                lastDate: now,
              );
              if (picked != null) save(profile.copyWith(birthDate: picked));
            },
          ),
        ],
      ),
    );
  }
}

class _BloodReportLink extends ConsumerWidget {
  const _BloodReportLink();

  static String _summary(DateTime drawn, int adjusted, bool needsDoctor) {
    final String changes = adjusted == 0
        ? 'no target changes'
        : '$adjusted target ${adjusted == 1 ? 'change' : 'changes'}';
    final String doctor = needsDoctor ? ' · see a doctor' : '';
    return '${Fmt.date(drawn)} · $changes$doctor';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ClinicalAssessment assessment =
        ref.watch(assessmentProvider).valueOrNull ?? ClinicalAssessment.none;
    final MarkerSnapshot snapshot =
        ref.watch(markerSnapshotProvider).valueOrNull ?? MarkerSnapshot.empty;

    final DateTime? drawn = snapshot.lastDrawDate;
    final int adjusted = assessment.nutritional.length;

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(
          Icons.science_outlined,
          color: assessment.needsDoctor ? AppTheme.danger : AppTheme.water,
        ),
        title: const Text('Blood report',
            style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          drawn == null
              ? 'Add your results and the targets follow them'
              : _summary(drawn, adjusted, assessment.needsDoctor),
          style: theme.textTheme.bodySmall,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const BloodReportPage()),
        ),
      ),
    );
  }
}

class _GoalSection extends StatelessWidget {
  const _GoalSection({required this.profile, required this.save});

  final UserProfile profile;
  final Future<void> Function(UserProfile) save;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Activity and goal',
      child: Column(
        children: <Widget>[
          DropdownButtonFormField<ActivityLevel>(
            initialValue: profile.activityLevel,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Activity level'),
            items: <DropdownMenuItem<ActivityLevel>>[
              for (final ActivityLevel a in ActivityLevel.values)
                DropdownMenuItem<ActivityLevel>(
                  value: a,
                  child: Text('${a.label} (×${a.multiplier})',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (ActivityLevel? a) {
              if (a != null) save(profile.copyWith(activityLevel: a));
            },
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              profile.activityLevel.description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 14),
          SegmentedButton<WeightGoal>(
            segments: <ButtonSegment<WeightGoal>>[
              for (final WeightGoal g in WeightGoal.values)
                ButtonSegment<WeightGoal>(value: g, label: Text(g.label)),
            ],
            selected: <WeightGoal>{profile.goal},
            showSelectedIcon: false,
            onSelectionChanged: (Set<WeightGoal> s) =>
                save(profile.copyWith(goal: s.first)),
          ),
          if (profile.goal != WeightGoal.maintain) ...<Widget>[
            const SizedBox(height: 14),
            NumberField(
              label: 'Rate',
              suffix: 'kg / week',
              decimals: 2,
              value: profile.rateKgPerWeek,
              helper: '0.5 kg/week is the usual safe ceiling. '
                  'The deficit is capped so your budget never drops below BMR.',
              onChanged: (double v) =>
                  save(profile.copyWith(rateKgPerWeek: v.abs())),
            ),
          ],
          const SizedBox(height: 14),
          DropdownButtonFormField<BmrFormula>(
            initialValue: profile.bmrFormula,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'BMR formula'),
            items: <DropdownMenuItem<BmrFormula>>[
              for (final BmrFormula f in BmrFormula.values)
                DropdownMenuItem<BmrFormula>(
                    value: f,
                    child: Text(f.label, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (BmrFormula? f) {
              if (f != null) save(profile.copyWith(bmrFormula: f));
            },
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              profile.bmrFormula.description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsCard extends StatelessWidget {
  const _ResultsCard({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final double bmr = TargetCalculator.bmr(profile);
    final double tdee = TargetCalculator.tdee(profile);
    final double budget = TargetCalculator.energyBudget(profile);
    final double adjustment = TargetCalculator.energyAdjustment(profile);

    return SectionCard(
      title: 'What that works out to',
      trailing: TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const TargetsPage()),
        ),
        child: const Text('Details'),
      ),
      child: Column(
        children: <Widget>[
          StatRow(
            tiles: <Widget>[
              StatTile(
                label: 'BMR',
                value: Fmt.energy(bmr),
                caption: 'at rest',
              ),
              StatTile(
                label: 'TDEE',
                value: Fmt.energy(tdee),
                caption: 'burned daily',
              ),
              StatTile(
                label: 'Budget',
                value: Fmt.energy(budget),
                caption: adjustment == 0
                    ? 'maintain'
                    : '${adjustment > 0 ? '+' : ''}${adjustment.round()} kcal',
                color: AppTheme.energy,
              ),
            ],
          ),
          const Divider(height: 26),
          StatRow(
            tiles: <Widget>[
              for (final Nutrient n in Nutrient.macros)
                StatTile(
                  label: n.shortLabel,
                  value: Fmt.amount(
                    n,
                    TargetCalculator.build(profile, date: DateTime.now())
                        .amountFor(n),
                  ),
                ),
              StatTile(
                label: 'Water',
                value: Fmt.volume(
                    TargetCalculator.water(profile).drinkingTargetMl),
                color: AppTheme.water,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MacroSection extends StatelessWidget {
  const _MacroSection({required this.profile, required this.save});

  final UserProfile profile;
  final Future<void> Function(UserProfile) save;

  @override
  Widget build(BuildContext context) {
    final bool hasBodyFat = profile.leanBodyMassKg != null;

    return SectionCard(
      title: 'Macro split',
      child: Column(
        children: <Widget>[
          NumberField(
            label: 'Protein',
            suffix: 'g / kg',
            decimals: 2,
            value: profile.proteinGPerKg,
            helper: '0.8 sedentary · 1.6 active · 2.2 building muscle. '
                'If a doctor has capped your protein, set that as an override '
                'in All nutrients instead.',
            onChanged: (double v) => save(profile.copyWith(proteinGPerKg: v)),
          ),
          const SizedBox(height: 12),
          SegmentedButton<ProteinBasis>(
            segments: <ButtonSegment<ProteinBasis>>[
              for (final ProteinBasis b in ProteinBasis.values)
                ButtonSegment<ProteinBasis>(
                  value: b,
                  label: Text(b.label),
                  enabled: b == ProteinBasis.bodyWeight || hasBodyFat,
                ),
            ],
            selected: <ProteinBasis>{profile.proteinBasis},
            showSelectedIcon: false,
            onSelectionChanged: (Set<ProteinBasis> s) =>
                save(profile.copyWith(proteinBasis: s.first)),
          ),
          if (!hasBodyFat)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Add your body fat % above to use lean mass.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),
          const SizedBox(height: 14),
          NumberField(
            label: 'Fat',
            suffix: '% of energy',
            decimals: 0,
            value: profile.fatPercentOfEnergy * 100,
            helper: '20-35% is the usual range. Carbs take whatever energy '
                'is left after protein and fat.',
            onChanged: (double v) => save(profile.copyWith(
                fatPercentOfEnergy: (v / 100).clamp(0.05, 0.8))),
          ),
          const SizedBox(height: 12),
          NumberField(
            label: 'Calorie budget override',
            suffix: 'kcal',
            decimals: 0,
            allowEmpty: true,
            value: profile.energyOverrideKcal,
            helper: 'Leave empty to use the calculated budget above.',
            onChanged: (double v) =>
                save(profile.copyWith(energyOverrideKcal: v)),
            onCleared: () => save(profile.copyWith(clearEnergyOverride: true)),
          ),
        ],
      ),
    );
  }
}

class _WaterSection extends StatelessWidget {
  const _WaterSection({required this.profile, required this.save});

  final UserProfile profile;
  final Future<void> Function(UserProfile) save;

  @override
  Widget build(BuildContext context) {
    final WaterTarget w = TargetCalculator.water(profile);

    return SectionCard(
      title: 'Water',
      subtitle: 'Target right now: ${Fmt.volume(w.drinkingTargetMl)} to drink.',
      child: Column(
        children: <Widget>[
          NumberField(
            label: 'Baseline',
            suffix: 'ml / kg',
            decimals: 0,
            value: profile.waterMlPerKg,
            helper: '35 ml/kg is the standard adult figure. '
                'Raise it only if a doctor has told you to.',
            onChanged: (double v) => save(profile.copyWith(waterMlPerKg: v)),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: NumberField(
                  label: 'Exercise',
                  suffix: 'min / day',
                  decimals: 0,
                  value: profile.dailyExerciseMinutes.toDouble(),
                  onChanged: (double v) => save(
                      profile.copyWith(dailyExerciseMinutes: v.round().abs())),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NumberField(
                  label: 'Per minute',
                  suffix: 'ml',
                  decimals: 0,
                  value: profile.waterMlPerExerciseMinute,
                  onChanged: (double v) =>
                      save(profile.copyWith(waterMlPerExerciseMinute: v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<Climate>(
            initialValue: profile.climate,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Climate'),
            items: <DropdownMenuItem<Climate>>[
              for (final Climate c in Climate.values)
                DropdownMenuItem<Climate>(
                  value: c,
                  child: Text(c.extraWaterMl == 0
                      ? c.label
                      : '${c.label} (+${c.extraWaterMl} ml)'),
                ),
            ],
            onChanged: (Climate? c) {
              if (c != null) save(profile.copyWith(climate: c));
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Count water from food'),
            subtitle: const Text(
              'Subtracts the water in what you eat from the amount you have '
              'to drink. Only accurate if you log the water content of your '
              'foods.',
            ),
            isThreeLine: true,
            value: profile.countFoodWaterTowardsTarget,
            onChanged: (bool v) =>
                save(profile.copyWith(countFoodWaterTowardsTarget: v)),
          ),
        ],
      ),
    );
  }
}

class _ReminderSection extends ConsumerWidget {
  const _ReminderSection({required this.profile, required this.save});

  final UserProfile profile;
  final Future<void> Function(UserProfile) save;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final int effective = NotificationService.effectiveIntervalMinutes(profile);
    final int count = NotificationService.buildSlots(profile).length;
    final bool stretched = effective != profile.reminderIntervalMinutes;

    Future<void> pickTime(bool wake) async {
      final int minutes =
          wake ? profile.wakeMinuteOfDay : profile.sleepMinuteOfDay;
      final TimeOfDay? picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      );
      if (picked == null) return;
      final int value = picked.hour * 60 + picked.minute;
      await save(wake
          ? profile.copyWith(wakeMinuteOfDay: value)
          : profile.copyWith(sleepMinuteOfDay: value));
    }

    return SectionCard(
      title: 'Water reminders',
      child: Column(
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Remind me to drink'),
            subtitle: Text(profile.remindersEnabled
                ? '$count reminders a day, spread across your waking hours'
                : 'Off'),
            value: profile.remindersEnabled,
            onChanged: (bool v) async {
              if (v) {
                final bool granted = await ref
                    .read(notificationServiceProvider)
                    .requestPermissions();
                if (!granted) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Notifications are blocked. Turn them on in the '
                          'iOS Settings app, under Notifications, HydraFuel.',
                        ),
                      ),
                    );
                  }
                  return;
                }
              }
              await save(profile.copyWith(remindersEnabled: v));
            },
          ),
          if (profile.remindersEnabled) ...<Widget>[
            const Divider(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Wake'),
                    subtitle: Text(Fmt.timeOfDay(profile.wakeMinuteOfDay)),
                    onTap: () => pickTime(true),
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sleep'),
                    subtitle: Text(Fmt.timeOfDay(profile.sleepMinuteOfDay)),
                    onTap: () => pickTime(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            NumberField(
              label: 'Reminder every',
              suffix: 'minutes',
              decimals: 0,
              value: profile.reminderIntervalMinutes.toDouble(),
              helper: stretched
                  ? 'Stretched to $effective minutes: iOS holds at most '
                      '${NotificationService.maxReminders} scheduled reminders, '
                      'and anything closer together would lose the evening ones.'
                  : 'Minimum ${NotificationService.minIntervalMinutes} minutes.',
              onChanged: (double v) => save(
                  profile.copyWith(reminderIntervalMinutes: v.round().abs())),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ReminderSchedulePage(),
                      ),
                    ),
                    child: const Text('See schedule'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await ref
                          .read(notificationServiceProvider)
                          .showTestNotification();
                    },
                    child: const Text('Send a test'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Reminders are scheduled on the phone itself, so they fire with '
              'no internet connection.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _DataSection extends ConsumerWidget {
  const _DataSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return SectionCard(
      title: 'Your data',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Everything lives on this phone. There is no account and nothing '
            'is sent anywhere. That also means an export is your only backup.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            icon: const Icon(Icons.ios_share),
            label: const Text('Export a backup'),
            onPressed: () async {
              final String json =
                  await ref.read(backupServiceProvider).export();
              await Share.share(
                json,
                subject:
                    'HydraFuel backup ${DateTime.now().toIso8601String().split('T').first}',
              );
            },
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.download_outlined),
            label: const Text('Restore from a backup'),
            onPressed: () => _restore(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final TextEditingController controller = TextEditingController();

    final String? json = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Restore'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'Paste the backup here. This replaces every food and every '
              'logged day currently on this phone.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 5,
              decoration:
                  const InputDecoration(hintText: '{ "formatVersion" …'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Replace everything'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (json == null || json.trim().isEmpty) return;

    try {
      final Object result = await ref.read(backupServiceProvider).restore(json);
      // The restore wrote straight to the database, so pull the profile back
      // into memory and refresh everything derived from the tables.
      await ref.read(profileProvider.notifier).reload();
      ref.invalidate(foodListProvider);
      ref.invalidate(daySummaryProvider);
      ref.invalidate(historyProvider);
      ref.invalidate(drinkPresetsProvider);
      ref.invalidate(bloodResultsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$result')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not restore: $e')));
      }
    }
  }
}
