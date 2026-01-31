// lib/services/favorite_recipes_service.dart
// ✅ FIXED: Enhanced duplicate prevention and better error handling

import 'dart:convert';
import '../models/favorite_recipe.dart';
import '../config/app_config.dart';
import 'database_service_core.dart';
import 'auth_service.dart';

class FavoriteRecipesService {
  static const String _CACHE_KEY = 'cache_favorite_recipes';

  // --------------------------------------------------
  // GET FAVORITE RECIPES (with caching)
  // --------------------------------------------------
  static Future<List<FavoriteRecipe>> getFavoriteRecipes() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return [];

    try {
      // Try cache first
      final cached = await DatabaseServiceCore.getCachedData(_CACHE_KEY);
      if (cached != null) {
        final list = jsonDecode(cached) as List;
        return list.map((e) => FavoriteRecipe.fromJson(e)).toList();
      }

      // Fetch from Worker
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'favorite_recipes',
        columns: ['*'],
        filters: {'user_id': userId},
        orderBy: 'created_at',
        ascending: false,
      );

      final recipes = (response as List)
          .map((e) => FavoriteRecipe.fromJson(e))
          .toList();

      // Cache for next time
      await DatabaseServiceCore.cacheData(_CACHE_KEY, jsonEncode(response));

      return recipes;
    } catch (e) {
      throw Exception('Failed to load favorite recipes: $e');
    }
  }

  // --------------------------------------------------
  // ✅ IMPROVED: CHECK IF RECIPE IS ALREADY FAVORITED
  // Now checks BOTH recipe_id AND recipe_name for better accuracy
  // --------------------------------------------------
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

  // --------------------------------------------------
  // ✅ FIXED: ADD FAVORITE RECIPE (enhanced duplicate prevention)
  // --------------------------------------------------
  static Future<FavoriteRecipe> addFavoriteRecipe(
    String recipeName,
    String ingredients,
    String directions, {
    int? recipeId, // Optional recipe_id from recipe_master
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

      final response = await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'favorite_recipes',
        data: data,
      );

      // Worker returns list
      final row = (response as List).first;

      // Clear cache to force refresh
      await DatabaseServiceCore.clearCache(_CACHE_KEY);

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

  // --------------------------------------------------
  // REMOVE FAVORITE
  // --------------------------------------------------
  static Future<void> removeFavoriteRecipe(int recipeId) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
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

      await DatabaseServiceCore.clearCache(_CACHE_KEY);
      
    } catch (e) {
      AppConfig.debugPrint('❌ Error removing favorite: $e');
      throw Exception('Failed to remove favorite recipe. Please try again.');
    }
  }

  // --------------------------------------------------
  // ✅ IMPROVED: CHECK IF FAVORITED (supports both recipe_id and name)
  // --------------------------------------------------
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

  // --------------------------------------------------
  // ✅ NEW: BULK CHECK FAVORITES (efficient for lists)
  // --------------------------------------------------
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

  // --------------------------------------------------
  // ✅ NEW: BULK CHECK BY IDs (for recipe_master integration)
  // --------------------------------------------------
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

  // --------------------------------------------------
  // ✅ NEW: CLEAR ALL FAVORITES (useful for testing/reset)
  // --------------------------------------------------
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

      await DatabaseServiceCore.clearCache(_CACHE_KEY);
      
    } catch (e) {
      AppConfig.debugPrint('❌ Error clearing favorites: $e');
      throw Exception('Failed to clear favorites. Please try again.');
    }
  }
  // --------------------------------------------------
  // ✅ NEW: GET FAVORITE RECIPES COUNT (for ProfileScreen)
  // --------------------------------------------------
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
}