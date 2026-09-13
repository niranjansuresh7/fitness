import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrafuel/app.dart';
import 'package:hydrafuel/data/database.dart';
import 'package:hydrafuel/data/food_repository.dart';
import 'package:hydrafuel/data/seed_foods.dart';
import 'package:hydrafuel/data/settings_repository.dart';
import 'package:hydrafuel/domain/food_item.dart';
import 'package:hydrafuel/core/dates.dart';
import 'package:hydrafuel/domain/daily_summary.dart';
import 'package:hydrafuel/domain/nutrients.dart';
import 'package:hydrafuel/domain/profile.dart';
import 'package:hydrafuel/services/notification_service.dart';
import 'package:hydrafuel/state/providers.dart';
import 'package:hydrafuel/ui/food_edit_page.dart';
import 'package:hydrafuel/ui/log_food_page.dart';
import 'package:hydrafuel/ui/profile_page.dart';
import 'package:hydrafuel/ui/reminder_schedule_page.dart';
import 'package:hydrafuel/ui/today_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Stands in for the real plugin, which has no platform to talk to in tests.
class _FakeNotifications extends NotificationService {
  int rescheduleCount = 0;
  UserProfile? lastProfile;

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<void> rescheduleWaterReminders(UserProfile profile) async {
    rescheduleCount++;
    lastProfile = profile;
  }

  @override
  Future<void> cancelWaterReminders() async {}
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // The isolate-backed factory deadlocks under flutter_test's fake clock:
    // pumpAndSettle never yields to the real event loop, so the query reply
    // never arrives and the loading spinner animates forever. The no-isolate
    // factory runs the same SQLite engine on the test isolate.
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late AppDatabase db;
  late _FakeNotifications notifications;

  /// Taps a widget after scrolling it into view.
  ///
  /// The test viewport is a phone, so anything below the fold has to be
  /// scrolled to before it can receive a tap — exactly as on the device.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// The scroll view of [page]. Its own list comes before the scrollables that
  /// every TextField carries internally, so `.first` is the page's list.
  Finder listOf(Type page) => find
      .descendant(of: find.byType(page), matching: find.byType(Scrollable))
      .first;

  /// Brings [target] into view inside [page], building it first if the lazy
  /// list has not reached that far down yet.
  Future<void> revealIn(WidgetTester tester, Type page, Finder target) async {
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(target, 250, scrollable: listOf(page));
    } else {
      await tester.ensureVisible(target);
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapIn(WidgetTester tester, Type page, Finder target) async {
    await revealIn(tester, page, target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// Scopes [matching] to [page]'s subtree.
  ///
  /// Needed because the confirmation snackbar repeats the food name, and lives
  /// in the shell's Scaffold rather than the page — an unscoped text finder
  /// would match it instead of the diary row.
  Finder inPage(Type page, Finder matching) =>
      find.descendant(of: find.byType(page), matching: matching);

  Future<void> typeIn(
      WidgetTester tester, Type page, Finder target, String text) async {
    await revealIn(tester, page, target);
    await tester.enterText(target, text);
    await tester.pumpAndSettle();
  }

  Future<ProviderContainer> boot(WidgetTester tester) async {
    // iPhone-sized viewport (390 x 844 logical points).
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    db = await AppDatabase.open(path: inMemoryDatabasePath);
    final SettingsRepository settings = SettingsRepository(db);
    final FoodRepository foods = FoodRepository(db);
    for (final FoodItem f in SeedFoods.build()) {
      await foods.insert(f);
    }
    notifications = _FakeNotifications();

    final List<Override> overrides = <Override>[
      appDatabaseProvider.overrideWithValue(db),
      notificationServiceProvider.overrideWithValue(notifications),
      initialProfileProvider.overrideWithValue(await settings.loadProfile()),
    ];

    final ProviderContainer container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const HydraFuelApp(),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  tearDown(() async => db.close());

  testWidgets('boots to the Today screen with a water target', (tester) async {
    await boot(tester);

    expect(find.text('Today'), findsWidgets);
    expect(find.text('Water'), findsWidgets);
    // Default profile is 70 kg at 35 ml/kg = 2450 ml.
    expect(find.textContaining('2.45 L'), findsWidgets);
  });

  testWidgets('logging a drink updates the total and what is left',
      (tester) async {
    await boot(tester);

    await tester.tap(find.text('Water').last);
    await tester.pumpAndSettle();

    expect(find.text('0 ml'), findsWidgets);

    // Tap the 500 ml "Bottle" preset.
    await tapVisible(tester, find.text('500 ml'));

    expect(find.textContaining('500 ml'), findsWidgets);
    // 2450 - 500 = 1950 ml still to go.
    expect(find.textContaining('1.95 L'), findsWidgets);
  });

  testWidgets('a drink can be removed again', (tester) async {
    await boot(tester);
    await tester.tap(find.text('Water').last);
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text('250 ml'));
    expect(find.byIcon(Icons.close), findsOneWidget);

    await tapVisible(tester, find.byIcon(Icons.close));
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('the food library is seeded and searchable', (tester) async {
    await boot(tester);

    await tester.tap(find.text('Foods').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Chicken breast'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'oats');
    await tester.pumpAndSettle();

    expect(find.textContaining('Oats'), findsWidgets);
    expect(find.textContaining('Chicken breast'), findsNothing);
  });

  testWidgets('logging food lands on Today with the right macros',
      (tester) async {
    await boot(tester);

    await tester.tap(find.text('Log food'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'chicken');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Chicken breast').first);
    await tester.pumpAndSettle();

    // 200 g of chicken breast: 240 kcal and 45 g protein.
    // Scope to the current route: the page underneath is still in the tree and
    // its search box would otherwise match first.
    await tester.enterText(
      find.descendant(
        of: find.byType(LogAmountPage),
        matching: find.byType(TextField),
      ),
      '200',
    );
    await tester.pumpAndSettle();
    expect(find.text('240 kcal'), findsWidgets);
    expect(find.text('45 g'), findsWidgets);

    await tapVisible(tester, find.textContaining('Log 200 g'));

    // Logging returns to the diary, not the picker.
    expect(find.byType(LogFoodPage), findsNothing);
    expect(find.textContaining('Logged 200 g'), findsWidgets);

    // The entry is at the bottom of the Today list, below the cards.
    final Finder row = inPage(TodayPage, find.textContaining('Chicken breast'));
    await revealIn(tester, TodayPage, row);
    expect(row, findsOneWidget);
    expect(inPage(TodayPage, find.textContaining('240 kcal')), findsWidgets);
  });

  testWidgets('changing weight moves the water target and reschedules',
      (tester) async {
    final ProviderContainer container = await boot(tester);

    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();

    final int before = notifications.rescheduleCount;

    await typeIn(
        tester, ProfilePage, find.widgetWithText(TextField, 'Weight'), '90');
    // NumberField commits on submit or focus loss, not on every keystroke.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(container.read(profileProvider).weightKg, 90.0);
    expect(notifications.rescheduleCount, greaterThan(before));

    // The new target should be live on the Water tab: 90 kg × 35 ml/kg.
    await tester.tap(find.text('Water').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('3.15 L'), findsWidgets);
  });

  testWidgets('the food editor catches bad data, then normalises per-serving',
      (tester) async {
    final ProviderContainer container = await boot(tester);

    await tester.tap(find.text('Foods').last);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('New food'));

    await typeIn(tester, FoodEditPage,
        find.widgetWithText(TextFormField, 'Name'), 'Test protein bar');
    await typeIn(tester, FoodEditPage,
        find.widgetWithText(TextFormField, 'Weighs'), '50');

    // Type the figures off a 50 g packet rather than per 100 g.
    await tapIn(tester, FoodEditPage, find.text('Per serving'));
    await typeIn(tester, FoodEditPage,
        find.widgetWithText(TextFormField, 'Energy'), '200');
    await typeIn(tester, FoodEditPage,
        find.widgetWithText(TextFormField, 'Protein'), '10');

    // 200 kcal cannot come from 10 g of protein alone, and saving says so.
    await tapVisible(tester, find.text('Add to library'));
    expect(find.text('Check these numbers'), findsOneWidget);
    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();

    expect(
      await container.read(foodRepositoryProvider).all(query: 'Test protein'),
      isEmpty,
      reason: 'nothing should be saved while the warning is unresolved',
    );

    // 10 g protein + 20 g carbs + 8 g fat = 192 kcal, near enough to 200.
    await typeIn(tester, FoodEditPage,
        find.widgetWithText(TextFormField, 'Carbohydrate'), '20');
    await typeIn(
        tester, FoodEditPage, find.widgetWithText(TextFormField, 'Fat'), '8');

    await tapVisible(tester, find.text('Add to library'));
    expect(find.text('Check these numbers'), findsNothing);

    // A 50 g serving is half of 100 g, so everything doubles on the way in.
    final List<FoodItem> saved =
        await container.read(foodRepositoryProvider).all(query: 'Test protein');
    expect(saved, hasLength(1));
    expect(saved.single.per100g[Nutrient.energy], closeTo(400.0, 1e-9));
    expect(saved.single.per100g[Nutrient.protein], closeTo(20.0, 1e-9));
    expect(saved.single.per100g[Nutrient.carbs], closeTo(40.0, 1e-9));
    expect(saved.single.per100g[Nutrient.fat], closeTo(16.0, 1e-9));
    expect(saved.single.servingGrams, 50.0);
  });

  testWidgets('the reminder schedule lists every reminder', (tester) async {
    await boot(tester);

    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    await tapIn(tester, ProfilePage, find.text('See schedule'));

    expect(find.text('Reminder schedule'), findsOneWidget);
    // Default 07:00-23:00 every 90 minutes is 10 reminders.
    expect(find.textContaining('10 reminders'), findsOneWidget);

    // The last call sits at the bottom of a lazily-built list.
    await revealIn(
        tester, ReminderSchedulePage, find.textContaining('Last call'));
    expect(find.textContaining('Last call'), findsWidgets);
  });

  testWidgets('a logged entry can be corrected without losing its snapshot',
      (tester) async {
    final ProviderContainer container = await boot(tester);

    // Log 200 g of chicken.
    await tester.tap(find.text('Log food'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'chicken');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Chicken breast').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(LogAmountPage),
        matching: find.byType(TextField),
      ),
      '200',
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.textContaining('Log 200 g'));

    // Let the confirmation snackbar time out before looking for the row.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // Reopen it from the diary and correct the weight to 100 g.
    await tapIn(tester, TodayPage,
        inPage(TodayPage, find.textContaining('Chicken breast')));
    expect(find.byType(LogAmountPage), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byType(LogAmountPage),
        matching: find.byType(TextField),
      ),
      '100',
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Save changes'));

    final DaySummary day =
        await container.read(daySummaryProvider(dayKey(DateTime.now())).future);
    expect(day.entries, hasLength(1), reason: 'edited, not duplicated');
    expect(day.entries.single.grams, 100.0);
    expect(day.consumed(Nutrient.energy), closeTo(120.0, 1e-9));
  });

  testWidgets('a nutrient override survives into the targets screen',
      (tester) async {
    final ProviderContainer container = await boot(tester);

    await container.read(profileProvider.notifier).save(
          container.read(profileProvider).copyWith(
            customTargets: <Nutrient, double>{Nutrient.sodium: 1500},
          ),
        );
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text('All nutrients'));

    expect(find.textContaining('1500 mg'), findsWidgets);
  });
}
