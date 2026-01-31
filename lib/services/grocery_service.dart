// lib/services/grocery_service.dart
// Handles grocery list CRUD, parsing, formatting, and adding ingredients from recipes.


import '../models/grocery_item.dart';

import 'auth_service.dart';              // currentUserId + auth check
import 'database_service_core.dart';     // workerQuery + cache helpers

class GroceryService {
  // ==================================================
  // GET GROCERY LIST
  // ==================================================
  static Future<List<GroceryItem>> getGroceryList() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return [];

    try {
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'grocery_items',
        columns: ['*'],
        filters: {'user_id': userId},
        orderBy: 'order_index',
        ascending: true,
      );

      return (response as List)
          .map((json) => GroceryItem.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Failed to load grocery list: $e');
    }
  }

  // ==================================================
  // SAVE LIST (Clear + Insert all)
  // ==================================================
  static Future<void> saveGroceryList(List<String> items) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    final userId = AuthService.currentUserId!;

    try {
      // Delete existing
      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'grocery_items',
        filters: {'user_id': userId},
      );

      // Insert new list
      if (items.isNotEmpty) {
        final rows = items.asMap().entries.map((entry) {
          return {
            'user_id': userId,
            'item': entry.value,
            'order_index': entry.key,
            'created_at': DateTime.now().toIso8601String(),
          };
        }).toList();

        for (final item in rows) {
          await DatabaseServiceCore.workerQuery(
            action: 'insert',
            table: 'grocery_items',
            data: item,
          );
        }
      }
    } catch (e) {
      throw Exception('Failed to save grocery list: $e');
    }
  }

  // ==================================================
  // CLEAR LIST
  // ==================================================
  static Future<void> clearGroceryList() async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    try {
      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'grocery_items',
        filters: {'user_id': AuthService.currentUserId!},
      );
    } catch (e) {
      throw Exception('Failed to clear grocery list: $e');
    }
  }

  // ==================================================
  // ADD SINGLE ITEM
  // ==================================================
  static Future<void> addToGroceryList(String item, {String? quantity}) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    final userId = AuthService.currentUserId!;

    try {
      final currentItems = await getGroceryList();
      final newOrderIndex = currentItems.length;

      final formatted = quantity != null && quantity.isNotEmpty
          ? '$quantity x $item'
          : item;

      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'grocery_items',
        data: {
          'user_id': userId,
          'item': formatted,
          'order_index': newOrderIndex,
          'created_at': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      throw Exception('Failed to add item: $e');
    }
  }

  // ==================================================
  // ITEM PARSING HELPERS
  // ==================================================

  static Map<String, String> parseGroceryItem(String text) {
    final parts = text.split(' x ');

    if (parts.length == 2) {
      return {
        'quantity': parts[0].trim(),
        'name': parts[1].trim(),
      };
    }

    return {
      'quantity': '',
      'name': text.trim(),
    };
  }

  static String formatGroceryItem(String name, String quantity) {
    if (quantity.isNotEmpty) {
      return '$quantity x $name';
    }
    return name;
  }

  // ==================================================
  // PARSE INGREDIENTS FROM SCANNED TEXT
  // ==================================================
  static List<String> _parseIngredients(String text) {
    final items = text
        .split(RegExp(r'[,\n•\-\*]|\d+\.'))
        .map((i) => i.trim())
        .where((i) => i.isNotEmpty)
        .map((i) {
          i = i.replaceAll(
              RegExp(r'^\d+\s*(cups?|tbsp|tsp|lbs?|oz|grams?|kg|ml|liters?)?\s*'),
              '');
          i = i.replaceAll(
              RegExp(r'^\d+/\d+\s*(cups?|tbsp|tsp|lbs?|oz|grams?|kg|ml|liters?)?\s*'),
              '');
          i = i.replaceAll(RegExp(r'^(a\s+)?(pinch\s+of\s+|dash\s+of\s+)?'), '');
          return i.trim();
        })
        .where((i) => i.isNotEmpty && i.length > 2)
        .toList();

    return items;
  }

  static bool _similar(String a, String b) {
    final ca = a.toLowerCase().replaceAll(RegExp(r'[^a-z\s]'), '').trim();
    final cb = b.toLowerCase().replaceAll(RegExp(r'[^a-z\s]'), '').trim();
    if (ca == cb) return true;
    if (ca.contains(cb) || cb.contains(ca)) return true;
    return false;
  }

  // ==================================================
  // ADD RECIPE INGREDIENTS → SHOPPING LIST
  // ==================================================
  static Future<Map<String, dynamic>> addRecipeToShoppingList(
    String recipeName,
    String ingredients,
  ) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    try {
      final current = await getGroceryList();
      final currentNames = current
          .map((i) => parseGroceryItem(i.item)['name']!.toLowerCase())
          .toList();

      final newItems = _parseIngredients(ingredients);

      final added = <String>[];
      final skipped = <String>[];

      for (final item in newItems) {
        bool exists = false;

        for (final existing in currentNames) {
          if (_similar(item.toLowerCase(), existing)) {
            exists = true;
            skipped.add(item);
            break;
          }
        }

        if (!exists) {
          bool dup = false;
          for (final a in added) {
            if (_similar(a.toLowerCase(), item.toLowerCase())) {
              dup = true;
              break;
            }
          }
          if (!dup) {
            added.add(item);
          } else {
            skipped.add(item);
          }
        }
      }

      final updatedList = [
        ...current.map((i) => i.item),
        ...added,
      ];

      await saveGroceryList(updatedList);

      return {
        'added': added.length,
        'skipped': skipped.length,
        'addedItems': added,
        'skippedItems': skipped,
        'recipeName': recipeName,
      };
    } catch (e) {
      throw Exception('Failed to add recipe ingredients: $e');
    }
  }

  // ==================================================
  // COUNT ITEMS
  // ==================================================
  static Future<int> getShoppingListCount() async {
    try {
      final items = await getGroceryList();
      return items.length;
    } catch (_) {
      return 0;
    }
  }
}
