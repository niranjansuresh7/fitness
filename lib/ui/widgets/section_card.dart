import 'package:flutter/material.dart';

/// A titled card. Used everywhere so spacing stays consistent.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.trailing,
    this.subtitle,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? titleText = title;
    final String? subtitleText = subtitle;

    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (titleText != null) ...<Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      titleText,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              if (subtitleText != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  subtitleText,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// A row of [StatTile]s that shares the width evenly.
///
/// Phone screens are about 390 points wide, and three or four stat tiles laid
/// out at their natural size overflow that. Giving each an equal [Expanded]
/// share, and letting the value scale down inside it, keeps the row intact at
/// every width instead of clipping the last tile.
class StatRow extends StatelessWidget {
  const StatRow({super.key, required this.tiles, this.spacing = 8});

  final List<Widget> tiles;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < tiles.length; i++) ...<Widget>[
          if (i > 0) SizedBox(width: spacing),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }
}

/// A short label above a value, used in the stat rows.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.caption,
  });

  final String label;
  final String value;
  final String? caption;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? captionText = caption;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        // Numbers shrink rather than truncate: a clipped figure would be
        // actively misleading, a slightly smaller one is not.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (captionText != null)
          Text(
            captionText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }
}
