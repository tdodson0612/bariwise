// lib/models/ingredient_search_result.dart
// Search result model for multi-database ingredient search
// iOS 14 Compatible | Production Ready

import 'nutrition_info.dart';

class IngredientSearchResult {
  final String id;
  final String name;
  final String? brand;
  final String? barcode;
  final String source; // 'Open Food Facts', 'USDA', 'custom', etc.
  final NutritionInfo? nutrition;
  final String? servingSize;
  final double relevanceScore; // 0.0 to 1.0 for ranking

  const IngredientSearchResult({
    required this.id,
    required this.name,
    this.brand,
    this.barcode,
    required this.source,
    this.nutrition,
    this.servingSize,
    this.relevanceScore = 0.5,
  });

  // ========================================
  // FACTORY CONSTRUCTORS
  // ========================================

  factory IngredientSearchResult.fromJson(Map<String, dynamic> json) {
    return IngredientSearchResult(
      id: json['id'] as String,
      name: json['name'] as String,
      brand: json['brand'] as String?,
      barcode: json['barcode'] as String?,
      source: json['source'] as String? ?? 'unknown',
      nutrition: json['nutrition'] != null
          ? NutritionInfo.fromJson(json['nutrition'])
          : null,
      servingSize: json['servingSize'] as String?,
      relevanceScore: (json['relevanceScore'] as num?)?.toDouble() ?? 0.5,
    );
  }

  factory IngredientSearchResult.fromCustomIngredient(
    Map<String, dynamic> customIngredient,
  ) {
    return IngredientSearchResult(
      id: customIngredient['id'] as String,
      name: customIngredient['name'] as String,
      brand: customIngredient['brand'] as String?,
      barcode: customIngredient['barcode'] as String?,
      source: 'custom',
      nutrition: customIngredient['nutrition'] != null
          ? NutritionInfo.fromJson(customIngredient['nutrition'])
          : null,
      servingSize: customIngredient['serving_size'] as String?,
      relevanceScore: 1.0, // Custom ingredients are always highly relevant
    );
  }

  // ========================================
  // JSON SERIALIZATION
  // ========================================

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (brand != null) 'brand': brand,
      if (barcode != null) 'barcode': barcode,
      'source': source,
      if (nutrition != null) 'nutrition': nutrition!.toJson(),
      if (servingSize != null) 'servingSize': servingSize,
      'relevanceScore': relevanceScore,
    };
  }

  // ========================================
  // DISPLAY HELPERS
  // ========================================

  /// Get full display name with brand
  String get displayName {
    if (brand != null && brand!.isNotEmpty) {
      return '$brand - $name';
    }
    return name;
  }

  /// Get display name limited to max characters
  String getDisplayName({int maxLength = 50}) {
    final full = displayName;
    if (full.length <= maxLength) return full;
    return '${full.substring(0, maxLength - 3)}...';
  }

  /// Get source badge text
  String get sourceBadge {
    switch (source.toLowerCase()) {
      case 'open food facts':
        return 'OFF';
      case 'usda fooddata central':
      case 'usda':
        return 'USDA';
      case 'custom':
        return 'Custom';
      default:
        return source.substring(0, 4).toUpperCase();
    }
  }

  /// Check if nutrition data is available
  bool get hasNutrition => nutrition != null && !nutrition!.isEmpty;

  /// Check if this is a custom ingredient
  bool get isCustom => source.toLowerCase() == 'custom';

  /// Get serving size display
  String? get servingSizeDisplay {
    if (servingSize != null) return servingSize;
    if (nutrition != null) return nutrition!.servingSizeDisplay;
    return null;
  }

  // ========================================
  // COMPARISON
  // ========================================

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is IngredientSearchResult &&
        other.id == id &&
        other.source == source;
  }

  @override
  int get hashCode => Object.hash(id, source);

  @override
  String toString() {
    return 'IngredientSearchResult('
        'name: $name, '
        'brand: $brand, '
        'source: $source, '
        'relevance: ${relevanceScore.toStringAsFixed(2)}'
        ')';
  }

  /// Copy with modifications
  IngredientSearchResult copyWith({
    String? id,
    String? name,
    String? brand,
    String? barcode,
    String? source,
    NutritionInfo? nutrition,
    String? servingSize,
    double? relevanceScore,
  }) {
    return IngredientSearchResult(
      id: id ?? this.id,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      barcode: barcode ?? this.barcode,
      source: source ?? this.source,
      nutrition: nutrition ?? this.nutrition,
      servingSize: servingSize ?? this.servingSize,
      relevanceScore: relevanceScore ?? this.relevanceScore,
    );
  }
}