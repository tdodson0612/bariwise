// lib/services/ratings_service.dart
// Handles recipe ratings: get average, get user rating, rate recipe

import '../config/app_config.dart';

import 'auth_service.dart';            // Auth + currentUserId
import 'database_service_core.dart';   // Worker query


class RatingsService {

  // ==================================================
  // GET AVERAGE RATING FOR A RECIPE
  // ==================================================

  static Future<Map<String, dynamic>> getRecipeAverageRating(int recipeId) async {
    try {
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'recipe_ratings',
        columns: ['rating'],
        filters: {'recipe_id': recipeId},
      );

      if (response == null || (response as List).isEmpty) {
        return {'average': 0.0, 'count': 0};
      }

      final ratings = (response)
          .map((r) => r['rating'] as int)
          .toList();

      final count = ratings.length;
      final average = ratings.reduce((a, b) => a + b) / count;

      return {
        'average': double.parse(average.toStringAsFixed(1)),
        'count': count,
      };
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting average rating: $e');
      return {'average': 0.0, 'count': 0};
    }
  }

  // ==================================================
  // GET USER'S RATING FOR A RECIPE
  // ==================================================

  static Future<int?> getUserRecipeRating(int recipeId) async {
    final userId = AuthService.currentUserId;
    if (userId == null) return null;

    try {
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'recipe_ratings',
        columns: ['rating'],
        filters: {
          'recipe_id': recipeId,
          'user_id': userId,
        },
        limit: 1,
      );

      if (response == null || (response as List).isEmpty) return null;

      return response[0]['rating'] as int?;
    } catch (e) {
      return null;
    }
  }

  // ==================================================
  // RATE A RECIPE
  // ==================================================

  static Future<void> rateRecipe(int recipeId, int rating) async {
    DatabaseServiceCore.ensureUserAuthenticated();

    if (rating < 1 || rating > 5) {
      throw Exception('Rating must be between 1 and 5');
    }

    try {
      final userId = AuthService.currentUserId!;

      // Cannot rate own recipe
      final recipe = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'submitted_recipes',
        columns: ['user_id'],
        filters: {'id': recipeId},
        limit: 1,
      );

      if (recipe == null || (recipe as List).isEmpty) {
        throw Exception('Recipe not found');
      }

      if (recipe[0]['user_id'] == userId) {
        throw Exception('You cannot rate your own recipe');
      }

      // Check for existing rating
      final existingRating = await getUserRecipeRating(recipeId);

      if (existingRating != null) {
        // Update rating
        await DatabaseServiceCore.workerQuery(
          action: 'update',
          table: 'recipe_ratings',
          filters: {
            'recipe_id': recipeId,
            'user_id': userId,
          },
          data: {
            'rating': rating,
            'updated_at': DateTime.now().toIso8601String(),
          },
        );
      } else {
        // Insert rating
        await DatabaseServiceCore.workerQuery(
          action: 'insert',
          table: 'recipe_ratings',
          data: {
            'recipe_id': recipeId,
            'user_id': userId,
            'rating': rating,
            'created_at': DateTime.now().toIso8601String(),
          },
        );
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Failed to rate recipe: $e');
      throw Exception('Failed to rate recipe: $e');
    }
  }
}
