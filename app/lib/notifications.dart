import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Thin wrapper around flutter_local_notifications for the countdown-timer
/// alert. Only Android is wired up (this app ships Android only).
class Notifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _channelId = 'countdown_timers';
  static const AndroidNotificationDetails _android = AndroidNotificationDetails(
    _channelId,
    'Countdown timers',
    channelDescription: 'Fires when a countdown timer reaches zero.',
    importance: Importance.max,
    priority: Priority.high,
    category: AndroidNotificationCategory.alarm,
  );

  /// Initialise the plugin, timezone database and channel. Safe to call once
  /// at startup; failures are swallowed so the app still runs without alerts.
  static Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      const androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(
          const InitializationSettings(android: androidInit));
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        _channelId,
        'Countdown timers',
        description: 'Fires when a countdown timer reaches zero.',
        importance: Importance.max,
      ));
      await android?.requestNotificationsPermission();
      _ready = true;
    } catch (_) {
      // Notifications are best-effort; ignore setup errors.
    }
  }

  /// A stable small int id for a timer's string id (notification ids are ints).
  static int idFor(String timerId) => timerId.hashCode & 0x7fffffff;

  /// Schedule the "countdown finished" notification at [when]. Reschedules if
  /// already set for this id.
  static Future<void> scheduleCountdown(
      String timerId, String label, DateTime when) async {
    await init();
    if (!_ready) return;
    final title = label.trim().isEmpty ? 'Countdown finished' : '$label — time!';
    try {
      await _plugin.zonedSchedule(
        idFor(timerId),
        title,
        'Reached zero — the timer keeps running for overtime.',
        tz.TZDateTime.from(when, tz.local),
        const NotificationDetails(android: _android),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      // ignore scheduling errors (e.g. permission not granted)
    }
  }

  static Future<void> cancel(String timerId) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(idFor(timerId));
    } catch (_) {}
  }
}
