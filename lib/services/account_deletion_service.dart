// lib/services/account_deletion_service.dart
// Handles COMPLETE user account deletion from all tables + R2 storage cleanup + Auth deletion

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import 'database_service_core.dart';
import 'profile_service.dart';

class AccountDeletionService {

  // ==================================================
  // DELETE ACCOUNT COMPLETELY
  // ==================================================
  static Future<void> deleteAccountCompletely() async {
    DatabaseServiceCore.ensureUserAuthenticated();
    final userId = DatabaseServiceCore.currentUserId!;
    
    // Get auth token before deletion
    final authToken = Supabase.instance.client.auth.currentSession?.accessToken;
    if (authToken == null) {
      throw Exception('No authentication session found. Please sign out and sign back in.');
    }

    try {
      AppConfig.debugPrint('🗑️ Starting account deletion for $userId');

      // --------------------------------------------------
      // 1) GET PROFILE (to read picture URLs)
      // --------------------------------------------------
      AppConfig.debugPrint('📋 Fetching profile...');
      final profile = await ProfileService.getUserProfile(userId);

      final picturesJson = profile?['pictures'];
      final profilePicUrl = profile?['profile_picture'];
      final bgPicUrl = profile?['profile_background'];

      // --------------------------------------------------
      // 2) DELETE ALL R2 STORAGE FILES (gallery, profile, background)
      // --------------------------------------------------
      // Gallery
      if (picturesJson != null && picturesJson.isNotEmpty) {
        try {
          final pics = List<String>.from(jsonDecode(picturesJson));

          AppConfig.debugPrint('🗑️ Deleting ${pics.length} gallery pictures...');
          for (final url in pics) {
            try {
              await DatabaseServiceCore.deleteFileByPublicUrl(url);
            } catch (e) {
              AppConfig.debugPrint('⚠️ Failed to delete gallery picture: $e');
            }
          }
        } catch (e) {
          AppConfig.debugPrint('⚠️ Failed to parse gallery JSON: $e');
        }
      }

      // Profile picture
      if (profilePicUrl is String && profilePicUrl.isNotEmpty) {
        try {
          AppConfig.debugPrint('🗑️ Deleting profile picture...');
          await DatabaseServiceCore.deleteFileByPublicUrl(profilePicUrl);
        } catch (e) {
          AppConfig.debugPrint('⚠️ Failed to delete profile picture: $e');
        }
      }

      // Background picture
      if (bgPicUrl is String && bgPicUrl.isNotEmpty) {
        try {
          AppConfig.debugPrint('🗑️ Deleting background picture...');
          await DatabaseServiceCore.deleteFileByPublicUrl(bgPicUrl);
        } catch (e) {
          AppConfig.debugPrint('⚠️ Failed to delete background picture: $e');
        }
      }

      // --------------------------------------------------
      // 3) DELETE ALL DATABASE DATA (children → parents)
      // --------------------------------------------------
      AppConfig.debugPrint('🗑️ Deleting database rows...');

      // Grocery items
      await _safeDelete('grocery_items', {'user_id': userId});

      // Submitted recipes
      await _safeDelete('submitted_recipes', {'user_id': userId});

      // Favorite recipes
      await _safeDelete('favorite_recipes', {'user_id': userId});

      // Achievements
      await _safeDelete('user_achievements', {'user_id': userId});

      // Recipe ratings
      await _safeDelete('recipe_ratings', {'user_id': userId});

      // Recipe comments
      await _safeDelete('recipe_comments', {'user_id': userId});

      // Comment likes
      await _safeDelete('comment_likes', {'user_id': userId});

      // Friend requests (sender)
      await _safeDelete('friend_requests', {'sender': userId});

      // Friend requests (receiver)
      await _safeDelete('friend_requests', {'receiver': userId});

      // Messages (sent)
      await _safeDelete('messages', {'sender': userId});

      // Messages (received)
      await _safeDelete('messages', {'receiver': userId});

      // Finally: user profile
      await _safeDelete('user_profiles', {'id': userId});

      // --------------------------------------------------
      // 4) DELETE AUTH USER (via Cloudflare Worker)
      // --------------------------------------------------
      AppConfig.debugPrint('🗑️ Deleting authentication user...');
      
      try {
        final response = await http.post(
          Uri.parse('${AppConfig.cloudflareWorkerQueryEndpoint}/auth/delete-user'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'userId': userId,
            'authToken': authToken,
          }),
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw Exception('Auth deletion timed out'),
        );

        if (response.statusCode != 200) {
          final errorBody = response.body;
          AppConfig.debugPrint('❌ Auth user deletion failed: ${response.statusCode} - $errorBody');
          throw Exception('Failed to delete auth user: $errorBody');
        }

        final result = jsonDecode(response.body);
        AppConfig.debugPrint('✅ Auth user deleted: ${result['message']}');
      } catch (e) {
        AppConfig.debugPrint('❌ Auth deletion error: $e');
        // Don't throw here - data is already deleted, just log the error
        AppConfig.debugPrint('⚠️ Auth user may still exist, but all data has been deleted');
      }

      // --------------------------------------------------
      // 5) CLEAR LOCAL CACHE
      // --------------------------------------------------
      AppConfig.debugPrint('🧹 Clearing local cache...');
      await DatabaseServiceCore.clearAllUserCache();

      AppConfig.debugPrint('✅ Account deletion successfully completed.');
    } catch (e) {
      AppConfig.debugPrint('❌ deleteAccountCompletely error: $e');
      throw Exception("Failed to delete account: $e");
    }
  }

  // ==================================================
  // Helper: SAFE DELETE WRAPPER
  // ==================================================
  static Future<void> _safeDelete(
    String table,
    Map<String, dynamic> filters,
  ) async {
    try {
      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: table,
        filters: filters,
      );
      AppConfig.debugPrint('✔ Deleted $table (filters: $filters)');
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error deleting $table: $e');
    }
  }
}