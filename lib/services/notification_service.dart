import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/profile.dart';
import '../domain/targets.dart';

/// Schedules the water reminders.
///
/// These are **local** notifications: the phone holds them itself, so they fire
/// with no server, no push certificate and no internet connection. iOS allows
/// 64 pending local notifications per app; one repeating daily notification
/// costs a single slot, so a reminder every 45 minutes across a 16-hour day
/// (21 slots) stays comfortably inside the budget.
class NotificationService {
  NotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Reminder notification ids live in this range so they can be cancelled as
  /// a group without touching anything else.
  static const int _waterIdBase = 1000;
  static const int _waterIdMax = 1099;

  static const String _androidChannelId = 'water_reminders';

  /// iOS keeps at most 64 pending local notifications per app and silently
  /// drops the rest, so a short interval across a long day would quietly lose
  /// its evening reminders. Cap well below the limit to leave headroom.
  static const int maxReminders = 48;

  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;

    tzdata.initializeTimeZones();
    try {
      final String name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (e) {
      // Falls back to UTC. Reminders would drift, so surface it in debug.
      debugPrint('Could not resolve local timezone, using UTC: $e');
    }

    const DarwinInitializationSettings darwin = DarwinInitializationSettings(
      // Permission is requested explicitly from the UI instead, so the prompt
      // appears at a moment the user understands rather than at first launch.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const AndroidInitializationSettings android =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: darwin),
    );
    _ready = true;
  }

  /// Asks iOS for permission. Returns false if the user declined.
  Future<bool> requestPermissions() async {
    await init();

    final IOSFlutterLocalNotificationsPlugin? ios =
        _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final bool? granted = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final bool? granted =
          await androidPlugin.requestNotificationsPermission();
      return granted ?? false;
    }

    return false;
  }

  NotificationDetails _details() => const NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
        android: AndroidNotificationDetails(
          _androidChannelId,
          'Water reminders',
          channelDescription: 'Regular prompts to drink water through the day.',
          importance: Importance.high,
          priority: Priority.high,
        ),
      );

  /// Rebuild the whole reminder schedule from [profile].
  ///
  /// Call this whenever the profile changes: the old reminders are cancelled
  /// first so a shorter interval can never leave stale ones behind.
  Future<void> rescheduleWaterReminders(UserProfile profile) async {
    await init();
    await cancelWaterReminders();

    if (!profile.remindersEnabled) return;

    final List<ReminderSlot> slots = buildSlots(profile);
    for (int i = 0; i < slots.length; i++) {
      final ReminderSlot slot = slots[i];
      await _plugin.zonedSchedule(
        _waterIdBase + i,
        slot.title,
        slot.body,
        _nextOccurrenceOf(slot.minuteOfDay),
        _details(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        // Repeat every day at this time.
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  Future<void> cancelWaterReminders() async {
    await init();
    for (int id = _waterIdBase; id <= _waterIdMax; id++) {
      await _plugin.cancel(id);
    }
  }

  Future<List<PendingNotificationRequest>> pending() async {
    await init();
    return _plugin.pendingNotificationRequests();
  }

  /// Fire a notification right now — used by the "test reminder" button so you
  /// can confirm the permission actually took before relying on it.
  Future<void> showTestNotification() async {
    await init();
    await _plugin.show(
      _waterIdMax,
      'Water reminder test',
      'Reminders are working. This is what they will look like.',
      _details(),
    );
  }

  tz.TZDateTime _nextOccurrenceOf(int minuteOfDay) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      minuteOfDay ~/ 60,
      minuteOfDay % 60,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// The interval actually used, which may be longer than the one requested.
  ///
  /// A 15-minute interval across an 18-hour day wants 72 reminders, more than
  /// iOS will hold. Rather than let the evening ones vanish without warning,
  /// stretch the interval to the next 5-minute step that fits inside
  /// [maxReminders]. The settings screen shows the result so the change is
  /// never silent.
  static int effectiveIntervalMinutes(UserProfile profile) {
    final int requested = profile.reminderIntervalMinutes;
    final int waking = profile.wakingMinutes;
    if (requested < minIntervalMinutes || waking <= 0) return requested;

    if (waking ~/ requested <= maxReminders) return requested;

    final int needed = (waking / maxReminders).ceil();
    return ((needed + 4) ~/ 5) * 5;
  }

  /// Reminders closer together than this are nagging rather than helpful, and
  /// the schedule refuses to build them.
  static const int minIntervalMinutes = 15;

  /// Work out every reminder time and its message.
  ///
  /// Pure and static so the schedule can be unit-tested and previewed in the
  /// settings screen without touching the notification plugin.
  static List<ReminderSlot> buildSlots(UserProfile profile) {
    if (profile.reminderIntervalMinutes < minIntervalMinutes) {
      return const <ReminderSlot>[];
    }

    final int waking = profile.wakingMinutes;
    if (waking <= 0) return const <ReminderSlot>[];

    final int interval = effectiveIntervalMinutes(profile);

    final WaterTarget target = TargetCalculator.water(profile);
    final double totalMl = target.drinkingTargetMl;

    // Reminders start one interval after waking and stop at bedtime, so there
    // is never a prompt to drink a litre five minutes before sleeping.
    final List<int> offsets = <int>[];
    for (int t = interval; t <= waking; t += interval) {
      offsets.add(t);
    }
    if (offsets.isEmpty) return const <ReminderSlot>[];

    final int count = offsets.length;
    final double perSlot = totalMl / count;

    final List<ReminderSlot> slots = <ReminderSlot>[];
    for (int i = 0; i < count; i++) {
      final int minuteOfDay =
          (profile.wakeMinuteOfDay + offsets[i]) % (24 * 60);
      final double cumulative = perSlot * (i + 1);
      final bool isLast = i == count - 1;

      slots.add(ReminderSlot(
        minuteOfDay: minuteOfDay,
        perSlotMl: perSlot,
        cumulativeMl: cumulative,
        title: isLast
            ? 'Last call for water'
            : 'Time to drink ${_roundMl(perSlot)} ml',
        body: isLast
            ? 'Finish the day on ${_formatLitres(totalMl)}. '
                'Top up now if you are short.'
            : 'You should be at ${_formatLitres(cumulative)} of '
                '${_formatLitres(totalMl)} by now.',
      ));
    }
    return slots;
  }

  /// Round to the nearest 10 ml — a reminder saying "drink 237 ml" is precision
  /// theatre. The tracking stays exact; only this prompt is rounded.
  static int _roundMl(double ml) => (ml / 10).round() * 10;

  static String _formatLitres(double ml) =>
      ml >= 1000 ? '${(ml / 1000).toStringAsFixed(2)} L' : '${ml.round()} ml';
}

/// One scheduled reminder.
class ReminderSlot {
  const ReminderSlot({
    required this.minuteOfDay,
    required this.perSlotMl,
    required this.cumulativeMl,
    required this.title,
    required this.body,
  });

  final int minuteOfDay;
  final double perSlotMl;
  final double cumulativeMl;
  final String title;
  final String body;

  String get timeLabel {
    final int h = minuteOfDay ~/ 60;
    final int m = minuteOfDay % 60;
    final int h12 = h % 12 == 0 ? 12 : h % 12;
    final String period = h < 12 ? 'AM' : 'PM';
    return '$h12:${m.toString().padLeft(2, '0')} $period';
  }
}
