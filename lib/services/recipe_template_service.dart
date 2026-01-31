// lib/services/recipe_template_service.dart
// Handles recipe templating with change detection

import 'dart:convert';
import '../models/nutrition_info.dart';

class RecipeTemplate {
  final String recipeName;
  final String description;
  final List<String> originalIngredients;
  final String instructions;
  final int? healthScore;
  
  RecipeTemplate({
    required this.recipeName,
    required this.description,
    required this.originalIngredients,
    required this.instructions,
    this.healthScore,
  });
  
  Map<String, dynamic> toJson() => {
    'recipeName': recipeName,
    'description': description,
    'originalIngredients': originalIngredients,
    'instructions': instructions,
    'healthScore': healthScore,
  };
  
  factory RecipeTemplate.fromJson(Map<String, dynamic> json) => RecipeTemplate(
    recipeName: json['recipeName'] ?? '',
    description: json['description'] ?? '',
    originalIngredients: List<String>.from(json['originalIngredients'] ?? []),
    instructions: json['instructions'] ?? '',
    healthScore: json['healthScore'],
  );
}

class RecipeTemplateService {
  /// Check if ingredients list has been modified from template
  static bool hasIngredientsChanged({
    required List<String> originalIngredients,
    required List<String> currentIngredients,
  }) {
    // Must have at least one change
    if (originalIngredients.length != currentIngredients.length) {
      return true; // Ingredient added or removed
    }
    
    // Normalize ingredients for comparison (lowercase, trim)
    final normalizedOriginal = originalIngredients
        .map((i) => i.trim().toLowerCase())
        .toSet();
    
    final normalizedCurrent = currentIngredients
        .map((i) => i.trim().toLowerCase())
        .toSet();
    
    // Check if any ingredient is different
    return !normalizedOriginal.containsAll(normalizedCurrent) ||
           !normalizedCurrent.containsAll(normalizedOriginal);
  }
  
  /// Validate that recipe has been sufficiently modified from template
  static String? validateTemplateChanges({
    required RecipeTemplate template,
    required String newRecipeName,
    required List<String> newIngredients,
    required String newInstructions,
  }) {
    // Check if recipe name is different (optional but good practice)
    final nameChanged = newRecipeName.trim().toLowerCase() != 
                        template.recipeName.trim().toLowerCase();
    
    // Check if ingredients changed
    final ingredientsChanged = hasIngredientsChanged(
      originalIngredients: template.originalIngredients,
      currentIngredients: newIngredients,
    );
    
    // Check if instructions changed significantly
    final instructionsChanged = newInstructions.trim() != template.instructions.trim();
    
    // Require at least ingredient changes
    if (!ingredientsChanged) {
      return 'You must modify the ingredients:\n'
             '• Add at least one ingredient\n'
             '• Remove at least one ingredient\n'
             '• Or substitute an ingredient';
    }
    
    // Optional: Suggest changing name if identical
    if (!nameChanged && !instructionsChanged) {
      return 'Consider giving your recipe a unique name and customizing the instructions.';
    }
    
    return null; // Validation passed
  }
  
  /// Get summary of changes made
  static Map<String, dynamic> getChangeSummary({
    required RecipeTemplate template,
    required List<String> newIngredients,
  }) {
    final originalSet = template.originalIngredients
        .map((i) => i.trim().toLowerCase())
        .toSet();
    
    final currentSet = newIngredients
        .map((i) => i.trim().toLowerCase())
        .toSet();
    
    final added = currentSet.difference(originalSet).toList();
    final removed = originalSet.difference(currentSet).toList();
    final kept = originalSet.intersection(currentSet).toList();
    
    return {
      'added': added.length,
      'removed': removed.length,
      'kept': kept.length,
      'addedIngredients': added,
      'removedIngredients': removed,
    };
  }
  
  /// Check if a recipe name already exists in submitted recipes
  static Future<bool> isRecipeNameTaken(String recipeName) async {
    try {
      // This would need to query your database
      // For now, returning false - implement based on your DB structure
      return false;
    } catch (e) {
      return false;
    }
  }
}