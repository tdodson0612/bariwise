// lib/models/surgery_nutrition_profile.dart
// Bariatric surgery-specific nutrition guidelines

class SurgeryNutritionProfile {
  // 6 Bariatric Surgery Types
  static const String GASTRIC_BYPASS = 'Gastric Bypass (Roux-en-Y)';
  static const String SLEEVE = 'Sleeve Gastrectomy';
  static const String GASTRIC_BAND = 'Adjustable Gastric Band';
  static const String BPD_DS = 'Biliopancreatic Diversion (BPD/DS)';
  static const String MINI_BYPASS = 'Mini Gastric Bypass';
  static const String NOT_SPECIFIED = 'Not specified (general bariatric)';
  static const String OTHER = 'Not specified (general bariatric)'; // Alias for NOT_SPECIFIED

  static List<String> getAllSurgeryTypes() {
    return [
      GASTRIC_BYPASS,
      SLEEVE,
      GASTRIC_BAND,
      BPD_DS,
      MINI_BYPASS,
      NOT_SPECIFIED,
    ];
  }

  /// Get user-friendly description of surgery-specific nutrition focus
  static String getSurgeryGuidance(String surgeryType) {
    switch (surgeryType) {
      case GASTRIC_BYPASS:
        return 'Focus on: Protein 60-80g/day, avoid sugar >10g (dumping syndrome), limit fat >15g. Take B12, Iron, Calcium, Folate daily.';
      
      case SLEEVE:
        return 'Focus on: Protein 60-80g/day, avoid sugar >15g, no carbonated beverages. Take B12, Vitamin D, Calcium daily.';
      
      case GASTRIC_BAND:
        return 'Focus on: Protein 50-60g/day, avoid sugar >15g and tough/fibrous foods, limit fat >20g. Take multivitamins and Calcium daily.';
      
      case BPD_DS:
        return 'Focus on: HIGH protein 80-120g/day (most critical), avoid sugar >15g and fat >15g (malabsorption). Take Vitamins A/D/E/K, Calcium, Iron, B12 daily.';
      
      case MINI_BYPASS:
        return 'Focus on: Protein 60-80g/day, avoid sugar >15g, fat >15g, and alcohol. Take B12, Iron, Calcium, Vitamin D daily.';
      
      default:
        return 'Using general bariatric nutrition guidelines. Protein first, avoid sugar, take prescribed vitamins daily.';
    }
  }

  /// Get critical warnings for specific surgery type
  static String getSurgeryWarning(String surgeryType) {
    switch (surgeryType) {
      case GASTRIC_BYPASS:
        return '⚠️ CRITICAL: Avoid sugar >10g to prevent dumping syndrome. Protein is essential for healing.';
      
      case SLEEVE:
        return '⚠️ CRITICAL: Prioritize protein. Avoid carbonated drinks - they can stretch your sleeve.';
      
      case GASTRIC_BAND:
        return '⚠️ CRITICAL: Chew thoroughly. Avoid tough meats, bread, and fibrous vegetables that can cause blockage.';
      
      case BPD_DS:
        return '⚠️ CRITICAL: Highest protein needs (80-120g/day). Severe malabsorption - lifelong vitamins required.';
      
      case MINI_BYPASS:
        return '⚠️ CRITICAL: Avoid sugar >15g (dumping risk) and all alcohol (increased absorption).';
      
      default:
        return '⚠️ General bariatric guidelines: Protein first, avoid sugar, stay hydrated, take vitamins.';
    }
  }

  /// Get protein target range for surgery type
  static String getProteinTarget(String surgeryType) {
    switch (surgeryType) {
      case GASTRIC_BYPASS:
      case SLEEVE:
      case MINI_BYPASS:
        return '60-80g per day';
      
      case GASTRIC_BAND:
        return '50-60g per day';
      
      case BPD_DS:
        return '80-120g per day (highest needs)';
      
      default:
        return '60-80g per day';
    }
  }

  /// Get sugar limit for surgery type (grams)
  static int getSugarLimit(String surgeryType) {
    switch (surgeryType) {
      case GASTRIC_BYPASS:
        return 10; // Strictest due to dumping syndrome risk
      
      case SLEEVE:
      case GASTRIC_BAND:
      case BPD_DS:
      case MINI_BYPASS:
        return 15;
      
      default:
        return 15;
    }
  }

  /// Get fat limit for surgery type (grams)
  static int getFatLimit(String surgeryType) {
    switch (surgeryType) {
      case GASTRIC_BYPASS:
      case BPD_DS:
      case MINI_BYPASS:
        return 15; // Stricter for bypass procedures
      
      case SLEEVE:
        return 20; // Moderate
      
      case GASTRIC_BAND:
        return 20; // Most tolerant
      
      default:
        return 15;
    }
  }

  /// Get essential vitamin/supplement list for surgery type
  static List<String> getRequiredSupplements(String surgeryType) {
    switch (surgeryType) {
      case GASTRIC_BYPASS:
        return ['B12', 'Iron', 'Calcium', 'Folate', 'Vitamin D', 'Multivitamin'];
      
      case SLEEVE:
        return ['B12', 'Vitamin D', 'Calcium', 'Multivitamin'];
      
      case GASTRIC_BAND:
        return ['Multivitamin', 'Calcium', 'Vitamin D'];
      
      case BPD_DS:
        return ['Vitamins A/D/E/K (fat-soluble)', 'Calcium', 'Iron', 'B12', 'Zinc', 'Multivitamin'];
      
      case MINI_BYPASS:
        return ['B12', 'Iron', 'Calcium', 'Vitamin D', 'Multivitamin'];
      
      default:
        return ['Multivitamin', 'Calcium', 'Vitamin D', 'B12'];
    }
  }

  /// Get eating guidelines for surgery type
  static List<String> getEatingGuidelines(String surgeryType) {
    List<String> commonGuidelines = [
      'Eat protein first, always',
      'Take small bites and chew thoroughly',
      'Eat slowly (meals should take 20-30 minutes)',
      'Stop eating when full',
      'Wait 30 minutes before/after meals to drink',
      'Stay hydrated between meals',
      'Take vitamins as prescribed',
    ];

    // Add surgery-specific guidelines
    switch (surgeryType) {
      case GASTRIC_BYPASS:
        commonGuidelines.addAll([
          'Avoid sugar to prevent dumping syndrome',
          'Limit high-fat foods',
        ]);
        break;
      
      case SLEEVE:
        commonGuidelines.addAll([
          'Avoid carbonated beverages',
          'Focus on nutrient-dense foods',
        ]);
        break;
      
      case GASTRIC_BAND:
        commonGuidelines.addAll([
          'Avoid tough, dry, or fibrous foods',
          'Chew extra thoroughly to prevent blockage',
        ]);
        break;
      
      case BPD_DS:
        commonGuidelines.addAll([
          'Prioritize HIGH protein (80-120g/day)',
          'Take fat-soluble vitamins (A/D/E/K)',
          'Monitor for malabsorption symptoms',
        ]);
        break;
      
      case MINI_BYPASS:
        commonGuidelines.addAll([
          'Absolutely avoid alcohol',
          'Monitor for dumping syndrome',
        ]);
        break;
    }

    return commonGuidelines;
  }

  /// Get detailed nutritional recommendations for surgery type
  static Map<String, dynamic> getNutritionRecommendations(String surgeryType) {
    switch (surgeryType) {
      case GASTRIC_BYPASS:
        return {
          'proteinMin': 60,
          'proteinMax': 80,
          'sugarLimit': 10,
          'fatLimit': 15,
          'sodiumLimit': 2000,
          'calorieTarget': '1000-1200',
          'fluidGoal': '64 oz per day',
          'mealFrequency': '5-6 small meals',
          'portionSize': '1/2 to 1 cup',
          'criticalNutrients': ['Protein', 'B12', 'Iron', 'Calcium', 'Folate'],
          'avoidFoods': ['High sugar items', 'High fat foods', 'Alcohol'],
        };
      
      case SLEEVE:
        return {
          'proteinMin': 60,
          'proteinMax': 80,
          'sugarLimit': 15,
          'fatLimit': 20,
          'sodiumLimit': 2000,
          'calorieTarget': '1000-1200',
          'fluidGoal': '64 oz per day',
          'mealFrequency': '5-6 small meals',
          'portionSize': '1/2 to 1 cup',
          'criticalNutrients': ['Protein', 'B12', 'Vitamin D', 'Calcium'],
          'avoidFoods': ['Carbonated drinks', 'High sugar items', 'Tough meats'],
        };
      
      case GASTRIC_BAND:
        return {
          'proteinMin': 50,
          'proteinMax': 60,
          'sugarLimit': 15,
          'fatLimit': 20,
          'sodiumLimit': 2000,
          'calorieTarget': '1000-1200',
          'fluidGoal': '64 oz per day',
          'mealFrequency': '3-4 small meals',
          'portionSize': '1/2 to 1 cup',
          'criticalNutrients': ['Protein', 'Multivitamin', 'Calcium'],
          'avoidFoods': ['Tough meats', 'Bread', 'Pasta', 'Fibrous vegetables', 'Nuts'],
        };
      
      case BPD_DS:
        return {
          'proteinMin': 80,
          'proteinMax': 120,
          'sugarLimit': 15,
          'fatLimit': 15,
          'sodiumLimit': 2000,
          'calorieTarget': '1200-1500',
          'fluidGoal': '64-80 oz per day',
          'mealFrequency': '6+ small meals',
          'portionSize': '1/2 to 1 cup',
          'criticalNutrients': ['HIGH Protein', 'Vitamins A/D/E/K', 'Calcium', 'Iron', 'B12', 'Zinc'],
          'avoidFoods': ['High sugar items', 'Very high fat foods', 'Alcohol'],
        };
      
      case MINI_BYPASS:
        return {
          'proteinMin': 60,
          'proteinMax': 80,
          'sugarLimit': 15,
          'fatLimit': 15,
          'sodiumLimit': 2000,
          'calorieTarget': '1000-1200',
          'fluidGoal': '64 oz per day',
          'mealFrequency': '5-6 small meals',
          'portionSize': '1/2 to 1 cup',
          'criticalNutrients': ['Protein', 'B12', 'Iron', 'Calcium', 'Vitamin D'],
          'avoidFoods': ['Alcohol (STRICT)', 'High sugar items', 'High fat foods'],
        };
      
      default:
        return {
          'proteinMin': 60,
          'proteinMax': 80,
          'sugarLimit': 15,
          'fatLimit': 15,
          'sodiumLimit': 2000,
          'calorieTarget': '1000-1200',
          'fluidGoal': '64 oz per day',
          'mealFrequency': '5-6 small meals',
          'portionSize': '1/2 to 1 cup',
          'criticalNutrients': ['Protein', 'Multivitamin', 'Calcium', 'B12'],
          'avoidFoods': ['High sugar items', 'Very high fat foods', 'Carbonated drinks'],
        };
    }
  }

  /// Check if food is safe for surgery type based on nutrition
  static Map<String, dynamic> checkFoodSafety({
    required String surgeryType,
    required double sugar,
    required double fat,
    required double protein,
    required double fiber,
    double? saturatedFat,
    double? sodium,
  }) {
    List<String> warnings = [];
    List<String> positives = [];
    List<String> tips = [];
    bool isSafe = true;

    int sugarLimit = getSugarLimit(surgeryType);
    int fatLimit = getFatLimit(surgeryType);

    // Check sugar (critical for all surgeries)
    if (sugar > sugarLimit) {
      warnings.add('⚠️ High sugar (>${sugarLimit}g) - may cause dumping syndrome');
      isSafe = false;
    } else if (sugar <= 5) {
      positives.add('✅ Low sugar - excellent choice');
    } else if (sugar <= 10) {
      positives.add('✅ Moderate sugar - acceptable');
    }

    // Check fat
    if (fat > fatLimit) {
      warnings.add('⚠️ High fat (>${fatLimit}g) - may cause discomfort');
      isSafe = false;
    } else if (fat <= 10) {
      positives.add('✅ Low fat - good choice');
    }

    // Check saturated fat if available
    if (saturatedFat != null && saturatedFat > 5) {
      warnings.add('⚠️ High saturated fat (>5g)');
    }

    // Check sodium if available
    if (sodium != null) {
      if (sodium > 600) {
        warnings.add('⚠️ High sodium - stay well hydrated');
      } else if (sodium < 300) {
        positives.add('✅ Low sodium');
      }
    }

    // Check protein (varies by surgery)
    double proteinTarget = surgeryType == BPD_DS ? 25.0 : 20.0;
    if (protein >= proteinTarget) {
      positives.add('✅ Excellent protein content!');
    } else if (protein >= 15) {
      positives.add('✅ Good protein content');
    } else if (protein < 10) {
      warnings.add('ℹ️ Low protein - consider adding supplement');
      tips.add('Try adding: Greek yogurt, protein powder, cottage cheese, or lean meat');
    } else {
      tips.add('Moderate protein - could add more for optimal healing');
    }

    // Fiber bonus
    if (fiber >= 5) {
      positives.add('✅ Good fiber content');
    } else if (fiber >= 3) {
      positives.add('✅ Moderate fiber');
    }

    // Surgery-specific tips
    switch (surgeryType) {
      case GASTRIC_BYPASS:
        if (sugar > 10) {
          tips.add('Gastric bypass patients are especially prone to dumping syndrome with sugar >10g');
        }
        tips.add('Remember to take your B12, Iron, Calcium, and Folate supplements');
        break;
      
      case SLEEVE:
        tips.add('Avoid carbonated beverages - they can stretch your sleeve over time');
        tips.add('Remember to take your B12, Vitamin D, and Calcium supplements');
        break;
      
      case GASTRIC_BAND:
        tips.add('Make sure to chew this food thoroughly to avoid band blockage');
        tips.add('Take small bites and eat slowly');
        break;
      
      case BPD_DS:
        if (protein < 25) {
          tips.add('BPD/DS patients need higher protein (aim for 80-120g/day)');
        }
        tips.add('Don\'t forget your fat-soluble vitamins (A/D/E/K) - crucial for BPD/DS');
        break;
      
      case MINI_BYPASS:
        tips.add('Absolutely avoid alcohol - absorption is greatly increased after mini bypass');
        tips.add('Remember your B12, Iron, Calcium, and Vitamin D supplements');
        break;
    }

    return {
      'isSafe': isSafe,
      'warnings': warnings,
      'positives': positives,
      'tips': tips,
      'sugarStatus': sugar <= sugarLimit ? 'safe' : 'warning',
      'fatStatus': fat <= fatLimit ? 'safe' : 'warning',
      'proteinStatus': protein >= 15 ? 'good' : 'low',
    };
  }

  /// Get meal timing recommendations
  static List<String> getMealTimingGuidelines() {
    return [
      'Wait 30 minutes before meals to drink fluids',
      'Wait 30 minutes after meals to drink fluids',
      'Sip fluids slowly throughout the day',
      'Eat meals every 3-4 hours',
      'Don\'t skip meals - this can slow metabolism',
      'Stop eating immediately if you feel full',
      'Take 20-30 minutes to eat each meal',
    ];
  }

  /// Get hydration guidelines
  static Map<String, dynamic> getHydrationGuidelines(String surgeryType) {
    return {
      'dailyGoal': surgeryType == BPD_DS ? '64-80 oz' : '64 oz',
      'tips': [
        'Sip water throughout the day',
        'Avoid drinking 30 minutes before and after meals',
        'Choose water, herbal tea, or sugar-free beverages',
        'Avoid carbonated drinks (especially for sleeve)',
        'Use a water tracking app if helpful',
        'Carry a water bottle with you',
      ],
      'warning': 'Dehydration is common after bariatric surgery - stay vigilant!',
    };
  }

  /// Get vitamin supplementation schedule
  static Map<String, String> getSupplementSchedule(String surgeryType) {
    Map<String, String> schedule = {
      'Morning': 'Multivitamin with food',
      'Afternoon': 'Calcium citrate (500mg)',
      'Evening': 'Calcium citrate (500mg)',
    };

    switch (surgeryType) {
      case GASTRIC_BYPASS:
      case MINI_BYPASS:
        schedule['Morning with Multivitamin'] = 'B12 sublingual (1000mcg)';
        schedule['With meals'] = 'Iron (if prescribed) - separate from calcium';
        break;
      
      case SLEEVE:
        schedule['Morning'] = 'B12 sublingual (1000mcg), Multivitamin';
        schedule['Bedtime'] = 'Vitamin D (2000-3000 IU)';
        break;
      
      case BPD_DS:
        schedule = {
          'Morning': 'Fat-soluble vitamins (A/D/E/K), Multivitamin, B12',
          'Mid-morning': 'Calcium citrate (500mg)',
          'Lunch': 'Iron (with vitamin C for absorption)',
          'Afternoon': 'Calcium citrate (500mg)',
          'Dinner': 'Zinc supplement',
          'Evening': 'Calcium citrate (500mg)',
        };
        break;
    }

    return schedule;
  }
}