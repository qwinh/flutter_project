// lib/services/notification_service.dart
// Wraps flutter_local_notifications.
// Call [init] once at startup (after WidgetsFlutterBinding.ensureInitialized).

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  int _idCounter = 0;

  static const _channelId = 'photovault_channel';
  static const _channelName = 'PhotoVault';
  static const _reminderNotificationId = 999;

  static const _androidDetails = AndroidNotificationDetails(
    _channelId,
    _channelName,
    channelDescription: 'PhotoVault notifications',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );
  static const _notifDetails = NotificationDetails(android: _androidDetails);

  Future<void> init() async {
    // Initialise timezone database and set local location.
    tz.initializeTimeZones();
    final tzInfo = await FlutterTimezone.getLocalTimezone();
    final tzName = tzInfo.identifier;
    tz.setLocalLocation(tz.getLocation(tzName));

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(
          android: androidSettings, iOS: darwinSettings),
    );

    await _scheduleOrganiseReminder();
  }

  /// Shows an immediate notification.
  Future<void> show(String title, String body) async {
    await _plugin.show(_idCounter++, title, body, _notifDetails);
  }

  /// Schedules a daily reminder at 20:00 to organise new photos.
  /// Uses [DateTimeComponents.time] so it repeats every day at that time.
  Future<void> _scheduleOrganiseReminder() async {
    await _plugin.cancel(_reminderNotificationId);

    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, 20, 0);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    const reminderDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'PhotoVault notifications',
        importance: Importance.low,
        priority: Priority.low,
      ),
    );

    await _plugin.zonedSchedule(
      _reminderNotificationId,
      'Organise your photos 📸',
      'You have new photos waiting to be added to an album.',
      scheduled,
      reminderDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Cancels the daily reminder (e.g. if the user opts out).
  Future<void> cancelReminder() => _plugin.cancel(_reminderNotificationId);
}

