// Renders the real app at iPhone dimensions and writes PNGs of each screen.
//
// Run it explicitly — it lives outside test/ so `flutter test` in CI does not
// pick it up, because golden rendering differs between machines and would make
// CI fail for reasons that have nothing to do with the code:
//
//   flutter test tool/screenshots/app_screenshots_test.dart --update-goldens
//
// Output lands in tool/screenshots/shots/.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrafuel/app.dart';
import 'package:hydrafuel/core/theme.dart';
import 'package:hydrafuel/data/database.dart';
import 'package:hydrafuel/data/food_repository.dart';
import 'package:hydrafuel/data/log_repository.dart';
import 'package:hydrafuel/data/marker_repository.dart';
import 'package:hydrafuel/data/seed_foods.dart';
import 'package:hydrafuel/data/settings_repository.dart';
import 'package:hydrafuel/data/water_repository.dart';
import 'package:hydrafuel/domain/blood_marker.dart';
import 'package:hydrafuel/domain/food_item.dart';
import 'package:hydrafuel/domain/log_entry.dart';
import 'package:hydrafuel/domain/profile.dart';
import 'package:hydrafuel/domain/water_entry.dart';
import 'package:hydrafuel/services/notification_service.dart';
import 'package:hydrafuel/state/providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _SilentNotifications extends NotificationService {
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermissions() async => true;
  @override
  Future<void> rescheduleWaterReminders(UserProfile profile) async {}
  @override
  Future<void> cancelWaterReminders() async {}
}

/// The Flutter SDK root, derived from the Dart binary running this test.
String get _flutterRoot {
  final String? env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env;
  // <root>/bin/cache/dart-sdk/bin/dart
  Directory d = File(Platform.resolvedExecutable).parent;
  for (int i = 0; i < 4; i++) {
    d = d.parent;
  }
  return d.path;
}

/// Load real fonts.
///
/// Without this the test renderer draws every glyph as a filled box, which
/// makes a screenshot useless for judging a layout.
Future<void> _loadFonts() async {
  final String dir = '$_flutterRoot/bin/cache/artifacts/material_fonts';

  Future<ByteData> read(String file) async => ByteData.sublistView(
      Uint8List.fromList(File('$dir/$file').readAsBytesSync()));

  final FontLoader roboto = FontLoader('Roboto');
  for (final String f in <String>[
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    if (File('$dir/$f').existsSync()) roboto.addFont(read(f));
  }
  await roboto.load();

  final FontLoader icons = FontLoader('MaterialIcons');
  icons.addFont(read('MaterialIcons-Regular.otf'));
  await icons.load();
}

ThemeData _withNamedAppBarFont(ThemeData base) => base.copyWith(
      appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle:
            base.appBarTheme.titleTextStyle?.copyWith(fontFamily: 'Roboto'),
      ),
    );

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    await _loadFonts();
  });

  late AppDatabase db;

  tearDown(() async => db.close());

  /// A realistic half-lived day: some water in, two meals logged, and a blood
  /// panel recorded.
  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532); // iPhone, 390 x 844 pt
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    db = await AppDatabase.open(path: inMemoryDatabasePath);
    final SettingsRepository settings = SettingsRepository(db);
    final FoodRepository foods = FoodRepository(db);
    final LogRepository logs = LogRepository(db);
    final WaterRepository water = WaterRepository(db);
    final MarkerRepository markers = MarkerRepository(db);

    for (final FoodItem f in SeedFoods.build()) {
      await foods.insert(f);
    }

    final UserProfile profile = UserProfile(
      name: 'Niranjan',
      sex: Sex.male,
      birthDate: DateTime(DateTime.now().year - 24, 4, 12),
      heightCm: 175,
      weightKg: 72,
      activityLevel: ActivityLevel.moderate,
      dailyExerciseMinutes: 45,
      wakeMinuteOfDay: 7 * 60,
      sleepMinuteOfDay: 23 * 60,
      reminderIntervalMinutes: 90,
    );
    await settings.saveProfile(profile);

    final DateTime today = DateTime.now();
    DateTime at(int hour, int minute) =>
        DateTime(today.year, today.month, today.day, hour, minute);

    for (final List<Object> drink in <List<Object>>[
      <Object>[300.0, 'Glass', 7, 20],
      <Object>[500.0, 'Bottle', 9, 45],
      <Object>[250.0, 'Glass', 11, 30],
      <Object>[350.0, 'Large glass', 13, 15],
    ]) {
      await water.add(WaterEntry(
        volumeMl: drink[0] as double,
        label: drink[1] as String,
        loggedAt: at(drink[2] as int, drink[3] as int),
      ));
    }

    Future<void> log(
        String name, double grams, MealType meal, int h, int m) async {
      final List<FoodItem> matches = await foods.all(query: name);
      final FoodItem f = matches.first;
      await logs.insert(LogEntry(
        foodId: f.id,
        foodName: f.displayName,
        grams: grams,
        per100gSnapshot: f.per100g,
        meal: meal,
        loggedAt: at(h, m),
      ));
    }

    await log('Oats', 60, MealType.breakfast, 8, 0);
    await log('Milk, whole', 200, MealType.breakfast, 8, 0);
    await log('Banana', 118, MealType.breakfast, 8, 5);
    await log('Rice', 150, MealType.lunch, 13, 30);
    await log('Toor dal', 60, MealType.lunch, 13, 30);
    await log('Chicken breast', 150, MealType.lunch, 13, 30);
    await log('Spinach', 100, MealType.lunch, 13, 35);
    await log('Almonds', 25, MealType.snack, 16, 0);

    await markers.saveDraw(DateTime(2026, 9, 13), <BloodMarker, double>{
      BloodMarker.totalCholesterol: 191,
      BloodMarker.triglycerides: 72,
      BloodMarker.hdl: 36,
      BloodMarker.nonHdl: 155,
      BloodMarker.ldl: 141,
      BloodMarker.ast: 308,
      BloodMarker.alt: 133,
      BloodMarker.ggt: 24,
      BloodMarker.creatinine: 1.03,
      BloodMarker.egfr: 105,
      BloodMarker.uricAcid: 6.3,
      BloodMarker.hba1c: 4.7,
      BloodMarker.vitaminD: 16.5,
      BloodMarker.vitaminB12: 306,
      BloodMarker.hemoglobin: 15.1,
      BloodMarker.tsh: 2.4754,
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          notificationServiceProvider.overrideWithValue(_SilentNotifications()),
          initialProfileProvider.overrideWithValue(profile),
        ],
        // The app's own MaterialApp, rebuilt here only so the app-bar title
        // style names a font. It has no family of its own — on a device that
        // resolves to the system face, but the test renderer draws boxes for
        // it. Every other style already comes from the theme's typography.
        child: MaterialApp(
          title: 'HydraFuel',
          debugShowCheckedModeBanner: false,
          theme: _withNamedAppBarFont(AppTheme.light()),
          home: const HomeShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/$name.png'),
    );
  }

  Future<void> tab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('01 today', (tester) async {
    await boot(tester);
    await shoot(tester, '01-today');
  });

  testWidgets('02 today meals', (tester) async {
    await boot(tester);
    await tester.drag(find.byType(ListView).first, const Offset(0, -620));
    await tester.pumpAndSettle();
    await shoot(tester, '02-today-meals');
  });

  testWidgets('03 water', (tester) async {
    await boot(tester);
    await tab(tester, 'Water');
    await shoot(tester, '03-water');
  });

  testWidgets('04 water breakdown', (tester) async {
    await boot(tester);
    await tab(tester, 'Water');
    await tester.drag(find.byType(ListView).first, const Offset(0, -560));
    await tester.pumpAndSettle();
    await shoot(tester, '04-water-breakdown');
  });

  testWidgets('05 all nutrients', (tester) async {
    await boot(tester);
    await tester.tap(find.text('All nutrients'));
    await tester.pumpAndSettle();
    await shoot(tester, '05-all-nutrients');
  });

  testWidgets('06 nutrient detail', (tester) async {
    await boot(tester);
    await tester.tap(find.text('All nutrients'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saturated fat'));
    await tester.pumpAndSettle();
    await shoot(tester, '06-nutrient-detail');
  });

  testWidgets('07 blood report', (tester) async {
    await boot(tester);
    await tab(tester, 'Profile');
    await tester.tap(find.text('Blood report'));
    await tester.pumpAndSettle();
    await shoot(tester, '07-blood-report');
  });

  testWidgets('08 blood results list', (tester) async {
    await boot(tester);
    await tab(tester, 'Profile');
    await tester.tap(find.text('Blood report'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    await shoot(tester, '08-blood-results');
  });

  testWidgets('09 foods', (tester) async {
    await boot(tester);
    await tab(tester, 'Foods');
    await shoot(tester, '09-foods');
  });

  testWidgets('10 log amount', (tester) async {
    await boot(tester);
    await tester.tap(find.text('Log food'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'chicken');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Chicken breast').first);
    await tester.pumpAndSettle();
    await shoot(tester, '10-log-amount');
  });

  testWidgets('11 profile', (tester) async {
    await boot(tester);
    await tab(tester, 'Profile');
    await shoot(tester, '11-profile');
  });

  testWidgets('12 profile targets', (tester) async {
    await boot(tester);
    await tab(tester, 'Profile');
    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    await shoot(tester, '12-profile-targets');
  });

  testWidgets('13 reminder schedule', (tester) async {
    await boot(tester);
    await tab(tester, 'Profile');
    await tester.dragUntilVisible(
      find.text('See schedule'),
      find.byType(ListView).first,
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('See schedule'));
    await tester.pumpAndSettle();
    await shoot(tester, '13-reminder-schedule');
  });

  testWidgets('14 history', (tester) async {
    await boot(tester);
    await tab(tester, 'History');
    await shoot(tester, '14-history');
  });

  testWidgets('15 food editor', (tester) async {
    await boot(tester);
    await tab(tester, 'Foods');
    // Search first: the library is long and Paneer sits well below the fold.
    await tester.enterText(find.byType(TextField).first, 'paneer');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Paneer').first);
    await tester.pumpAndSettle();
    await shoot(tester, '15-food-editor');
  });
}
