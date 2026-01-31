// lib/services/cookbook_service.dart
import 'dart:convert';
import '../models/cookbook_recipe.dart';
import '../config/app_config.dart';
import 'database_service_core.dart';
import 'auth_service.dart';

class CookbookService {
  static const String _CACHE_KEY = 'cache_cookbook_recipes';

  // Get all cookbook recipes for current user
  static Future<List<CookbookRecipe>> getCookbookRecipes() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return [];

    try {
      // Try cache first
      final cached = await DatabaseServiceCore.getCachedData(_CACHE_KEY);
      if (cached != null) {
        final list = jsonDecode(cached) as List;
        return list.map((e) => CookbookRecipe.fromJson(e)).toList();
      }

      // Fetch from database
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'cookbook_recipes',
        columns: ['*'],
        filters: {'user_id': userId},
        orderBy: 'created_at',
        ascending: false,
      );

      final recipes = (response as List)
          .map((e) => CookbookRecipe.fromJson(e))
          .toList();

      // Cache for next time
      await DatabaseServiceCore.cacheData(_CACHE_KEY, jsonEncode(response));

      return recipes;
    } catch (e) {
      throw Exception('Failed to load cookbook recipes: $e');
    }
  }

  // Check if recipe exists in cookbook
  static Future<CookbookRecipe?> findExistingRecipe({
    int? recipeId,
    String? recipeName,
  }) async {
    final userId = AuthService.currentUserId;
    if (userId == null) return null;

    try {
      // Check by recipe_id first
      if (recipeId != null) {
        final response = await DatabaseServiceCore.workerQuery(
          action: 'select',
          table: 'cookbook_recipes',
          columns: ['*'],
          filters: {
            'user_id': userId,
            'recipe_id': recipeId,
          },
          limit: 1,
        );

        if (response != null && (response as List).isNotEmpty) {
          return CookbookRecipe.fromJson(response.first);
        }
      }

      // Fallback to recipe_name
      if (recipeName != null && recipeName.trim().isNotEmpty) {
        final response = await DatabaseServiceCore.workerQuery(
          action: 'select',
          table: 'cookbook_recipes',
          columns: ['*'],
          filters: {
            'user_id': userId,
            'recipe_name': recipeName.trim(),
          },
          limit: 1,
        );

        if (response != null && (response as List).isNotEmpty) {
          return CookbookRecipe.fromJson(response.first);
        }
      }

      return null;
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error checking for existing cookbook recipe: $e');
      return null;
    }
  }

  // Add recipe to cookbook
  static Future<CookbookRecipe> addToCookbook(
    String recipeName,
    String ingredients,
    String directions, {
    int? recipeId,
    String? notes,
  }) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    final trimmedName = recipeName.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Recipe name cannot be empty');
    }

    // Check for duplicates
    final existing = await findExistingRecipe(
      recipeId: recipeId,
      recipeName: trimmedName,
    );

    if (existing != null) {
      throw Exception('This recipe is already in your cookbook!');
    }

    try {
      final data = <String, dynamic>{
        'user_id': AuthService.currentUserId!,
        'recipe_name': trimmedName,
        'ingredients': ingredients.trim(),
        'directions': directions.trim(),
        'created_at': DateTime.now().toIso8601String(),
      };

      if (recipeId != null) {
        data['recipe_id'] = recipeId;
      }

      if (notes != null && notes.trim().isNotEmpty) {
        data['notes'] = notes.trim();
      }

      final response = await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'cookbook_recipes',
        data: data,
      );

      final row = (response as List).first;

      // Clear cache
      await DatabaseServiceCore.clearCache(_CACHE_KEY);

      return CookbookRecipe.fromJson(row);
      
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      
      if (errorStr.contains('duplicate key') || 
          errorStr.contains('already exists') ||
          errorStr.contains('unique constraint')) {
        throw Exception('This recipe is already in your cookbook!');
      }
      
      AppConfig.debugPrint('❌ Database error adding to cookbook: $e');
      throw Exception('Failed to add recipe to cookbook. Please try again.');
    }
  }

  // Remove recipe from cookbook
  static Future<void> removeFromCookbook(int recipeId) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    try {
      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'cookbook_recipes',
        filters: {
          'id': recipeId,
          'user_id': AuthService.currentUserId!,
        },
      );

      await DatabaseServiceCore.clearCache(_CACHE_KEY);
      
    } catch (e) {
      AppConfig.debugPrint('❌ Error removing from cookbook: $e');
      throw Exception('Failed to remove recipe from cookbook. Please try again.');
    }
  }

  // Check if recipe is in cookbook
  static Future<bool> isInCookbook({
    int? recipeId,
    String? recipeName,
  }) async {
    final userId = AuthService.currentUserId;
    if (userId == null) return false;

    try {
      final existing = await findExistingRecipe(
        recipeId: recipeId,
        recipeName: recipeName,
      );
      
      return existing != null;
      
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error checking cookbook: $e');
      return false;
    }
  }

  // Update recipe notes
  static Future<void> updateRecipeNotes(int recipeId, String notes) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    try {
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'cookbook_recipes',
        filters: {
          'id': recipeId,
          'user_id': AuthService.currentUserId!,
        },
        data: {
          'notes': notes.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      await DatabaseServiceCore.clearCache(_CACHE_KEY);
      
    } catch (e) {
      AppConfig.debugPrint('❌ Error updating notes: $e');
      throw Exception('Failed to update notes. Please try again.');
    }
  }

  // Get cookbook count
  static Future<int> getCookbookCount() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return 0;

    try {
      final recipes = await getCookbookRecipes();
      return recipes.length;
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error getting cookbook count: $e');
      return 0;
    }
  }
}