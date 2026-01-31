// lib/models/favorite_recipe.dart
// FIXED: Added description field
class FavoriteRecipe {
  final int? id; // Primary key in favorite_recipes table
  final String userId;
  final int? recipeId; // Foreign key to recipe_master table
  final String recipeName;
  final String? description;  // 🔥 NEW: Recipe description
  final String ingredients;
  final String directions;
  final DateTime createdAt;
  final DateTime? updatedAt;

  FavoriteRecipe({
    this.id,
    required this.userId,
    this.recipeId,
    required this.recipeName,
    this.description,  // 🔥 NEW
    required this.ingredients,
    required this.directions,
    required this.createdAt,
    this.updatedAt,
  });

  // From Supabase database response
  factory FavoriteRecipe.fromJson(Map<String, dynamic> json) {
    return FavoriteRecipe(
      id: json['id'],
      userId: json['user_id'] ?? '',
      recipeId: json['recipe_id'],
      // Handle both 'recipe_name' and 'title' for backwards compatibility
      recipeName: json['recipe_name'] ?? json['title'] ?? '',
      description: json['description'] as String?,  // 🔥 NEW
      ingredients: json['ingredients'] ?? '',
      directions: json['directions'] ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
    );
  }

  // To Supabase database (for insert/update)
  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      if (recipeId != null) 'recipe_id': recipeId,
      'recipe_name': recipeName,
      'description': description,  // 🔥 NEW
      'ingredients': ingredients,
      'directions': directions,
      'created_at': createdAt.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  // For local cache storage (includes all fields)
  Map<String, dynamic> toCache() {
    return {
      'id': id,
      'user_id': userId,
      'recipe_id': recipeId,
      'recipe_name': recipeName,
      'description': description,  // 🔥 NEW
      'ingredients': ingredients,
      'directions': directions,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'cached_at': DateTime.now().toIso8601String(),
    };
  }

  // From local cache storage
  factory FavoriteRecipe.fromCache(Map<String, dynamic> json) {
    return FavoriteRecipe(
      id: json['id'],
      userId: json['user_id'] ?? '',
      recipeId: json['recipe_id'],
      recipeName: json['recipe_name'] ?? '',
      description: json['description'] as String?,  // 🔥 NEW
      ingredients: json['ingredients'] ?? '',
      directions: json['directions'] ?? '',
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
    );
  }

  // Create a copy with updated fields
  FavoriteRecipe copyWith({
    int? id,
    String? userId,
    int? recipeId,
    String? recipeName,
    String? description,  // 🔥 NEW
    String? ingredients,
    String? directions,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FavoriteRecipe(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      recipeId: recipeId ?? this.recipeId,
      recipeName: recipeName ?? this.recipeName,
      description: description ?? this.description,  // 🔥 NEW
      ingredients: ingredients ?? this.ingredients,
      directions: directions ?? this.directions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'FavoriteRecipe(id: $id, userId: $userId, recipeId: $recipeId, recipeName: $recipeName)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FavoriteRecipe &&
        other.id == id &&
        other.userId == userId &&
        other.recipeId == recipeId &&
        other.recipeName == recipeName;
  }

  @override
  int get hashCode {
    return Object.hash(id, userId, recipeId, recipeName);
  }
}