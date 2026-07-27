// lib/services/database_service_core.dart
// CORE: Worker + Storage + Cache + Auth helpers only

import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class DatabaseServiceCore {
  static final SupabaseClient _supabase = Supabase.instance.client;

  // ==============================
  // PRIVATE CACHE KEYS (original)
  // ==============================
  static const String _cacheBadges = 'cache_badges';
  static const String _cacheUserBadges = 'cache_user_badges_';
  static const String _cacheUserProfile = 'cache_user_profile_';
  static const String _cacheProfileTimestamp = 'cache_profile_timestamp_';
  static const String _cacheFriends = 'cache_friends_';
  static const String _cacheMessages = 'cache_messages_';
  static const String _cacheLastMessageTime = 'cache_last_message_time_';
  static const String _cachePosts = 'cache_posts';
  static const String _cacheLastPostTime = 'cache_last_post_time';
  static const String _cacheUserPosts = 'cache_user_posts_';
  static const String _cacheSubmittedRecipes = 'cache_submitted_recipes';
  static const String _cacheFavoriteRecipes = 'cache_favorite_recipes';

  // ==============================
  // PRIVATE BUCKET NAMES
  // ==============================
  static const String _profileBucket = 'profile-pictures';
  static const String _backgroundBucket = 'background-pictures';
  static const String _albumBucket = 'photo-album';

  static const List<String> _knownBuckets = [
    _profileBucket,
    _backgroundBucket,
    _albumBucket,
  ];

  // ==============================
  // PUBLIC CONSTANT ALIASES
  // ==============================
  // → So other services can use the same keys/buckets safely
  static const String cacheBadges = _cacheBadges;
  static const String cacheUserBadges = _cacheUserBadges;
  static const String cacheUserProfile = _cacheUserProfile;
  static const String cacheProfileTimestamp = _cacheProfileTimestamp;
  static const String cacheFriends = _cacheFriends;
  static const String cacheMessages = _cacheMessages;
  static const String cacheLastMessageTime = _cacheLastMessageTime;
  static const String cachePosts = _cachePosts;
  static const String cacheLastPostTime = _cacheLastPostTime;
  static const String cacheUserPosts = _cacheUserPosts;
  static const String cacheSubmittedRecipes = _cacheSubmittedRecipes;
  static const String cacheFavoriteRecipes = _cacheFavoriteRecipes;

  static const String profileBucket = _profileBucket;
  static const String backgroundBucket = _backgroundBucket;
  static const String albumBucket = _albumBucket;

  static const List<String> knownBuckets = _knownBuckets;

  // ==================================================
  // CURRENT USER ID & AUTH CHECK (Uses Supabase auth)
  // ==================================================

  static String? get currentUserId => _supabase.auth.currentUser?.id;

  static void ensureUserAuthenticated() {
    if (currentUserId == null) {
      throw Exception('Please sign in to continue');
    }
  }

  static bool get isUserLoggedIn => currentUserId != null;

  // ==================================================
  // PUBLIC WRAPPERS FOR CORE HELPERS
  // ==================================================
  // Use these from other services instead of the private underscored ones.

  static Future<dynamic> workerQuery({
    required String action,
    required String table,
    List<String>? columns,
    Map<String, dynamic>? filters,
    Map<String, dynamic>? data,
    String? orderBy,
    bool? ascending,
    int? limit,
    bool requireAuth = false,
  }) {
    return _workerQuery(
      action: action,
      table: table,
      columns: columns,
      filters: filters,
      data: data,
      orderBy: orderBy,
      ascending: ascending,
      limit: limit,
      requireAuth: requireAuth,
    );
  }

  static Future<String> workerStorageUpload({
    required String bucket,
    required String path,
    required String base64Data,
    required String contentType,
  }) {
    return _workerStorageUpload(
      bucket: bucket,
      path: path,
      base64Data: base64Data,
      contentType: contentType,
    );
  }

  static Future<void> workerStorageDelete({
    required String bucket,
    required String path,
  }) {
    return _workerStorageDelete(bucket: bucket, path: path);
  }

  static Future<void> deleteFileByPublicUrl(String url) {
    return _deleteFileByPublicUrl(url);
  }

  static Future<void> cacheData(String key, String data) {
    return _cacheData(key, data);
  }

  static Future<String?> getCachedData(String key) {
    return _getCachedData(key);
  }

  static Future<void> clearCache(String key) {
    return _clearCache(key);
  }

  static Future<void> clearAllUserCache() async {
    if (currentUserId == null) return;
    final prefs = await _getPrefs();
    final keys = prefs.getKeys().where((key) =>
      key.contains(currentUserId!) ||
      key == _cacheBadges ||
      key == _cachePosts ||
      key == _cacheLastPostTime
    ).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  /// 🆕 HELPER: Clear all profile-related caches for a user
  /// Consolidates the 3-4 cache clears that happen after profile updates
  static Future<void> clearUserProfileCaches([String? userId]) async {
    final targetUserId = userId ?? currentUserId;
    if (targetUserId == null) return;
    
    await clearCache('$_cacheUserProfile$targetUserId');
    await clearCache('$_cacheProfileTimestamp$targetUserId');
    await clearCache('user_profile_$targetUserId'); // Legacy key
    await clearCache('user_pictures'); // Picture gallery cache
    
    AppConfig.debugPrint('✅ Cleared all profile caches for user: $targetUserId');
  }

  // ==================================================
  // CLOUDFLARE WORKER HELPER METHODS - WITH AUTH TOKEN
  // ==================================================

  /// Send a query to the Cloudflare Worker WITH authentication token
  static Future<dynamic> _workerQuery({
    required String action,
    required String table,
    List<String>? columns,
    Map<String, dynamic>? filters,
    Map<String, dynamic>? data,
    String? orderBy,
    bool? ascending,
    int? limit,
    bool requireAuth = false, // Require auth for sensitive operations
  }) async {
    try {
      final authToken = _supabase.auth.currentSession?.accessToken;

      // Verify auth for sensitive operations
      if (requireAuth && authToken == null) {
        throw Exception('Authentication required. Please sign in again.');
      }

      AppConfig.debugPrint(
        '🔐 Worker query ($action) with auth: ${authToken != null ? "YES" : "NO"}',
      );

      final response = await http
          .post(
            Uri.parse(AppConfig.cloudflareWorkerQueryEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'action': action,
              'table': table,
              'authToken': authToken,
              if (columns != null) 'columns': columns,
              if (filters != null) 'filters': filters,
              if (data != null) 'data': data,
              if (orderBy != null) 'orderBy': orderBy,
              if (ascending != null) 'ascending': ascending,
              if (limit != null) 'limit': limit,
            }),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception('Worker request timed out'),
          );

      if (response.statusCode < 200 || response.statusCode > 299) {
        final errorBody = response.body;
        AppConfig.debugPrint(
          '❌ Worker error ($action): ${response.statusCode} - $errorBody',
        );
        throw Exception('Worker query failed ($action): $errorBody');
      }

      return jsonDecode(response.body);
    } catch (e) {
      throw Exception('Failed to execute worker query ($action): $e');
    }
  }

  /// Upload file to R2 storage via Cloudflare Worker WITH auth token
  static Future<String> _workerStorageUpload({
    required String bucket,
    required String path,
    required String base64Data,
    required String contentType,
  }) async {
    try {
      final authToken = _supabase.auth.currentSession?.accessToken;

      if (authToken == null) {
        throw Exception('Session expired. Please sign out and sign back in.');
      }

      AppConfig.debugPrint('🔐 Storage upload with auth token');
      AppConfig.debugPrint('📦 Bucket: $bucket, Path: $path');

      // Validate and clean base64 data
      String cleanBase64 = base64Data.trim();
      
      // Remove any data URI prefix if present
      if (cleanBase64.contains(',')) {
        cleanBase64 = cleanBase64.split(',').last;
      }
      
      // Remove any whitespace/newlines
      cleanBase64 = cleanBase64.replaceAll(RegExp(r'\s'), '');
      
      AppConfig.debugPrint('📊 Cleaned base64 length: ${cleanBase64.length} chars');

      // Validate file size early
      final estimatedMB = (cleanBase64.length * 0.75 / 1024 / 1024);
      if (estimatedMB > 10) {
        throw Exception(
          'Image file too large (${estimatedMB.toStringAsFixed(1)}MB). Please choose a smaller image (max 10MB).',
        );
      }

      // 🔥 FIX: Use the correct storage endpoint
      final storageUrl = '${AppConfig.cloudflareWorkerUrl}/storage';
      
      AppConfig.debugPrint('📡 Uploading to: $storageUrl');

      final response = await http
          .post(
            Uri.parse(storageUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'action': 'upload',
              'bucket': bucket,
              'path': path,
              'data': cleanBase64, // Send cleaned base64
              'contentType': contentType,
              'authToken': authToken,
            }),
          )
          .timeout(
            const Duration(seconds: 90), // Increased timeout for large uploads
            onTimeout: () {
              throw Exception(
                'Upload timeout - connection too slow. Please try again with a smaller image or better connection.',
              );
            },
          );

      AppConfig.debugPrint('📡 Response status: ${response.statusCode}');
      AppConfig.debugPrint('📡 Response body preview: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');

      // Better error handling
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Authentication failed. Please sign out and sign back in.');
      }

      if (response.statusCode == 413) {
        throw Exception('Image too large. Please choose a smaller image.');
      }

      if (response.statusCode == 429) {
        throw Exception('Too many uploads. Please wait a moment and try again.');
      }

      if (response.statusCode != 200) {
        final errorBody = response.body;
        AppConfig.debugPrint('❌ Upload failed: $errorBody');
        
        // Try to parse error message
        try {
          final errorJson = jsonDecode(errorBody);
          final errorMsg = errorJson['error'] ?? errorBody;
          throw Exception('Upload failed: $errorMsg');
        } catch (_) {
          throw Exception(
            'Upload failed (${response.statusCode}): ${errorBody.length > 100 ? errorBody.substring(0, 100) : errorBody}',
          );
        }
      }

      final uploadResult = jsonDecode(response.body);
      final publicUrl = uploadResult['url'] ?? uploadResult['publicUrl'];

      if (publicUrl == null) {
        throw Exception('Upload succeeded but no URL returned.');
      }

      AppConfig.debugPrint('✅ Upload successful: $publicUrl');
      return publicUrl;
    } on http.ClientException catch (e) {
      throw Exception(
        'Network error: Unable to connect. Check your internet connection. ($e)',
      );
    } on FormatException catch (e) {
      throw Exception('Invalid response from server. Please try again. ($e)');
    } catch (e) {
      AppConfig.debugPrint('❌ Storage upload error: $e');
      
      // Check if it's a timeout error
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('timeout')) {
        throw Exception('Upload timeout. Please try with a smaller image or better connection.');
      }
      
      rethrow;
    }
  }

  /// Delete file from R2 storage via Cloudflare Worker WITH auth token
  static Future<void> _workerStorageDelete({
    required String bucket,
    required String path,
  }) async {
    try {
      final authToken = _supabase.auth.currentSession?.accessToken;

      if (authToken == null) {
        throw Exception('Authentication required. Please sign in again.');
      }

      AppConfig.debugPrint('🔐 Storage delete with auth token');
      AppConfig.debugPrint('📦 Bucket: $bucket, Path: $path');

      final response = await http
          .post(
            Uri.parse('${AppConfig.cloudflareWorkerQueryEndpoint}/storage'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'action': 'delete',
              'bucket': bucket,
              'path': path,
              'authToken': authToken,
            }),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Delete timeout - server not responding');
            },
          );

      if (response.statusCode == 401) {
        throw Exception('Authentication failed. Please sign out and sign back in.');
      }

      if (response.statusCode == 403) {
        throw Exception('Permission denied. You can only delete your own files.');
      }

      if (response.statusCode != 200) {
        throw Exception('Delete failed (${response.statusCode}): ${response.body}');
      }

      AppConfig.debugPrint('✅ Delete successful');
    } catch (e) {
      AppConfig.debugPrint('❌ Storage delete error: $e');
      rethrow;
    }
  }

  /// Helper: delete a file from any known bucket using its public URL
  static Future<void> _deleteFileByPublicUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;

      for (final bucket in _knownBuckets) {
        final bucketIndex = segments.indexOf(bucket);
        if (bucketIndex != -1 && bucketIndex < segments.length - 1) {
          final filePath = segments.sublist(bucketIndex + 1).join('/');
          AppConfig.debugPrint('🗑️ Deleting from $bucket: $filePath');
          await _workerStorageDelete(bucket: bucket, path: filePath);
          return;
        }
      }

      AppConfig.debugPrint('⚠️ Could not determine bucket for URL: $url');
    } catch (e) {
      AppConfig.debugPrint('❌ _deleteFileByPublicUrl error: $e');
      rethrow;
    }
  }

  // ==================================================
  // CACHE HELPER METHODS (Local only - no Worker needed)
  // ==================================================

  static Future<SharedPreferences> _getPrefs() async {
    return await SharedPreferences.getInstance();
  }

  static Future<void> _cacheData(String key, String data) async {
    final prefs = await _getPrefs();
    await prefs.setString(key, data);
  }

  static Future<String?> _getCachedData(String key) async {
    final prefs = await _getPrefs();
    return prefs.getString(key);
  }

  static Future<void> _clearCache(String key) async {
    final prefs = await _getPrefs();
    await prefs.remove(key);
  }

  static Future<void> removeBackgroundPicture() async {
    ensureUserAuthenticated();
    
    try {
      final userId = currentUserId!;
      
      // Update profile to remove background
      await _workerQuery(
        action: 'update',
        table: 'profiles',
        filters: {'id': userId},
        data: {
          'profile_background': null,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );
      
      // Use new helper to clear all profile caches
      await clearUserProfileCaches(userId);
      
      AppConfig.debugPrint('✅ Background picture removed');
    } catch (e) {
      throw Exception('Failed to remove background picture: $e');
    }
  }

  static Future<void> deleteSubmittedRecipe(int recipeId) async {
    ensureUserAuthenticated();

    try {
      await _workerQuery(
        action: 'delete',
        table: 'submitted_recipes',
        filters: {'id': recipeId},
      );
      
      await _clearCache(_cacheSubmittedRecipes);
    } catch (e) {
      throw Exception('Failed to delete submitted recipe: $e');
    }
  }
}