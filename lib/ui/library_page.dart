import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatting.dart';
import '../domain/food_item.dart';
import '../domain/nutrients.dart';
import '../state/providers.dart';
import 'food_edit_page.dart';

/// Your personal food library.
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<FoodItem>> async =
        ref.watch(foodListProvider(_query));

    return Scaffold(
      appBar: AppBar(title: const Text('Foods')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-new-food',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const FoodEditPage()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New food'),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _search,
              onChanged: (String v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search',
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
                  return Center(
                    child: Text(
                      _query.isEmpty
                          ? 'No foods yet. Add the ones you actually eat.'
                          : 'Nothing matches "$_query".',
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: foods.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int i) =>
                      _FoodRow(food: foods[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FoodRow extends ConsumerWidget {
  const _FoodRow({required this.food});

  final FoodItem food;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return ListTile(
      title: Text(food.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${Fmt.energy(food.per100g[Nutrient.energy])} · '
            'P ${Fmt.bare(Nutrient.protein, food.per100g[Nutrient.protein])} · '
            'C ${Fmt.bare(Nutrient.carbs, food.per100g[Nutrient.carbs])} · '
            'F ${Fmt.bare(Nutrient.fat, food.per100g[Nutrient.fat])} per 100 g',
          ),
          if (food.servingGrams != null)
            Text(
              '${food.servingName.isEmpty ? 'Serving' : food.servingName} '
              '= ${Fmt.grams(food.servingGrams!)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
      isThreeLine: food.servingGrams != null,
      trailing: IconButton(
        icon: Icon(food.favorite ? Icons.star : Icons.star_border),
        onPressed: () => ref.read(actionsProvider).toggleFavorite(food),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FoodEditPage(existing: food),
        ),
      ),
    );
  }
}
