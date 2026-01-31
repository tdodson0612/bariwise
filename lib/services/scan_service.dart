// lib/services/scan_service.dart
// Handles daily scan limits, premium bypass, and scan counters.

import '../config/app_config.dart';

import 'profile_service.dart';           // For getUserProfile + isPremium
import 'achievements_service.dart';     // For awardBadge
import 'database_service_core.dart';    // Worker queries + cache


class ScanService {

  // ==================================================
  // GET DAILY SCAN COUNT
  // ==================================================

  static Future<int> getDailyScanCount() async {
    final userId = DatabaseServiceCore.currentUserId;
    if (userId == null) return 0;

    try {
      final profile = await ProfileService.getUserProfile(userId);
      final today = DateTime.now().toIso8601String().split('T')[0];
      final lastScanDate = profile?['last_scan_date'] ?? '';

      // If new day → reset scans
      if (lastScanDate != today) {
        await DatabaseServiceCore.workerQuery(
          action: 'update',
          table: 'profiles',
          filters: {'id': userId},
          data: {
            'daily_scans_used': 0,
            'last_scan_date': today,
          },
        );

        await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
        await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');

        return 0;
      }

      return profile?['daily_scans_used'] ?? 0;
    } catch (e) {
      AppConfig.debugPrint('❌ getDailyScanCount error: $e');
      return 0;
    }
  }

  // ==================================================
  // CAN USER PERFORM A SCAN?
  // Premium users → unlimited
  // ==================================================

  static Future<bool> canPerformScan() async {
    try {
      if (await ProfileService.isPremiumUser()) return true;

      final count = await getDailyScanCount();
      return count < 3;
    } catch (_) {
      return true; // fail-safe
    }
  }

  // ==================================================
  // INCREMENT DAILY SCAN COUNT
  // Also triggers badge awards
  // ==================================================

  static Future<void> incrementScanCount() async {
    final userId = DatabaseServiceCore.currentUserId;
    if (userId == null) return;

    try {
      // Premium users → skip counting
      if (await ProfileService.isPremiumUser()) return;

      final currentCount = await getDailyScanCount();

      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'profiles',
        filters: {'id': userId},
        data: {
          'daily_scans_used': currentCount + 1,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');

      // Award badges (original behavior)
      try {
        await AchievementsService.awardBadge('first_scan');

        final totalScans = currentCount + 1;
        if (totalScans >= 10) await AchievementsService.awardBadge('scans_10');
        if (totalScans >= 50) await AchievementsService.awardBadge('scans_50');
      } catch (_) {}

    } catch (e) {
      throw Exception('Failed to update scan count: $e');
    }
  }
}