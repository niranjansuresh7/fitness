import 'package:flutter_test/flutter_test.dart';
import 'package:hydrafuel/domain/profile.dart';
import 'package:hydrafuel/services/notification_service.dart';

void main() {
  UserProfile profile({
    int wake = 7 * 60,
    int sleep = 23 * 60,
    int interval = 90,
    double weightKg = 80,
    bool enabled = true,
  }) =>
      UserProfile(
        weightKg: weightKg,
        wakeMinuteOfDay: wake,
        sleepMinuteOfDay: sleep,
        reminderIntervalMinutes: interval,
        remindersEnabled: enabled,
      );

  group('reminder schedule', () {
    test('fills the waking day at the chosen interval', () {
      // 07:00 to 23:00 is 960 minutes; every 90 minutes gives 10 slots,
      // the first at 08:30 and the last at 22:00.
      final List<ReminderSlot> slots =
          NotificationService.buildSlots(profile());
      expect(slots.length, 10);
      expect(slots.first.minuteOfDay, 8 * 60 + 30);
      expect(slots.last.minuteOfDay, 22 * 60);
    });

    test('never schedules a reminder after bedtime', () {
      for (final int interval in <int>[30, 45, 60, 90, 120, 180]) {
        final List<ReminderSlot> slots =
            NotificationService.buildSlots(profile(interval: interval));
        for (final ReminderSlot s in slots) {
          expect(s.minuteOfDay, lessThanOrEqualTo(23 * 60),
              reason: 'interval $interval put a reminder past bedtime');
        }
      }
    });

    test('the slots divide the day target exactly', () {
      final List<ReminderSlot> slots =
          NotificationService.buildSlots(profile());
      final double total = slots.fold<double>(
          0.0, (double sum, ReminderSlot s) => sum + s.perSlotMl);
      expect(total, closeTo(2800.0, 1e-6));
      expect(slots.last.cumulativeMl, closeTo(2800.0, 1e-6));
    });

    test('cumulative targets rise monotonically', () {
      final List<ReminderSlot> slots =
          NotificationService.buildSlots(profile());
      for (int i = 1; i < slots.length; i++) {
        expect(slots[i].cumulativeMl, greaterThan(slots[i - 1].cumulativeMl));
      }
    });

    test('a schedule crossing midnight still works', () {
      // Awake 10:00 to 02:00 — 16 hours.
      final List<ReminderSlot> slots = NotificationService.buildSlots(
        profile(wake: 10 * 60, sleep: 2 * 60),
      );
      expect(slots, isNotEmpty);
      expect(slots.last.minuteOfDay, lessThan(24 * 60));
      // Last slot is 22:00 + 60 = 01:00, i.e. it wrapped past midnight.
      expect(slots.last.minuteOfDay, 60);
    });

    test('an interval below 15 minutes is refused outright', () {
      expect(NotificationService.buildSlots(profile(interval: 5)), isEmpty);
    });

    test('stays inside the iOS 64-notification budget at every interval', () {
      for (final int interval in <int>[15, 20, 30, 45, 60, 90]) {
        final List<ReminderSlot> slots = NotificationService.buildSlots(
          profile(wake: 5 * 60, sleep: 23 * 60 + 59, interval: interval),
        );
        expect(slots.length,
            lessThanOrEqualTo(NotificationService.maxReminders),
            reason: 'interval $interval produced ${slots.length} reminders');
      }
    });

    test('a too-short interval is stretched rather than silently truncated', () {
      // 05:00-23:59 is 1139 waking minutes. At 15-minute spacing that is 75
      // reminders, past what iOS will hold, so the interval must widen.
      final UserProfile p =
          profile(wake: 5 * 60, sleep: 23 * 60 + 59, interval: 15);
      final int effective = NotificationService.effectiveIntervalMinutes(p);
      expect(effective, greaterThan(15));
      expect(effective % 5, 0);

      final List<ReminderSlot> slots = NotificationService.buildSlots(p);
      expect(slots.length,
          lessThanOrEqualTo(NotificationService.maxReminders));
      // Still covers the full day rather than stopping early.
      expect(slots.last.cumulativeMl,
          closeTo(slots.fold<double>(0, (double s, ReminderSlot r) => s + r.perSlotMl), 1e-6));
    });

    test('an interval that already fits is left exactly as chosen', () {
      final UserProfile p = profile(interval: 90);
      expect(NotificationService.effectiveIntervalMinutes(p), 90);
    });

    test('every slot has a title and a body', () {
      for (final ReminderSlot s in NotificationService.buildSlots(profile())) {
        expect(s.title, isNotEmpty);
        expect(s.body, isNotEmpty);
      }
    });

    test('the final slot is a last call, not another interval prompt', () {
      final List<ReminderSlot> slots =
          NotificationService.buildSlots(profile());
      expect(slots.last.title.toLowerCase(), contains('last call'));
    });

    test('time labels render in 12-hour form', () {
      final List<ReminderSlot> slots =
          NotificationService.buildSlots(profile());
      expect(slots.first.timeLabel, '8:30 AM');
      expect(slots.last.timeLabel, '10:00 PM');
    });

    test('a heavier person gets larger per-slot amounts', () {
      final double light = NotificationService.buildSlots(
        profile(weightKg: 55),
      ).first.perSlotMl;
      final double heavy = NotificationService.buildSlots(
        profile(weightKg: 95),
      ).first.perSlotMl;
      expect(heavy, greaterThan(light));
    });
  });

  group('waking window', () {
    test('same-day window', () {
      expect(profile().wakingMinutes, 960);
    });

    test('window crossing midnight wraps correctly', () {
      expect(profile(wake: 10 * 60, sleep: 2 * 60).wakingMinutes, 16 * 60);
    });
  });
}
