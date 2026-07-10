// lib/services/recent_activity_tracker.dart
//
// In-memory tracker for two BBRS Home Workspace checklist items:
//   • Recently Used Section  — last few screens/recipes the user touched
//   • Smart Prompt Area      — single highest-priority contextual nudge
//
// UI/UX-ONLY PHASE: this is intentionally in-memory only. No SharedPreferences,
// no database, no persistence across app restarts. State resets on cold start
// by design — do not add storage here without re-confirming with engineering.
//
// Static-class pattern to match the existing AuthService / TrackerService style.

import '../config/app_config.dart';
import '../models/bari_models.dart';
import 'bari_features_service.dart';
import 'tracker_service.dart';

// ────────────────────────────────────────────────────────────────
// RECENTLY USED
// ────────────────────────────────────────────────────────────────

enum RecentItemType { screen, recipe }

class RecentItem {
  final RecentItemType type;
  final String label;
  final String? route; // for screens
  final String? recipeId; // for recipes, if/when available
  final DateTime viewedAt;
  final String icon; // emoji, simplest cross-platform option for now

  RecentItem({
    required this.type,
    required this.label,
    required this.viewedAt,
    required this.icon,
    this.route,
    this.recipeId,
  });
}

class RecentActivityTracker {
  RecentActivityTracker._(); // static-only, no instances

  static const int _maxItems = 8;

  // In-memory only — intentionally not persisted. Resets on app restart.
  static final List<RecentItem> _recentItems = [];

  /// Record that a screen was visited. Call this from a screen's initState
  /// (or didChangeDependencies) for any page worth surfacing in "Recently Used."
  static void recordScreen({required String label, required String route}) {
    _recordItem(RecentItem(
      type: RecentItemType.screen,
      label: label,
      route: route,
      viewedAt: DateTime.now(),
      icon: '📄',
    ));
  }

  /// Record that a recipe was viewed.
  static void recordRecipe({required String label, String? recipeId}) {
    _recordItem(RecentItem(
      type: RecentItemType.recipe,
      label: label,
      recipeId: recipeId,
      viewedAt: DateTime.now(),
      icon: '🍽️',
    ));
  }

  static void _recordItem(RecentItem item) {
    // De-dupe: if the same label+type was already recently viewed, move it
    // to the front instead of creating a second entry.
    _recentItems.removeWhere(
        (existing) => existing.type == item.type && existing.label == item.label);

    _recentItems.insert(0, item);

    if (_recentItems.length > _maxItems) {
      _recentItems.removeRange(_maxItems, _recentItems.length);
    }

    AppConfig.debugPrint(
        '🕒 Recent activity recorded: ${item.type.name} — ${item.label}');
  }

  /// Returns the most recent items, newest first, capped at [limit].
  static List<RecentItem> getRecent({int limit = 5}) {
    return _recentItems.take(limit).toList();
  }

  /// Clears all recent activity. Useful on sign-out.
  static void clear() {
    _recentItems.clear();
  }
}

// ────────────────────────────────────────────────────────────────
// SMART PROMPT
// ────────────────────────────────────────────────────────────────

enum SmartPromptKind { hydration, supplement, nutrition, symptomCheckIn }

class SmartPrompt {
  final SmartPromptKind kind;
  final String title;
  final String message;
  final String route;
  final String icon;
  final String actionLabel;

  const SmartPrompt({
    required this.kind,
    required this.title,
    required this.message,
    required this.route,
    required this.icon,
    required this.actionLabel,
  });
}

class SmartPromptService {
  SmartPromptService._();

  // In-memory dismissal tracking — resets each session, per UI/UX-only phase.
  static final Set<SmartPromptKind> _dismissedThisSession = {};

  static void dismiss(SmartPromptKind kind) {
    _dismissedThisSession.add(kind);
  }

  static void resetDismissals() {
    _dismissedThisSession.clear();
  }

  /// Evaluates all triggers in priority order — hydration, supplements,
  /// nutrition, then symptom check-in — and returns the single highest
  /// priority prompt to show, or null if nothing applies (or everything
  /// applicable was already dismissed this session).
  static Future<SmartPrompt?> getCurrentPrompt({required String userId}) async {
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    // 1. Hydration — nothing logged yet today.
    if (!_dismissedThisSession.contains(SmartPromptKind.hydration)) {
      try {
        final cups = await BariFeaturesService.getTodayCups(
          todayStart.toIso8601String().split('T').first,
        );
        if (cups <= 0) {
          return const SmartPrompt(
            kind: SmartPromptKind.hydration,
            title: 'Stay on track with water',
            message: "You haven't logged any water yet today.",
            route: '/hydration-log',
            icon: '💧',
            actionLabel: 'Log Water',
          );
        }
      } catch (e) {
        AppConfig.debugPrint('⚠️ SmartPrompt hydration check failed: $e');
      }
    }

    // 2. Supplements — a schedule exists whose time has passed with no
    //    matching taken-log entry today.
    if (!_dismissedThisSession.contains(SmartPromptKind.supplement)) {
      try {
        final schedules = await BariFeaturesService.getSupplementSchedules();
        if (schedules.isNotEmpty) {
          final takenToday = await BariFeaturesService.getSupplementTakenLog(
            from: todayStart,
            to: todayEnd,
          );

          final nowMinutes = today.hour * 60 + today.minute;

          for (final schedule in schedules) {
            final alreadyTaken = takenToday.any((t) =>
                t.scheduleId == schedule.id || t.name == schedule.name);
            if (alreadyTaken) continue;

            final scheduleMinutes = _parseTimeOfDayToMinutes(schedule.timeOfDay);
            if (scheduleMinutes != null && scheduleMinutes <= nowMinutes) {
              return SmartPrompt(
                kind: SmartPromptKind.supplement,
                title: 'Supplement reminder',
                message: '${schedule.name} (${schedule.dose}) is due.',
                route: '/supplement-schedule',
                icon: '💊',
                actionLabel: 'View Schedule',
              );
            }
          }
        }
      } catch (e) {
        AppConfig.debugPrint('⚠️ SmartPrompt supplement check failed: $e');
      }
    }

    // 3. Nutrition — no meals logged yet today.
    if (!_dismissedThisSession.contains(SmartPromptKind.nutrition)) {
      try {
        final dateStr = todayStart.toIso8601String().split('T').first;
        final entry = await TrackerService.getEntryForDate(userId, dateStr);
        if (entry == null || entry.meals.isEmpty) {
          return const SmartPrompt(
            kind: SmartPromptKind.nutrition,
            title: "Log today's nutrition",
            message: "You haven't logged any meals yet today.",
            route: '/tracker',
            icon: '🍽️',
            actionLabel: 'Log a Meal',
          );
        }
      } catch (e) {
        AppConfig.debugPrint('⚠️ SmartPrompt nutrition check failed: $e');
      }
    }

    // 4. Symptom check-in — soft, low-frequency nudge only. Not a "you
    //    missed something" prompt — symptoms are reactive, not scheduled.
    //    Only surfaces if no symptom log activity in 7+ days, and is framed
    //    as an open, optional check-in rather than a compliance reminder.
    if (!_dismissedThisSession.contains(SmartPromptKind.symptomCheckIn)) {
      try {
        final sevenDaysAgo = today.subtract(const Duration(days: 7));
        final recent = await BariFeaturesService.getSymptomLog(from: sevenDaysAgo);
        if (recent.isEmpty) {
          return const SmartPrompt(
            kind: SmartPromptKind.symptomCheckIn,
            title: 'How are you feeling?',
            message: 'It\'s been a while since your last check-in.',
            route: '/symptom-log',
            icon: '📋',
            actionLabel: 'Check In',
          );
        }
      } catch (e) {
        AppConfig.debugPrint('⚠️ SmartPrompt symptom check failed: $e');
      }
    }

    return null;
  }

  /// Parses a "HH:mm" string (as used by SupplementSchedule.timeOfDay,
  /// per the time-picker options in supplement_schedule_page.dart) into
  /// minutes since midnight. Returns null if unparseable.
  static int? _parseTimeOfDayToMinutes(String timeOfDay) {
    final parts = timeOfDay.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }
}