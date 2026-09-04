import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
      );
    }
  }

  /// `zonedSchedule` needs a `TZDateTime`; the timezone package
  /// initialization is expected to happen once at app start (see
  /// `timezone` setup in a full implementation) — omitted here for
  /// brevity, using local time as a placeholder.
  DateTime _nextInstanceOf(int hour, int minute) {
    final now = DateTime.now();
    var scheduled = DateTime(now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
