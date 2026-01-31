// lib/services/xp_service.dart
// Handles XP gaining, level calculation, and progress toward next level

import '../config/app_config.dart';
import 'auth_service.dart';              // For currentUserId + ensureLoggedIn()
import 'database_service_core.dart';     // Worker queries + cache helpers
import 'profile_service.dart';           // For getUserProfile()


class XPService {

  // ==================================================
  // ADD XP TO CURRENT USER
  // ==================================================

  static Future<Map<String, dynamic>> addXP(int xpAmount, {String? reason}) async {
    AuthService.ensureLoggedIn();
    final userId = AuthService.currentUserId!;

    try {
      // Fetch profile to get current XP + Level
      final profile = await ProfileService.getUserProfile(userId);
      final currentXP = profile?['xp'] ?? 0;
      final currentLevel = profile?['level'] ?? 1;

      final newXP = currentXP + xpAmount;
      final newLevel = _calculateLevel(newXP);
      final leveledUp = newLevel > currentLevel;

      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'profiles',
        filters: {'id': userId},
        data: {
          'xp': newXP,
          'level': newLevel,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      // Clear cached profile so UI updates immediately
      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');

      return {
        'xp_gained': xpAmount,
        'total_xp': newXP,
        'new_level': newLevel,
        'leveled_up': leveledUp,
        'reason': reason,
      };
    } catch (e) {
      AppConfig.debugPrint('❌ Failed to add XP: $e');
      throw Exception('Failed to add XP: $e');
    }
  }

  // ==================================================
  // LEVEL CALCULATION
  // ==================================================

  static int _calculateLevel(int xp) {
    int level = 1;
    int xpNeeded = 100;

    while (xp >= xpNeeded) {
      level++;
      xpNeeded += (level * 50);
    }
    return level;
  }

  // ==================================================
  // XP FOR NEXT LEVEL
  // ==================================================

  static int getXPForNextLevel(int currentLevel) {
    int xpNeeded = 100;
    for (int i = 2; i <= currentLevel + 1; i++) {
      xpNeeded += (i * 50);
    }
    return xpNeeded;
  }

  // ==================================================
  // LEVEL PROGRESS (0.0 -> 1.0)
  // ==================================================

  static double getLevelProgress(int currentXP, int currentLevel) {
    int xpForCurrent = getXPForNextLevel(currentLevel - 1);
    int xpForNext = getXPForNextLevel(currentLevel);

    final xpIntoLevel = currentXP - xpForCurrent;
    final xpNeeded = xpForNext - xpForCurrent;

    return xpIntoLevel / xpNeeded;
  }
}
