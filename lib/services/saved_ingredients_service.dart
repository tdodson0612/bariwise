import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bari_wise/models/nutrition_info.dart';

class SavedIngredientsService {
  static const String _key = 'saved_ingredients';

  /// Load all saved ingredients
  static Future<List<NutritionInfo>> loadSavedIngredients() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_key) ?? [];

    return rawList.map((encoded) {
      final data = json.decode(encoded);

      return NutritionInfo.fromJson({
        'product': {
          'product_name': data['product_name'],
          'nutriments': data['nutriments'],
        }
      });
    }).toList();
  }

  /// Save a new ingredient (removes duplicates)
  static Future<void> saveIngredient(NutritionInfo item) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> rawList = prefs.getStringList(_key) ?? [];

    // Convert the NutritionInfo object into saved format
    final jsonMap = {
      'product_name': item.productName,
      'nutriments': {
        'energy-kcal_100g': item.calories,
        'fat_100g': item.fat,
        'sugars_100g': item.sugar,
        'sodium_100g': item.sodium,
      }
    };

    // Remove existing entry (duplicate control)
    rawList.removeWhere((s) {
      final decoded = json.decode(s);
      return decoded['product_name'] == item.productName;
    });

    // Add new entry at top
    rawList.insert(0, json.encode(jsonMap));

    await prefs.setStringList(_key, rawList);
  }

  /// Remove ingredient by name
  static Future<void> removeIngredient(String productName) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> rawList = prefs.getStringList(_key) ?? [];

    rawList.removeWhere((s) {
      final decoded = json.decode(s);
      return decoded['product_name'] == productName;
    });

    await prefs.setStringList(_key, rawList);
  }

  /// Check if ingredient is saved
  static Future<bool> isSaved(String productName) async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_key) ?? [];

    return rawList.any((s) {
      final decoded = json.decode(s);
      return decoded['product_name'] == productName;
    });
  }
}
