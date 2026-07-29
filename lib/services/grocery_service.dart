// lib/services/grocery_service.dart
// ✅ Adds category/checked persistence.
// ✅ saveGroceryList now takes List<GroceryItem> instead of List<String>
//    so category/checked can be saved along with each item.
// ✅ Delete calls include user_id filter so the Cloudflare Worker can
//    execute them without returning an error.

import '../models/grocery_item.dart';
import 'auth_service.dart';
import 'database_service_core.dart';
import 'package:flutter/foundation.dart';

class GroceryService {
  // ==================================================
  // CATEGORY SYSTEM (shared source of truth — used by
  // this service AND the grocery list page)
  // ==================================================
  static const List<String> categories = [
    'Produce',
    'Dairy & Eggs',
    'Meat & Seafood',
    'Bakery',
    'Pantry',
    'Frozen',
    'Beverages',
    'Snacks',
    'Household',
    'Other',
  ];

  static const Map<String, List<String>> _categoryKeywords = {
    'Produce': [
      'apple', 'banana', 'orange', 'lettuce', 'tomato', 'onion', 'carrot',
      'potato', 'spinach', 'broccoli', 'pepper', 'cucumber', 'avocado',
      'garlic', 'lemon', 'lime', 'berry', 'berries', 'fruit', 'vegetable',
      'celery', 'kale', 'mushroom', 'grape',
    ],
    'Dairy & Eggs': [
      'milk', 'cheese', 'yogurt', 'egg', 'butter', 'cream', 'sour cream',
      'cottage cheese',
    ],
    'Meat & Seafood': [
      'chicken', 'beef', 'pork', 'turkey', 'fish', 'shrimp', 'salmon',
      'bacon', 'sausage', 'steak', 'tuna', 'tilapia', 'ground beef',
      'ground turkey',
    ],
    'Bakery': [
      'bread', 'bagel', 'tortilla', 'bun', 'roll', 'muffin', 'croissant',
      'baguette',
    ],
    'Pantry': [
      'rice', 'pasta', 'flour', 'sugar', 'oil', 'cereal', 'beans',
      'canned', 'sauce', 'spice', 'salt', 'honey', 'peanut butter', 'oats',
      'broth', 'stock',
    ],
    'Frozen': ['frozen', 'ice cream', 'popsicle'],
    'Beverages': [
      'water', 'juice', 'soda', 'coffee', 'tea', 'wine', 'beer',
      'sparkling',
    ],
    'Snacks': [
      'chips', 'crackers', 'cookie', 'candy', 'nuts', 'popcorn', 'pretzel',
      'granola bar',
    ],
    'Household': [
      'paper towel', 'toilet paper', 'detergent', 'soap', 'trash bag',
      'cleaner', 'dish soap', 'sponge', 'foil', 'plastic wrap',
    ],
  };

  /// Auto-assigns a category by keyword match. Falls back to 'Other'.
  /// Shared by the grocery page (manual entry / scanned items) and by
  /// addRecipeToShoppingList, so there is one place that owns this logic.
  static String autoAssignCategory(String itemName) {
    final lower = itemName.toLowerCase();
    for (final entry in _categoryKeywords.entries) {
      for (final keyword in entry.value) {
        if (lower.contains(keyword)) {
          return entry.key;
        }
      }
    }
    return 'Other';
  }

  // ==================================================
  // GET GROCERY LIST
  // ==================================================
  static Future<List<GroceryItem>> getGroceryList() async {
debugPrint('📋 GroceryService.getGroceryList() called');

    final userId = AuthService.currentUserId;

    if (userId == null || userId.isEmpty) {

      return [];
    }

    try {

      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'grocery_items',
        columns: ['*'],
        orderBy: 'order_index',
        ascending: true,
      );

      if (response == null) {

        return [];
      }

      if (response is! List) {

        return [];
      }

      final items = <GroceryItem>[];
      for (var i = 0; i < response.length; i++) {
        try {
          final json = response[i];
          if (json is Map<String, dynamic>) {

            final item = GroceryItem.fromJson(json);
            if (item.isValid()) {
              items.add(item);
            } else {

            }
          } else {

          }
        // ignore: empty_catches
        } catch (e) {

        }
      }

      return items;
    } catch (e) {

      final errorMsg = e.toString();
      if (errorMsg.contains('table') || errorMsg.contains('column')) {
        throw Exception('Database schema error: $e');
      } else if (errorMsg.contains('auth') || errorMsg.contains('session')) {
        throw Exception('Authentication error: Please log in again. Error: $e');
      } else if (errorMsg.contains('network') || errorMsg.contains('timeout')) {
        throw Exception(
            'Network error: Please check your internet connection. Error: $e');
      } else {
        throw Exception('Failed to load grocery list: $e');
      }
    }
  }

  // ==================================================
  // SAVE LIST (Clear + Insert all)
  // ✅ Now takes List<GroceryItem> so category/checked persist.
  // ==================================================
  static Future<void> saveGroceryList(List<GroceryItem> items) async {

debugPrint('💾 GroceryService.saveGroceryList() START');

    final userId = AuthService.currentUserId;

    if (userId == null || userId.isEmpty) {

      throw Exception('Please sign in to continue');
    }

debugPrint('📋 Items list: ${items.map((e) => e.item).toList()}');

    try {
      // STEP 1: Delete existing items for this user

      try {
        await DatabaseServiceCore.workerQuery(
          action: 'delete',
          table: 'grocery_items',
          filters: {'user_id': userId},
        );

      } catch (deleteError) {

        throw Exception('Failed to clear existing items: $deleteError');
      }

      // STEP 2: Insert new items
      if (items.isEmpty) {
debugPrint('\nℹ️ No items to insert (list is empty)');

        return;
      }

      for (var i = 0; i < items.length; i++) {
        final entry = items[i];
        final name = entry.item.trim();

debugPrint('   Raw value: "$name" (category: ${entry.category}, checked: ${entry.checked})');

        if (name.isEmpty) {

          continue;
        }

        try {
          final data = {
            'user_id': userId,
            'item_name': name,
            'order_index': i,
            'created_at': DateTime.now().toIso8601String(),
            'category': entry.category.trim().isEmpty ? 'Other' : entry.category.trim(),
            'checked': entry.checked,
          };

          await DatabaseServiceCore.workerQuery(
            action: 'insert',
            table: 'grocery_items',
            data: data,
          );

        } catch (itemError) {

          throw Exception('Failed to insert item "$name": $itemError');
        }
      }

    } catch (e) {

      final errorStr = e.toString().toLowerCase();

      if (errorStr.contains('user_id') && errorStr.contains('null')) {
        throw Exception('User ID is null. Please log out and log back in.');
      } else if (errorStr.contains('user_id') &&
          errorStr.contains('foreign key')) {
        throw Exception(
            'User account not found. Please log out and log back in.');
      } else if (errorStr.contains('rls') || errorStr.contains('policy')) {
        throw Exception(
            'Permission denied. RLS policy blocking insert. Check policies in Supabase.');
      } else if (errorStr.contains('permission denied')) {
        throw Exception(
            'Permission denied. Check RLS policies in Supabase.');
      } else if (errorStr.contains('column') &&
          (errorStr.contains('item_name') ||
              errorStr.contains('category') ||
              errorStr.contains('checked'))) {
        throw Exception(
            'Database schema error: check item_name/category/checked columns exist: $e');
      } else if (errorStr.contains('column')) {
        throw Exception('Database schema error: $e');
      } else if (errorStr.contains('null value') &&
          errorStr.contains('violates not-null')) {
        throw Exception('Required field is null: $e');
      } else {
        throw Exception('Failed to save grocery list: $e');
      }
    }
  }

  // ==================================================
  // CLEAR LIST
  // ==================================================
  static Future<void> clearGroceryList() async {
debugPrint('🗑️ GroceryService.clearGroceryList() called');

    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    final userId = AuthService.currentUserId!;

    try {
      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'grocery_items',
        filters: {'user_id': userId},
      );

    } catch (e) {

      throw Exception('Failed to clear grocery list: $e');
    }
  }

  // ==================================================
  // ADD SINGLE ITEM
  // ==================================================
  static Future<void> addToGroceryList(String item,
      {String? quantity}) async {
    debugPrint(
        '➕ GroceryService.addToGroceryList() called: "$item" (qty: $quantity)');

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
          'item_name': formatted.trim(),
          'order_index': newOrderIndex,
          'created_at': DateTime.now().toIso8601String(),
          'category': autoAssignCategory(formatted),
          'checked': false,
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
              RegExp(
                  r'^\d+\s*(cups?|tbsp|tsp|lbs?|oz|grams?|kg|ml|liters?)?\s*'),
              '');
          i = i.replaceAll(
              RegExp(
                  r'^\d+/\d+\s*(cups?|tbsp|tsp|lbs?|oz|grams?|kg|ml|liters?)?\s*'),
              '');
          i = i.replaceAll(
              RegExp(r'^(a\s+)?(pinch\s+of\s+|dash\s+of\s+)?'), '');
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
  // ✅ Updated for List<GroceryItem> saveGroceryList signature.
  // ==================================================
  static Future<Map<String, dynamic>> addRecipeToShoppingList(
    String recipeName,
    String ingredients,
  ) async {

    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }
    final userId = AuthService.currentUserId!;

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

      final addedItems = added
          .map((name) => GroceryItem(
                userId: userId,
                item: name,
                orderIndex: 0,
                createdAt: DateTime.now(),
                category: autoAssignCategory(name),
                checked: false,
              ))
          .toList();

      final updatedList = <GroceryItem>[...current, ...addedItems];

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
    } catch (e) {

      return 0;
    }
  }

  // ==================================================
  // TEST DATABASE CONNECTION
  // ==================================================
  static Future<bool> testDatabaseConnection() async {
    try {

      final userId = AuthService.currentUserId;
      if (userId == null) {

        return false;
      }

      await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'grocery_items',
        columns: ['id'],
        limit: 1,
      );

      return true;
    } catch (e) {

      return false;
    }
  }
}