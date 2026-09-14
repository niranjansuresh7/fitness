import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dates.dart';
import '../core/formatting.dart';
import '../domain/food_item.dart';
import '../domain/log_entry.dart';
import '../domain/nutrients.dart';
import '../domain/nutrition.dart';
import '../state/providers.dart';
import 'food_edit_page.dart';
import 'widgets/nutrient_bar.dart';
import 'widgets/section_card.dart';

/// Step one of logging: pick the food.
class LogFoodPage extends ConsumerStatefulWidget {
  const LogFoodPage({super.key, this.meal});

  final MealType? meal;

  @override
  ConsumerState<LogFoodPage> createState() => _LogFoodPageState();
}

class _LogFoodPageState extends ConsumerState<LogFoodPage> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<FoodItem>> async =
        ref.watch(foodListProvider(_query));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log food'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New food',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const FoodEditPage()),
            ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _search,
              onChanged: (String v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search your foods',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object e, StackTrace st) => Center(child: Text('$e')),
              data: (List<FoodItem> foods) {
                if (foods.isEmpty) {
                  return _EmptyLibrary(query: _query);
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 32),
                  itemCount: foods.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int i) {
                    final FoodItem f = foods[i];
                    return ListTile(
                      title: Text(f.displayName),
                      subtitle: Text(
                        '${Fmt.energy(f.per100g[Nutrient.energy])} · '
                        'P ${Fmt.bare(Nutrient.protein, f.per100g[Nutrient.protein])} · '
                        'C ${Fmt.bare(Nutrient.carbs, f.per100g[Nutrient.carbs])} · '
                        'F ${Fmt.bare(Nutrient.fat, f.per100g[Nutrient.fat])} '
                        'per 100 g',
                      ),
                      trailing:
                          f.favorite ? const Icon(Icons.star, size: 18) : null,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              LogAmountPage(food: f, meal: widget.meal),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.no_food_outlined,
                size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              query.isEmpty
                  ? 'Your library is empty.'
                  : 'No food matches "$query".',
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const FoodEditPage()),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add a food'),
            ),
          ],
        ),
      ),
    );
  }
}

/// How the amount is being entered.
enum AmountMode { grams, servings, millilitres }

/// Step two: say how much, and see exactly what it contributes before logging.
class LogAmountPage extends ConsumerStatefulWidget {
  const LogAmountPage({super.key, required this.food, this.meal, this.editing});

  final FoodItem food;
  final MealType? meal;

  /// When set, the page edits an existing entry rather than creating one.
  final LogEntry? editing;

  @override
  ConsumerState<LogAmountPage> createState() => _LogAmountPageState();
}

class _LogAmountPageState extends ConsumerState<LogAmountPage> {
  late final TextEditingController _amount;
  late AmountMode _mode;
  late MealType _meal;

  @override
  void initState() {
    super.initState();
    final LogEntry? editing = widget.editing;
    _amount = TextEditingController(
      text: editing != null
          ? Fmt.number(editing.grams, 1)
          : (widget.food.servingGrams != null ? '1' : '100'),
    );
    _mode = editing == null && widget.food.servingGrams != null
        ? AmountMode.servings
        : AmountMode.grams;
    _meal =
        editing?.meal ?? widget.meal ?? MealType.forHour(DateTime.now().hour);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  double get _input => double.tryParse(_amount.text.trim()) ?? 0.0;

  /// The composition this entry is measured against.
  ///
  /// When editing, the entry's own snapshot wins over the library food. Fixing
  /// a mistyped weight must not silently re-price the entry against a food
  /// definition that has changed since it was logged.
  NutritionFacts get _facts =>
      widget.editing?.per100gSnapshot ?? widget.food.per100g;

  /// The single number everything else is derived from.
  ///
  /// Servings and millilitres are converted to grams here, once, so the
  /// nutrition maths only ever deals in weight.
  double get _grams {
    switch (_mode) {
      case AmountMode.grams:
        return _input;
      case AmountMode.servings:
        return _input * (widget.food.servingGrams ?? 0);
      case AmountMode.millilitres:
        return widget.food.millilitresToGrams(_input) ?? 0;
    }
  }

  List<AmountMode> get _availableModes => <AmountMode>[
        AmountMode.grams,
        if (widget.food.servingGrams != null) AmountMode.servings,
        if (widget.food.densityGPerMl != null) AmountMode.millilitres,
      ];

  String _modeLabel(AmountMode m) {
    switch (m) {
      case AmountMode.grams:
        return 'Grams';
      case AmountMode.servings:
        final String name = widget.food.servingName;
        return name.isEmpty ? 'Servings' : name;
      case AmountMode.millilitres:
        return 'Millilitres';
    }
  }

  String get _suffix {
    switch (_mode) {
      case AmountMode.grams:
        return 'g';
      case AmountMode.servings:
        return '×';
      case AmountMode.millilitres:
        return 'ml';
    }
  }

  Future<void> _save() async {
    final double grams = _grams;
    if (grams <= 0) return;

    final LogEntry? editing = widget.editing;
    final DateTime selected = ref.read(selectedDateProvider);
    final DateTime now = DateTime.now();

    // Back-filling an earlier day logs at midday so the entry sorts sensibly.
    final DateTime at = editing?.loggedAt ??
        (isSameDay(selected, now)
            ? now
            : DateTime(selected.year, selected.month, selected.day, 12));

    final LogEntry entry = LogEntry(
      id: editing?.id,
      foodId: widget.food.id,
      foodName: widget.food.displayName,
      grams: grams,
      per100gSnapshot: _facts,
      meal: _meal,
      loggedAt: at,
    );

    // Captured before the await: the messenger has to be resolved while this
    // page's context is still mounted, but used after it is gone.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);

    if (editing == null) {
      await ref.read(actionsProvider).logFood(entry);
    } else {
      await ref.read(actionsProvider).updateEntry(entry);
    }
    if (!mounted) return;

    // Return to the diary rather than the food picker. Landing back on the
    // list you just came from looks like nothing happened; the snackbar plus
    // the updated totals make the result obvious.
    navigator.popUntil((Route<dynamic> route) => route.isFirst);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          editing == null
              ? 'Logged ${Fmt.grams(grams)} of ${widget.food.name}'
              : 'Entry updated',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double grams = _grams;
    final NutritionFacts result = _facts.scaledToGrams(grams);
    final List<AmountMode> modes = _availableModes;

    return Scaffold(
      appBar: AppBar(title: Text(widget.food.displayName)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: <Widget>[
          SectionCard(
            title: 'How much?',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (modes.length > 1) ...<Widget>[
                  SegmentedButton<AmountMode>(
                    segments: <ButtonSegment<AmountMode>>[
                      for (final AmountMode m in modes)
                        ButtonSegment<AmountMode>(
                          value: m,
                          label: Text(_modeLabel(m)),
                        ),
                    ],
                    selected: <AmountMode>{_mode},
                    showSelectedIcon: false,
                    onSelectionChanged: (Set<AmountMode> s) =>
                        setState(() => _mode = s.first),
                  ),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: _amount,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(suffixText: _suffix),
                ),
                if (_mode != AmountMode.grams) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    '= ${Fmt.grams(grams)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Meal',
            child: Wrap(
              spacing: 8,
              children: <Widget>[
                for (final MealType m in MealType.values)
                  ChoiceChip(
                    label: Text(m.label),
                    selected: _meal == m,
                    onSelected: (_) => setState(() => _meal = m),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'This adds',
            subtitle: 'Scaled from the per-100 g values you saved.',
            child: Column(
              children: <Widget>[
                StatRow(
                  tiles: <Widget>[
                    StatTile(
                      label: 'Energy',
                      value: Fmt.energy(result[Nutrient.energy]),
                      color: colorForNutrient(Nutrient.energy, context),
                    ),
                    for (final Nutrient n in Nutrient.macros)
                      StatTile(
                        label: n.shortLabel,
                        value: Fmt.amount(n, result[n]),
                        color: colorForNutrient(n, context),
                      ),
                  ],
                ),
                const Divider(height: 24),
                for (final Nutrient n in Nutrient.values)
                  if (n != Nutrient.energy &&
                      !Nutrient.macros.contains(n) &&
                      _facts.has(n))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(n.label,
                                style: theme.textTheme.bodyMedium),
                          ),
                          Text(
                            Fmt.amount(n, result[n]),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontFeatures: const <FontFeature>[
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
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
          onPressed: grams > 0 ? _save : null,
          child: Text(widget.editing == null
              ? 'Log ${Fmt.grams(grams)}'
              : 'Save changes'),
        ),
      ),
    );
  }
}
