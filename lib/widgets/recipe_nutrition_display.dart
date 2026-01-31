// lib/widgets/recipe_nutrition_display.dart - UPDATED: Standardized macro/micro format
import 'package:flutter/material.dart';
import 'package:bari_wise/services/recipe_nutrition_service.dart';
import 'package:bari_wise/barihealthbar.dart';

class RecipeNutritionDisplay extends StatelessWidget {
  final RecipeNutrition nutrition;

  const RecipeNutritionDisplay({
    super.key,
    required this.nutrition,
  });

  /// Calculate macronutrient percentages
  Map<String, double> _calculateMacros() {
    // Calories from macros (per gram):
    // - Protein: 4 cal/g
    // - Carbs: 4 cal/g
    // - Fat: 9 cal/g

    final proteinCals = nutrition.protein * 4;
    final carbsCals = nutrition.carbohydrates * 4;
    final fatCals = nutrition.fat * 9;

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
            const Text(
              "Recipe Nutrition Summary",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(thickness: 2),
            const SizedBox(height: 12),

            // MACRONUTRIENTS SECTION
            _buildSectionHeader('MACRONUTRIENTS'),
            const SizedBox(height: 8),

            _buildNutrientRow('Calories', '${nutrition.calories.toStringAsFixed(0)} kcal', 'MACRO', isBold: true),
            _buildNutrientRow('Protein', '${nutrition.protein.toStringAsFixed(1)} g', 'MACRO', isBold: true),
            _buildNutrientRow('Total Fat', '${nutrition.fat.toStringAsFixed(1)} g', 'MACRO', isBold: true),
            _buildIndentedRow('Monounsaturated Fat', '${nutrition.monounsaturatedFat.toStringAsFixed(1)} g', 'MACRO'),
            _buildIndentedRow('Saturated Fat', '${nutrition.saturatedFat.toStringAsFixed(1)} g', 'MACRO'),
            _buildIndentedRow('Trans Fat', '${nutrition.transFat.toStringAsFixed(1)} g', 'MACRO'),
            _buildNutrientRow('Carbohydrates', '${nutrition.carbohydrates.toStringAsFixed(1)} g', 'MACRO', isBold: true),
            _buildIndentedRow('Fiber', '${nutrition.fiber.toStringAsFixed(1)} g', 'MACRO'),
            _buildIndentedRow('Net Carbohydrates', '${nutrition.netCarbs.toStringAsFixed(1)} g', 'MACRO'),
            _buildIndentedRow('Sugar', '${nutrition.sugar.toStringAsFixed(1)} g', 'MACRO'),

            const SizedBox(height: 16),
            const Divider(thickness: 2),
            const SizedBox(height: 12),

            // MICRONUTRIENTS SECTION
            _buildSectionHeader('MICRONUTRIENTS'),
            const SizedBox(height: 8),

            _buildNutrientRow('Iron', '${nutrition.iron.toStringAsFixed(1)} mg', 'MICRO'),
            _buildNutrientRow('Sodium', '${nutrition.sodium.toStringAsFixed(0)} mg', 'MICRO'),
            _buildNutrientRow('Potassium', '${nutrition.potassium.toStringAsFixed(0)} mg', 'MICRO'),
            _buildNutrientRow('Cholesterol', '${nutrition.cholesterol.toStringAsFixed(0)} mg', 'MICRO'),
            _buildNutrientRow('Cobalt', '${nutrition.cobalt.toStringAsFixed(1)} mcg', 'MICRO'),

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
                '${nutrition.protein.toStringAsFixed(1)}g',
              ),
              const SizedBox(height: 8),
              
              _buildMacroBar(
                'Carbs',
                macros['carbs']!,
                Colors.orange,
                '${nutrition.carbohydrates.toStringAsFixed(1)}g',
              ),
              const SizedBox(height: 8),
              
              _buildMacroBar(
                'Fat',
                macros['fat']!,
                Colors.purple,
                '${nutrition.fat.toStringAsFixed(1)}g',
              ),
            ],

            const SizedBox(height: 20),
            const Divider(thickness: 2),
            
            // bari health score
            const SizedBox(height: 12),
            BariHealthBar(healthScore: nutrition.bariScore),
          ],
        ),
      ),
    );
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