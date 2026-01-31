// lib/models/cookbook_recipe.dart - UPDATED WITH NUTRITION
import 'dart:convert';
import 'package:bari_wise/models/nutrition_info.dart';

class CookbookRecipe {
  final int id;
  final String userId;
  final int? recipeId;
  final String recipeName;
  final String ingredients;
  final String directions;
  final String? notes;
  final NutritionInfo? nutrition;  // 🔥 NEW
  final int? servings;             // 🔥 NEW
  final DateTime createdAt;
  final DateTime? updatedAt;

  CookbookRecipe({
    required this.id,
    required this.userId,
    this.recipeId,
    required this.recipeName,
    required this.ingredients,
    required this.directions,
    this.notes,
    this.nutrition,     // 🔥 NEW
    this.servings,      // 🔥 NEW
    required this.createdAt,
    this.updatedAt,
  });

  // Create from JSON (from database)
  factory CookbookRecipe.fromJson(Map<String, dynamic> json) {
    NutritionInfo? nutrition;
    
    // Try to parse nutrition if it exists
    if (json['nutrition'] != null) {
      try {
        final nutritionData = json['nutrition'] is String 
          ? jsonDecode(json['nutrition']) 
          : json['nutrition'];
        
        if (nutritionData is Map<String, dynamic>) {
          nutrition = NutritionInfo.fromDatabaseJson(nutritionData);
        }
      } catch (e) {
        print('Error parsing nutrition in cookbook recipe: $e');
      }
    }

    return CookbookRecipe(
      id: json['id'] as int,
      userId: json['user_id'] as String,
      recipeId: json['recipe_id'] as int?,
      recipeName: json['recipe_name'] as String,
      ingredients: json['ingredients'] as String,
      directions: json['directions'] as String,
      notes: json['notes'] as String?,
      nutrition: nutrition,           // 🔥 NEW
      servings: json['servings'] as int?,  // 🔥 NEW
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null 
        ? DateTime.parse(json['updated_at'] as String)
        : null,
    );
  }

  // Convert to JSON (for database)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'recipe_id': recipeId,
      'recipe_name': recipeName,
      'ingredients': ingredients,
      'directions': directions,
      'notes': notes,
      'nutrition': nutrition?.toJsonString(),  // 🔥 NEW
      'servings': servings,                    // 🔥 NEW
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  // Create a copy with modified fields
  CookbookRecipe copyWith({
    int? id,
    String? userId,
    int? recipeId,
    String? recipeName,
    String? ingredients,
    String? directions,
    String? notes,
    NutritionInfo? nutrition,  // 🔥 NEW
    int? servings,             // 🔥 NEW
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CookbookRecipe(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      recipeId: recipeId ?? this.recipeId,
      recipeName: recipeName ?? this.recipeName,
      ingredients: ingredients ?? this.ingredients,
      directions: directions ?? this.directions,
      notes: notes ?? this.notes,
      nutrition: nutrition ?? this.nutrition,      // 🔥 NEW
      servings: servings ?? this.servings,        // 🔥 NEW
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'CookbookRecipe(id: $id, recipeName: $recipeName, userId: $userId)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CookbookRecipe &&
      other.id == id &&
      other.userId == userId &&
      other.recipeName == recipeName;
  }

  @override
  int get hashCode {
    return id.hashCode ^ userId.hashCode ^ recipeName.hashCode;
  }
}