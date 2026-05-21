// lib/services/grocery_service.dart
// ✅ FIXED: Delete calls now include user_id filter so the Cloudflare
//           Worker can execute them without returning an error.

import '../models/grocery_item.dart';
import 'auth_service.dart';
import 'database_service_core.dart';

class GroceryService {
  // ==================================================
  // GET GROCERY LIST
  // ==================================================
  static Future<List<GroceryItem>> getGroceryList() async {
    print('📋 GroceryService.getGroceryList() called');

    final userId = AuthService.currentUserId;
    print('👤 Current userId: $userId');

    if (userId == null || userId.isEmpty) {
      print('❌ No userId available - returning empty list');
      return [];
    }

    try {
      print('🔍 Querying grocery_items table...');

      // RLS policies will filter by user automatically
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'grocery_items',
        columns: ['*'],
        orderBy: 'order_index',
        ascending: true,
      );

      print('✅ Worker query response type: ${response.runtimeType}');
      print('📦 Response data: $response');

      if (response == null) {
        print('⚠️ Worker returned null - returning empty list');
        return [];
      }

      if (response is! List) {
        print('⚠️ Worker returned non-list: ${response.runtimeType}');
        return [];
      }

      final items = <GroceryItem>[];
      for (var i = 0; i < response.length; i++) {
        try {
          final json = response[i];
          if (json is Map<String, dynamic>) {
            print('Parsing item $i: $json');
            final item = GroceryItem.fromJson(json);
            if (item.isValid()) {
              items.add(item);
            } else {
              print('⚠️ Skipping invalid item at index $i: $json');
            }
          } else {
            print('⚠️ Item at index $i is not a Map: ${json.runtimeType}');
          }
        } catch (e, stackTrace) {
          print('⚠️ Error parsing item at index $i: $e');
          print('Stack trace: $stackTrace');
          // Continue processing other items
        }
      }

      print('✅ Successfully loaded ${items.length} grocery items');
      return items;
    } catch (e, stackTrace) {
      print('❌ Error in getGroceryList: $e');
      print('Stack trace: $stackTrace');

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
  // ✅ FIX: Delete now passes user_id filter so the Worker
  //         knows which rows to remove.
  // ==================================================
  static Future<void> saveGroceryList(List<String> items) async {
    print('\n========================================');
    print('💾 GroceryService.saveGroceryList() START');
    print('========================================');
    print('📊 Items to save: ${items.length}');

    final userId = AuthService.currentUserId;
    print('👤 Current userId: $userId');

    if (userId == null || userId.isEmpty) {
      print('❌ No userId - cannot save');
      throw Exception('Please sign in to continue');
    }

    print('📋 Items list: $items');

    try {
      // STEP 1: Delete existing items for this user
      print('\n--- STEP 1: DELETE EXISTING ITEMS ---');
      print('🗑️ Calling delete query...');
      try {
        final deleteResult = await DatabaseServiceCore.workerQuery(
          action: 'delete',
          table: 'grocery_items',
          // ✅ FIX: explicit user_id filter so the Worker executes the delete
          filters: {'user_id': userId},
        );
        print('✅ Delete successful');
        print('📦 Delete result: $deleteResult');
      } catch (deleteError, deleteStack) {
        print('❌ DELETE FAILED!');
        print('❌ Error: $deleteError');
        print('❌ Stack: $deleteStack');
        throw Exception('Failed to clear existing items: $deleteError');
      }

      // STEP 2: Insert new items
      if (items.isEmpty) {
        print('\nℹ️ No items to insert (list is empty)');
        print('========================================\n');
        return;
      }

      print('\n--- STEP 2: INSERT NEW ITEMS ---');
      print('📝 Inserting ${items.length} items...');

      for (var i = 0; i < items.length; i++) {
        final item = items[i];

        print('\n➡️ Processing item $i of ${items.length}');
        print('   Raw value: "$item"');

        if (item.trim().isEmpty) {
          print('   ⚠️ Empty - skipping');
          continue;
        }

        try {
          final data = {
            'user_id': userId,
            'item_name': item.trim(),
            'order_index': i,
            'created_at': DateTime.now().toIso8601String(),
          };

          print('   📤 Data to insert: $data');

          final insertResult = await DatabaseServiceCore.workerQuery(
            action: 'insert',
            table: 'grocery_items',
            data: data,
          );

          print('   ✅ Insert successful');
          print('   📦 Result: $insertResult');
        } catch (itemError, itemStack) {
          print('   ❌ INSERT FAILED for item $i!');
          print('   ❌ Item: "$item"');
          print('   ❌ Error: $itemError');
          print('   ❌ Stack: $itemStack');

          // Stop on first error to diagnose
          throw Exception('Failed to insert item "$item": $itemError');
        }
      }

      print('\n✅ ALL ITEMS INSERTED SUCCESSFULLY');
      print('========================================\n');
    } catch (e, stackTrace) {
      print('\n❌❌❌ FINAL ERROR IN saveGroceryList ❌❌❌');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      print('========================================\n');

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
          errorStr.contains('item_name')) {
        throw Exception(
            'Database schema error: item_name column issue: $e');
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
  // ✅ FIX: Delete now passes user_id filter so the Worker
  //         knows which rows to remove.
  // ==================================================
  static Future<void> clearGroceryList() async {
    print('🗑️ GroceryService.clearGroceryList() called');

    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    final userId = AuthService.currentUserId!;
    print('👤 Clearing for user: $userId');

    try {
      // ✅ FIX: explicit user_id filter so the Worker executes the delete
      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'grocery_items',
        filters: {'user_id': userId},
      );
      print('✅ Successfully cleared grocery list');
    } catch (e, stackTrace) {
      print('❌ Error in clearGroceryList: $e');
      print('Stack trace: $stackTrace');
      throw Exception('Failed to clear grocery list: $e');
    }
  }

  // ==================================================
  // ADD SINGLE ITEM
  // ==================================================
  static Future<void> addToGroceryList(String item,
      {String? quantity}) async {
    print(
        '➕ GroceryService.addToGroceryList() called: "$item" (qty: $quantity)');

    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    final userId = AuthService.currentUserId!;
    print('👤 Adding for user: $userId');

    try {
      // Get current items to determine order index
      final currentItems = await getGroceryList();
      final newOrderIndex = currentItems.length;

      final formatted = quantity != null && quantity.isNotEmpty
          ? '$quantity x $item'
          : item;

      print('📤 Adding item: "$formatted" at index $newOrderIndex');

      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'grocery_items',
        data: {
          'user_id': userId,
          'item_name': formatted.trim(),
          'order_index': newOrderIndex,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      print('✅ Successfully added item to grocery list');
    } catch (e, stackTrace) {
      print('❌ Error in addToGroceryList: $e');
      print('Stack trace: $stackTrace');
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
    final ca =
        a.toLowerCase().replaceAll(RegExp(r'[^a-z\s]'), '').trim();
    final cb =
        b.toLowerCase().replaceAll(RegExp(r'[^a-z\s]'), '').trim();
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
    print('📝 Adding recipe "$recipeName" ingredients to shopping list');

    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    try {
      final current = await getGroceryList();
      final currentNames = current
          .map((i) => parseGroceryItem(i.item)['name']!.toLowerCase())
          .toList();

      final newItems = _parseIngredients(ingredients);
      print('🔍 Parsed ${newItems.length} ingredients from recipe');

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

      print(
          '✅ Added ${added.length} items, skipped ${skipped.length} duplicates');

      return {
        'added': added.length,
        'skipped': skipped.length,
        'addedItems': added,
        'skippedItems': skipped,
        'recipeName': recipeName,
      };
    } catch (e, stackTrace) {
      print('❌ Error in addRecipeToShoppingList: $e');
      print('Stack trace: $stackTrace');
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
      print('⚠️ Error getting shopping list count: $e');
      return 0;
    }
  }

  // ==================================================
  // TEST DATABASE CONNECTION
  // ==================================================
  static Future<bool> testDatabaseConnection() async {
    try {
      print('🧪 Testing database connection...');

      final userId = AuthService.currentUserId;
      if (userId == null) {
        print('❌ No user ID - cannot test connection');
        return false;
      }

      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'grocery_items',
        columns: ['id'],
        limit: 1,
      );

      print('✅ Database connection test successful');
      print('Response type: ${response.runtimeType}');
      return true;
    } catch (e) {
      print('❌ Database connection test failed: $e');
      return false;
    }
  }
}