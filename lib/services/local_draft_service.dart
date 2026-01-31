// lib/services/local_draft_service.dart
// ✅ COMPLETE FIXED VERSION with all required methods

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalDraftService {
  static const String _draftKey = "local_recipe_drafts";

  /// Capitalize each word in a string (e.g., "brunswick stew" → "Brunswick Stew")
  static String _capitalizeTitle(String text) {
    if (text.isEmpty) return text;
    
    return text
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  /// Save or overwrite a draft (must include name)
  /// ✅ Automatically capitalizes recipe names
  static Future<void> saveDraft({
    required String name,
    String? description,
    required String ingredients,
    required String directions,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> drafts = {};
    
    final existing = prefs.getString(_draftKey);
    if (existing != null) {
      try {
        drafts = jsonDecode(existing);
      } catch (e) {
        print('⚠️ Error decoding existing drafts: $e');
        drafts = {};
      }
    }

    // ✅ Capitalize the recipe name before saving
    final capitalizedName = _capitalizeTitle(name.trim());

    drafts[capitalizedName] = {
      "name": capitalizedName,
      "ingredients": ingredients,
      "directions": directions,
      "created_at": DateTime.now().toIso8601String(),
      "updated_at": DateTime.now().toIso8601String(),
    };

    await prefs.setString(_draftKey, jsonEncode(drafts));
    print('✅ Draft saved: $capitalizedName');
  }

  /// Get all drafts as a Map (key = recipe name, value = draft data)
  static Future<Map<String, dynamic>> getDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_draftKey);
    
    if (data == null || data.isEmpty) return {};
    
    try {
      return jsonDecode(data);
    } catch (e) {
      print('⚠️ Error decoding drafts: $e');
      return {};
    }
  }

  /// ✅ Get all drafts as a list (for UI display)
  /// Returns list with 'id' field added for each draft
  static Future<List<Map<String, dynamic>>> getDraftsList() async {
    final draftsMap = await getDrafts();
    
    if (draftsMap.isEmpty) return [];
    
    // Convert map to list and add ID field
    final draftsList = draftsMap.entries.map((entry) {
      final draft = Map<String, dynamic>.from(entry.value);
      draft['id'] = entry.key; // Use the key (recipe name) as the ID
      return draft;
    }).toList();
    
    // Sort by updated_at (most recent first)
    draftsList.sort((a, b) {
      final aTime = a['updated_at'] ?? '';
      final bTime = b['updated_at'] ?? '';
      return bTime.compareTo(aTime);
    });
    
    return draftsList;
  }

  /// Load a single draft by name
  static Future<Map<String, dynamic>?> loadDraft(String name) async {
    final drafts = await getDrafts();
    
    if (drafts.isEmpty) return null;
    
    // ✅ Try both original name and capitalized version
    if (drafts.containsKey(name)) {
      return drafts[name];
    }
    
    final capitalizedName = _capitalizeTitle(name);
    if (drafts.containsKey(capitalizedName)) {
      return drafts[capitalizedName];
    }
    
    print('⚠️ Draft not found: $name');
    return null;
  }

  /// ✅ Update an existing draft by ID (name)
  /// If the name changes, the old draft is removed
  static Future<void> updateDraft({
    required String id,
    required String name,
    required String ingredients,
    required String directions,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> drafts = {};
    
    final existing = prefs.getString(_draftKey);
    if (existing != null) {
      try {
        drafts = jsonDecode(existing);
      } catch (e) {
        print('⚠️ Error decoding existing drafts: $e');
        drafts = {};
      }
    }
    
    // Store the creation date if it exists
    String? createdAt;
    if (drafts.containsKey(id)) {
      createdAt = drafts[id]['created_at'];
    }
    
    // Remove old entry if name changed
    if (id != name) {
      drafts.remove(id);
      drafts.remove(_capitalizeTitle(id));
      print('🔄 Draft renamed from "$id" to "$name"');
    }
    
    // ✅ Capitalize the recipe name before saving
    final capitalizedName = _capitalizeTitle(name.trim());
    
    drafts[capitalizedName] = {
      "name": capitalizedName,
      "ingredients": ingredients,
      "directions": directions,
      "created_at": createdAt ?? DateTime.now().toIso8601String(),
      "updated_at": DateTime.now().toIso8601String(),
    };
    
    await prefs.setString(_draftKey, jsonEncode(drafts));
    print('✅ Draft updated: $capitalizedName');
  }

  /// ✅ Check if a draft exists by name
  static Future<bool> draftExists(String name) async {
    final drafts = await getDrafts();
    
    if (drafts.isEmpty) return false;
    
    return drafts.containsKey(name) || 
           drafts.containsKey(_capitalizeTitle(name));
  }

  /// Get count of drafts
  static Future<int> getDraftCount() async {
    final drafts = await getDrafts();
    return drafts.length;
  }

  /// Delete a draft by name
  static Future<void> deleteDraft(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await getDrafts();
    
    if (drafts.isEmpty) {
      print('⚠️ No drafts to delete');
      return;
    }
    
    // ✅ Try to delete both versions (original and capitalized)
    final removed = drafts.remove(name) != null;
    final removedCap = drafts.remove(_capitalizeTitle(name)) != null;
    
    if (removed || removedCap) {
      await prefs.setString(_draftKey, jsonEncode(drafts));
      print('✅ Draft deleted: $name');
    } else {
      print('⚠️ Draft not found for deletion: $name');
    }
  }

  /// Clear all drafts
  static Future<void> clearDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
    print('🗑️ All drafts cleared');
  }

  /// ✅ Get draft names only (for quick lookups)
  static Future<List<String>> getDraftNames() async {
    final drafts = await getDrafts();
    return drafts.keys.toList();
  }

  /// ✅ Duplicate a draft with a new name
  static Future<void> duplicateDraft({
    required String originalName,
    required String newName,
  }) async {
    final draft = await loadDraft(originalName);
    
    if (draft == null) {
      throw Exception('Original draft not found: $originalName');
    }
    
    await saveDraft(
      name: newName,
      ingredients: draft['ingredients'] ?? '',
      directions: draft['directions'] ?? '',
    );
    
    print('✅ Draft duplicated: $originalName → $newName');
  }

  /// ✅ Rename a draft (preserves creation date)
  static Future<void> renameDraft({
    required String oldName,
    required String newName,
  }) async {
    final draft = await loadDraft(oldName);
    
    if (draft == null) {
      throw Exception('Draft not found: $oldName');
    }
    
    // Check if new name already exists
    final exists = await draftExists(newName);
    if (exists) {
      throw Exception('A draft with name "$newName" already exists');
    }
    
    await updateDraft(
      id: oldName,
      name: newName,
      ingredients: draft['ingredients'] ?? '',
      directions: draft['directions'] ?? '',
    );
    
    print('✅ Draft renamed: $oldName → $newName');
  }

  /// ✅ Export all drafts as JSON string (for backup)
  static Future<String> exportDrafts() async {
    final drafts = await getDrafts();
    return jsonEncode(drafts);
  }

  /// ✅ Import drafts from JSON string (merge with existing)
  static Future<void> importDrafts(String jsonString, {bool overwrite = false}) async {
    final prefs = await SharedPreferences.getInstance();
    
    try {
      final importedDrafts = jsonDecode(jsonString) as Map<String, dynamic>;
      
      if (overwrite) {
        // Replace all existing drafts
        await prefs.setString(_draftKey, jsonString);
        print('✅ Drafts imported (overwrite): ${importedDrafts.length} drafts');
      } else {
        // Merge with existing drafts
        final existingDrafts = await getDrafts();
        existingDrafts.addAll(importedDrafts);
        await prefs.setString(_draftKey, jsonEncode(existingDrafts));
        print('✅ Drafts imported (merged): ${importedDrafts.length} new drafts');
      }
    } catch (e) {
      print('❌ Error importing drafts: $e');
      throw Exception('Invalid draft data format');
    }
  }
}