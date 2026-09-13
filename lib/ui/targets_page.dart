import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatting.dart';
import '../domain/daily_summary.dart';
import '../domain/nutrients.dart';
import '../domain/profile.dart';
import '../domain/targets.dart';
import '../state/providers.dart';
import 'widgets/nutrient_bar.dart';
import 'widgets/section_card.dart';

/// Every tracked nutrient against its target, with the reasoning behind each
/// number and a way to override it.
///
/// This is where a blood report turns into settings: tap a nutrient, read why
/// the default is what it is, and replace it with what your doctor asked for.
class TargetsPage extends ConsumerWidget {
  const TargetsPage({super.key});

  static const List<NutrientGroup> _order = <NutrientGroup>[
    NutrientGroup.energy,
    NutrientGroup.macro,
    NutrientGroup.carbQuality,
    NutrientGroup.lipid,
    NutrientGroup.mineral,
    NutrientGroup.vitamin,
    NutrientGroup.other,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<DaySummary> async = ref.watch(todayProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('All nutrients')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace st) => Center(child: Text('$e')),
        data: (DaySummary day) {
          final DailyTargets t = day.targets;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: <Widget>[
              for (final NutrientGroup g in _order)
                Builder(builder: (BuildContext context) {
                  final List<Nutrient> tracked = Nutrient.inGroup(g)
                      .where((Nutrient n) =>
                          t.nutrients.containsKey(n) || day.totals.has(n))
                      .toList();
                  if (tracked.isEmpty) return const SizedBox.shrink();

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: SectionCard(
                      title: g.label,
                      child: Column(
                        children: <Widget>[
                          for (final Nutrient n in tracked)
                            NutrientBar(
                              nutrient: n,
                              consumed: day.consumed(n),
                              target: t[n],
                              color: colorForNutrient(n, context),
                              dense: true,
                              onTap: () => _showDetail(context, ref, day, n),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  void _showDetail(
      BuildContext context, WidgetRef ref, DaySummary day, Nutrient n) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) =>
          _NutrientDetailSheet(nutrient: n, day: day),
    );
  }
}

class _NutrientDetailSheet extends ConsumerWidget {
  const _NutrientDetailSheet({required this.nutrient, required this.day});

  final Nutrient nutrient;
  final DaySummary day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final NutrientTarget? t = day.targets[nutrient];
    final double consumed = day.consumed(nutrient);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              nutrient.label,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                StatTile(
                  label: 'Today',
                  value: Fmt.amount(nutrient, consumed),
                ),
                if (t != null)
                  StatTile(
                    label: t.kind == TargetKind.limit ? 'Ceiling' : 'Target',
                    value: Fmt.amount(nutrient, t.amount),
                  ),
                if (t != null)
                  StatTile(
                    label: t.kind == TargetKind.limit ? 'Headroom' : 'Left',
                    value: Fmt.amount(nutrient, t.remainingFrom(consumed)),
                  ),
              ],
            ),
            if (t != null) ...<Widget>[
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      t.isOverride ? 'Your override' : 'How this is worked out',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(t.rationale, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () => _editOverride(context, ref, t),
                      child: Text(t.isOverride
                          ? 'Change override'
                          : 'Set my own target'),
                    ),
                  ),
                  if (t.isOverride) ...<Widget>[
                    const SizedBox(width: 10),
                    IconButton(
                      tooltip: 'Remove override',
                      icon: const Icon(Icons.restart_alt),
                      onPressed: () {
                        final UserProfile p = ref.read(profileProvider);
                        final Map<Nutrient, double> next =
                            Map<Nutrient, double>.of(p.customTargets)
                              ..remove(nutrient);
                        ref
                            .read(profileProvider.notifier)
                            .save(p.copyWith(customTargets: next));
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _editOverride(
      BuildContext context, WidgetRef ref, NutrientTarget t) async {
    final TextEditingController controller = TextEditingController(
      text: Fmt.bare(nutrient, t.amount),
    );

    final double? value = await showDialog<double>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('Target for ${nutrient.label}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: nutrient.unit.symbol),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx)
                .pop(double.tryParse(controller.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (value == null || value <= 0) return;
    if (!context.mounted) return;

    final UserProfile p = ref.read(profileProvider);
    final Map<Nutrient, double> next =
        Map<Nutrient, double>.of(p.customTargets)..[nutrient] = value;
    await ref.read(profileProvider.notifier).save(p.copyWith(customTargets: next));

    if (context.mounted) Navigator.of(context).pop();
  }
}
