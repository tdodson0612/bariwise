// lib/services/custom_ingredients_service.dart
// User-created custom ingredients with free/premium limits
// iOS 14 Compatible | Production Ready

import '../models/nutrition_info.dart';
import '../models/ingredient_search_result.dart';
import '../config/app_config.dart';
import 'database_service_core.dart';
import 'profile_service.dart';
import 'auth_service.dart';

class CustomIngredientsService {
  static const String _CACHE_KEY = 'cache_custom_ingredients';

  // ============================================================
  // PUBLIC API
  // ============================================================

  /// Add custom ingredient (respects free/premium limits)
  /// FREE: 3 max, PREMIUM: unlimited
  static Future<String> addCustomIngredient({
    required String name,
    required NutritionInfo nutrition,
    String? barcode,
    String? brand,
    String? servingSize,
    String? category,
    bool isbariFriendly = true,
  }) async {
    AuthService.ensureUserAuthenticated();
    final userId = AuthService.currentUserId!;

    try {
      // Validate input
      if (name.trim().isEmpty) {
        throw Exception('Ingredient name cannot be empty');
      }

      // Check if user can add more custom ingredients
      final canAdd = await canAddCustomIngredient(userId);
      if (!canAdd) {
        final remaining = await getRemainingSlots(userId);
        throw Exception(
          'Free users are limited to 3 custom ingredients. '
          'You have $remaining slots remaining. '
          'Upgrade to Premium for unlimited custom ingredients.',
        );
      }

      // Check for duplicates
      final existing = await getUserCustomIngredients(userId);
      final duplicate = existing.any(
        (ing) => ing['name'].toString().toLowerCase() == name.toLowerCase(),
      );

      if (duplicate) {
        throw Exception('You already have a custom ingredient named "$name"');
      }

      // Insert into database
      final response = await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'custom_ingredients',
        requireAuth: true,
        data: {
          'user_id': userId,
          'name': name.trim(),
          'barcode': barcode?.trim(),
          'brand': brand?.trim(),
          'nutrition': nutrition.toJson(),
          'serving_size': servingSize?.trim(),
          'category': category?.trim(),
          'is_bari_friendly': isbariFriendly,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      // Clear cache
      await DatabaseServiceCore.clearCache(_CACHE_KEY);

      final result = (response as List).first;
      final ingredientId = result['id'] as String;

      AppConfig.debugPrint('✅ Custom ingredient created: $ingredientId');

      return ingredientId;
    } catch (e) {
      AppConfig.debugPrint('❌ Error adding custom ingredient: $e');

      if (e.toString().contains('duplicate key') ||
          e.toString().contains('already have')) {
        throw Exception('You already have a custom ingredient with that name');
      }

      throw Exception('Failed to add custom ingredient: $e');
    }
  }

  /// Update existing custom ingredient
  static Future<void> updateCustomIngredient({
    required String ingredientId,
    String? name,
    NutritionInfo? nutrition,
    String? barcode,
    String? brand,
    String? servingSize,
    String? category,
    bool? isbariFriendly,
  }) async {
    AuthService.ensureUserAuthenticated();
    final userId = AuthService.currentUserId!;

    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (name != null) updates['name'] = name.trim();
      if (nutrition != null) updates['nutrition'] = nutrition.toJson();
      if (barcode != null) updates['barcode'] = barcode.trim();
      if (brand != null) updates['brand'] = brand.trim();
      if (servingSize != null) updates['serving_size'] = servingSize.trim();
      if (category != null) updates['category'] = category.trim();
      if (isbariFriendly != null) {
        updates['is_bari_friendly'] = isbariFriendly;
      }

      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'custom_ingredients',
        requireAuth: true,
        filters: {
          'id': ingredientId,
          'user_id': userId, // Security: ensure user owns this ingredient
        },
        data: updates,
      );

      // Clear cache
      await DatabaseServiceCore.clearCache(_CACHE_KEY);

      AppConfig.debugPrint('✅ Custom ingredient updated: $ingredientId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error updating custom ingredient: $e');
      throw Exception('Failed to update custom ingredient: $e');
    }
  }

  /// Delete custom ingredient
  static Future<void> deleteCustomIngredient(String ingredientId) async {
    AuthService.ensureUserAuthenticated();
    final userId = AuthService.currentUserId!;

    try {
      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'custom_ingredients',
        requireAuth: true,
        filters: {
          'id': ingredientId,
          'user_id': userId, // Security: ensure user owns this ingredient
        },
      );

      // Clear cache
      await DatabaseServiceCore.clearCache(_CACHE_KEY);

      AppConfig.debugPrint('✅ Custom ingredient deleted: $ingredientId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error deleting custom ingredient: $e');
      throw Exception('Failed to delete custom ingredient: $e');
    }
  }

  /// Get user's custom ingredients
  static Future<List<Map<String, dynamic>>> getUserCustomIngredients(
    String userId,
  ) async {
    try {
      // Try cache first
      final cached = await DatabaseServiceCore.getCachedData(_CACHE_KEY);
      if (cached != null) {
        final data = _decodeCacheData(cached);
        if (data['userId'] == userId) {
          return List<Map<String, dynamic>>.from(data['ingredients']);
        }
      }

      // Fetch from database
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'custom_ingredients',
        columns: ['*'],
        filters: {'user_id': userId},
        orderBy: 'created_at',
        ascending: false,
      );

      if (response == null) return [];

      final ingredients = List<Map<String, dynamic>>.from(response as List);

      // Cache the results
      await _cacheIngredients(userId, ingredients);

      return ingredients;
    } catch (e) {
      AppConfig.debugPrint('❌ Error loading custom ingredients: $e');
      throw Exception('Failed to load custom ingredients: $e');
    }
  }

  /// Search user's custom ingredients
  static Future<List<IngredientSearchResult>> searchCustomIngredients(
    String userId,
    String query,
  ) async {
    try {
      final ingredients = await getUserCustomIngredients(userId);

      if (query.trim().isEmpty) {
        return ingredients
            .map((ing) => IngredientSearchResult.fromCustomIngredient(ing))
            .toList();
      }

      final lowerQuery = query.toLowerCase();

      return ingredients.where((ing) {
        final name = (ing['name'] as String).toLowerCase();
        final brand = (ing['brand'] as String?)?.toLowerCase() ?? '';

        return name.contains(lowerQuery) || brand.contains(lowerQuery);
      }).map((ing) {
        return IngredientSearchResult.fromCustomIngredient(ing);
      }).toList();
    } catch (e) {
      AppConfig.debugPrint('❌ Error searching custom ingredients: $e');
      return [];
    }
  }

  /// Check if user can add more custom ingredients
  /// FREE: 3 max, PREMIUM: unlimited
  static Future<bool> canAddCustomIngredient(String userId) async {
    try {
      // Check premium status
      final isPremium = await ProfileService.isPremiumUser();
      if (isPremium) return true;

      // Free users limited to 3
      final count = await getCustomIngredientCount(userId);
      return count < 3;
    } catch (e) {
      AppConfig.debugPrint('❌ Error checking custom ingredient limit: $e');
      return false;
    }
  }

  /// Get number of custom ingredients user has
  static Future<int> getCustomIngredientCount(String userId) async {
    try {
      final ingredients = await getUserCustomIngredients(userId);
      return ingredients.length;
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting custom ingredient count: $e');
      return 0;
    }
  }

  /// Get remaining custom ingredient slots for free users
  /// Returns -1 for premium users (unlimited)
  static Future<int> getRemainingSlots(String userId) async {
    try {
      final isPremium = await ProfileService.isPremiumUser();
      if (isPremium) return -1; // Unlimited

      final count = await getCustomIngredientCount(userId);
      return (3 - count).clamp(0, 3);
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting remaining slots: $e');
      return 0;
    }
  }

  /// Get custom ingredient by ID
  static Future<Map<String, dynamic>?> getCustomIngredient(
    String ingredientId,
  ) async {
    AuthService.ensureUserAuthenticated();
    final userId = AuthService.currentUserId!;

    try {
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'custom_ingredients',
        columns: ['*'],
        filters: {
          'id': ingredientId,
          'user_id': userId,
        },
        limit: 1,
      );

      if (response == null || (response as List).isEmpty) {
        return null;
      }

      return (response).first;
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting custom ingredient: $e');
      return null;
    }
  }

  /// Check if custom ingredient with name already exists
  static Future<bool> customIngredientExists(
    String userId,
    String name,
  ) async {
    try {
      final ingredients = await getUserCustomIngredients(userId);
      return ingredients.any(
        (ing) => ing['name'].toString().toLowerCase() == name.toLowerCase(),
      );
    } catch (e) {
      return false;
    }
  }

  // ============================================================
  // PRIVATE HELPERS
  // ============================================================

  static Future<void> _cacheIngredients(
    String userId,
    List<Map<String, dynamic>> ingredients,
  ) async {
    try {
      final cacheData = {
        'userId': userId,
        'ingredients': ingredients,
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
      };

      await DatabaseServiceCore.cacheData(
        _CACHE_KEY,
        _encodeCacheData(cacheData),
      );
    } catch (e) {
      AppConfig.debugPrint('⚠️ Failed to cache custom ingredients: $e');
    }
  }

  static Map<String, dynamic> _decodeCacheData(String cached) {
    try {
      return Map<String, dynamic>.from(
        // Using a simple JSON decode
        cached.split('|||').fold<Map<String, dynamic>>({}, (map, part) {
          final kv = part.split(':::');
          if (kv.length == 2) {
            map[kv[0]] = kv[1];
          }
          return map;
        }),
      );
    } catch (e) {
      return {};
    }
  }

  static String _encodeCacheData(Map<String, dynamic> data) {
    // Simple encoding for cache
    return data.entries.map((e) => '${e.key}:::${e.value}').join('|||');
  }
}