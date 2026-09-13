import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/database.dart';
import 'data/food_repository.dart';
import 'data/seed_foods.dart';
import 'data/settings_repository.dart';
import 'domain/food_item.dart';
import 'domain/profile.dart';
import 'services/notification_service.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final AppDatabase database = await AppDatabase.open();
  final SettingsRepository settings = SettingsRepository(database);
  final FoodRepository foods = FoodRepository(database);

  // First launch: put a few reference foods in the library so the app is
  // usable immediately. Every one of them is editable and deletable.
  if (!await settings.isOnboarded()) {
    if (await foods.count() == 0) {
      for (final FoodItem food in SeedFoods.build()) {
        await foods.insert(food);
      }
    }
    await settings.setOnboarded(true);
  }

  final UserProfile profile = await settings.loadProfile();

  final NotificationService notifications = NotificationService();
  await notifications.init();
  // Re-arm on every launch: iOS drops pending notifications when the app is
  // reinstalled or the device is restored, and rescheduling is idempotent.
  await notifications.rescheduleWaterReminders(profile);

  runApp(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        notificationServiceProvider.overrideWithValue(notifications),
        initialProfileProvider.overrideWithValue(profile),
      ],
      child: const HydraFuelApp(),
    ),
  );
}
