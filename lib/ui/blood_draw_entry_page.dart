import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatting.dart';
import '../core/theme.dart';
import '../domain/blood_marker.dart';
import '../state/providers.dart';
import 'widgets/section_card.dart';

/// Type in the numbers from one blood panel.
///
/// Everything is optional — fill in only the markers your panel actually
/// covered. A blank field records nothing rather than recording a zero.
class BloodDrawEntryPage extends ConsumerStatefulWidget {
  const BloodDrawEntryPage({super.key, this.initialDate});

  final DateTime? initialDate;

  @override
  ConsumerState<BloodDrawEntryPage> createState() => _BloodDrawEntryPageState();
}

class _BloodDrawEntryPageState extends ConsumerState<BloodDrawEntryPage> {
  final Map<BloodMarker, TextEditingController> _fields =
      <BloodMarker, TextEditingController>{};

  late DateTime _takenOn;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    _takenOn = widget.initialDate ?? DateTime.now();
    for (final BloodMarker m in BloodMarker.values) {
      _fields[m] = TextEditingController();
    }
  }

  /// Pre-fill from the last recorded draw so a re-test only needs the numbers
  /// that changed to be retyped.
  void _prefillFrom(MarkerSnapshot snapshot) {
    if (_prefilled || snapshot.isEmpty) return;
    _prefilled = true;
    for (final MapEntry<BloodMarker, BloodResult> e
        in snapshot.latest.entries) {
      _fields[e.key]?.text = _trim(e.value.value);
    }
  }

  static String _trim(double v) {
    final String s = v.toStringAsFixed(2);
    if (!s.contains('.')) return s;
    return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  @override
  void dispose() {
    for (final TextEditingController c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<BloodMarker, double> _values() {
    final Map<BloodMarker, double> out = <BloodMarker, double>{};
    _fields.forEach((BloodMarker m, TextEditingController c) {
      final String text = c.text.trim();
      if (text.isEmpty) return;
      final double? v = double.tryParse(text);
      if (v != null) out[m] = v;
    });
    return out;
  }

  Future<void> _save() async {
    final Map<BloodMarker, double> values = _values();
    if (values.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill in at least one marker.')),
      );
      return;
    }

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await ref.read(actionsProvider).saveBloodDraw(_takenOn, values);
    if (!mounted) return;

    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Saved ${values.length} '
            '${values.length == 1 ? 'result' : 'results'} '
            'from ${Fmt.date(_takenOn)}'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Map<BloodMarker, double> entered = _values();

    ref.listen<AsyncValue<MarkerSnapshot>>(markerSnapshotProvider,
        (AsyncValue<MarkerSnapshot>? _, AsyncValue<MarkerSnapshot> next) {
      final MarkerSnapshot? snap = next.valueOrNull;
      if (snap != null && widget.initialDate == null) {
        setState(() => _prefillFrom(snap));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Add results')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: <Widget>[
          SectionCard(
            title: 'When was the blood drawn?',
            subtitle: 'Targets always follow your most recent draw.',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(Fmt.longDate(_takenOn)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final DateTime now = DateTime.now();
                final DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate: _takenOn,
                  firstDate: DateTime(now.year - 20),
                  lastDate: now,
                );
                if (picked != null) setState(() => _takenOn = picked);
              },
            ),
          ),
          const SizedBox(height: 14),
          for (final MarkerPanel panel in MarkerPanel.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: SectionCard(
                title: panel.label,
                child: Column(
                  children: <Widget>[
                    for (final BloodMarker m in BloodMarker.inPanel(panel))
                      _MarkerField(
                        marker: m,
                        controller: _fields[m]!,
                        onChanged: () => setState(() {}),
                      ),
                  ],
                ),
              ),
            ),
          Text(
            'Leave anything your panel did not cover blank — a blank field '
            'records nothing, which is different from recording a zero.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: FilledButton(
          onPressed: entered.isEmpty ? null : _save,
          child: Text(entered.isEmpty
              ? 'Fill in at least one marker'
              : 'Save ${entered.length} '
                  '${entered.length == 1 ? 'result' : 'results'}'),
        ),
      ),
    );
  }
}

class _MarkerField extends StatelessWidget {
  const _MarkerField({
    required this.marker,
    required this.controller,
    required this.onChanged,
  });

  final BloodMarker marker;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double? value = double.tryParse(controller.text.trim());
    final MarkerStatus? status = value == null ? null : marker.statusOf(value);

    Color? statusColor;
    if (status == MarkerStatus.high) statusColor = AppTheme.danger;
    if (status == MarkerStatus.low) statusColor = AppTheme.warning;
    if (status == MarkerStatus.normal) statusColor = AppTheme.good;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 3,
            child: TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                labelText: marker.label,
                suffixText: marker.unit,
                isDense: true,
                helperText: 'Ref ${marker.rangeLabel}',
                helperMaxLines: 2,
              ),
            ),
          ),
          if (status != null) ...<Widget>[
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor?.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
