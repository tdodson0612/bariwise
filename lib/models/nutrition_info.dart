// lib/models/nutrition_info.dart - COMPLETE VERSION
import 'dart:convert';
import 'package:bari_wise/barihealthbar.dart';

class NutritionInfo {
  final String productName;
  final double calories;
  final double fat;
  final double saturatedFat;
  final double? monounsaturatedFat;
  final double? polyunsaturatedFat;
  final double? transFat;
  final double? cholesterol;
  final double sodium;
  final double carbs;
  final double? fiber;
  final double sugar;
  final double protein;
  final double? vitaminA;
  final double? vitaminC;
  final double? vitaminD;
  final double? calcium;
  final double? iron;
  final double? potassium;
  final double? cobalt;

  NutritionInfo({
    required this.productName,
    required this.calories,
    required this.fat,
    this.saturatedFat = 0,
    this.monounsaturatedFat,
    this.polyunsaturatedFat,
    this.transFat,
    this.cholesterol,
    required this.sodium,
    required this.carbs,
    this.fiber,
    required this.sugar,
    required this.protein,
    this.vitaminA,
    this.vitaminC,
    this.vitaminD,
    this.calcium,
    this.iron,
    this.potassium,
    this.cobalt,
  });

  /// Calculate net carbs (Total Carbs - Fiber)
  double get netCarbs {
    if (fiber == null || fiber == 0) return carbs;
    return (carbs - fiber!).clamp(0, carbs);
  }

  /// Parse from Open Food Facts API response
  factory NutritionInfo.fromJson(Map<String, dynamic> json) {
    final product = json['product'] ?? {};
    final nutriments = product['nutriments'] ?? {};

    // Helper to safely get nutrient values
    double getDoubleValue(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    double? getOptionalDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    return NutritionInfo(
      productName: product['product_name'] ?? 'Unknown Product',
      
      // Energy
      calories: getDoubleValue(
        nutriments['energy-kcal_100g'] ?? 
        nutriments['energy-kcal'] ?? 
        (nutriments['energy_100g'] != null ? nutriments['energy_100g'] / 4.184 : null)
      ),
      
      // Fats
      fat: getDoubleValue(nutriments['fat_100g'] ?? nutriments['fat']),
      saturatedFat: getDoubleValue(
        nutriments['saturated-fat_100g'] ?? 
        nutriments['saturated-fat']
      ),
      monounsaturatedFat: getOptionalDouble(
        nutriments['monounsaturated-fat_100g'] ?? 
        nutriments['monounsaturated-fat']
      ),
      polyunsaturatedFat: getOptionalDouble(
        nutriments['polyunsaturated-fat_100g'] ?? 
        nutriments['polyunsaturated-fat']
      ),
      transFat: getOptionalDouble(
        nutriments['trans-fat_100g'] ?? 
        nutriments['trans-fat']
      ),
      cholesterol: getOptionalDouble(
        nutriments['cholesterol_100g'] ?? 
        nutriments['cholesterol']
      ),
      
      // Sodium
      sodium: getDoubleValue(
        nutriments['sodium_100g'] ?? 
        nutriments['sodium'] ?? 
        (nutriments['salt_100g'] != null ? nutriments['salt_100g'] * 400 : null)
      ),
      
      // Carbohydrates
      carbs: getDoubleValue(
        nutriments['carbohydrates_100g'] ?? 
        nutriments['carbohydrates']
      ),
      fiber: getOptionalDouble(
        nutriments['fiber_100g'] ?? 
        nutriments['fiber']
      ),
      sugar: getDoubleValue(
        nutriments['sugars_100g'] ?? 
        nutriments['sugars']
      ),
      
      // Protein
      protein: getDoubleValue(
        nutriments['proteins_100g'] ?? 
        nutriments['proteins']
      ),
      
      // Vitamins
      vitaminA: getOptionalDouble(
        nutriments['vitamin-a_100g'] ?? 
        nutriments['vitamin-a']
      ),
      vitaminC: getOptionalDouble(
        nutriments['vitamin-c_100g'] ?? 
        nutriments['vitamin-c']
      ),
      vitaminD: getOptionalDouble(
        nutriments['vitamin-d_100g'] ?? 
        nutriments['vitamin-d']
      ),
      
      // Minerals
      calcium: getOptionalDouble(
        nutriments['calcium_100g'] ?? 
        nutriments['calcium']
      ),
      iron: getOptionalDouble(
        nutriments['iron_100g'] ?? 
        nutriments['iron']
      ),
      potassium: getOptionalDouble(
        nutriments['potassium_100g'] ?? 
        nutriments['potassium']
      ),
      cobalt: getOptionalDouble(
        nutriments['cobalt_100g'] ?? 
        nutriments['cobalt']
      ),
    );
  }

  /// Parse from database JSON (stored as string)
  factory NutritionInfo.fromDatabaseJson(Map<String, dynamic> json) {
    double? getOptionalDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    double getDoubleValue(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    return NutritionInfo(
      productName: json['productName'] ?? json['product_name'] ?? 'Unknown',
      calories: getDoubleValue(json['calories']),
      fat: getDoubleValue(json['fat']),
      saturatedFat: getDoubleValue(json['saturatedFat'] ?? json['saturated_fat']),
      monounsaturatedFat: getOptionalDouble(json['monounsaturatedFat'] ?? json['monounsaturated_fat']),
      polyunsaturatedFat: getOptionalDouble(json['polyunsaturatedFat'] ?? json['polyunsaturated_fat']),
      transFat: getOptionalDouble(json['transFat'] ?? json['trans_fat']),
      cholesterol: getOptionalDouble(json['cholesterol']),
      sodium: getDoubleValue(json['sodium']),
      carbs: getDoubleValue(json['carbs'] ?? json['carbohydrates']),
      fiber: getOptionalDouble(json['fiber']),
      sugar: getDoubleValue(json['sugar'] ?? json['sugars']),
      protein: getDoubleValue(json['protein']),
      vitaminA: getOptionalDouble(json['vitaminA'] ?? json['vitamin_a']),
      vitaminC: getOptionalDouble(json['vitaminC'] ?? json['vitamin_c']),
      vitaminD: getOptionalDouble(json['vitaminD'] ?? json['vitamin_d']),
      calcium: getOptionalDouble(json['calcium']),
      iron: getOptionalDouble(json['iron']),
      potassium: getOptionalDouble(json['potassium']),
      cobalt: getOptionalDouble(json['cobalt']),
    );
  }

  /// Create an empty NutritionInfo with all zeros
  factory NutritionInfo.empty({String productName = 'Combined'}) {
    return NutritionInfo(
      productName: productName,
      calories: 0.0,
      fat: 0.0,
      saturatedFat: 0.0,
      sodium: 0.0,
      carbs: 0.0,
      sugar: 0.0,
      protein: 0.0,
    );
  }

  /// Convert to JSON for database storage
  Map<String, dynamic> toJson() {
    return {
      'productName': productName,
      'calories': calories,
      'fat': fat,
      'saturatedFat': saturatedFat,
      'monounsaturatedFat': monounsaturatedFat,
      'polyunsaturatedFat': polyunsaturatedFat,
      'transFat': transFat,
      'cholesterol': cholesterol,
      'sodium': sodium,
      'carbs': carbs,
      'fiber': fiber,
      'sugar': sugar,
      'protein': protein,
      'vitaminA': vitaminA,
      'vitaminC': vitaminC,
      'vitaminD': vitaminD,
      'calcium': calcium,
      'iron': iron,
      'potassium': potassium,
      'cobalt': cobalt,
    };
  }

  /// Convert to JSON string for storage
  String toJsonString() => jsonEncode(toJson());

  /// Create a copy with updated values
  NutritionInfo copyWith({
    String? productName,
    double? calories,
    double? fat,
    double? saturatedFat,
    double? monounsaturatedFat,
    double? polyunsaturatedFat,
    double? transFat,
    double? cholesterol,
    double? sodium,
    double? carbs,
    double? fiber,
    double? sugar,
    double? protein,
    double? vitaminA,
    double? vitaminC,
    double? vitaminD,
    double? calcium,
    double? iron,
    double? potassium,
    double? cobalt,
  }) {
    return NutritionInfo(
      productName: productName ?? this.productName,
      calories: calories ?? this.calories,
      fat: fat ?? this.fat,
      saturatedFat: saturatedFat ?? this.saturatedFat,
      monounsaturatedFat: monounsaturatedFat ?? this.monounsaturatedFat,
      polyunsaturatedFat: polyunsaturatedFat ?? this.polyunsaturatedFat,
      transFat: transFat ?? this.transFat,
      cholesterol: cholesterol ?? this.cholesterol,
      sodium: sodium ?? this.sodium,
      carbs: carbs ?? this.carbs,
      fiber: fiber ?? this.fiber,
      sugar: sugar ?? this.sugar,
      protein: protein ?? this.protein,
      vitaminA: vitaminA ?? this.vitaminA,
      vitaminC: vitaminC ?? this.vitaminC,
      vitaminD: vitaminD ?? this.vitaminD,
      calcium: calcium ?? this.calcium,
      iron: iron ?? this.iron,
      potassium: potassium ?? this.potassium,
      cobalt: cobalt ?? this.cobalt,
    );
  }

  @override
  String toString() {
    return 'NutritionInfo(product: $productName, calories: ${calories}kcal, '
           'protein: ${protein}g, carbs: ${carbs}g, fat: ${fat}g)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    
    return other is NutritionInfo &&
        other.productName == productName &&
        other.calories == calories &&
        other.fat == fat &&
        other.saturatedFat == saturatedFat &&
        other.sodium == sodium &&
        other.carbs == carbs &&
        other.sugar == sugar &&
        other.protein == protein;
  }

  @override
  int get hashCode {
    return Object.hash(
      productName,
      calories,
      fat,
      saturatedFat,
      sodium,
      carbs,
      sugar,
      protein,
    );
  }

  /// Scale nutrition values by a multiplier (e.g., for different serving sizes)
  NutritionInfo scale(double multiplier) {
    return NutritionInfo(
      productName: productName,
      calories: calories * multiplier,
      fat: fat * multiplier,
      saturatedFat: saturatedFat * multiplier,
      monounsaturatedFat: monounsaturatedFat != null ? monounsaturatedFat! * multiplier : null,
      polyunsaturatedFat: polyunsaturatedFat != null ? polyunsaturatedFat! * multiplier : null,
      transFat: transFat != null ? transFat! * multiplier : null,
      cholesterol: cholesterol != null ? cholesterol! * multiplier : null,
      sodium: sodium * multiplier,
      carbs: carbs * multiplier,
      fiber: fiber != null ? fiber! * multiplier : null,
      sugar: sugar * multiplier,
      protein: protein * multiplier,
      vitaminA: vitaminA != null ? vitaminA! * multiplier : null,
      vitaminC: vitaminC != null ? vitaminC! * multiplier : null,
      vitaminD: vitaminD != null ? vitaminD! * multiplier : null,
      calcium: calcium != null ? calcium! * multiplier : null,
      iron: iron != null ? iron! * multiplier : null,
      potassium: potassium != null ? potassium! * multiplier : null,
      cobalt: cobalt != null ? cobalt! * multiplier : null,
    );
  }

  /// Add two NutritionInfo objects together (for combining ingredients)
  NutritionInfo operator +(NutritionInfo other) {
    return NutritionInfo(
      productName: productName, // Keep the first product name
      calories: calories + other.calories,
      fat: fat + other.fat,
      saturatedFat: saturatedFat + other.saturatedFat,
      monounsaturatedFat: _addOptional(monounsaturatedFat, other.monounsaturatedFat),
      polyunsaturatedFat: _addOptional(polyunsaturatedFat, other.polyunsaturatedFat),
      transFat: _addOptional(transFat, other.transFat),
      cholesterol: _addOptional(cholesterol, other.cholesterol),
      sodium: sodium + other.sodium,
      carbs: carbs + other.carbs,
      fiber: _addOptional(fiber, other.fiber),
      sugar: sugar + other.sugar,
      protein: protein + other.protein,
      vitaminA: _addOptional(vitaminA, other.vitaminA),
      vitaminC: _addOptional(vitaminC, other.vitaminC),
      vitaminD: _addOptional(vitaminD, other.vitaminD),
      calcium: _addOptional(calcium, other.calcium),
      iron: _addOptional(iron, other.iron),
      potassium: _addOptional(potassium, other.potassium),
      cobalt: _addOptional(cobalt, other.cobalt),
    );
  }

  /// Helper to add optional values (null-safe)
  static double? _addOptional(double? a, double? b) {
    if (a == null && b == null) return null;
    return (a ?? 0.0) + (b ?? 0.0);
  }

  /// Combine multiple nutrition infos (for recipes)
  static NutritionInfo combine(List<NutritionInfo> items, {String? combinedName}) {
    if (items.isEmpty) {
      return NutritionInfo(
        productName: combinedName ?? 'Combined',
        calories: 0,
        fat: 0,
        sodium: 0,
        carbs: 0,
        sugar: 0,
        protein: 0,
      );
    }

    double? sumOptional(List<double?> values) {
      final nonNullValues = values.whereType<double>().toList();
      if (nonNullValues.isEmpty) return null;
      return nonNullValues.fold<double>(0.0, (sum, v) => sum + v);
    }

    return NutritionInfo(
      productName: combinedName ?? 'Combined Nutrition',
      calories: items.fold(0.0, (sum, i) => sum + i.calories),
      fat: items.fold(0.0, (sum, i) => sum + i.fat),
      saturatedFat: items.fold(0.0, (sum, i) => sum + i.saturatedFat),
      monounsaturatedFat: sumOptional(items.map((i) => i.monounsaturatedFat).toList()),
      polyunsaturatedFat: sumOptional(items.map((i) => i.polyunsaturatedFat).toList()),
      transFat: sumOptional(items.map((i) => i.transFat).toList()),
      cholesterol: sumOptional(items.map((i) => i.cholesterol).toList()),
      sodium: items.fold(0.0, (sum, i) => sum + i.sodium),
      carbs: items.fold(0.0, (sum, i) => sum + i.carbs),
      fiber: sumOptional(items.map((i) => i.fiber).toList()),
      sugar: items.fold(0.0, (sum, i) => sum + i.sugar),
      protein: items.fold(0.0, (sum, i) => sum + i.protein),
      vitaminA: sumOptional(items.map((i) => i.vitaminA).toList()),
      vitaminC: sumOptional(items.map((i) => i.vitaminC).toList()),
      vitaminD: sumOptional(items.map((i) => i.vitaminD).toList()),
      calcium: sumOptional(items.map((i) => i.calcium).toList()),
      iron: sumOptional(items.map((i) => i.iron).toList()),
      potassium: sumOptional(items.map((i) => i.potassium).toList()),
      cobalt: sumOptional(items.map((i) => i.cobalt).toList()),
    );
  }

  /// Get macro percentages (% of calories from protein, carbs, fat)
  Map<String, double> get macroPercentages {
    final proteinCals = protein * 4;
    final carbCals = carbs * 4;
    final fatCals = fat * 9;
    final total = proteinCals + carbCals + fatCals;

    if (total == 0) {
      return {'protein': 0, 'carbs': 0, 'fat': 0};
    }

    return {
      'protein': (proteinCals / total * 100),
      'carbs': (carbCals / total * 100),
      'fat': (fatCals / total * 100),
    };
  }

  /// Check if this food is high in protein (>20% calories from protein)
  bool get isHighProtein {
    final macros = macroPercentages;
    return macros['protein']! >= 20;
  }

  /// Check if this food is low carb (<20% calories from carbs)
  bool get isLowCarb {
    final macros = macroPercentages;
    return macros['carbs']! < 20;
  }

  /// Check if this food is low fat (<30% calories from fat)
  bool get isLowFat {
    final macros = macroPercentages;
    return macros['fat']! < 30;
  }

  /// Check if this food is high in fiber (>5g per serving)
  bool get isHighFiber {
    return fiber != null && fiber! >= 5;
  }

  /// Check if this food is low sodium (<140mg per serving)
  bool get isLowSodium {
    return sodium < 140;
  }

  /// Get a summary description of this food
  String get nutritionSummary {
    final List<String> descriptors = [];
    
    if (isHighProtein) descriptors.add('High Protein');
    if (isLowCarb) descriptors.add('Low Carb');
    if (isLowFat) descriptors.add('Low Fat');
    if (isHighFiber) descriptors.add('High Fiber');
    if (isLowSodium) descriptors.add('Low Sodium');
    
    if (descriptors.isEmpty) {
      return 'Balanced nutrition';
    }
    
    return descriptors.join(', ');
  }

  /// Get serving size display text
  String get servingSizeDisplay {
    // Default to 100g since Open Food Facts data is per 100g
    return '100g';
  }

  /// Calculate bari health score for this nutrition info
  int calculatebariScore({String? surgeryType}) {
    return BariHealthCalculator.calculate(
      fat: fat,
      sodium: sodium,
      sugar: sugar,
      calories: calories,
      surgeryType: surgeryType,
      protein: protein,
      fiber: fiber,
      saturatedFat: saturatedFat,
    );
  }

  /// Check if nutrition info is empty (no meaningful data)
  bool get isEmpty {
    return calories == 0.0 &&
        fat == 0.0 &&
        sodium == 0.0 &&
        carbs == 0.0 &&
        sugar == 0.0 &&
        protein == 0.0;
  }

  /// Format nutrition for display (per 100g)
  String toDisplayString() {
    return '''
Product: $productName

Nutritional Facts Per Serving
Calories: ${calories.toStringAsFixed(0)} kcal
Protein: ${protein.toStringAsFixed(1)} g
Total Fat: ${fat.toStringAsFixed(1)} g
  - Monounsaturated Fat: ${monounsaturatedFat?.toStringAsFixed(1) ?? 'N/A'} g
  - Polyunsaturated Fat: ${polyunsaturatedFat?.toStringAsFixed(1) ?? 'N/A'} g
  - Saturated Fat: ${saturatedFat.toStringAsFixed(1)} g
  - Trans Fat: ${transFat?.toStringAsFixed(1) ?? 'N/A'} g
Carbohydrates: ${carbs.toStringAsFixed(1)} g
  - Fiber: ${fiber?.toStringAsFixed(1) ?? 'N/A'} g
  - Net Carbohydrates: ${netCarbs.toStringAsFixed(1)} g
  - Sugar: ${sugar.toStringAsFixed(1)} g
Iron: ${iron?.toStringAsFixed(1) ?? 'N/A'} mg
Sodium: ${sodium.toStringAsFixed(0)} mg
Potassium: ${potassium?.toStringAsFixed(0) ?? 'N/A'} mg
Cholesterol: ${cholesterol?.toStringAsFixed(0) ?? 'N/A'} mg
Cobalt: ${cobalt?.toStringAsFixed(1) ?? 'N/A'} mcg
''';
  }
}