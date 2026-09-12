import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Schedules the "catch up with anyone?" prompts described in DESIGN.md
/// §8. Entirely local — there is no server, so this is plain OS-level
/// scheduled notifications, not push.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'checkin_prompts';
  static const _checkinNotificationId = 1001;

  Future<void> init() async {
    tz_data.initializeTimeZones();
    final deviceTimezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(deviceTimezone));

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    const channel = AndroidNotificationChannel(
      _channelId,
      'Check-in prompts',
      description: 'Reminders to log a catch-up with someone in your circle',
      importance: Importance.defaultImportance,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Schedules the daily prompt times. Defaults to the brief's "a couple
  /// of times daily" — late morning and early evening — configurable from
  /// Settings.
  Future<void> scheduleDailyPrompts({
    List<(int hour, int minute)> times = const [(11, 30), (18, 30)],
  }) async {
    await _plugin.cancelAll();
    for (final (hour, minute) in times) {
      await _plugin.zonedSchedule(
        _checkinNotificationId + hour,
        'Catch up with anyone today?',
        'Log it in a couple of taps.',
        _nextInstanceOf(hour, minute),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Check-in prompts',
            importance: Importance.defaultImportance,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        // Our TZDateTime is already an absolute instant computed against
        // tz.local (see _nextInstanceOf) rather than a wall-clock time to
        // reinterpret at fire-time, so absoluteTime is the correct mode.
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
