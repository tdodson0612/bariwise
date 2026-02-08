// lib/services/favorite_recipes_service.dart
// ✅ FIXED: Backward-compatible method names + enhanced implementation

import 'dart:convert';
import '../models/favorite_recipe.dart';
import '../services/database_service_core.dart';
import '../services/auth_service.dart';
import '../config/app_config.dart';

/// Service for managing favorite recipes
/// 
/// Features:
/// - Silent failure for auth errors (no popups on login)
/// - Robust duplicate prevention
/// - Caching for better performance
/// - Graceful degradation when database is unavailable
/// - Backward-compatible method names
class FavoriteRecipesService {
  static const String _CACHE_KEY = 'favorite_recipes_cache';
  static const Duration _CACHE_DURATION = Duration(minutes: 5);
  
  // In-memory cache to prevent duplicate checks during rapid operations
  static final Map<String, DateTime> _recentOperations = {};
  static const Duration _OPERATION_COOLDOWN = Duration(milliseconds: 500);

  // ==================== BACKWARD-COMPATIBLE PUBLIC API ====================

  /// Get all favorite recipes for the current user
  /// Returns empty list instead of throwing on auth errors
  static Future<List<FavoriteRecipe>> getFavoriteRecipes() async {
    final userId = AuthService.currentUserId;
    
    // Silent return for no session - don't throw error
    if (userId == null) {
      AppConfig.debugPrint('⚠️ getFavoriteRecipes: No user session - returning empty list');
      return [];
    }

    try {
      // Try cache first
      final cached = await _getCachedFavorites();
      if (cached != null) {
        AppConfig.debugPrint('✅ Loaded ${cached.length} favorites from cache');
        return cached;
      }

      // Fetch from database
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'favorite_recipes',
        columns: ['*'],
        filters: {'user_id': userId},
        orderBy: 'created_at',
        ascending: false,
      );

      if (response == null) {
        AppConfig.debugPrint('⚠️ Worker returned null for favorites');
        return [];
      }

      final recipes = (response as List)
          .map((e) => FavoriteRecipe.fromJson(e))
          .toList();

      AppConfig.debugPrint('✅ Loaded ${recipes.length} favorites from database');

      // Cache the results
      await _cacheFavorites(recipes);

      return recipes;
      
    } on SessionExpiredException {
      // Session expired - return empty list, don't throw
      AppConfig.debugPrint('⚠️ Session expired loading favorites - returning empty list');
      return [];
      
    } catch (e) {
      AppConfig.debugPrint('❌ Error loading favorites: $e');
      
      // Check if it's an auth/session error
      if (_isAuthError(e)) {
        // Silent failure for auth errors - just return empty list
        return [];
      }
      
      // For other errors, try to return cached data if available
      final cached = await _getCachedFavorites(ignoreExpiry: true);
      if (cached != null) {
        AppConfig.debugPrint('⚠️ Returning stale cache due to error');
        return cached;
      }
      
      // Last resort: return empty list (better than crashing)
      AppConfig.debugPrint('⚠️ Returning empty list due to error: $e');
      return [];
    }
  }

  /// ✅ BACKWARD COMPATIBLE: Get favorite recipes count
  static Future<int> getFavoriteRecipesCount() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return 0;

    try {
      final recipes = await getFavoriteRecipes();
      return recipes.length;
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error getting favorite recipes count: $e');
      return 0;
    }
  }

  /// ✅ BACKWARD COMPATIBLE: Find existing favorite by recipe_id or recipe_name
  static Future<FavoriteRecipe?> findExistingFavorite({
    int? recipeId,
    String? recipeName,
  }) async {
    final userId = AuthService.currentUserId;
    if (userId == null) return null;

    try {
      // ✅ STRATEGY 1: Check by recipe_id first (most reliable)
      if (recipeId != null) {
        final response = await DatabaseServiceCore.workerQuery(
          action: 'select',
          table: 'favorite_recipes',
          columns: ['*'],
          filters: {
            'user_id': userId,
            'recipe_id': recipeId,
          },
          limit: 1,
        );

        if (response != null && (response as List).isNotEmpty) {
          return FavoriteRecipe.fromJson(response.first);
        }
      }

      // ✅ STRATEGY 2: Fallback to recipe_name if no recipe_id match
      if (recipeName != null && recipeName.trim().isNotEmpty) {
        final response = await DatabaseServiceCore.workerQuery(
          action: 'select',
          table: 'favorite_recipes',
          columns: ['*'],
          filters: {
            'user_id': userId,
            'recipe_name': recipeName.trim(),
          },
          limit: 1,
        );

        if (response != null && (response as List).isNotEmpty) {
          return FavoriteRecipe.fromJson(response.first);
        }
      }

      return null;
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error checking for existing favorite: $e');
      return null;
    }
  }

  /// ✅ BACKWARD COMPATIBLE: Add favorite recipe (original signature)
  static Future<FavoriteRecipe> addFavoriteRecipe(
    String recipeName,
    String ingredients,
    String directions, {
    int? recipeId, // Optional recipe_id from recipe_master
    String? description, // Optional description
  }) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    final trimmedName = recipeName.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Recipe name cannot be empty');
    }

    // ✅ CRITICAL: Check for duplicates BEFORE inserting
    final existing = await findExistingFavorite(
      recipeId: recipeId,
      recipeName: trimmedName,
    );

    if (existing != null) {
      throw Exception('This recipe is already in your favorites!');
    }

    // Check if operation was done recently (prevent duplicates from rapid taps)
    final operationKey = 'add_$trimmedName';
    if (_isRecentOperation(operationKey)) {
      AppConfig.debugPrint('⚠️ Duplicate add operation detected, throwing error');
      throw Exception('This recipe is already in your favorites!');
    }

    try {
      final data = <String, dynamic>{
        'user_id': AuthService.currentUserId!,
        'recipe_name': trimmedName,
        'ingredients': ingredients.trim(),
        'directions': directions.trim(),
        'created_at': DateTime.now().toIso8601String(),
      };

      // Include recipe_id if available (links to recipe_master table)
      if (recipeId != null) {
        data['recipe_id'] = recipeId;
      }

      // Include description if available
      if (description != null && description.trim().isNotEmpty) {
        data['description'] = description.trim();
      }

      final response = await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'favorite_recipes',
        data: data,
      );

      // Worker returns list
      final row = (response as List).first;

      // Clear cache to force refresh
      await _clearCache();

      // Record operation to prevent duplicates
      _recordOperation(operationKey);

      return FavoriteRecipe.fromJson(row);
      
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      
      // ✅ IMPROVED: Detect various constraint violation patterns
      if (errorStr.contains('duplicate key') || 
          errorStr.contains('already exists') ||
          errorStr.contains('unique constraint') ||
          errorStr.contains('23505')) { // PostgreSQL unique violation code
        
        // ✅ Check if it's a database configuration issue
        if (errorStr.contains('user_id_key') || 
            errorStr.contains('favorite_recipes_user_id_key')) {
          throw Exception(
            'Database configuration error detected. '
            'The unique constraint is incorrectly set on user_id alone. '
            'Required fix: Run SQL migration to update constraint to (user_id, recipe_id) or (user_id, recipe_name).'
          );
        }
        
        // Normal duplicate - recipe already favorited
        throw Exception('This recipe is already in your favorites!');
      }
      
      // ✅ Preserve specific error messages
      if (errorStr.contains('already in your favorites')) {
        rethrow;
      }
      
      if (errorStr.contains('recipe name cannot be empty')) {
        rethrow;
      }
      
      // Generic database error
      AppConfig.debugPrint('❌ Database error adding favorite: $e');
      throw Exception('Failed to add favorite recipe. Please try again.');
    }
  }

  /// ✅ BACKWARD COMPATIBLE: Remove favorite by ID
  static Future<void> removeFavoriteRecipe(int recipeId) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    // Check if operation was done recently
    final operationKey = 'remove_$recipeId';
    if (_isRecentOperation(operationKey)) {
      AppConfig.debugPrint('⚠️ Duplicate remove operation detected, ignoring');
      return;
    }

    try {
      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'favorite_recipes',
        filters: {
          'id': recipeId,
          'user_id': AuthService.currentUserId!, // ✅ Added user_id check for security
        },
      );

      await _clearCache();
      
      // Record operation
      _recordOperation(operationKey);
      
    } catch (e) {
      AppConfig.debugPrint('❌ Error removing favorite: $e');
      throw Exception('Failed to remove favorite recipe. Please try again.');
    }
  }

  // ==================== ADDITIONAL PUBLIC METHODS ====================

  /// Check if a recipe is favorited (by recipe_id or name)
  static Future<bool> isRecipeFavorited({
    int? recipeId,
    String? recipeName,
  }) async {
    final userId = AuthService.currentUserId;
    if (userId == null) return false;

    try {
      final existing = await findExistingFavorite(
        recipeId: recipeId,
        recipeName: recipeName,
      );
      
      return existing != null;
      
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error checking if favorited: $e');
      return false;
    }
  }

  /// Get favorite by recipe name
  static Future<FavoriteRecipe?> getFavoriteByName(String recipeName) async {
    final userId = AuthService.currentUserId;
    if (userId == null) return null;

    try {
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'favorite_recipes',
        columns: ['*'],
        filters: {
          'user_id': userId,
          'recipe_name': recipeName,
        },
        limit: 1,
      );

      if (response == null || (response as List).isEmpty) {
        return null;
      }

      return FavoriteRecipe.fromJson((response as List).first);
      
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error getting favorite by name: $e');
      return null;
    }
  }

  /// Get favorite by recipe ID
  static Future<FavoriteRecipe?> getFavoriteByRecipeId(int recipeId) async {
    final userId = AuthService.currentUserId;
    if (userId == null) return null;

    try {
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'favorite_recipes',
        columns: ['*'],
        filters: {
          'user_id': userId,
          'recipe_id': recipeId,
        },
        limit: 1,
      );

      if (response == null || (response as List).isEmpty) {
        return null;
      }

      return FavoriteRecipe.fromJson((response as List).first);
      
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error getting favorite by recipe ID: $e');
      return null;
    }
  }

  /// Bulk check favorites by recipe names (efficient for lists)
  static Future<Set<String>> getFavoritedRecipeNames() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return {};

    try {
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'favorite_recipes',
        columns: ['recipe_name'],
        filters: {'user_id': userId},
      );

      if (response == null) return {};

      return (response as List)
          .map((e) => e['recipe_name'] as String)
          .toSet();
          
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error loading favorited recipe names: $e');
      return {};
    }
  }

  /// Bulk check by IDs (for recipe_master integration)
  static Future<Set<int>> getFavoritedRecipeIds() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return {};

    try {
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'favorite_recipes',
        columns: ['recipe_id'],
        filters: {'user_id': userId},
      );

      if (response == null) return {};

      return (response as List)
          .where((e) => e['recipe_id'] != null)
          .map((e) => e['recipe_id'] as int)
          .toSet();
          
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error loading favorited recipe IDs: $e');
      return {};
    }
  }

  /// Update a favorite recipe
  static Future<bool> updateFavorite({
    required int favoriteId,
    String? recipeName,
    String? description,
    String? ingredients,
    String? directions,
  }) async {
    final userId = AuthService.currentUserId;
    
    if (userId == null) {
      AppConfig.debugPrint('⚠️ Cannot update favorite: No user session');
      return false;
    }

    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      if (recipeName != null) updates['recipe_name'] = recipeName;
      if (description != null) updates['description'] = description;
      if (ingredients != null) updates['ingredients'] = ingredients;
      if (directions != null) updates['directions'] = directions;

      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'favorite_recipes',
        data: updates,
        filters: {
          'id': favoriteId,
          'user_id': userId,
        },
      );

      AppConfig.debugPrint('✅ Updated favorite: $favoriteId');

      // Clear cache
      await _clearCache();

      return true;
      
    } on SessionExpiredException {
      AppConfig.debugPrint('⚠️ Session expired updating favorite');
      return false;
      
    } catch (e) {
      AppConfig.debugPrint('❌ Error updating favorite: $e');
      
      if (_isAuthError(e)) {
        return false;
      }
      
      throw Exception('Failed to update favorite: ${e.toString()}');
    }
  }

  /// Clear all favorites (useful for testing/reset)
  static Future<void> clearAllFavorites() async {
    final userId = AuthService.currentUserId;
    if (userId == null) {
      throw Exception('Please sign in to continue');
    }

    try {
      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'favorite_recipes',
        filters: {'user_id': userId},
      );

      await _clearCache();
      
    } catch (e) {
      AppConfig.debugPrint('❌ Error clearing favorites: $e');
      throw Exception('Failed to clear favorites. Please try again.');
    }
  }

  /// Clear all caches and in-memory data (useful for logout)
  static Future<void> clearAll() async {
    _recentOperations.clear();
    await _clearCache();
    AppConfig.debugPrint('✅ Cleared all favorite recipes data');
  }

  // ==================== PRIVATE HELPER METHODS ====================

  /// Check if recipe exists in favorites
  static Future<bool> _checkIfExists(String recipeName, String userId) async {
    try {
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'favorite_recipes',
        columns: ['id'],
        filters: {
          'user_id': userId,
          'recipe_name': recipeName,
        },
        limit: 1,
      );

      return response != null && (response as List).isNotEmpty;
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error checking if favorite exists: $e');
      return false; // Assume it doesn't exist on error
    }
  }

  /// Check if an operation was performed recently
  static bool _isRecentOperation(String operationKey) {
    final lastOperation = _recentOperations[operationKey];
    if (lastOperation == null) {
      return false;
    }
    
    final timeSince = DateTime.now().difference(lastOperation);
    return timeSince < _OPERATION_COOLDOWN;
  }

  /// Record an operation to prevent duplicates
  static void _recordOperation(String operationKey) {
    _recentOperations[operationKey] = DateTime.now();
    
    // Clean up old operations (keep last 50)
    if (_recentOperations.length > 50) {
      final sortedEntries = _recentOperations.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      _recentOperations.clear();
      _recentOperations.addEntries(sortedEntries.take(50));
    }
  }

  /// Check if an error is authentication-related
  static bool _isAuthError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    return errorString.contains('session') ||
           errorString.contains('jwt') ||
           errorString.contains('auth') ||
           errorString.contains('token') ||
           errorString.contains('unauthorized') ||
           errorString.contains('not authenticated');
  }

  /// Get cached favorites
  static Future<List<FavoriteRecipe>?> _getCachedFavorites({bool ignoreExpiry = false}) async {
    try {
      final cachedJson = await DatabaseServiceCore.getCachedData(_CACHE_KEY);
      if (cachedJson == null) {
        return null;
      }

      final cacheData = jsonDecode(cachedJson) as Map<String, dynamic>;
      final timestamp = DateTime.parse(cacheData['timestamp'] as String);
      final recipes = (cacheData['recipes'] as List)
          .map((e) => FavoriteRecipe.fromCache(e))
          .toList();

      // Check if cache is expired
      if (!ignoreExpiry) {
        final age = DateTime.now().difference(timestamp);
        if (age > _CACHE_DURATION) {
          AppConfig.debugPrint('⚠️ Cache expired (${age.inMinutes}m old)');
          return null;
        }
      }

      return recipes;
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error reading cache: $e');
      await _clearCache(); // Clear corrupted cache
      return null;
    }
  }

  /// Cache favorites
  static Future<void> _cacheFavorites(List<FavoriteRecipe> recipes) async {
    try {
      final cacheData = {
        'timestamp': DateTime.now().toIso8601String(),
        'recipes': recipes.map((r) => r.toCache()).toList(),
      };
      
      await DatabaseServiceCore.cacheData(
        _CACHE_KEY,
        jsonEncode(cacheData),
      );
    } catch (e) {
      AppConfig.debugPrint('⚠️ Failed to cache favorites: $e');
      // Non-critical, continue
    }
  }

  /// Clear the cache
  static Future<void> _clearCache() async {
    try {
      await DatabaseServiceCore.clearCache(_CACHE_KEY);
    } catch (e) {
      AppConfig.debugPrint('⚠️ Failed to clear cache: $e');
      // Non-critical
    }
  }
}

/// Custom exception for session expiration
class SessionExpiredException implements Exception {
  final String message;
  SessionExpiredException([this.message = 'Session expired']);
  
  @override
  String toString() => message;
}