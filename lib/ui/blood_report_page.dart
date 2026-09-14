import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatting.dart';
import '../core/theme.dart';
import '../domain/blood_marker.dart';
import '../domain/clinical_flags.dart';
import '../state/providers.dart';
import 'blood_draw_entry_page.dart';
import 'widgets/section_card.dart';

/// Your blood results, and what the app did about them.
class BloodReportPage extends ConsumerWidget {
  const BloodReportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<MarkerSnapshot> snapshot =
        ref.watch(markerSnapshotProvider);
    final AsyncValue<ClinicalAssessment> assessment =
        ref.watch(assessmentProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Blood report')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-add-results',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const BloodDrawEntryPage()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add results'),
      ),
      body: snapshot.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace st) => Center(child: Text('$e')),
        data: (MarkerSnapshot snap) {
          if (snap.isEmpty) return const _EmptyReport();
          return _ReportBody(
            snapshot: snap,
            assessment: assessment.valueOrNull ?? ClinicalAssessment.none,
          );
        },
      ),
    );
  }
}

class _EmptyReport extends StatelessWidget {
  const _EmptyReport();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.science_outlined,
                size: 42, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              'No results recorded yet.',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Type in the numbers from your last blood panel and the app '
              'will move the targets that your results actually justify — '
              'and say which ones it moved, and why.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const BloodDrawEntryPage()),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add results'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.snapshot, required this.assessment});

  final MarkerSnapshot snapshot;
  final ClinicalAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime? drawn = snapshot.lastDrawDate;
    final List<BloodResult> flagged = snapshot.outOfRange;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[
        SectionCard(
          title: drawn == null ? 'Latest results' : Fmt.longDate(drawn),
          subtitle: flagged.isEmpty
              ? 'Everything recorded is inside its reference range.'
              : '${flagged.length} of ${snapshot.latest.length} markers are '
                  'outside their reference range.',
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: const SizedBox.shrink(),
        ),
        if (assessment.needsDoctor) ...<Widget>[
          const SizedBox(height: 14),
          _MedicalCard(findings: assessment.medical),
        ],
        if (assessment.nutritional.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          _AdjustmentsCard(findings: assessment.nutritional),
        ],
        const SizedBox(height: 14),
        for (final MarkerPanel panel in MarkerPanel.values)
          Builder(builder: (BuildContext context) {
            final List<BloodMarker> recorded = BloodMarker.inPanel(panel)
                .where(snapshot.has)
                .toList(growable: false);
            if (recorded.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: SectionCard(
                title: panel.label,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  children: <Widget>[
                    for (final BloodMarker m in recorded)
                      _ResultRow(result: snapshot.resultFor(m)!),
                  ],
                ),
              ),
            );
          }),
        Text(
          'Reference intervals follow those printed on Indian pathology '
          'panels. This app is a tracker, not a diagnosis — take the report '
          'itself to a doctor.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _MedicalCard extends StatelessWidget {
  const _MedicalCard({required this.findings});

  final List<ClinicalFinding> findings;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      color: AppTheme.danger.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.medical_services_outlined,
                    color: AppTheme.danger, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Show these to a doctor',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.danger,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'These are not things eating differently will fix, and the app '
              'will not pretend otherwise.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            for (final ClinicalFinding f in findings)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      f.flag.label,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(f.detail, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 2),
                    Text(
                      f.flag.effect,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AdjustmentsCard extends StatelessWidget {
  const _AdjustmentsCard({required this.findings});

  final List<ClinicalFinding> findings;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SectionCard(
      title: 'What this changed',
      subtitle: 'Your targets, moved off the general-population defaults.',
      child: Column(
        children: <Widget>[
          for (final ClinicalFinding f in findings)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(Icons.tune, size: 16, color: AppTheme.warning),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          f.flag.label,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(f.detail, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    f.flag.effect,
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

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.result});

  final BloodResult result;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final BloodMarker m = result.marker;

    final Color color;
    switch (result.status) {
      case MarkerStatus.normal:
        color = AppTheme.good;
      case MarkerStatus.low:
        color = AppTheme.warning;
      case MarkerStatus.high:
        color = AppTheme.danger;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  m.label,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  'Reference ${m.rangeLabel}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                if (m.note.isNotEmpty && result.isOutOfRange)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      m.note,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                '${Fmt.number(result.value, result.value < 10 ? 2 : 0)} '
                '${m.unit}',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  result.status.label,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: color, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
