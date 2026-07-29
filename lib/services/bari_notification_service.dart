// lib/services/bari_notification_service.dart
// Schedules local notifications for hydration reminders and supplement alerts.
// Uses flutter_local_notifications (add to pubspec if not present).
// FCM is already set up in main.dart — this handles LOCAL scheduling only.
//
// Ported from liverwise liver_notification_service.dart.
// All channel IDs, preference keys, and copy updated for bariatric context.
//
// Notification ID ranges (avoid collisions with existing app notifications):
//   Hydration:  4000–4009
//   Supplement: 4100–4119
//   Check-in:   4200
//
// ── Section 14 addition (this session) ──────────────────────────────────
// setDailyCheckinReminder previously persisted no enabled-flag at all, so
// callers had no way to read current state back. Added _checkinNotifKey +
// isDailyCheckinReminderEnabled() getter, matching the pattern already used
// for hydration reminders. Additive only — every existing method, key, and
// behavior is unchanged.

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../config/app_config.dart';
import '../models/bari_models.dart';

class BariNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  // ── SharedPreferences keys ──────────────────────────────────────────────
  static const String _hydrNotifKey    = 'bari_hydration_notif_enabled';
  static const String _hydrIntervalKey = 'bari_hydration_interval_h';
  static const String _suppNotifKey    = 'bari_supplement_notif_enabled';
  // ✅ Added this session — see file header note.
  static const String _checkinNotifKey = 'bari_checkin_notif_enabled';

  // ── Notification channel IDs ────────────────────────────────────────────
  static const String _hydrChannelId    = 'bari_hydration';
  static const String _suppChannelId    = 'bari_supplement';
  static const String _checkinChannelId = 'bari_checkin';

  // ── Notification ID ranges ──────────────────────────────────────────────
  static const int _hydrBaseId  = 4000;
  static const int _suppBaseId  = 4100;
  static const int _checkinId   = 4200;

  // ================================================================
  // INIT
  // ================================================================

  static Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb) return; // No local notifications on web

    try {
      tz_data.initializeTimeZones();

      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false, // Requested in main.dart
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      _initialized = true;
      AppConfig.debugPrint('✅ BariNotificationService initialized');
    } catch (e) {
      AppConfig.debugPrint(
          '⚠️ BariNotificationService init failed: $e');
      // Non-fatal — app works without notifications
    }
  }

  static void _onNotificationTapped(NotificationResponse response) {
    AppConfig.debugPrint(
        '🔔 Notification tapped: ${response.payload}');
    // Navigation handled by calling widget via GlobalKey<NavigatorState>
    // Payload format: "route:/bari-dashboard"
  }

  // ================================================================
  // HYDRATION REMINDERS
  // ================================================================

  /// Enable or disable periodic hydration reminders.
  /// Post-bariatric patients must sip fluids constantly — reminders help.
  static Future<void> setHydrationReminders({
    required bool enabled,
    int intervalHours = 2, // Remind every N hours between 8am–9pm
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hydrNotifKey, enabled);
    await prefs.setInt(_hydrIntervalKey, intervalHours);

    // Cancel existing hydration notifications
    for (int i = 0; i < 10; i++) {
      await _plugin.cancel(_hydrBaseId + i);
    }

    if (!enabled) {
      AppConfig.debugPrint('🔕 Bariatric hydration reminders disabled');
      return;
    }

    // Schedule reminders from 8am to 9pm at intervalHours spacing
    const startHour = 8;
    const endHour = 21;
    int notifIndex = 0;

    for (int hour = startHour; hour <= endHour; hour += intervalHours) {
      await _scheduleDaily(
        id: _hydrBaseId + notifIndex,
        channelId: _hydrChannelId,
        channelName: 'Hydration Reminders',
        title: '💧 Time to hydrate!',
        body: 'Log a cup of water in BariWise to stay on track.',
        hour: hour,
        minute: 0,
        payload: 'route:/hydration-log',
      );
      notifIndex++;
      if (notifIndex >= 10) break;
    }

    AppConfig.debugPrint(
        '✅ Scheduled $notifIndex hydration reminders (every ${intervalHours}h)');
  }

  static Future<bool> isHydrationReminderEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hydrNotifKey) ?? false;
  }

  static Future<int> getHydrationReminderInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_hydrIntervalKey) ?? 2;
  }

  // ================================================================
  // SUPPLEMENT REMINDERS
  // ================================================================

  /// Schedule a daily notification for each active bariatric supplement schedule.
  /// Post-op patients require lifelong supplementation; reminders are critical.
  static Future<void> scheduleSupplementReminders(
      List<SupplementSchedule> schedules) async {
    // Cancel all existing supplement notifications
    for (int i = 0; i < 20; i++) {
      await _plugin.cancel(_suppBaseId + i);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_suppNotifKey, schedules.isNotEmpty);

    int notifIndex = 0;
    for (final schedule in schedules.take(20)) {
      if (!schedule.isActive) continue;

      final timeParts = schedule.timeOfDay.split(':');
      int hour = 8;
      int minute = 0;

      if (timeParts.length == 2) {
        hour = int.tryParse(timeParts[0]) ?? 8;
        minute = int.tryParse(timeParts[1]) ?? 0;
      } else {
        // Handle label-style time entries
        final label = schedule.timeOfDay.toLowerCase();
        if (label.contains('morning')) {
          hour = 8;
        } else if (label.contains('noon') || label.contains('lunch')) {
          hour = 12;
        } else if (label.contains('evening') || label.contains('night')) {
          hour = 20;
        }
      }

      await _scheduleDaily(
        id: _suppBaseId + notifIndex,
        channelId: _suppChannelId,
        channelName: 'Supplement Reminders',
        title: '💊 Supplement reminder',
        body: '${schedule.name} — ${schedule.dose}',
        hour: hour,
        minute: minute,
        payload: 'route:/supplement-schedule',
      );

      notifIndex++;
      AppConfig.debugPrint(
          '✅ Supplement notif scheduled: ${schedule.name} at '
          '$hour:${minute.toString().padLeft(2, "0")}');
    }
  }

  // ================================================================
  // DAILY CHECK-IN REMINDER
  // ================================================================

  /// Schedule (or cancel) the daily bariatric health check-in reminder.
  static Future<void> setDailyCheckinReminder({
    required bool enabled,
    int hour = 20, // 8pm default
    int minute = 0,
  }) async {
    // ✅ Added this session — persist the enabled flag so callers can read
    // it back (previously this method never stored any state at all).
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_checkinNotifKey, enabled);

    await _plugin.cancel(_checkinId);

    if (!enabled) {
      AppConfig.debugPrint('🔕 Daily bariatric check-in reminder disabled');
      return;
    }

    await _scheduleDaily(
      id: _checkinId,
      channelId: _checkinChannelId,
      channelName: 'Daily Check-in',
      title: '🩺 Daily bariatric check-in',
      body: 'Log today\'s symptoms, supplements, and water intake.',
      hour: hour,
      minute: minute,
      payload: 'route:/symptom-log',
    );

    AppConfig.debugPrint(
        '✅ Daily check-in scheduled at $hour:${minute.toString().padLeft(2, "0")}');
  }

  /// ✅ Added this session — getter to accompany the newly-persisted
  /// _checkinNotifKey above.
  static Future<bool> isDailyCheckinReminderEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_checkinNotifKey) ?? false;
  }

  // ================================================================
  // PRIVATE HELPERS
  // ================================================================

  static Future<void> _scheduleDaily({
    required int id,
    required String channelId,
    required String channelName,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String? payload,
  }) async {
    if (!_initialized) await initialize();

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    // If the scheduled time already passed today, push to tomorrow
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // repeat daily
      payload: payload,
    );
  }

  /// Cancel ALL bariatric feature notifications.
  static Future<void> cancelAll() async {
    for (int i = 0; i < 10; i++) {
      await _plugin.cancel(_hydrBaseId + i);
    }
    for (int i = 0; i < 20; i++) {
      await _plugin.cancel(_suppBaseId + i);
    }
    await _plugin.cancel(_checkinId);
    AppConfig.debugPrint('🔕 All bariatric notifications cancelled');
  }
}