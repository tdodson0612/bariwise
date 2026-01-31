// lib/services/friends_visibility_service.dart
// Handles friend list visibility + fetching a user's friends list

import '../config/app_config.dart';
import 'database_service_core.dart';
import 'profile_service.dart';

class FriendsVisibilityService {
  // ==================================================
  // FETCH USER'S FRIEND LIST (public view)
  // ==================================================
  static Future<List<Map<String, dynamic>>> getUserFriends(String userId) async {
    try {
      // Pull all accepted requests (Worker cannot do OR filters directly)
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'friend_requests',
        columns: ['*'],
        filters: {'status': 'accepted'},
      );

      // Safety check: ensure response is a List
      if (response is! List) {
        AppConfig.debugPrint('⚠️ getUserFriends: response is not a List');
        return [];
      }

      final friends = <Map<String, dynamic>>[];

      for (var row in response) {
        try {
          if (row['sender'] == userId || row['receiver'] == userId) {
            final friendId =
                row['sender'] == userId ? row['receiver'] : row['sender'];

            final friendProfile = await DatabaseServiceCore.workerQuery(
              action: 'select',
              table: 'profiles',
              columns: [
                'id',
                'email',
                'username',
                'first_name',
                'last_name',
                'avatar_url'
              ],
              filters: {'id': friendId},
              limit: 1,
            );

            if (friendProfile != null && (friendProfile as List).isNotEmpty) {
              friends.add(friendProfile[0]);
            }
          }
        } catch (e) {
          // Skip this friend if there's an error fetching their profile
          AppConfig.debugPrint('⚠️ Failed to fetch friend profile: $e');
          continue;
        }
      }

      return friends;
    } catch (e) {
      AppConfig.debugPrint('❌ getUserFriends error: $e');
      return []; // Return empty list instead of throwing
    }
  }

  // ==================================================
  // GET VISIBILITY SETTING
  // ==================================================
  static Future<bool> getFriendsListVisibility() async {
    if (DatabaseServiceCore.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    try {
      final profile = await ProfileService.getUserProfile(
        DatabaseServiceCore.currentUserId!,
      );
      return profile?['friends_list_visible'] ?? true;
    } catch (_) {
      return true; // default to visible
    }
  }

  // ==================================================
  // UPDATE VISIBILITY SETTING
  // ==================================================
  static Future<void> updateFriendsListVisibility(bool isVisible) async {
    if (DatabaseServiceCore.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    final userId = DatabaseServiceCore.currentUserId!;

    try {
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'profiles',
        filters: {'id': userId},
        data: {
          'friends_list_visible': isVisible,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');
    } catch (e) {
      throw Exception('Failed to update visibility setting: $e');
    }
  }
}