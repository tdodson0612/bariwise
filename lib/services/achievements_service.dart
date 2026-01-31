// lib/services/achievements_service.dart
// Handles badges, achievements, and XP rewards

import 'dart:convert';
import '../config/app_config.dart';         // auth + user profile
import 'database_service_core.dart';     // workerQuery + cache
import 'xp_reward_service.dart';


class AchievementsService {

  // ==================================================
  // GET ALL BADGES (CACHED)
  // ==================================================

  static Future<List<Map<String, dynamic>>> getAllBadges() async {
    try {
      const cacheKey = 'cache_badges';

      // Try cache first
      final cached = await DatabaseServiceCore.getCachedData(cacheKey);
      if (cached != null) {
        return List<Map<String, dynamic>>.from(jsonDecode(cached));
      }

      // Fetch from Worker
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'badges',
        columns: ['*'],
        orderBy: 'xp_reward',
        ascending: true,
      );

      final badges = List<Map<String, dynamic>>.from(response as List);

      // Cache it
      await DatabaseServiceCore.cacheData(cacheKey, jsonEncode(badges));

      return badges;
    } catch (e) {
      throw Exception('Failed to get badges: $e');
    }
  }

  // ==================================================
  // GET USER BADGES (CACHED)
  // ==================================================

  static Future<List<Map<String, dynamic>>> getUserBadges(String userId) async {
    try {
      final cacheKey = 'cache_user_badges_$userId';

      final cached = await DatabaseServiceCore.getCachedData(cacheKey);
      if (cached != null) {
        return List<Map<String, dynamic>>.from(jsonDecode(cached));
      }

      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'user_achievements',
        columns: ['*'],
        filters: {'user_id': userId},
        orderBy: 'earned_at',
        ascending: false,
      );

      final badges = List<Map<String, dynamic>>.from(response);

      await DatabaseServiceCore.cacheData(cacheKey, jsonEncode(badges));

      return badges;
    } catch (e) {
      throw Exception('Failed to get user badges: $e');
    }
  }

  // ==================================================
  // AWARD BADGE (ALSO GIVES XP)
  // ==================================================

  static Future<bool> awardBadge(String badgeId) async {
    DatabaseServiceCore.ensureUserAuthenticated();
    final userId = DatabaseServiceCore.currentUserId!;

    try {
      // Check existing
      final existing = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'user_achievements',
        columns: ['*'],
        filters: {
          'user_id': userId,
          'badge_id': badgeId,
        },
        limit: 1,
      );

      if (existing != null && (existing as List).isNotEmpty) {
        return false; // Already earned
      }

      // Add badge
      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'user_achievements',
        data: {
          'user_id': userId,
          'badge_id': badgeId,
          'earned_at': DateTime.now().toIso8601String(),
        },
      );

      // Invalidate cache
      await DatabaseServiceCore.clearCache('cache_user_badges_$userId');

      // Fetch badge XP reward
      final badgeData = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'badges',
        columns: ['xp_reward'],
        filters: {'id': badgeId},
        limit: 1,
      );
      if (badgeData != null &&
          (badgeData as List).isNotEmpty &&
          badgeData[0]['xp_reward'] != null &&
          badgeData[0]['xp_reward'] > 0) {

        await XpRewardService.rewardXPFromBadge(
          badgeData[0]['xp_reward'],
          badgeId,
        );
      }


      return true;
    } catch (e) {
      AppConfig.debugPrint('❌ awardBadge error: $e');
      return false;
    }
  }

  // ==================================================
  // CHECK ACHIEVEMENTS (RECIPE COUNT → BADGES)
  // ==================================================

  static Future<void> checkAchievements() async {
    DatabaseServiceCore.ensureUserAuthenticated();
    final userId = DatabaseServiceCore.currentUserId!;

    try {
      // Count submitted recipes
      final recipes = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'submitted_recipes',
        columns: ['id'],
        filters: {'user_id': userId},
      );

      final count = (recipes as List).length;

      if (count >= 1) await awardBadge('first_recipe');
      if (count >= 5) await awardBadge('recipe_5');
      if (count >= 25) await awardBadge('recipe_25');
      if (count >= 50) await awardBadge('recipe_50');
      if (count >= 100) await awardBadge('recipe_100');

    } catch (e) {
      AppConfig.debugPrint('⚠️ Error checking achievements: $e');
    }
  }
}
