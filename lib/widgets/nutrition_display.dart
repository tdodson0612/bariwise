// lib/widgets/nutrition_display.dart - UPDATED: Standardized macro/micro format
import 'package:flutter/material.dart';
import '../models/nutrition_info.dart';

class NutritionDisplay extends StatelessWidget {
  final NutritionInfo nutrition;
  final int bariScore;
  final String? disclaimer;

  const NutritionDisplay({
    super.key,
    required this.nutrition,
    required this.bariScore,
    this.disclaimer,
  });

  /// Calculate macronutrient percentages
  Map<String, double> _calculateMacros() {
    // Calories from macros (per gram):
    // - Protein: 4 cal/g
    // - Carbs: 4 cal/g
    // - Fat: 9 cal/g

    final protein = nutrition.protein ?? 0.0;
    final carbs = nutrition.carbs ?? 0.0;
    final fat = nutrition.fat ?? 0.0;

    final proteinCals = protein * 4;
    final carbsCals = carbs * 4;
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

  @override
  Widget build(BuildContext context) {
    final macros = _calculateMacros();
    final hasValidMacros = macros['protein']! > 0 ||
        macros['carbs']! > 0 ||
        macros['fat']! > 0;

    // Local nullable-safe values
    final calories = nutrition.calories ?? 0.0;
    final fat = nutrition.fat ?? 0.0;
    final saturatedFat = nutrition.saturatedFat ?? 0.0;
    final monounsaturatedFat = nutrition.monounsaturatedFat;
    final polyunsaturatedFat = nutrition.polyunsaturatedFat;
    final transFat = nutrition.transFat;
    final carbs = nutrition.carbs ?? 0.0;
    final sugar = nutrition.sugar ?? 0.0;
    final fiber = nutrition.fiber ?? 0.0;
    final protein = nutrition.protein ?? 0.0;
    final sodium = nutrition.sodium ?? 0.0;
    final iron = nutrition.iron;
    final potassium = nutrition.potassium;
    final cholesterol = nutrition.cholesterol;
    final cobalt = nutrition.cobalt;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product name header
            Text(
              nutrition.productName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(thickness: 2),
            const SizedBox(height: 12),

            // MACRONUTRIENTS SECTION
            _buildSectionHeader('MACRONUTRIENTS'),
            const SizedBox(height: 8),

            _buildNutrientRow('Calories', '${calories.toStringAsFixed(0)} kcal', 'MACRO', isBold: true),
            _buildNutrientRow('Protein', '${protein.toStringAsFixed(1)} g', 'MACRO', isBold: true),
            _buildNutrientRow('Total Fat', '${fat.toStringAsFixed(1)} g', 'MACRO', isBold: true),
            _buildIndentedRow('Monounsaturated Fat', '${monounsaturatedFat?.toStringAsFixed(1) ?? 'N/A'} g', 'MACRO'),
            _buildIndentedRow('Polyunsaturated Fat', '${polyunsaturatedFat?.toStringAsFixed(1) ?? 'N/A'} g', 'MACRO'),
            _buildIndentedRow('Saturated Fat', '${saturatedFat.toStringAsFixed(1)} g', 'MACRO'),
            _buildIndentedRow('Trans Fat', '${transFat?.toStringAsFixed(1) ?? 'N/A'} g', 'MACRO'),
            _buildNutrientRow('Carbohydrates', '${carbs.toStringAsFixed(1)} g', 'MACRO', isBold: true),
            _buildIndentedRow('Fiber', '${fiber.toStringAsFixed(1)} g', 'MACRO'),
            _buildIndentedRow('Net Carbohydrates', '${nutrition.netCarbs.toStringAsFixed(1)} g', 'MACRO'),
            _buildIndentedRow('Sugar', '${sugar.toStringAsFixed(1)} g', 'MACRO'),

            const SizedBox(height: 16),
            const Divider(thickness: 2),
            const SizedBox(height: 12),

            // MICRONUTRIENTS SECTION
            _buildSectionHeader('MICRONUTRIENTS'),
            const SizedBox(height: 8),

            _buildNutrientRow('Iron', '${iron?.toStringAsFixed(1) ?? 'N/A'} mg', 'MICRO'),
            _buildNutrientRow('Sodium', '${sodium.toStringAsFixed(0)} mg', 'MICRO'),
            _buildNutrientRow('Potassium', '${potassium?.toStringAsFixed(0) ?? 'N/A'} mg', 'MICRO'),
            _buildNutrientRow('Cholesterol', '${cholesterol?.toStringAsFixed(0) ?? 'N/A'} mg', 'MICRO'),
            _buildNutrientRow('Cobalt', '${cobalt?.toStringAsFixed(1) ?? 'N/A'} mcg', 'MICRO'),

            // OTHER NUTRIENTS (if present)
            if (_hasOtherNutrients()) ...[
              const SizedBox(height: 16),
              const Divider(thickness: 2),
              const SizedBox(height: 12),
              _buildSectionHeader('OTHER NUTRIENTS'),
              const SizedBox(height: 8),
              
              if (nutrition.vitaminA != null)
                _buildNutrientRow('Vitamin A', '${nutrition.vitaminA!.toStringAsFixed(1)} mcg', 'MICRO'),
              if (nutrition.vitaminC != null)
                _buildNutrientRow('Vitamin C', '${nutrition.vitaminC!.toStringAsFixed(1)} mg', 'MICRO'),
              if (nutrition.vitaminD != null)
                _buildNutrientRow('Vitamin D', '${nutrition.vitaminD!.toStringAsFixed(1)} mcg', 'MICRO'),
              if (nutrition.calcium != null)
                _buildNutrientRow('Calcium', '${nutrition.calcium!.toStringAsFixed(0)} mg', 'MICRO'),
            ],

            // 🔥 Macros Section (kept from original)
            if (hasValidMacros) ...[
              const SizedBox(height: 20),
              const Divider(thickness: 2),
              const SizedBox(height: 12),
              
              Row(
                children: [
                  Icon(Icons.pie_chart, size: 20, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  const Text(
                    'Macros:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Macro bars with percentages
              _buildMacroBar(
                'Protein',
                macros['protein']!,
                Colors.blue,
                '${protein.toStringAsFixed(1)}g',
              ),
              const SizedBox(height: 8),

              _buildMacroBar(
                'Carbs',
                macros['carbs']!,
                Colors.orange,
                '${carbs.toStringAsFixed(1)}g',
              ),
              const SizedBox(height: 8),

              _buildMacroBar(
                'Fat',
                macros['fat']!,
                Colors.purple,
                '${fat.toStringAsFixed(1)}g',
              ),
            ],

            // Disclaimer if provided
            if (disclaimer != null && disclaimer!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        disclaimer!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _hasOtherNutrients() {
    return nutrition.vitaminA != null ||
        nutrition.vitaminC != null ||
        nutrition.vitaminD != null ||
        nutrition.calcium != null;
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.orange.shade900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildNutrientRow(String label, String value, String type, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                decoration: isBold ? TextDecoration.underline : null,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: type == 'MACRO' ? Colors.blue.shade100 : Colors.orange.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              type,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: type == 'MACRO' ? Colors.blue.shade900 : Colors.orange.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndentedRow(String label, String value, String type) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 4, bottom: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: type == 'MACRO' ? Colors.blue.shade50 : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              type,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: type == 'MACRO' ? Colors.blue.shade700 : Colors.orange.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroBar(String label, double percentage, Color color, String grams) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Row(
              children: [
                Text(
                  '${percentage.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  ' ($grams)',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percentage / 100,
            minHeight: 8,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}