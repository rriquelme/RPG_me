import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Wrapper around flutter_local_notifications for timers: a persistent
/// "chronometer" notification that ticks in the status bar while a timer runs,
/// and a one-shot alert when a countdown reaches zero. Android only.
class Notifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _alertChannel = 'countdown_timers';
  static const _ongoingChannel = 'running_timers';

  static const AndroidNotificationDetails _alert = AndroidNotificationDetails(
    _alertChannel,
    'Countdown alerts',
    channelDescription: 'Fires when a countdown timer reaches zero.',
    importance: Importance.max,
    priority: Priority.high,
    category: AndroidNotificationCategory.alarm,
    fullScreenIntent: true,
  );

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
        _alertChannel,
        'Countdown alerts',
        description: 'Fires when a countdown timer reaches zero.',
        importance: Importance.max,
      ));
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        _ongoingChannel,
        'Running timers',
        description: 'A live counter while a timer runs.',
        importance: Importance.low,
      ));
      await android?.requestNotificationsPermission();
      _ready = true;
    } catch (_) {
      // best-effort
    }
  }

  /// Ask for notification + exact-alarm permission (safe to call repeatedly).
  static Future<void> ensurePermissions() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      await android?.requestExactAlarmsPermission();
    } catch (_) {}
  }

  static int _hash(String s) => s.hashCode & 0x7fffffff;
  static int idFor(String timerId) => _hash('alert:$timerId');
  static int ongoingIdFor(String timerId) => _hash('ongoing:$timerId');

  /// Schedule the "countdown finished" alert at [when] (exact when allowed).
  static Future<void> scheduleCountdown(
      String timerId, String label, DateTime when) async {
    await init();
    if (!_ready) return;
    final title =
        label.trim().isEmpty ? 'Countdown finished' : '$label — time!';
    try {
      await _plugin.zonedSchedule(
        idFor(timerId),
        title,
        'Reached zero — the timer keeps running for overtime.',
        tz.TZDateTime.from(when, tz.local),
        const NotificationDetails(android: _alert),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {}
  }

  /// Fire the alert immediately (used when the app itself notices zero).
  static Future<void> alertNow(String timerId, String label) async {
    await init();
    if (!_ready) return;
    final title =
        label.trim().isEmpty ? 'Countdown finished' : '$label — time!';
    try {
      await _plugin.show(idFor(timerId), title,
          'Reached zero — the timer keeps running for overtime.',
          const NotificationDetails(android: _alert));
    } catch (_) {}
  }

  /// Show/refresh the ongoing status-bar counter for a running timer. The
  /// system ticks it on its own from [whenEpochMs]; [countDown] shows remaining
  /// (going negative into overtime) for a countdown.
  static Future<void> showOngoing(String timerId, String title, String body,
      int whenEpochMs, bool countDown) async {
    await init();
    if (!_ready) return;
    final android = AndroidNotificationDetails(
      _ongoingChannel,
      'Running timers',
      channelDescription: 'A live counter while a timer runs.',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      showWhen: true,
      when: whenEpochMs,
      usesChronometer: true,
      chronometerCountDown: countDown,
    );
    try {
      await _plugin.show(ongoingIdFor(timerId), title,
          body.isEmpty ? null : body, NotificationDetails(android: android));
    } catch (_) {}
  }

  static Future<void> cancelAlert(String timerId) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(idFor(timerId));
    } catch (_) {}
  }

  static Future<void> cancelOngoing(String timerId) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(ongoingIdFor(timerId));
    } catch (_) {}
  }

  static Future<void> cancelAll(String timerId) async {
    await cancelAlert(timerId);
    await cancelOngoing(timerId);
  }
}
