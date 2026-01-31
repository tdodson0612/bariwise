// lib/models/draft_recipe.dart
// Database-backed recipe model with nutrition auto-calculation
// iOS 14 Compatible | Production Ready | Uses NutritionInfo

import 'nutrition_info.dart';
import '../barihealthbar.dart';

class DraftRecipe {
  final String? id; // UUID from database
  final String userId;
  final String title;
  final String? description;
  final List<RecipeIngredient> ingredients;
  final String? instructions;
  final int? prepTime; // minutes
  final int? cookTime; // minutes
  final int servings;
  final NutritionInfo? totalNutrition; // Auto-calculated
  final String? imageUrl;
  final bool isbariFriendly;
  final DateTime createdAt;
  final DateTime updatedAt;

  DraftRecipe({
    this.id,
    required this.userId,
    required this.title,
    this.description,
    required this.ingredients,
    this.instructions,
    this.prepTime,
    this.cookTime,
    this.servings = 1,
    this.totalNutrition,
    this.imageUrl,
    this.isbariFriendly = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  // ============================================================
  // FROM JSON (Database → Dart)
  // ============================================================
  factory DraftRecipe.fromJson(Map<String, dynamic> json) {
    // Parse ingredients
    final ingredientsJson = json['ingredients'] as List? ?? [];
    final ingredients = ingredientsJson
        .map((i) => RecipeIngredient.fromJson(i as Map<String, dynamic>))
        .toList();

    // Parse nutrition
    NutritionInfo? nutrition;
    if (json['total_nutrition'] != null) {
      try {
        nutrition = NutritionInfo.fromDatabaseJson(
          json['total_nutrition'] as Map<String, dynamic>,
        );
      } catch (e) {
        print('⚠️ Error parsing nutrition: $e');
      }
    }

    return DraftRecipe(
      id: json['id'] as String?,
      userId: json['user_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      ingredients: ingredients,
      instructions: json['instructions'] as String?,
      prepTime: json['prep_time'] as int?,
      cookTime: json['cook_time'] as int?,
      servings: json['servings'] as int? ?? 1,
      totalNutrition: nutrition,
      imageUrl: json['image_url'] as String?,
      isbariFriendly: json['is_bari_friendly'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  // ============================================================
  // TO JSON (Dart → Database)
  // ============================================================
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'title': title,
      'description': description,
      'ingredients': ingredients.map((i) => i.toJson()).toList(),
      'instructions': instructions,
      'prep_time': prepTime,
      'cook_time': cookTime,
      'servings': servings,
      'total_nutrition': totalNutrition?.toJson(),
      'image_url': imageUrl,
      'is_bari_friendly': isbariFriendly,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // ============================================================
  // COPY WITH (Immutable Updates)
  // ============================================================
  DraftRecipe copyWith({
    String? id,
    String? userId,
    String? title,
    String? description,
    List<RecipeIngredient>? ingredients,
    String? instructions,
    int? prepTime,
    int? cookTime,
    int? servings,
    NutritionInfo? totalNutrition,
    String? imageUrl,
    bool? isbariFriendly,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DraftRecipe(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      ingredients: ingredients ?? this.ingredients,
      instructions: instructions ?? this.instructions,
      prepTime: prepTime ?? this.prepTime,
      cookTime: cookTime ?? this.cookTime,
      servings: servings ?? this.servings,
      totalNutrition: totalNutrition ?? this.totalNutrition,
      imageUrl: imageUrl ?? this.imageUrl,
      isbariFriendly: isbariFriendly ?? this.isbariFriendly,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  /// Get total time (prep + cook)
  int? get totalTime {
    if (prepTime == null && cookTime == null) return null;
    return (prepTime ?? 0) + (cookTime ?? 0);
  }

  /// Check if recipe has complete nutrition data
  bool get hasNutrition {
    return totalNutrition != null && !totalNutrition!.isEmpty;
  }

  /// Get ingredient count
  int get ingredientCount => ingredients.length;

  /// Check if recipe is complete (has all required fields)
  bool get isComplete {
    return title.isNotEmpty &&
        ingredients.isNotEmpty &&
        (instructions?.isNotEmpty ?? false);
  }
  
  /// Get health score from nutrition
  int get healthScore {
    if (totalNutrition == null) return 0;
    return totalNutrition!.calculatebariScore();
  }

  @override
  String toString() {
    return 'DraftRecipe(id: $id, title: $title, ingredients: ${ingredients.length})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is DraftRecipe &&
        other.id == id &&
        other.userId == userId &&
        other.title == title;
  }

  @override
  int get hashCode {
    return id.hashCode ^ userId.hashCode ^ title.hashCode;
  }
}

// ============================================================
// RECIPE INGREDIENT MODEL
// ============================================================

class RecipeIngredient {
  final String? barcode;
  final String productName;
  final double quantity;
  final String unit; // "cup", "oz", "g", "tbsp"
  final NutritionInfo? nutrition;
  final String? source; // 'scan', 'search', 'custom'

  RecipeIngredient({
    this.barcode,
    required this.productName,
    required this.quantity,
    required this.unit,
    this.nutrition,
    this.source,
  });

  factory RecipeIngredient.fromJson(Map<String, dynamic> json) {
    NutritionInfo? nutrition;
    if (json['nutrition'] != null) {
      try {
        nutrition = NutritionInfo.fromDatabaseJson(
          json['nutrition'] as Map<String, dynamic>,
        );
      } catch (e) {
        print('⚠️ Error parsing ingredient nutrition: $e');
      }
    }

    return RecipeIngredient(
      barcode: json['barcode'] as String?,
      productName: json['product_name'] as String,
      quantity: (json['quantity'] as num).toDouble(),
      unit: json['unit'] as String,
      nutrition: nutrition,
      source: json['source'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (barcode != null) 'barcode': barcode,
      'product_name': productName,
      'quantity': quantity,
      'unit': unit,
      if (nutrition != null) 'nutrition': nutrition!.toJson(),
      if (source != null) 'source': source,
    };
  }

  RecipeIngredient copyWith({
    String? barcode,
    String? productName,
    double? quantity,
    String? unit,
    NutritionInfo? nutrition,
    String? source,
  }) {
    return RecipeIngredient(
      barcode: barcode ?? this.barcode,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      nutrition: nutrition ?? this.nutrition,
      source: source ?? this.source,
    );
  }

  /// Get display string (e.g., "2 cups Flour")
  String get displayString {
    return '${quantity.toStringAsFixed(quantity.truncateToDouble() == quantity ? 0 : 1)} $unit $productName';
  }

  @override
  String toString() {
    return 'RecipeIngredient($displayString)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is RecipeIngredient &&
        other.barcode == barcode &&
        other.productName == productName &&
        other.quantity == quantity &&
        other.unit == unit;
  }

  @override
  int get hashCode {
    return barcode.hashCode ^
        productName.hashCode ^
        quantity.hashCode ^
        unit.hashCode;
  }
}