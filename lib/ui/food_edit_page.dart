import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../domain/food_item.dart';
import '../domain/nutrients.dart';
import '../domain/nutrition.dart';
import '../state/providers.dart';
import 'widgets/section_card.dart';

/// What the numbers being typed in refer to.
enum EntryBasis { per100g, per100ml, perServing }

/// Create or edit a food in your library.
///
/// Values are entered on whatever basis the packet uses and normalised to
/// per 100 g once, on save. Everything downstream then deals only in weight.
class FoodEditPage extends ConsumerStatefulWidget {
  const FoodEditPage({super.key, this.existing});

  final FoodItem? existing;

  @override
  ConsumerState<FoodEditPage> createState() => _FoodEditPageState();
}

class _FoodEditPageState extends ConsumerState<FoodEditPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _brand;
  late final TextEditingController _note;
  late final TextEditingController _servingName;
  late final TextEditingController _servingGrams;
  late final TextEditingController _density;

  final Map<Nutrient, TextEditingController> _fields =
      <Nutrient, TextEditingController>{};

  EntryBasis _basis = EntryBasis.per100g;
  bool _isLiquid = false;
  bool _favorite = false;

  static const List<NutrientGroup> _groupOrder = <NutrientGroup>[
    NutrientGroup.energy,
    NutrientGroup.macro,
    NutrientGroup.carbQuality,
    NutrientGroup.lipid,
    NutrientGroup.mineral,
    NutrientGroup.vitamin,
    NutrientGroup.other,
  ];

  @override
  void initState() {
    super.initState();
    final FoodItem? f = widget.existing;

    _name = TextEditingController(text: f?.name ?? '');
    _brand = TextEditingController(text: f?.brand ?? '');
    _note = TextEditingController(text: f?.note ?? '');
    _servingName = TextEditingController(text: f?.servingName ?? '');
    _servingGrams = TextEditingController(
        text: f?.servingGrams == null ? '' : _trim(f!.servingGrams!));
    _density = TextEditingController(
        text: f?.densityGPerMl == null ? '' : _trim(f!.densityGPerMl!));
    _isLiquid = f?.isLiquid ?? false;
    _favorite = f?.favorite ?? false;

    for (final Nutrient n in Nutrient.values) {
      final double? v = f?.per100g.lookup(n);
      _fields[n] = TextEditingController(text: v == null ? '' : _trim(v));
    }
  }

  static String _trim(double v) {
    final String s = v.toStringAsFixed(4);
    return s.contains('.')
        ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : s;
  }

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _note.dispose();
    _servingName.dispose();
    _servingGrams.dispose();
    _density.dispose();
    for (final TextEditingController c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  double? get _servingGramsValue => double.tryParse(_servingGrams.text.trim());

  double? get _densityValue => double.tryParse(_density.text.trim());

  /// The weight in grams that the typed figures describe.
  double? get _basisGrams {
    switch (_basis) {
      case EntryBasis.per100g:
        return 100.0;
      case EntryBasis.per100ml:
        final double? d = _densityValue;
        return d == null || d <= 0 ? null : 100.0 * d;
      case EntryBasis.perServing:
        final double? g = _servingGramsValue;
        return g == null || g <= 0 ? null : g;
    }
  }

  /// The typed values, still on their entry basis.
  NutritionFacts _typedFacts() {
    final Map<Nutrient, double> out = <Nutrient, double>{};
    _fields.forEach((Nutrient n, TextEditingController c) {
      final String text = c.text.trim();
      if (text.isEmpty) return;
      final double? v = double.tryParse(text);
      if (v != null) out[n] = v;
    });
    return NutritionFacts(out);
  }

  FoodItem? _buildFood() {
    final double? basis = _basisGrams;
    if (basis == null) return null;

    return FoodItem(
      id: widget.existing?.id,
      name: _name.text.trim(),
      brand: _brand.text.trim(),
      note: _note.text.trim(),
      per100g: NutritionFacts.toPer100g(_typedFacts(), basisGrams: basis),
      servingName: _servingName.text.trim(),
      servingGrams: _servingGramsValue,
      densityGPerMl: _densityValue,
      isLiquid: _isLiquid,
      favorite: _favorite,
      useCount: widget.existing?.useCount ?? 0,
      createdAt: widget.existing?.createdAt,
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final FoodItem? food = _buildFood();
    if (food == null) {
      _snack('Fill in the serving weight or density first.');
      return;
    }

    final List<String> problems = food.validate();
    if (problems.isNotEmpty) {
      final bool? proceed = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('Check these numbers'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final String p in problems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('• $p'),
                ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Go back'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    await ref.read(actionsProvider).saveFood(food);
    if (mounted) Navigator.of(context).pop();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmDelete() async {
    final int? id = widget.existing?.id;
    if (id == null) return;

    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('Delete ${widget.existing!.name}?'),
        content: const Text(
          'It is removed from your library. Meals you have already logged '
          'from it keep their own nutrition and are not affected.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (yes != true) return;
    await ref.read(actionsProvider).deleteFood(id);
    if (mounted) Navigator.of(context).pop();
  }

  String get _basisHint {
    switch (_basis) {
      case EntryBasis.per100g:
        return 'Type the figures exactly as the packet prints them per 100 g.';
      case EntryBasis.per100ml:
        final double? d = _densityValue;
        return d == null
            ? 'Enter a density below so millilitres can be converted to grams.'
            : '100 ml of this weighs ${(100 * d).toStringAsFixed(0)} g. '
                'Values will be converted to per 100 g on save.';
      case EntryBasis.perServing:
        final double? g = _servingGramsValue;
        return g == null
            ? 'Enter the serving weight below so this can be converted.'
            : 'One serving weighs ${g.toStringAsFixed(0)} g. '
                'Values will be converted to per 100 g on save.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool editing = widget.existing != null;
    final FoodItem? preview = _buildFood();
    final List<String> problems = preview?.validate() ?? const <String>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit food' : 'New food'),
        actions: <Widget>[
          IconButton(
            icon: Icon(_favorite ? Icons.star : Icons.star_border),
            tooltip: 'Favourite',
            onPressed: () => setState(() => _favorite = !_favorite),
          ),
          if (editing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
          children: <Widget>[
            SectionCard(
              title: 'What is it?',
              child: Column(
                children: <Widget>[
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (String? v) =>
                        (v ?? '').trim().isEmpty ? 'Give it a name' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _brand,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Brand (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _note,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Portions',
              subtitle: 'Optional, but they make daily logging much faster.',
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _servingName,
                          decoration: const InputDecoration(
                            labelText: 'Serving name',
                            hintText: '1 roti',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _servingGrams,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Weighs',
                            suffixText: 'g',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('This is a liquid'),
                    subtitle: const Text('Lets you log it by millilitres'),
                    value: _isLiquid,
                    onChanged: (bool v) => setState(() => _isLiquid = v),
                  ),
                  if (_isLiquid)
                    TextFormField(
                      controller: _density,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Density',
                        suffixText: 'g/ml',
                        helperText: 'Water 1.0, milk 1.03, cooking oil 0.92',
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Nutrition',
              subtitle: _basisHint,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SegmentedButton<EntryBasis>(
                    segments: <ButtonSegment<EntryBasis>>[
                      const ButtonSegment<EntryBasis>(
                        value: EntryBasis.per100g,
                        label: Text('Per 100 g'),
                      ),
                      if (_isLiquid)
                        const ButtonSegment<EntryBasis>(
                          value: EntryBasis.per100ml,
                          label: Text('Per 100 ml'),
                        ),
                      const ButtonSegment<EntryBasis>(
                        value: EntryBasis.perServing,
                        label: Text('Per serving'),
                      ),
                    ],
                    selected: <EntryBasis>{_basis},
                    showSelectedIcon: false,
                    onSelectionChanged: (Set<EntryBasis> s) =>
                        setState(() => _basis = s.first),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (problems.isNotEmpty) ...<Widget>[
              Card(
                color: AppTheme.warning.withValues(alpha: 0.10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Icon(Icons.info_outline,
                              size: 18, color: AppTheme.warning),
                          const SizedBox(width: 8),
                          Text(
                            'Worth a second look',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.warning,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final String p in problems)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('• $p', style: theme.textTheme.bodySmall),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            for (final NutrientGroup g in _groupOrder)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: SectionCard(
                  title: g.label,
                  child: Column(
                    children: <Widget>[
                      for (final Nutrient n in Nutrient.inGroup(g))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: TextFormField(
                            controller: _fields[n],
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: n.label,
                              suffixText: n.unit.symbol,
                              isDense: true,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: FilledButton(
          onPressed: _save,
          child: Text(editing ? 'Save changes' : 'Add to library'),
        ),
      ),
    );
  }
}
