// lib/barihealthbar.dart
import 'package:flutter/material.dart';

String getFaceEmoji(int score) {
  if (score <= 25) return '😠';
  if (score <= 49) return '☹️';
  if (score <= 74) return '😐';
  return '😄';
}

/// Main calculator class for bariatric surgery-specific scoring
class BariHealthCalculator {
  /// Main calculate method - surgery type-specific scoring
  static int calculate({
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
    String? surgeryType,
    double? protein,
    double? fiber,
    double? saturatedFat,
    double? calcium,
    double? vitaminB12,
    double? iron,
    double? folate,
    double? vitaminD,
    double? vitaminA,
    double? vitaminE,
    double? vitaminK,
  }) {
    // Default to general bariatric scoring if no surgery type specified
    if (surgeryType == null || 
        surgeryType.isEmpty || 
        surgeryType == 'Not specified' ||
        surgeryType == 'Other (default scoring)') {
      return _calculateGeneralBariatricScore(
        fat: fat,
        sodium: sodium,
        sugar: sugar,
        calories: calories,
        protein: protein,
        fiber: fiber,
        saturatedFat: saturatedFat,
      );
    }

    // Surgery-specific scoring
    switch (surgeryType.toLowerCase()) {
      case 'gastric bypass (roux-en-y)':
      case 'gastric bypass':
      case 'roux-en-y':
        return _calculateGastricBypassScore(
          fat: fat,
          sodium: sodium,
          sugar: sugar,
          calories: calories,
          protein: protein,
          calcium: calcium,
          vitaminB12: vitaminB12,
          iron: iron,
          folate: folate,
        );

      case 'sleeve gastrectomy':
      case 'gastric sleeve':
      case 'sleeve':
        return _calculateSleeveGastrectomyScore(
          fat: fat,
          sodium: sodium,
          sugar: sugar,
          calories: calories,
          protein: protein,
          vitaminB12: vitaminB12,
          vitaminD: vitaminD,
          calcium: calcium,
        );

      case 'adjustable gastric band':
      case 'gastric band':
      case 'lap band':
        return _calculateGastricBandScore(
          fat: fat,
          sodium: sodium,
          sugar: sugar,
          calories: calories,
          protein: protein,
          calcium: calcium,
        );

      case 'biliopancreatic diversion (bpd/ds)':
      case 'biliopancreatic diversion':
      case 'bpd/ds':
      case 'bpd':
      case 'ds':
        return _calculateBPDDSScore(
          fat: fat,
          sodium: sodium,
          sugar: sugar,
          calories: calories,
          protein: protein,
          vitaminA: vitaminA,
          vitaminD: vitaminD,
          vitaminE: vitaminE,
          vitaminK: vitaminK,
          calcium: calcium,
          iron: iron,
          vitaminB12: vitaminB12,
        );

      case 'mini gastric bypass':
      case 'mini bypass':
        return _calculateMiniGastricBypassScore(
          fat: fat,
          sodium: sodium,
          sugar: sugar,
          calories: calories,
          protein: protein,
          vitaminB12: vitaminB12,
          iron: iron,
          calcium: calcium,
          vitaminD: vitaminD,
        );

      default:
        return _calculateGeneralBariatricScore(
          fat: fat,
          sodium: sodium,
          sugar: sugar,
          calories: calories,
          protein: protein,
          fiber: fiber,
          saturatedFat: saturatedFat,
        );
    }
  }

  // ============================================
  // GASTRIC BYPASS (ROUX-EN-Y)
  // Avoid: Sugar, Fat
  // Need: Protein, Calcium, Vitamin B12, Iron, Folate
  // ============================================
  static int _calculateGastricBypassScore({
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
    double? protein,
    double? calcium,
    double? vitaminB12,
    double? iron,
    double? folate,
  }) {
    int score = 50; // Start at neutral

    // CRITICAL: Sugar (dumping syndrome risk)
    if (sugar <= 5) {
      score += 25; // Excellent - very low sugar
    } else if (sugar <= 10) {
      score += 10; // Good - low sugar
    } else if (sugar <= 15) {
      score -= 15; // Caution - moderate sugar
    } else {
      score -= 35; // DANGER - high sugar, severe dumping risk
    }

    // CRITICAL: Fat
    if (fat <= 10) {
      score += 15; // Excellent - low fat
    } else if (fat <= 15) {
      score += 5; // Good - moderate fat
    } else if (fat > 20) {
      score -= 20; // Too high - absorption issues
    }

    // NEEDED: Protein (critical for healing)
    if (protein != null) {
      if (protein >= 25) {
        score += 20; // Excellent protein
      } else if (protein >= 20) {
        score += 15; // Very good
      } else if (protein >= 15) {
        score += 8; // Good
      } else if (protein < 10) {
        score -= 15; // Too low
      }
    }

    // NEEDED: Calcium
    if (calcium != null && calcium >= 200) {
      score += 8; // Good calcium source
    }

    // NEEDED: Vitamin B12
    if (vitaminB12 != null && vitaminB12 >= 2.4) {
      score += 5; // Meets B12 needs
    }

    // NEEDED: Iron
    if (iron != null && iron >= 3) {
      score += 5; // Good iron source
    }

    // NEEDED: Folate
    if (folate != null && folate >= 200) {
      score += 5; // Good folate source
    }

    return score.clamp(0, 100);
  }

  // ============================================
  // SLEEVE GASTRECTOMY
  // Avoid: Sugar, Carbonation
  // Need: Protein, Vitamin B12, Vitamin D, Calcium
  // ============================================
  static int _calculateSleeveGastrectomyScore({
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
    double? protein,
    double? vitaminB12,
    double? vitaminD,
    double? calcium,
  }) {
    int score = 50;

    // AVOID: Sugar
    if (sugar <= 5) {
      score += 20;
    } else if (sugar <= 10) {
      score += 10;
    } else if (sugar > 15) {
      score -= 25;
    }

    // NEEDED: Protein (very important)
    if (protein != null) {
      if (protein >= 25) {
        score += 25;
      } else if (protein >= 20) {
        score += 18;
      } else if (protein >= 15) {
        score += 10;
      } else if (protein < 10) {
        score -= 15;
      }
    }

    // NEEDED: Vitamin B12
    if (vitaminB12 != null && vitaminB12 >= 2.4) {
      score += 8;
    }

    // NEEDED: Vitamin D
    if (vitaminD != null && vitaminD >= 10) {
      score += 8;
    }

    // NEEDED: Calcium
    if (calcium != null && calcium >= 200) {
      score += 8;
    }

    // Fat is less critical than bypass, but still moderate
    if (fat > 20) {
      score -= 10;
    }

    return score.clamp(0, 100);
  }

  // ============================================
  // ADJUSTABLE GASTRIC BAND
  // Avoid: Sugar, Fat
  // Need: Protein, Multivitamins, Calcium
  // ============================================
  static int _calculateGastricBandScore({
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
    double? protein,
    double? calcium,
  }) {
    int score = 50;

    // AVOID: Sugar
    if (sugar <= 5) {
      score += 20;
    } else if (sugar <= 10) {
      score += 10;
    } else if (sugar > 15) {
      score -= 20;
    }

    // AVOID: Fat
    if (fat <= 10) {
      score += 15;
    } else if (fat <= 15) {
      score += 5;
    } else if (fat > 20) {
      score -= 20;
    }

    // NEEDED: Protein
    if (protein != null) {
      if (protein >= 20) {
        score += 20;
      } else if (protein >= 15) {
        score += 12;
      } else if (protein < 10) {
        score -= 15;
      }
    }

    // NEEDED: Calcium
    if (calcium != null && calcium >= 200) {
      score += 10;
    }

    return score.clamp(0, 100);
  }

  // ============================================
  // BILIOPANCREATIC DIVERSION (BPD/DS)
  // Avoid: Sugar, Fat (fat malabsorption)
  // Need: Protein (critical!), Vitamins A, D, E, K, Calcium, Iron, B12
  // ============================================
  static int _calculateBPDDSScore({
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
    double? protein,
    double? vitaminA,
    double? vitaminD,
    double? vitaminE,
    double? vitaminK,
    double? calcium,
    double? iron,
    double? vitaminB12,
  }) {
    int score = 50;

    // CRITICAL: Protein (most important for BPD/DS)
    if (protein != null) {
      if (protein >= 30) {
        score += 30; // Excellent - critical need
      } else if (protein >= 25) {
        score += 20;
      } else if (protein >= 20) {
        score += 10;
      } else if (protein < 15) {
        score -= 25; // Dangerously low
      }
    } else {
      score -= 20; // No protein data - concerning
    }

    // AVOID: Sugar
    if (sugar <= 5) {
      score += 15;
    } else if (sugar > 15) {
      score -= 25;
    }

    // AVOID: Fat (severe malabsorption with BPD/DS)
    if (fat <= 10) {
      score += 10;
    } else if (fat > 20) {
      score -= 25; // High fat poorly absorbed
    }

    // NEEDED: Fat-soluble vitamins (A, D, E, K)
    if (vitaminA != null && vitaminA >= 700) score += 5;
    if (vitaminD != null && vitaminD >= 10) score += 5;
    if (vitaminE != null && vitaminE >= 10) score += 5;
    if (vitaminK != null && vitaminK >= 80) score += 5;

    // NEEDED: Calcium
    if (calcium != null && calcium >= 300) {
      score += 8; // Higher calcium need
    }

    // NEEDED: Iron
    if (iron != null && iron >= 5) {
      score += 5;
    }

    // NEEDED: Vitamin B12
    if (vitaminB12 != null && vitaminB12 >= 2.4) {
      score += 5;
    }

    return score.clamp(0, 100);
  }

  // ============================================
  // MINI GASTRIC BYPASS
  // Avoid: Sugar, Fat, Alcohol
  // Need: Protein, Vitamin B12, Iron, Calcium, Vitamin D
  // ============================================
  static int _calculateMiniGastricBypassScore({
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
    double? protein,
    double? vitaminB12,
    double? iron,
    double? calcium,
    double? vitaminD,
  }) {
    int score = 50;

    // AVOID: Sugar (dumping syndrome)
    if (sugar <= 5) {
      score += 25;
    } else if (sugar <= 10) {
      score += 10;
    } else if (sugar > 15) {
      score -= 30;
    }

    // AVOID: Fat
    if (fat <= 10) {
      score += 15;
    } else if (fat > 20) {
      score -= 20;
    }

    // NEEDED: Protein
    if (protein != null) {
      if (protein >= 25) {
        score += 25;
      } else if (protein >= 20) {
        score += 15;
      } else if (protein < 10) {
        score -= 15;
      }
    }

    // NEEDED: Vitamin B12
    if (vitaminB12 != null && vitaminB12 >= 2.4) {
      score += 8;
    }

    // NEEDED: Iron
    if (iron != null && iron >= 3) {
      score += 8;
    }

    // NEEDED: Calcium
    if (calcium != null && calcium >= 200) {
      score += 8;
    }

    // NEEDED: Vitamin D
    if (vitaminD != null && vitaminD >= 10) {
      score += 5;
    }

    return score.clamp(0, 100);
  }

  // ============================================
  // GENERAL BARIATRIC SCORING (No specific surgery type)
  // ============================================
  static int _calculateGeneralBariatricScore({
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
    double? protein,
    double? fiber,
    double? saturatedFat,
  }) {
    int score = 50;

    // Protein is always critical for bariatric patients
    if (protein != null) {
      if (protein >= 20) {
        score += 25;
      } else if (protein >= 15) {
        score += 15;
      } else if (protein < 10) {
        score -= 20;
      }
    }

    // Sugar (dumping syndrome risk for most surgeries)
    if (sugar <= 5) {
      score += 20;
    } else if (sugar <= 10) {
      score += 10;
    } else if (sugar > 15) {
      score -= 25;
    }

    // Fat (absorption issues common)
    if (fat <= 10) {
      score += 15;
    } else if (fat > 20) {
      score -= 15;
    }

    // Fiber bonus
    if (fiber != null && fiber >= 5) {
      score += 10;
    }

    // Sodium
    if (sodium < 300) {
      score += 5;
    } else if (sodium > 600) {
      score -= 10;
    }

    // Saturated fat
    if (saturatedFat != null && saturatedFat > 5) {
      score -= 10;
    }

    return score.clamp(0, 100);
  }
}

/// Visual health bar widget with emoji indicator
class BariHealthBar extends StatelessWidget {
  final int healthScore;

  const BariHealthBar({super.key, required this.healthScore});

  /// Legacy static function for backwards compatibility
  /// Delegates to BariHealthCalculator.calculate()
  static int calculateScore({
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
    String? surgeryType,
    double? protein,
    double? fiber,
    double? saturatedFat,
  }) {
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

  @override
  Widget build(BuildContext context) {
    final face = getFaceEmoji(healthScore);
    return Stack(
      children: [
        // Gradient Bar
        Container(
          height: 25,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [Colors.red, Colors.orange, Colors.yellow, Colors.green],
            ),
          ),
        ),
        // Emoji sliding over bar
        Positioned(
          left: 16 + (MediaQuery.of(context).size.width - 32 - 28) * (healthScore / 100),
          top: -30,
          child: Text(
            face,
            style: const TextStyle(fontSize: 28),
          ),
        ),
      ],
    );
  }
}