// lib/services/user_search_service.dart
// Handles searching for users by username, email, first/last name

import '../config/app_config.dart';
import 'auth_service.dart';             // For ensureLoggedIn + currentUserId
import 'database_service_core.dart';    // Worker query

class UserSearchService {
  // ==================================================
  // SEARCH USERS (LOCAL FILTERING)
  // ==================================================
  
  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    AuthService.ensureLoggedIn();

    final search = query.trim().toLowerCase();
    if (search.isEmpty) return [];

    try {
      // Fetch all users (Worker cannot do OR filtering)
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'profiles',
        columns: ['id', 'email', 'username', 'first_name', 'last_name', 'avatar_url', 'profile_picture_url'],
        limit: 200,
      );

      final List<dynamic> users = response as List;
      final currentId = AuthService.currentUserId;
      final List<Map<String, dynamic>> results = [];

      for (var user in users) {
        // Skip yourself
        if (user['id'] == currentId) continue;

        final email = (user['email'] ?? '').toLowerCase();
        final username = (user['username'] ?? '').toLowerCase();
        final first = (user['first_name'] ?? '').toLowerCase();
        final last = (user['last_name'] ?? '').toLowerCase();

        if (email.contains(search) ||
            username.contains(search) ||
            first.contains(search) ||
            last.contains(search)) {
          results.add(user);
        }
      }

      return results;
    } catch (e) {
      AppConfig.debugPrint('❌ Failed to search users: $e');
      throw Exception('Failed to search users: $e');
    }
  }

  // ==================================================
  // GET SUGGESTED FRIENDS (APP OWNERS BY ID)
  // ==================================================
  
  static Future<List<Map<String, dynamic>>> getSuggestedFriends(List<String> ownerIds) async {
    AuthService.ensureLoggedIn();

    try {
      AppConfig.debugPrint('👥 Fetching suggested friends (app owners)...');

      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'profiles',
        columns: ['id', 'email', 'username', 'first_name', 'last_name', 'avatar_url', 'profile_picture_url'],
        limit: 200,
      );

      final List<dynamic> users = response as List;
      final currentId = AuthService.currentUserId;

      // Filter to only include owner accounts (and not current user)
      final List<Map<String, dynamic>> suggested = [];
      for (var user in users) {
        if (user['id'] != currentId && ownerIds.contains(user['id'])) {
          suggested.add(user);
        }
      }

      AppConfig.debugPrint('✅ Found ${suggested.length} suggested friends');
      return suggested;
    } catch (e) {
      AppConfig.debugPrint('❌ Failed to fetch suggested friends: $e');
      throw Exception('Failed to fetch suggested friends: $e');
    }
  }

  // ==================================================
  // 🔥 NEW: GET SUGGESTED FRIENDS BY EMAIL
  // ==================================================
  
  static Future<List<Map<String, dynamic>>> getSuggestedFriendsByEmail(List<String> emails) async {
    AuthService.ensureLoggedIn();

    try {
      AppConfig.debugPrint('🔍 Looking up users by emails: $emails');

      // Fetch all users
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'profiles',
        columns: ['id', 'email', 'username', 'first_name', 'last_name', 'avatar_url', 'profile_picture_url'],
        limit: 200,
      );

      final List<dynamic> users = response as List;
      final currentId = AuthService.currentUserId;

      // Filter to only include users with matching emails (and not current user)
      final List<Map<String, dynamic>> suggested = [];
      final normalizedEmails = emails.map((e) => e.toLowerCase().trim()).toList();

      for (var user in users) {
        final userEmail = (user['email'] ?? '').toLowerCase().trim();
        
        // Skip yourself
        if (user['id'] == currentId) {
          AppConfig.debugPrint('  ⏭️ Skipping self: $userEmail');
          continue;
        }

        // Check if this user's email matches any of the target emails
        if (normalizedEmails.contains(userEmail)) {
          suggested.add(user);
          AppConfig.debugPrint('  ✅ Found match: $userEmail (${user['username'] ?? 'no username'})');
        }
      }

      AppConfig.debugPrint('✅ Found ${suggested.length} users from ${emails.length} emails');
      
      if (suggested.isEmpty) {
        AppConfig.debugPrint('⚠️ WARNING: No users found with emails: $emails');
        AppConfig.debugPrint('   Make sure these emails exist in the database!');
      }

      return suggested;
    } catch (e) {
      AppConfig.debugPrint('❌ Failed to get suggested friends by email: $e');
      throw Exception('Failed to get suggested friends by email: $e');
    }
  }

  // ==================================================
  // DEBUG SEARCH TEST (DEVELOPER TOOL)
  // ==================================================
  
  static Future<void> debugTestUserSearch() async {
    AuthService.ensureLoggedIn();

    try {
      AppConfig.debugPrint('🔍 DEBUG: Starting user search test...');
      AppConfig.debugPrint('📝 Current user ID: ${AuthService.currentUserId}');

      // --- Fetch a few users ---
      AppConfig.debugPrint('\n--- TEST 1: Fetching sample users ---');
      final allUsers = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'profiles',
        columns: ['id', 'email', 'username', 'first_name', 'last_name'],
        limit: 10,
      );

      final list = (allUsers as List)
          .where((u) => u['id'] != AuthService.currentUserId)
          .toList();

      AppConfig.debugPrint('Found ${list.length} users:');
      for (var user in list) {
        AppConfig.debugPrint("  👤 ${user['username'] ?? user['email']}");
      }

      // --- Perform sample search ---
      AppConfig.debugPrint('\n--- TEST 2: Searching for "test" ---');
      final results = await searchUsers('test');
      AppConfig.debugPrint('Search returned ${results.length} result(s).');

      // --- Test email lookup ---
      AppConfig.debugPrint('\n--- TEST 3: Testing email lookup ---');
      final testEmails = ['terryd0612@gmail.com', 'bbrc2021bbc1298.442@icloud.com'];
      final emailResults = await getSuggestedFriendsByEmail(testEmails);
      AppConfig.debugPrint('Email lookup returned ${emailResults.length} result(s).');
      for (var user in emailResults) {
        AppConfig.debugPrint("  👤 ${user['email']} - ${user['first_name'] ?? 'No name'} ${user['last_name'] ?? ''}");
      }

      AppConfig.debugPrint('\n✅ DEBUG TEST COMPLETED.');
    } catch (e) {
      AppConfig.debugPrint('❌ DEBUG TEST FAILED: $e');
      throw Exception('Debug test failed: $e');
    }
  }
}