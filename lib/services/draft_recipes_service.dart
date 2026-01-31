// lib/services/draft_recipes_service.dart
// Database-backed draft recipe management with premium limits
// iOS 14 Compatible | Production Ready | FIXED

import '../models/draft_recipe.dart';
import '../models/nutrition_info.dart';
import '../config/app_config.dart';
import 'database_service_core.dart';
import 'auth_service.dart';
import 'profile_service.dart';
import 'ingredient_database_service.dart';

class DraftRecipesService {
  // ============================================================
  // RECIPE CRUD OPERATIONS
  // ============================================================

  /// Create new draft recipe
  static Future<String> createDraftRecipe(DraftRecipe recipe) async {
    try {
      final userId = AuthService.currentUserId;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Check if user can save more recipes
      final canSave = await canSaveRecipe(userId);
      if (!canSave) {
        final isPremium = await ProfileService.isPremiumUser();
        throw Exception(
          isPremium
              ? 'Failed to save recipe. Please try again.'
              : 'Recipe limit reached. Free users can save up to 5 recipes. '
                'Upgrade to Premium for unlimited recipes.',
        );
      }

      // Calculate nutrition if not provided
      final recipeWithNutrition = recipe.totalNutrition == null
          ? recipe.copyWith(
              totalNutrition: await calculateRecipeNutrition(recipe.ingredients),
            )
          : recipe;

      // Create in database
      final result = await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'draft_recipes',
        requireAuth: true,
        data: recipeWithNutrition.toJson(),
      );

      if (result == null) {
        throw Exception('Failed to create recipe');
      }

      // Get the created recipe ID
      final createdRecipe = result as List;
      final recipeId = createdRecipe[0]['id'] as String;

      AppConfig.debugPrint('✅ Draft recipe created: $recipeId');
      return recipeId;
    } catch (e) {
      AppConfig.debugPrint('❌ Error creating draft recipe: $e');
      rethrow;
    }
  }

  /// Get user's draft recipes
  static Future<List<DraftRecipe>> getUserDraftRecipes(String userId) async {
    try {
      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'draft_recipes',
        filters: {'user_id': userId},
        orderBy: 'updated_at',
        ascending: false,
      );

      if (result == null || (result as List).isEmpty) {
        return [];
      }

      return (result)
          .map((json) => DraftRecipe.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppConfig.debugPrint('❌ Error loading draft recipes: $e');
      throw Exception('Failed to load recipes: $e');
    }
  }

  /// Get single draft recipe by ID
  static Future<DraftRecipe?> getDraftRecipe(String recipeId) async {
    try {
      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'draft_recipes',
        filters: {'id': recipeId},
        limit: 1,
      );

      if (result == null || (result as List).isEmpty) {
        return null;
      }

      return DraftRecipe.fromJson(result[0] as Map<String, dynamic>);
    } catch (e) {
      AppConfig.debugPrint('❌ Error loading draft recipe: $e');
      return null;
    }
  }

  /// Update draft recipe
  static Future<void> updateDraftRecipe(
    String recipeId,
    DraftRecipe recipe,
  ) async {
    try {
      final userId = AuthService.currentUserId;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Recalculate nutrition
      final recipeWithNutrition = recipe.copyWith(
        totalNutrition: await calculateRecipeNutrition(recipe.ingredients),
        updatedAt: DateTime.now(),
      );

      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'draft_recipes',
        filters: {'id': recipeId, 'user_id': userId},
        data: recipeWithNutrition.toJson(),
      );

      AppConfig.debugPrint('✅ Draft recipe updated: $recipeId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error updating draft recipe: $e');
      throw Exception('Failed to update recipe: $e');
    }
  }

  /// Delete draft recipe
  static Future<void> deleteDraftRecipe(String recipeId) async {
    try {
      final userId = AuthService.currentUserId;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'draft_recipes',
        filters: {'id': recipeId, 'user_id': userId},
      );

      AppConfig.debugPrint('✅ Draft recipe deleted: $recipeId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error deleting draft recipe: $e');
      throw Exception('Failed to delete recipe: $e');
    }
  }

  // ============================================================
  // PREMIUM LIMITS
  // ============================================================

  /// Check if user can save more recipes (5 for free, unlimited for premium)
  static Future<bool> canSaveRecipe(String userId) async {
    try {
      // ✅ FIX: isPremiumUser() takes no parameters
      final isPremium = await ProfileService.isPremiumUser();
      if (isPremium) {
        return true; // Premium users have unlimited recipes
      }

      // Check recipe count for free users
      final count = await getUserDraftRecipeCount(userId);
      return count < 5; // Free users limited to 5 recipes
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error checking recipe limit: $e');
      return false; // Fail safe - don't allow if check fails
    }
  }

  /// Get user's draft recipe count
  static Future<int> getUserDraftRecipeCount(String userId) async {
    try {
      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'draft_recipes',
        filters: {'user_id': userId},
        columns: ['COUNT(*) as count'],
      );

      if (result == null || (result as List).isEmpty) {
        return 0;
      }

      return result[0]['count'] as int? ?? 0;
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error getting recipe count: $e');
      return 0;
    }
  }

  /// Get remaining recipe slots for free users
  static Future<int> getRemainingSlots(String userId) async {
    try {
      // ✅ FIX: isPremiumUser() takes no parameters
      final isPremium = await ProfileService.isPremiumUser();
      if (isPremium) {
        return -1; // -1 = unlimited
      }

      final count = await getUserDraftRecipeCount(userId);
      return (5 - count).clamp(0, 5);
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error getting remaining slots: $e');
      return 0;
    }
  }

  // ============================================================
  // NUTRITION CALCULATION
  // ============================================================

  /// Calculate total nutrition from ingredients
  static Future<NutritionInfo> calculateRecipeNutrition(
    List<RecipeIngredient> ingredients,
  ) async {
    try {
      if (ingredients.isEmpty) {
        return NutritionInfo.empty();
      }

      // Start with empty nutrition
      NutritionInfo total = NutritionInfo.empty();

      // Add up all ingredient nutrition
      for (final ingredient in ingredients) {
        if (ingredient.nutrition != null) {
          // Scale the nutrition by quantity
          final scaled = ingredient.nutrition!.scale(ingredient.quantity);
          total = total + scaled;
        }
      }

      return total;
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error calculating nutrition: $e');
      return NutritionInfo.empty();
    }
  }

  // ============================================================
  // INGREDIENT HELPERS
  // ============================================================

  /// Create ingredient from barcode scan
  static Future<RecipeIngredient> addIngredientFromBarcode(
    String barcode,
  ) async {
    try {
      AppConfig.debugPrint('🔎 Looking up barcode: $barcode');

      // Fetch nutrition from ingredient database
      final nutrition = await IngredientDatabaseService.getNutritionData(
        barcode,
      );

      if (nutrition == null) {
        throw Exception('Product not found for barcode: $barcode');
      }

      return RecipeIngredient(
        barcode: barcode,
        productName: nutrition.productName,
        quantity: 1.0,
        unit: 'serving',
        nutrition: nutrition,
        source: 'scan',
      );
    } catch (e) {
      AppConfig.debugPrint('❌ Error adding ingredient from barcode: $e');
      rethrow;
    }
  }

  /// Create ingredient from search result
  static Future<RecipeIngredient> addIngredientFromSearch(
    String ingredientName, {
    double quantity = 1.0,
    String unit = 'serving',
  }) async {
    try {
      AppConfig.debugPrint('🔍 Searching ingredient: $ingredientName');

      // Search ingredient database
      final results = await IngredientDatabaseService.searchIngredient(
        ingredientName,
        includeNutrition: true,
      );

      if (results.isEmpty) {
        throw Exception('Ingredient not found: $ingredientName');
      }

      // Use first result
      final result = results.first;

      return RecipeIngredient(
        barcode: result.barcode,
        productName: result.name,
        quantity: quantity,
        unit: unit,
        nutrition: result.nutrition,
        source: 'search',
      );
    } catch (e) {
      AppConfig.debugPrint('❌ Error adding ingredient from search: $e');
      rethrow;
    }
  }

  /// Create custom ingredient (no barcode/nutrition)
  static RecipeIngredient createCustomIngredient({
    required String productName,
    required double quantity,
    required String unit,
    NutritionInfo? nutrition,
  }) {
    return RecipeIngredient(
      productName: productName,
      quantity: quantity,
      unit: unit,
      nutrition: nutrition,
      source: 'custom',
    );
  }

  // ============================================================
  // SEARCH & FILTER
  // ============================================================

  /// Search user's recipes by title
  static Future<List<DraftRecipe>> searchRecipes(
    String userId,
    String query,
  ) async {
    try {
      final allRecipes = await getUserDraftRecipes(userId);

      if (query.isEmpty) {
        return allRecipes;
      }

      final lowerQuery = query.toLowerCase();

      return allRecipes.where((recipe) {
        final titleMatch = recipe.title.toLowerCase().contains(lowerQuery);
        final descMatch =
            recipe.description?.toLowerCase().contains(lowerQuery) ?? false;
        final ingredientMatch = recipe.ingredients.any(
          (ing) => ing.productName.toLowerCase().contains(lowerQuery),
        );

        return titleMatch || descMatch || ingredientMatch;
      }).toList();
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error searching recipes: $e');
      return [];
    }
  }

  /// Get recipes sorted by nutrition score
  static Future<List<DraftRecipe>> getRecipesByHealthScore(
    String userId, {
    bool ascending = false,
  }) async {
    try {
      final recipes = await getUserDraftRecipes(userId);

      recipes.sort((a, b) {
        final scoreA = a.healthScore;
        final scoreB = b.healthScore;

        return ascending
            ? scoreA.compareTo(scoreB)
            : scoreB.compareTo(scoreA);
      });

      return recipes;
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error sorting recipes: $e');
      return [];
    }
  }

  // ============================================================
  // UTILITIES
  // ============================================================

  /// Duplicate a recipe
  static Future<String> duplicateRecipe(String recipeId) async {
    try {
      final original = await getDraftRecipe(recipeId);
      if (original == null) {
        throw Exception('Recipe not found');
      }

      final duplicate = original.copyWith(
        id: null, // Remove ID to create new recipe
        title: '${original.title} (Copy)',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      return await createDraftRecipe(duplicate);
    } catch (e) {
      AppConfig.debugPrint('❌ Error duplicating recipe: $e');
      rethrow;
    }
  }

  /// Export recipe as JSON
  static Future<String> exportRecipe(String recipeId) async {
    try {
      final recipe = await getDraftRecipe(recipeId);
      if (recipe == null) {
        throw Exception('Recipe not found');
      }

      return recipe.toJson().toString();
    } catch (e) {
      rethrow;
    }
  }
}