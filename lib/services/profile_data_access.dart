// lib/services/profile_data_access.dart
// Neutral data-access layer for profile reads/updates.
// Breaks circular dependency between AuthService ↔ ProfileService.

import 'database_service_core.dart';

class ProfileDataAccess {
  // ==================================================
  // GET USER PROFILE
  // ==================================================
  static Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    final result = await DatabaseServiceCore.workerQuery(
      action: 'select',
      table: 'profiles',
      filters: {'id': userId},
      limit: 1,
    );

    if (result == null || (result as List).isEmpty) return null;
    return result[0];
  }

  // ==================================================
  // CREATE USER PROFILE
  // ==================================================
  static Future<void> createUserProfile(
    String userId,
    String email, {
    required bool isPremium,
  }) async {
    await DatabaseServiceCore.workerQuery(
      action: 'insert',
      table: 'profiles',
      requireAuth: true,
      data: {
        'id': userId,
        'email': email,
        'is_premium': isPremium,
        'daily_scans_used': 0,
        'last_scan_date': DateTime.now().toIso8601String().split('T')[0],
        'created_at': DateTime.now().toIso8601String(),
        'username': email.split('@')[0],
        'friends_list_visible': true,
        'xp': 0,
        'level': 1,
      },
    );
  }

  // ==================================================
  // UPDATE PREMIUM STATUS
  // ==================================================
  static Future<void> setPremium(String userId, bool isPremium) async {
    await DatabaseServiceCore.workerQuery(
      action: 'update',
      table: 'profiles',
      filters: {'id': userId},
      data: {
        'is_premium': isPremium,
        'updated_at': DateTime.now().toIso8601String(),
      },
    );

    await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
    await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');
  }
}
