import 'package:flutter/material.dart';

import '../../core/formatting.dart';
import '../../core/theme.dart';
import '../../domain/nutrients.dart';
import '../../domain/targets.dart';

/// One nutrient's progress towards its target.
///
/// A limit that has been breached turns red, and a goal that is met turns
/// green, so the row itself says whether the number is good news.
class NutrientBar extends StatelessWidget {
  const NutrientBar({
    super.key,
    required this.nutrient,
    required this.consumed,
    required this.target,
    this.color,
    this.onTap,
    this.dense = false,
  });

  final Nutrient nutrient;
  final double consumed;
  final NutrientTarget? target;
  final Color? color;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final NutrientTarget? t = target;

    final double progress =
        t == null || t.amount <= 0 ? 0.0 : consumed / t.amount;
    final bool exceeded = t != null && t.isExceededBy(consumed);
    final bool met = t != null && t.kind != TargetKind.limit && progress >= 1.0;

    final Color barColor = exceeded
        ? AppTheme.danger
        : met
            ? AppTheme.good
            : (color ?? theme.colorScheme.primary);

    final String trailing = t == null
        ? Fmt.amount(nutrient, consumed)
        : '${Fmt.bare(nutrient, consumed)} / ${Fmt.amount(nutrient, t.amount)}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 4,
          vertical: dense ? 6 : 9,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    nutrient.label,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  trailing,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: exceeded
                        ? AppTheme.danger
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: exceeded ? FontWeight.w700 : FontWeight.w500,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
            if (t != null) ...<Widget>[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: dense ? 5 : 7,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The colour convention used for macros throughout the app.
Color colorForNutrient(Nutrient n, BuildContext context) {
  switch (n) {
    case Nutrient.energy:
      return AppTheme.energy;
    case Nutrient.protein:
      return AppTheme.protein;
    case Nutrient.carbs:
      return AppTheme.carbs;
    case Nutrient.fat:
      return AppTheme.fat;
    case Nutrient.fiber:
      return AppTheme.fiber;
    default:
      return Theme.of(context).colorScheme.primary;
  }
}
