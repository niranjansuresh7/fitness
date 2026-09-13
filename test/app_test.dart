import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrafuel/app.dart';
import 'package:hydrafuel/data/database.dart';
import 'package:hydrafuel/data/food_repository.dart';
import 'package:hydrafuel/data/seed_foods.dart';
import 'package:hydrafuel/data/settings_repository.dart';
import 'package:hydrafuel/domain/food_item.dart';
import 'package:hydrafuel/domain/nutrients.dart';
import 'package:hydrafuel/domain/profile.dart';
import 'package:hydrafuel/services/notification_service.dart';
import 'package:hydrafuel/state/providers.dart';
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

  Future<ProviderContainer> boot(WidgetTester tester) async {
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
      initialProfileProvider
          .overrideWithValue(await settings.loadProfile()),
    ];

    final ProviderContainer container =
        ProviderContainer(overrides: overrides);
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
    await tester.tap(find.text('500 ml'));
    await tester.pumpAndSettle();

    expect(find.textContaining('500 ml'), findsWidgets);
    // 2450 - 500 = 1950 ml still to go.
    expect(find.textContaining('1.95 L'), findsWidgets);
  });

  testWidgets('a drink can be removed again', (tester) async {
    await boot(tester);
    await tester.tap(find.text('Water').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('250 ml'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
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
    await tester.enterText(find.byType(TextField).first, '200');
    await tester.pumpAndSettle();
    expect(find.text('240 kcal'), findsWidgets);
    expect(find.text('45 g'), findsWidgets);

    await tester.tap(find.textContaining('Log 200 g'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Chicken breast'), findsWidgets);
    expect(find.textContaining('240 kcal'), findsWidgets);
  });

  testWidgets('changing weight moves the water target and reschedules',
      (tester) async {
    final ProviderContainer container = await boot(tester);

    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();

    final int before = notifications.rescheduleCount;

    await tester.enterText(find.widgetWithText(TextField, 'Weight'), '90');
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

  testWidgets('a nutrient override survives into the targets screen',
      (tester) async {
    final ProviderContainer container = await boot(tester);

    await container.read(profileProvider.notifier).save(
          container.read(profileProvider).copyWith(
            customTargets: <Nutrient, double>{Nutrient.sodium: 1500},
          ),
        );
    await tester.pumpAndSettle();

    await tester.tap(find.text('All nutrients'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1500 mg'), findsWidgets);
  });
}
