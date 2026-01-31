// lib/services/recipe_nutrition_service.dart
// Calculates comprehensive nutrition for recipes - BARIATRIC VERSION
// iOS 14 Compatible | Production Ready

import 'package:bari_wise/models/nutrition_info.dart';
import 'package:bari_wise/barihealthbar.dart';

class RecipeNutrition {
  final double calories;
  final double fat;
  final double saturatedFat;
  final double monounsaturatedFat;
  final double transFat;
  final double sugar;
  final double sodium;
  final double potassium;
  final double protein;
  final double carbohydrates;
  final double fiber;
  final double iron;
  final double cholesterol;
  final double cobalt;
  final int bariScore;

  RecipeNutrition({
    required this.calories,
    required this.fat,
    this.saturatedFat = 0.0,
    this.monounsaturatedFat = 0.0,
    this.transFat = 0.0,
    required this.sugar,
    required this.sodium,
    this.potassium = 0.0,
    required this.protein,
    required this.carbohydrates,
    this.fiber = 0.0,
    this.iron = 0.0,
    this.cholesterol = 0.0,
    this.cobalt = 0.0,
    required this.bariScore,
  });

  /// Calculate macronutrient percentages
  Map<String, double> get macroPercentages {
    // Calories from macros (per gram):
    // - Protein: 4 cal/g
    // - Carbs: 4 cal/g
    // - Fat: 9 cal/g

    final proteinCals = protein * 4;
    final carbsCals = carbohydrates * 4;
    final fatCals = fat * 9;

    final totalMacroCals = proteinCals + carbsCals + fatCals;

    if (totalMacroCals == 0) {
      return {
        'protein': 0.0,
        'carbs': 0.0,
        'fat': 0.0,
      };
    }

    return {
      'protein': (proteinCals / totalMacroCals) * 100,
      'carbs': (carbsCals / totalMacroCals) * 100,
      'fat': (fatCals / totalMacroCals) * 100,
    };
  }

  /// Net carbohydrates (Total Carbs - Fiber)
  double get netCarbs {
    return (carbohydrates - fiber).clamp(0, double.infinity);
  }

  /// Convert to NutritionInfo for display widgets
  NutritionInfo toNutritionInfo({String productName = 'Recipe Total'}) {
    return NutritionInfo(
      productName: productName,
      calories: calories,
      fat: fat,
      saturatedFat: saturatedFat,
      monounsaturatedFat: monounsaturatedFat,
      transFat: transFat,
      sodium: sodium,
      potassium: potassium,
      sugar: sugar,
      protein: protein,
      carbs: carbohydrates,
      fiber: fiber,
      iron: iron,
      cholesterol: cholesterol,
      cobalt: cobalt,
    );
  }
}

class RecipeNutritionService {
  /// Combine multiple ingredients into one nutrition summary
  static RecipeNutrition calculateTotals(List<NutritionInfo> items) {
    double totalCalories = 0;
    double totalFat = 0;
    double totalSaturatedFat = 0;
    double totalMonounsaturatedFat = 0;
    double totalTransFat = 0;
    double totalSugar = 0;
    double totalSodium = 0;
    double totalPotassium = 0;
    double totalProtein = 0;
    double totalCarbohydrates = 0;
    double totalFiber = 0;
    double totalIron = 0;
    double totalCholesterol = 0;
    double totalCobalt = 0;

    for (final item in items) {
      totalCalories += item.calories;
      totalFat += item.fat;
      totalSaturatedFat += item.saturatedFat ?? 0.0;
      totalMonounsaturatedFat += item.monounsaturatedFat ?? 0.0;
      totalTransFat += item.transFat ?? 0.0;
      totalSugar += item.sugar;
      totalSodium += item.sodium;
      totalPotassium += item.potassium ?? 0.0;
      totalProtein += item.protein;
      totalCarbohydrates += item.carbs;
      totalFiber += item.fiber ?? 0.0;
      totalIron += item.iron ?? 0.0;
      totalCholesterol += item.cholesterol ?? 0.0;
      totalCobalt += item.cobalt ?? 0.0;
    }

    // Compute recipe bari score
    final int bariScore = BariHealthCalculator.calculate(
      fat: totalFat,
      sodium: totalSodium,
      sugar: totalSugar,
      calories: totalCalories,
      protein: totalProtein,
      fiber: totalFiber,
      saturatedFat: totalSaturatedFat,
    );

    return RecipeNutrition(
      calories: totalCalories,
      fat: totalFat,
      saturatedFat: totalSaturatedFat,
      monounsaturatedFat: totalMonounsaturatedFat,
      transFat: totalTransFat,
      sugar: totalSugar,
      sodium: totalSodium,
      potassium: totalPotassium,
      protein: totalProtein,
      carbohydrates: totalCarbohydrates,
      fiber: totalFiber,
      iron: totalIron,
      cholesterol: totalCholesterol,
      cobalt: totalCobalt,
      bariScore: bariScore,
    );
  }

  /// Calculate nutrition for a single serving
  static RecipeNutrition calculatePerServing(
    List<NutritionInfo> items,
    int servings,
  ) {
    if (servings <= 0) {
      throw ArgumentError('Servings must be greater than 0');
    }

    final totals = calculateTotals(items);

    return RecipeNutrition(
      calories: totals.calories / servings,
      fat: totals.fat / servings,
      saturatedFat: totals.saturatedFat / servings,
      monounsaturatedFat: totals.monounsaturatedFat / servings,
      transFat: totals.transFat / servings,
      sugar: totals.sugar / servings,
      sodium: totals.sodium / servings,
      potassium: totals.potassium / servings,
      protein: totals.protein / servings,
      carbohydrates: totals.carbohydrates / servings,
      fiber: totals.fiber / servings,
      iron: totals.iron / servings,
      cholesterol: totals.cholesterol / servings,
      cobalt: totals.cobalt / servings,
      bariScore: totals.bariScore, // bari score doesn't change per serving
    );
  }

  /// Get a summary string of macronutrients
  static String getMacroSummary(RecipeNutrition nutrition) {
    final macros = nutrition.macroPercentages;
    
    return 'Protein: ${macros['protein']!.toStringAsFixed(1)}% | '
           'Carbs: ${macros['carbs']!.toStringAsFixed(1)}% | '
           'Fat: ${macros['fat']!.toStringAsFixed(1)}%';
  }

  /// Check if recipe is high protein (>30% of calories from protein) - GOOD FOR BARIATRIC
  static bool isHighProtein(RecipeNutrition nutrition) {
    final macros = nutrition.macroPercentages;
    return macros['protein']! >= 30.0;
  }

  /// Check if recipe is low carb (<30% of calories from carbs)
  static bool isLowCarb(RecipeNutrition nutrition) {
    final macros = nutrition.macroPercentages;
    return macros['carbs']! < 30.0;
  }

  /// Check if recipe is low fat (<30% of calories from fat) - IMPORTANT FOR BARIATRIC
  static bool isLowFat(RecipeNutrition nutrition) {
    final macros = nutrition.macroPercentages;
    return macros['fat']! < 30.0;
  }

  /// Check if recipe is low sugar (<10g) - CRITICAL FOR BARIATRIC (dumping syndrome)
  static bool isLowSugar(RecipeNutrition nutrition) {
    return nutrition.sugar < 10.0;
  }

  /// Get dietary label for recipe based on macros
  static String getDietaryLabel(RecipeNutrition nutrition) {
    final labels = <String>[];

    if (isHighProtein(nutrition)) {
      labels.add('High Protein');
    }
    if (isLowCarb(nutrition)) {
      labels.add('Low Carb');
    }
    if (isLowFat(nutrition)) {
      labels.add('Low Fat');
    }
    if (isLowSugar(nutrition)) {
      labels.add('Low Sugar');
    }
    if (isBariatricFriendly(nutrition)) {
      labels.add('Bariatric Friendly');
    }

    return labels.isEmpty ? 'Balanced' : labels.join(', ');
  }

  /// Check if recipe is bariatric-friendly
  static bool isBariatricFriendly(RecipeNutrition nutrition) {
    return isHighProtein(nutrition) &&
           isLowSugar(nutrition) &&
           nutrition.fat < 20.0 &&
           nutrition.sodium < 400.0;
  }

  /// Get nutrient density score (nutrients per calorie)
  static double getNutrientDensity(RecipeNutrition nutrition) {
    if (nutrition.calories == 0) return 0;
    
    // Higher score = more nutrients per calorie
    final nutrientScore = 
      nutrition.protein + 
      nutrition.fiber + 
      (nutrition.potassium / 100) + 
      (nutrition.iron * 10);
    
    return (nutrientScore / nutrition.calories) * 100;
  }

  /// Get bariatric-specific warnings
  static List<String> getBariatricWarnings(RecipeNutrition nutrition) {
    final warnings = <String>[];

    if (nutrition.sugar > 10.0) {
      warnings.add('⚠️ High sugar - may cause dumping syndrome');
    }
    if (nutrition.fat > 15.0) {
      warnings.add('⚠️ High fat - may cause discomfort');
    }
    if (nutrition.saturatedFat > 5.0) {
      warnings.add('⚠️ High saturated fat');
    }
    if (nutrition.sodium > 400.0) {
      warnings.add('⚠️ High sodium - stay hydrated');
    }
    if (nutrition.protein < 15.0) {
      warnings.add('ℹ️ Low protein - consider adding protein supplement');
    }

    return warnings;
  }

  /// Get health benefits (bariatric-focused)
  static List<String> getHealthBenefits(RecipeNutrition nutrition) {
    final benefits = <String>[];

    if (nutrition.protein >= 20.0) {
      benefits.add('Excellent protein source');
    } else if (nutrition.protein >= 15.0) {
      benefits.add('Good protein source');
    }
    
    if (nutrition.fiber >= 5.0) {
      benefits.add('High fiber');
    }
    
    if (nutrition.iron >= 3.0) {
      benefits.add('Good iron source');
    }
    
    if (isLowSugar(nutrition)) {
      benefits.add('Low sugar');
    }
    
    if (isBariatricFriendly(nutrition)) {
      benefits.add('Bariatric-friendly');
    }

    return benefits;
  }

  /// Get surgery-specific guidance
  static String getSurgeryGuidance(RecipeNutrition nutrition, String surgeryType) {
    switch (surgeryType.toLowerCase()) {
      case 'gastric bypass (roux-en-y)':
        if (nutrition.sugar > 10) {
          return '⚠️ High sugar content may cause dumping syndrome with gastric bypass';
        }
        if (nutrition.protein >= 20) {
          return '✅ Good protein content for gastric bypass recovery';
        }
        return 'Monitor portion sizes and eat slowly';

      case 'sleeve gastrectomy':
        if (nutrition.protein < 15) {
          return '⚠️ Consider adding more protein to support healing';
        }
        return 'Eat slowly and avoid carbonated beverages';

      case 'adjustable gastric band':
        if (nutrition.fiber > 10) {
          return 'ℹ️ High fiber - chew thoroughly to prevent band obstruction';
        }
        return 'Focus on small, frequent meals';

      case 'biliopancreatic diversion (bpd/ds)':
        if (nutrition.fat > 15) {
          return '⚠️ High fat may not be well absorbed with BPD/DS';
        }
        if (nutrition.protein >= 30) {
          return '✅ Excellent protein - critical for BPD/DS patients';
        }
        return 'Prioritize protein and take all prescribed vitamins';

      case 'mini gastric bypass':
        if (nutrition.sugar > 10) {
          return '⚠️ Avoid high sugar to prevent dumping syndrome';
        }
        if (nutrition.fat > 15) {
          return '⚠️ High fat content may cause discomfort';
        }
        return 'Focus on lean protein and vegetables';

      default:
        return 'Consult your bariatric team for personalized nutrition guidance';
    }
  }
}