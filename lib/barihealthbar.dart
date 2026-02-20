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
  // Per-100g thresholds used for nutrient tile progress bars
  static const double fatMax = 20.0;
  static const double sodiumMax = 500.0;
  static const double sugarMax = 10.0; // Tighter than liver - dumping syndrome
  static const double calMax = 400.0;
  static const double proteinMin = 15.0; // Protein is a POSITIVE for bari

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

  /// Generate human-readable score explanations for ScanResultsCard
  static List<Map<String, dynamic>> explainScore({
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
    double? protein,
    String? surgeryType,
  }) {
    final List<Map<String, dynamic>> reasons = [];

    // Sugar — #1 concern for most bariatric patients (dumping syndrome)
    if (sugar <= 5) {
      reasons.add({
        'icon': '✅',
        'text': 'Very low sugar — minimal dumping syndrome risk',
        'positive': true,
      });
    } else if (sugar <= sugarMax) {
      reasons.add({
        'icon': '✅',
        'text': 'Moderate sugar — acceptable for most surgery types',
        'positive': true,
      });
    } else if (sugar <= 20) {
      reasons.add({
        'icon': '⚠️',
        'text': 'High sugar — may trigger dumping syndrome',
        'positive': false,
      });
    } else {
      reasons.add({
        'icon': '🚨',
        'text': 'Very high sugar — significant dumping syndrome risk',
        'positive': false,
      });
    }

    // Protein — critical positive for bariatric patients
    if (protein != null) {
      if (protein >= 25) {
        reasons.add({
          'icon': '💪',
          'text': 'Excellent protein — supports healing & muscle retention',
          'positive': true,
        });
      } else if (protein >= proteinMin) {
        reasons.add({
          'icon': '✅',
          'text': 'Good protein content for bariatric needs',
          'positive': true,
        });
      } else if (protein < 10) {
        reasons.add({
          'icon': '⚠️',
          'text': 'Low protein — prioritize higher protein options',
          'positive': false,
        });
      }
    }

    // Fat
    if (fat <= 10) {
      reasons.add({
        'icon': '✅',
        'text': 'Low fat — easy to absorb post-surgery',
        'positive': true,
      });
    } else if (fat > fatMax) {
      reasons.add({
        'icon': '⚠️',
        'text': 'High fat — may cause discomfort and nausea',
        'positive': false,
      });
    }

    // Sodium
    if (sodium < 300) {
      reasons.add({
        'icon': '✅',
        'text': 'Low sodium — good for blood pressure management',
        'positive': true,
      });
    } else if (sodium > sodiumMax) {
      reasons.add({
        'icon': '⚠️',
        'text': 'High sodium — can cause fluid retention',
        'positive': false,
      });
    }

    // Calories
    if (calories <= 150) {
      reasons.add({
        'icon': '✅',
        'text': 'Low calorie density — fits smaller post-surgery portions',
        'positive': true,
      });
    } else if (calories > calMax) {
      reasons.add({
        'icon': '⚠️',
        'text': 'High calorie density — limit portion size carefully',
        'positive': false,
      });
    }

    // Surgery-specific notes
    if (surgeryType != null &&
        (surgeryType.toLowerCase().contains('bypass') ||
            surgeryType.toLowerCase().contains('sleeve'))) {
      if (sugar > sugarMax) {
        reasons.add({
          'icon': '🚨',
          'text': 'Sugar risk is elevated for your surgery type',
          'positive': false,
        });
      }
    }

    return reasons;
  }

  /// Get bari-appropriate alternative food suggestions based on score
  static List<String> getAlternatives(int score) {
    if (score >= 75) return []; // Excellent — no alternatives needed

    if (score <= 25) {
      // Poor score — foundational bariatric staples
      return [
        '🍗 Grilled chicken breast or turkey (high protein, low fat)',
        '🥚 Eggs or egg whites (protein-dense, soft texture)',
        '🐟 Canned tuna or salmon in water',
        '🫘 Greek yogurt (plain, low-fat) — calcium + protein',
      ];
    } else if (score <= 49) {
      // Fair score — targeted improvements
      return [
        '🧀 Low-fat cottage cheese (high protein, soft)',
        '🥦 Steamed or soft-cooked vegetables',
        '🫘 Lentil soup (protein + fiber, no dumping risk)',
        '🐟 White fish (tilapia, cod) — easy to digest',
      ];
    } else {
      // Good — minor tweaks
      return [
        '💧 Drink fluids 30 min before or after meals, not during',
        '🥣 Try a smaller portion of this food next time',
      ];
    }
  }

  // ============================================
  // GASTRIC BYPASS (ROUX-EN-Y)
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
    int score = 50;

    if (sugar <= 5) {
      score += 25;
    } else if (sugar <= 10) {
      score += 10;
    } else if (sugar <= 15) {
      score -= 15;
    } else {
      score -= 35;
    }

    if (fat <= 10) {
      score += 15;
    } else if (fat <= 15) {
      score += 5;
    } else if (fat > 20) {
      score -= 20;
    }

    if (protein != null) {
      if (protein >= 25) {
        score += 20;
      } else if (protein >= 20) {
        score += 15;
      } else if (protein >= 15) {
        score += 8;
      } else if (protein < 10) {
        score -= 15;
      }
    }

    if (calcium != null && calcium >= 200) score += 8;
    if (vitaminB12 != null && vitaminB12 >= 2.4) score += 5;
    if (iron != null && iron >= 3) score += 5;
    if (folate != null && folate >= 200) score += 5;

    return score.clamp(0, 100);
  }

  // ============================================
  // SLEEVE GASTRECTOMY
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

    if (sugar <= 5) {
      score += 20;
    } else if (sugar <= 10) {
      score += 10;
    } else if (sugar > 15) {
      score -= 25;
    }

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

    if (vitaminB12 != null && vitaminB12 >= 2.4) score += 8;
    if (vitaminD != null && vitaminD >= 10) score += 8;
    if (calcium != null && calcium >= 200) score += 8;
    if (fat > 20) score -= 10;

    return score.clamp(0, 100);
  }

  // ============================================
  // ADJUSTABLE GASTRIC BAND
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

    if (sugar <= 5) {
      score += 20;
    } else if (sugar <= 10) {
      score += 10;
    } else if (sugar > 15) {
      score -= 20;
    }

    if (fat <= 10) {
      score += 15;
    } else if (fat <= 15) {
      score += 5;
    } else if (fat > 20) {
      score -= 20;
    }

    if (protein != null) {
      if (protein >= 20) {
        score += 20;
      } else if (protein >= 15) {
        score += 12;
      } else if (protein < 10) {
        score -= 15;
      }
    }

    if (calcium != null && calcium >= 200) score += 10;

    return score.clamp(0, 100);
  }

  // ============================================
  // BILIOPANCREATIC DIVERSION (BPD/DS)
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

    if (protein != null) {
      if (protein >= 30) {
        score += 30;
      } else if (protein >= 25) {
        score += 20;
      } else if (protein >= 20) {
        score += 10;
      } else if (protein < 15) {
        score -= 25;
      }
    } else {
      score -= 20;
    }

    if (sugar <= 5) {
      score += 15;
    } else if (sugar > 15) {
      score -= 25;
    }

    if (fat <= 10) {
      score += 10;
    } else if (fat > 20) {
      score -= 25;
    }

    if (vitaminA != null && vitaminA >= 700) score += 5;
    if (vitaminD != null && vitaminD >= 10) score += 5;
    if (vitaminE != null && vitaminE >= 10) score += 5;
    if (vitaminK != null && vitaminK >= 80) score += 5;
    if (calcium != null && calcium >= 300) score += 8;
    if (iron != null && iron >= 5) score += 5;
    if (vitaminB12 != null && vitaminB12 >= 2.4) score += 5;

    return score.clamp(0, 100);
  }

  // ============================================
  // MINI GASTRIC BYPASS
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

    if (sugar <= 5) {
      score += 25;
    } else if (sugar <= 10) {
      score += 10;
    } else if (sugar > 15) {
      score -= 30;
    }

    if (fat <= 10) {
      score += 15;
    } else if (fat > 20) {
      score -= 20;
    }

    if (protein != null) {
      if (protein >= 25) {
        score += 25;
      } else if (protein >= 20) {
        score += 15;
      } else if (protein < 10) {
        score -= 15;
      }
    }

    if (vitaminB12 != null && vitaminB12 >= 2.4) score += 8;
    if (iron != null && iron >= 3) score += 8;
    if (calcium != null && calcium >= 200) score += 8;
    if (vitaminD != null && vitaminD >= 10) score += 5;

    return score.clamp(0, 100);
  }

  // ============================================
  // GENERAL BARIATRIC SCORING
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

    if (protein != null) {
      if (protein >= 20) {
        score += 25;
      } else if (protein >= 15) {
        score += 15;
      } else if (protein < 10) {
        score -= 20;
      }
    }

    if (sugar <= 5) {
      score += 20;
    } else if (sugar <= 10) {
      score += 10;
    } else if (sugar > 15) {
      score -= 25;
    }

    if (fat <= 10) {
      score += 15;
    } else if (fat > 20) {
      score -= 15;
    }

    if (fiber != null && fiber >= 5) score += 10;

    if (sodium < 300) {
      score += 5;
    } else if (sodium > 600) {
      score -= 10;
    }

    if (saturatedFat != null && saturatedFat > 5) score -= 10;

    return score.clamp(0, 100);
  }
}

// ============================================================
// SCAN RESULTS CARD
// Rich scan result UI — shown after a successful barcode scan
// ============================================================
class BariScanResultsCard extends StatelessWidget {
  final String productName;
  final double calories;
  final double fat;
  final double sugar;
  final double sodium;
  final double? protein;
  final int healthScore;
  final String? surgeryType;

  const BariScanResultsCard({
    super.key,
    required this.productName,
    required this.calories,
    required this.fat,
    required this.sugar,
    required this.sodium,
    this.protein,
    required this.healthScore,
    this.surgeryType,
  });

  Color get _scoreColor {
    if (healthScore <= 25) return const Color(0xFFD32F2F);
    if (healthScore <= 49) return const Color(0xFFF57C00);
    if (healthScore <= 74) return const Color(0xFFF9A825);
    return const Color(0xFF388E3C);
  }

  String get _scoreLabel {
    if (healthScore <= 25) return 'Poor';
    if (healthScore <= 49) return 'Fair';
    if (healthScore <= 74) return 'Good';
    return 'Excellent';
  }

  String get _scoreEmoji {
    if (healthScore <= 25) return '😠';
    if (healthScore <= 49) return '☹️';
    if (healthScore <= 74) return '😐';
    return '😄';
  }

  @override
  Widget build(BuildContext context) {
    final reasons = BariHealthCalculator.explainScore(
      fat: fat,
      sodium: sodium,
      sugar: sugar,
      calories: calories,
      protein: protein,
      surgeryType: surgeryType,
    );
    final alternatives = BariHealthCalculator.getAlternatives(healthScore);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _scoreColor.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                bottom: BorderSide(color: _scoreColor.withOpacity(0.2), width: 1),
              ),
            ),
            child: Row(
              children: [
                // Score circle
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: _scoreColor, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: _scoreColor.withOpacity(0.2),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$healthScore',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: _scoreColor,
                        ),
                      ),
                      Text(
                        '/100',
                        style: TextStyle(
                          fontSize: 10,
                          color: _scoreColor.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        productName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _scoreColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$_scoreEmoji  $_scoreLabel for Bariatric',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (surgeryType != null &&
                          surgeryType!.isNotEmpty &&
                          surgeryType != 'Not specified' &&
                          surgeryType != 'Other (default scoring)') ...[
                        const SizedBox(height: 4),
                        Text(
                          '📋 Scored for: $surgeryType',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Nutrient Grid ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nutrition per 100g',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF757575),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _NutrientTile(
                        label: 'Calories',
                        value: calories,
                        unit: 'kcal',
                        max: BariHealthCalculator.calMax,
                        color: const Color(0xFFE53935),
                        icon: Icons.local_fire_department,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _NutrientTile(
                        label: 'Fat',
                        value: fat,
                        unit: 'g',
                        max: BariHealthCalculator.fatMax,
                        color: const Color(0xFFFB8C00),
                        icon: Icons.opacity,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _NutrientTile(
                        label: 'Sugar',
                        value: sugar,
                        unit: 'g',
                        max: BariHealthCalculator.sugarMax,
                        color: const Color(0xFF8E24AA),
                        icon: Icons.cake,
                        // Sugar is especially important for bari — highlight danger
                        dangerThreshold: 10.0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _NutrientTile(
                        label: 'Sodium',
                        value: sodium,
                        unit: 'mg',
                        max: BariHealthCalculator.sodiumMax,
                        color: const Color(0xFF00ACC1),
                        icon: Icons.water_drop,
                      ),
                    ),
                  ],
                ),
                // Protein row — if available, show as a positive tile
                if (protein != null) ...[
                  const SizedBox(height: 8),
                  _ProteinTile(protein: protein!),
                ],
              ],
            ),
          ),

          // ── Score Explanation ────────────────────────────────
          if (reasons.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Why this score?',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF424242),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...reasons.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r['icon'] as String,
                                style: const TextStyle(fontSize: 14)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                r['text'] as String,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: (r['positive'] as bool)
                                      ? const Color(0xFF2E7D32)
                                      : const Color(0xFFC62828),
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),

          // ── Alternatives ─────────────────────────────────────
          if (alternatives.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline,
                          size: 16, color: Colors.orange.shade700),
                      const SizedBox(width: 6),
                      Text(
                        'Bariatric-Friendly Alternatives',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...alternatives.map((alt) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          alt,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade900,
                            height: 1.4,
                          ),
                        ),
                      )),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Nutrient Tile ─────────────────────────────────────────────
class _NutrientTile extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final double max;
  final Color color;
  final IconData icon;
  final double? dangerThreshold;

  const _NutrientTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.max,
    required this.color,
    required this.icon,
    this.dangerThreshold,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = (value / max).clamp(0.0, 1.0);
    final isDanger = dangerThreshold != null && value > dangerThreshold!;
    final tileColor = isDanger ? const Color(0xFFD32F2F) : color;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tileColor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDanger
              ? tileColor.withOpacity(0.5)
              : tileColor.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: tileColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: tileColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isDanger) ...[
                const SizedBox(width: 4),
                Icon(Icons.warning_amber_rounded,
                    size: 12, color: tileColor),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${value.toStringAsFixed(1)} $unit',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: tileColor,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              backgroundColor: tileColor.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation<Color>(tileColor),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Protein Tile — positive indicator ────────────────────────
class _ProteinTile extends StatelessWidget {
  final double protein;

  const _ProteinTile({required this.protein});

  @override
  Widget build(BuildContext context) {
    final isGood = protein >= BariHealthCalculator.proteinMin;
    final color = isGood ? const Color(0xFF2E7D32) : const Color(0xFFF57C00);
    final ratio = (protein / 30.0).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.fitness_center, size: 14, color: color),
                    const SizedBox(width: 4),
                    Text(
                      'Protein',
                      style: TextStyle(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isGood ? 'GREAT' : 'LOW',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${protein.toStringAsFixed(1)} g',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    backgroundColor: color.withOpacity(0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            isGood ? '💪' : '⚠️',
            style: const TextStyle(fontSize: 24),
          ),
        ],
      ),
    );
  }
}

/// Legacy visual health bar widget — kept for backwards compatibility
class BariHealthBar extends StatelessWidget {
  final int healthScore;

  const BariHealthBar({super.key, required this.healthScore});

  /// Legacy static function for backwards compatibility
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
        Positioned(
          left: 16 +
              (MediaQuery.of(context).size.width - 32 - 28) *
                  (healthScore / 100),
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