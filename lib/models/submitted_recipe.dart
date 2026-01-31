//submitted_recipe.dart

class SubmittedRecipe {
  final int? id;
  final String userId;
  final String recipeName;
  final String ingredients;
  final String directions;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isVerified; // 🔥 NEW

  SubmittedRecipe({
    this.id,
    required this.userId,
    required this.recipeName,
    required this.ingredients,
    required this.directions,
    required this.createdAt,
    this.updatedAt,
    this.isVerified = false, // 🔥 NEW: Default to false
  });

  // UPDATE fromJson to include isVerified:
  factory SubmittedRecipe.fromJson(Map<String, dynamic> json) {
    return SubmittedRecipe(
      id: json['id'] as int?,
      userId: json['user_id'] as String,
      recipeName: json['recipe_name'] as String,
      ingredients: json['ingredients'] as String,
      directions: json['directions'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      isVerified: json['is_verified'] as bool? ?? false, // 🔥 NEW
    );
  }

  // UPDATE toJson to include isVerified:
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'recipe_name': recipeName,
      'ingredients': ingredients,
      'directions': directions,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'is_verified': isVerified, // 🔥 NEW
    };
  }

  // UPDATE copyWith to include isVerified:
  SubmittedRecipe copyWith({
    int? id,
    String? userId,
    String? recipeName,
    String? ingredients,
    String? directions,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isVerified, // 🔥 NEW
  }) {
    return SubmittedRecipe(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      recipeName: recipeName ?? this.recipeName,
      ingredients: ingredients ?? this.ingredients,
      directions: directions ?? this.directions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isVerified: isVerified ?? this.isVerified, // 🔥 NEW
    );
  }
}