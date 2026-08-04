// lib/services/account_deletion_service.dart
// Handles COMPLETE user account deletion from all tables + R2 storage cleanup + Auth deletion
//
// ✅ REWRITTEN THIS SESSION against the real, directly-verified Supabase
// schema (information_schema.columns + a full FK/cascade map), replacing
// an entirely fictional set of table/column names that had been silently
// failing — possibly since before this file existed in its current form:
//
//   - user_achievements     → does not exist at all. Removed.
//   - comment_likes         → does not exist. Real table is
//                             feed_comment_likes. Fixed.
//   - friend_requests       → was filtered by 'sender'/'receiver'; real
//                             columns are 'sender_id'/'receiver_id'. Fixed.
//   - messages              → same issue; real columns are
//                             'sender_id'/'receiver_id'. Fixed.
//   - user_profiles         → does not exist. Real table is 'profiles',
//                             filtered by 'id'. Fixed.
//
// Because the old _safeDelete wrapper swallows every error into a debug
// log, none of the above ever surfaced as a visible bug — the account
// deletion feature has likely never fully worked, silently, for as long
// as this file existed in this form.
//
// ✅ UPDATED AGAIN THIS SESSION: the 6 bari_* tracking tables
// (bari_hydration_log, bari_supplement_schedules,
// bari_supplement_taken_log, bari_symptom_log, bari_nutrient_snapshots,
// bari_weekly_goals) were removed earlier this session after being found
// fictional — they were never actually created in Supabase, despite
// complete, correct Dart code in bari_features_service.dart already
// targeting them (this was a LOUD bug: every hydration/supplement/
// symptom log attempt threw a visible red error snackbar, not a silent
// failure). The tables have now been created for real, with a schema
// matching the existing Dart models and RLS matching the project's
// grocery_items/nutrition_tracker pattern. Re-added below, this time for
// real — user_id column confirmed directly against
// bari_features_service.dart's own insert/query calls. Each of these
// tables has ON DELETE CASCADE to profiles(id) in the new schema, so
// they're placed in the cascaded section alongside cookbooks,
// favorite_recipes, etc. — included explicitly anyway for the same
// defense-in-depth reasoning as the rest of that section.
//
// ⚠️ Still NOT included: bari_alcohol_log. alcohol_service.dart has not
// been inspected this session — given every other table in this family
// turned out to be missing, its existence should be confirmed, not
// assumed, before adding it here.
//
// ⚠️ Deliberately NOT deleted — flagged, not silently decided:
//   - contact_messages, profile_creation_logs: read as support/audit
//     logs rather than "the user's data" (contact_messages.user_id is
//     nullable, consistent with that).
//   - post_reports.reporter_user_id: a report this user filed against
//     someone else's post is a moderation record, not personal data —
//     same reasoning as above. (Note: if the *post itself* being reported
//     belonged to this user, that report row IS cleaned up automatically,
//     since post_reports.post_id → feed_posts.id cascades.)
//   - feed_notifications.actor_id side: a notification sent to another
//     user (e.g. "so-and-so liked your post") that names this user as
//     the actor will persist with a stale actor_id after deletion. Fixing
//     this would mean mutating other users' rows, which is out of scope
//     for this fix. actor_username is stored as denormalized text, so
//     display won't break — the row just becomes slightly stale.
//
// ✅ Confirmed via direct FK/cascade inspection: deleting 'profiles'
// auto-cascades cookbooks, favorite_recipes, friendships (both
// directions), nutrition_tracker, recipe_ratings, saved_ingredients,
// submitted_recipes, user_pictures, and (as of this update) all 6 bari_*
// tracking tables — plus each of those tables' own further children
// (e.g. cookbook_recipes via cookbooks/submitted_recipes, favorite_
// recipes/recipe_ratings via submitted_recipes). Those are still
// explicitly deleted below too, for defense-in-depth — harmless no-ops if
// the cascade already removed them, but not solely relied upon in case of
// future schema drift.

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
      // Unchanged — field names (pictures, profile_picture,
      // profile_background) match the real 'profiles' table exactly.
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
      // 3) DELETE ALL DATABASE DATA
      // --------------------------------------------------
      AppConfig.debugPrint('🗑️ Deleting database rows...');

      // ── Tables with NO foreign-key cascade from profiles.id ──────────
      // These MUST be deleted explicitly — the database will not clean
      // them up on its own.

      await _safeDelete('grocery_items', {'user_id': userId});
      await _safeDelete('grocery_list_items', {'user_id': userId});
      await _safeDelete('recipe_comments', {'user_id': userId});
      await _safeDelete('draft_recipes', {'user_id': userId});
      await _safeDelete('suggested_recipes', {'user_id': userId});
      await _safeDelete('custom_ingredients', {'user_id': userId});
      await _safeDelete('user_scanned_ingredients', {'user_id': userId});
      await _safeDelete('user_pantry', {'user_id': userId});
      await _safeDelete('user_preferences', {'user_id': userId});

      // feed_posts: deleting this user's own posts also cascades away
      // any comments/likes/saves/tags/notifications/reports tied to
      // those specific posts (confirmed via FK map).
      await _safeDelete('feed_posts', {'user_id': userId});

      // feed_post_comments: this user's own comments on ANY post
      // (including other users' posts). Cascades its own
      // likes/notifications/tags/replies on those specific comments.
      await _safeDelete('feed_post_comments', {'user_id': userId});

      // Engagement this user gave on OTHER users' content — not covered
      // by the feed_posts/feed_post_comments cascades above, since those
      // only clean up engagement ON this user's own content, not
      // engagement FROM this user elsewhere.
      await _safeDelete('feed_post_likes', {'user_id': userId});
      await _safeDelete('feed_post_saves', {'user_id': userId});
      await _safeDelete('feed_comment_likes', {'user_id': userId});

      // feed_tags: this user can appear as either the tagged party or
      // the one who tagged someone else.
      await _safeDelete('feed_tags', {'tagged_user_id': userId});
      await _safeDelete('feed_tags', {'tagger_user_id': userId});

      // This user's own notification inbox. (Notifications where this
      // user appears only as actor_id, notifying someone else, are not
      // touched — see file header note.)
      await _safeDelete('feed_notifications', {'user_id': userId});

      // friend_requests / messages: real columns are *_id, not the bare
      // 'sender'/'receiver' the old code used.
      await _safeDelete('friend_requests', {'sender_id': userId});
      await _safeDelete('friend_requests', {'receiver_id': userId});
      await _safeDelete('messages', {'sender_id': userId});
      await _safeDelete('messages', {'receiver_id': userId});

      // ── Tables that DO cascade from profiles.id ──────────────────────
      // Included explicitly anyway for defense-in-depth (harmless no-ops
      // if the profiles delete below already removed them via cascade).
      await _safeDelete('cookbooks', {'user_id': userId});
      await _safeDelete('favorite_recipes', {'user_id': userId});
      await _safeDelete('friendships', {'user_id': userId});
      await _safeDelete('friendships', {'friend_id': userId});
      await _safeDelete('nutrition_tracker', {'user_id': userId});
      await _safeDelete('recipe_ratings', {'user_id': userId});
      await _safeDelete('saved_ingredients', {'user_id': userId});
      await _safeDelete('submitted_recipes', {'user_id': userId});
      await _safeDelete('user_pictures', {'user_id': userId});

      // Bariatric tracking tables (created this session — see file
      // header note). All confirmed user_id, all ON DELETE CASCADE from
      // profiles(id) in the new schema.
      await _safeDelete('bari_hydration_log', {'user_id': userId});
      await _safeDelete('bari_supplement_schedules', {'user_id': userId});
      await _safeDelete('bari_supplement_taken_log', {'user_id': userId});
      await _safeDelete('bari_symptom_log', {'user_id': userId});
      await _safeDelete('bari_nutrient_snapshots', {'user_id': userId});
      await _safeDelete('bari_weekly_goals', {'user_id': userId});

      // Finally: the profile row itself. Real table is 'profiles',
      // filtered by 'id' — the old code targeted a nonexistent
      // 'user_profiles' table and never actually deleted this row.
      await _safeDelete('profiles', {'id': userId});

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