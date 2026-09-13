import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatting.dart';
import '../core/theme.dart';
import '../domain/profile.dart';
import '../services/notification_service.dart';
import '../state/providers.dart';

/// Exactly which reminders are scheduled, and what each one will say.
///
/// Reminders you cannot inspect are reminders you stop trusting, so this shows
/// the real schedule rather than a promise about it.
class ReminderSchedulePage extends ConsumerWidget {
  const ReminderSchedulePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final UserProfile profile = ref.watch(profileProvider);
    final List<ReminderSlot> slots =
        NotificationService.buildSlots(profile);

    final DateTime now = DateTime.now();
    final int minuteNow = now.hour * 60 + now.minute;

    return Scaffold(
      appBar: AppBar(title: const Text('Reminder schedule')),
      body: slots.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No reminders scheduled. Check the interval in Profile.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            )
          : ListView.separated(
              itemCount: slots.length + 1,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Text(
                      '${slots.length} reminders between '
                      '${Fmt.timeOfDay(profile.wakeMinuteOfDay)} and '
                      '${Fmt.timeOfDay(profile.sleepMinuteOfDay)}, every '
                      '${NotificationService.effectiveIntervalMinutes(profile)} '
                      'minutes. Each repeats daily.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }

                final ReminderSlot s = slots[i - 1];
                final bool past = s.minuteOfDay <= minuteNow;

                return ListTile(
                  leading: Icon(
                    past
                        ? Icons.notifications_none
                        : Icons.notifications_active_outlined,
                    color: past
                        ? theme.colorScheme.onSurfaceVariant
                        : AppTheme.water,
                  ),
                  title: Text(
                    '${s.timeLabel} — ${s.title}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: past ? theme.colorScheme.onSurfaceVariant : null,
                    ),
                  ),
                  subtitle: Text(s.body),
                );
              },
            ),
    );
  }
}
