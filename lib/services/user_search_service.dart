// lib/services/user_search_service.dart

import 'dart:async';
import '../config/app_config.dart';
import 'auth_service.dart';
import 'database_service_core.dart';

class UserSearchService {

  // ==================================================
  // SEARCH USERS
  // ==================================================

  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    AuthService.ensureLoggedIn();

    final search = query.trim().toLowerCase();
    if (search.isEmpty) return [];

    List<dynamic> users = [];

    // Two attempts with a short delay between them
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await DatabaseServiceCore.workerQuery(
          action: 'select',
          table: 'profiles',
          columns: ['id', 'email', 'username', 'first_name', 'last_name',
                    'avatar_url', 'profile_picture_url'],
          limit: 200,
        ).timeout(const Duration(seconds: 15));

        users = response as List;
        break; // success — exit retry loop

      } on TimeoutException {
        AppConfig.debugPrint('⏱️ searchUsers attempt ${attempt + 1} timed out');
        if (attempt < 1) {
          await Future.delayed(const Duration(milliseconds: 800));
        } else {
          throw Exception('Search timed out. Please check your connection and try again.');
        }
      } catch (e) {
        AppConfig.debugPrint('❌ searchUsers attempt ${attempt + 1} failed: $e');
        if (attempt < 1) {
          await Future.delayed(const Duration(milliseconds: 800));
        } else {
          throw Exception('Search failed. Please check your connection and try again.');
        }
      }
    }

    final currentId = AuthService.currentUserId;
    final results = <Map<String, dynamic>>[];

    for (final user in users) {
      if (user['id'] == currentId) continue;

      final email    = (user['email']      ?? '').toLowerCase();
      final username = (user['username']   ?? '').toLowerCase();
      final first    = (user['first_name'] ?? '').toLowerCase();
      final last     = (user['last_name']  ?? '').toLowerCase();

      if (email.contains(search) ||
          username.contains(search) ||
          first.contains(search) ||
          last.contains(search)) {
        results.add(Map<String, dynamic>.from(user));
      }
    }

    AppConfig.debugPrint('✅ searchUsers("$search"): ${results.length} results');
    return results;
  }

  // ==================================================
  // GET SUGGESTED FRIENDS BY EMAIL
  // ==================================================

  static Future<List<Map<String, dynamic>>> getSuggestedFriendsByEmail(
      List<String> emails) async {
    AuthService.ensureLoggedIn();

    final normalizedEmails = emails.map((e) => e.toLowerCase().trim()).toList();
    List<dynamic> users = [];

    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await DatabaseServiceCore.workerQuery(
          action: 'select',
          table: 'profiles',
          columns: ['id', 'email', 'username', 'first_name', 'last_name',
                    'avatar_url', 'profile_picture_url'],
          limit: 200,
        ).timeout(const Duration(seconds: 15));

        users = response as List;
        break;

      } on TimeoutException {
        AppConfig.debugPrint('⏱️ getSuggestedFriendsByEmail attempt ${attempt + 1} timed out');
        if (attempt < 1) {
          await Future.delayed(const Duration(milliseconds: 800));
        } else {
          throw Exception('Request timed out. Please try again.');
        }
      } catch (e) {
        AppConfig.debugPrint('❌ getSuggestedFriendsByEmail attempt ${attempt + 1} failed: $e');
        if (attempt < 1) {
          await Future.delayed(const Duration(milliseconds: 800));
        } else {
          throw Exception('Failed to load suggested friends. Please try again.');
        }
      }
    }

    final currentId = AuthService.currentUserId;
    final results = <Map<String, dynamic>>[];

    for (final user in users) {
      if (user['id'] == currentId) continue;
      final userEmail = (user['email'] ?? '').toLowerCase().trim();
      if (normalizedEmails.contains(userEmail)) {
        results.add(Map<String, dynamic>.from(user));
        AppConfig.debugPrint('  ✅ Matched: $userEmail (${user['username'] ?? 'no username'})');
      }
    }

    AppConfig.debugPrint('✅ getSuggestedFriendsByEmail: ${results.length}/${emails.length} found');
    return results;
  }

  // ==================================================
  // GET SUGGESTED FRIENDS BY ID (kept for compatibility)
  // ==================================================

  static Future<List<Map<String, dynamic>>> getSuggestedFriends(
      List<String> ownerIds) async {
    AuthService.ensureLoggedIn();

    List<dynamic> users = [];

    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await DatabaseServiceCore.workerQuery(
          action: 'select',
          table: 'profiles',
          columns: ['id', 'email', 'username', 'first_name', 'last_name',
                    'avatar_url', 'profile_picture_url'],
          limit: 200,
        ).timeout(const Duration(seconds: 15));

        users = response as List;
        break;

      } on TimeoutException {
        if (attempt < 1) {
          await Future.delayed(const Duration(milliseconds: 800));
        } else {
          throw Exception('Request timed out. Please try again.');
        }
      } catch (e) {
        if (attempt < 1) {
          await Future.delayed(const Duration(milliseconds: 800));
        } else {
          throw Exception('Failed to load suggested friends. Please try again.');
        }
      }
    }

    final currentId = AuthService.currentUserId;
    final results = <Map<String, dynamic>>[];

    for (final user in users) {
      if (user['id'] == currentId) continue;
      if (ownerIds.contains(user['id'])) {
        results.add(Map<String, dynamic>.from(user));
      }
    }

    AppConfig.debugPrint('✅ getSuggestedFriends: ${results.length} found');
    return results;
  }

  // ==================================================
  // DEBUG TEST
  // ==================================================

  static Future<void> debugTestUserSearch() async {
    AuthService.ensureLoggedIn();

    try {
      AppConfig.debugPrint('🔍 DEBUG: Starting user search test...');
      AppConfig.debugPrint('📝 Current user ID: ${AuthService.currentUserId}');

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
      for (final user in list) {
        AppConfig.debugPrint('  👤 ${user['username'] ?? user['email']}');
      }

      AppConfig.debugPrint('\n--- TEST 2: Searching for "test" ---');
      final results = await searchUsers('test');
      AppConfig.debugPrint('Search returned ${results.length} result(s).');

      AppConfig.debugPrint('\n--- TEST 3: Email lookup ---');
      const testEmails = ['terryd0612@gmail.com', 'bbrc2021bbc1298.442@icloud.com'];
      final emailResults = await getSuggestedFriendsByEmail(testEmails);
      AppConfig.debugPrint('Email lookup returned ${emailResults.length} result(s).');
      for (final user in emailResults) {
        AppConfig.debugPrint(
            '  👤 ${user['email']} — ${user['first_name'] ?? 'No name'} ${user['last_name'] ?? ''}');
      }

      AppConfig.debugPrint('\n✅ DEBUG TEST COMPLETED.');
    } catch (e) {
      AppConfig.debugPrint('❌ DEBUG TEST FAILED: $e');
      throw Exception('Debug test failed: $e');
    }
  }
}