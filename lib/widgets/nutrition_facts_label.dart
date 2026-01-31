// lib/widgets/nutrition_facts_label.dart - FDA-STYLE NUTRITION FACTS
// Complete nutrition display with bold macros and macro/micro labels
// iOS 14 Compatible | Production Ready

import 'package:flutter/material.dart';
import 'package:bari_wise/models/nutrition_info.dart';
import 'package:bari_wise/barihealthbar.dart';

class NutritionFactsLabel extends StatelessWidget {
  final NutritionInfo nutrition;
  final int? servings;
  final bool showbariScore;
  final bool compact;

  const NutritionFactsLabel({
    super.key,
    required this.nutrition,
    this.servings,
    this.showbariScore = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.black, width: 2),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(),
            const Divider(thickness: 8, color: Colors.black, height: 16),
            
            // Serving info
            if (servings != null && servings! > 1) ...[
              _buildServingInfo(),
              const Divider(thickness: 1, color: Colors.black, height: 12),
            ],
            
            // Calories (prominent)
            _buildCalories(),
            const Divider(thickness: 4, color: Colors.black, height: 12),
            
            // Daily Value header
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '% Daily Value*',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(thickness: 1, color: Colors.grey, height: 8),
            
            // ========================================
            // MACRONUTRIENTS (BOLD)
            // ========================================
            _buildMacroSection(),
            
            const Divider(thickness: 4, color: Colors.black, height: 12),
            
            // ========================================
            // MICRONUTRIENTS
            // ========================================
            _buildMicronutrientsSection(),
            
            const Divider(thickness: 4, color: Colors.black, height: 12),
            
            // Footer
            _buildFooter(),
            
            // bari Health Score
            if (showbariScore) ...[
              const SizedBox(height: 16),
              const Divider(thickness: 2, color: Colors.black),
              const SizedBox(height: 12),
              BariHealthBar(
                healthScore: nutrition.calculatebariScore(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nutrition Facts',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        if (nutrition.productName != 'Unknown') ...[
          const SizedBox(height: 4),
          Text(
            nutrition.productName,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildServingInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${servings} serving${servings! > 1 ? 's' : ''} per container',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Serving size   ${nutrition.servingSizeDisplay}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildCalories() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          'Calories',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          '${nutrition.calories.toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildMacroSection() {
    return Column(
      children: [
        // Section header
        _buildSectionHeader('MACRONUTRIENTS'),
        const SizedBox(height: 8),

        // Total Fat (BOLD)
        _buildBoldNutrient(
          'Total Fat',
          '${nutrition.fat.toStringAsFixed(1)}g',
          _calculateDV(nutrition.fat, 78), // Based on 78g DV
          'MACRO',
        ),
        
        // Saturated Fat (indented)
        _buildIndentedNutrient(
          'Saturated Fat',
          '${nutrition.saturatedFat?.toStringAsFixed(1) ?? '0'}g',
          nutrition.saturatedFat != null 
            ? _calculateDV(nutrition.saturatedFat!, 20) 
            : null,
          'MACRO',
        ),
        
        // Monounsaturated Fat (indented)
        _buildIndentedNutrient(
          'Monounsaturated Fat',
          '${nutrition.monounsaturatedFat?.toStringAsFixed(1) ?? '0'}g',
          null, // No DV for monounsaturated
          'MACRO',
        ),

        // Polyunsaturated Fat (indented)
        _buildIndentedNutrient(
          'Polyunsaturated Fat',
          '${nutrition.polyunsaturatedFat?.toStringAsFixed(1) ?? '0'}g',
          null, // No DV for polyunsaturated
          'MACRO',
        ),
        
        // Trans Fat (indented)
        _buildIndentedNutrient(
          'Trans Fat',
          '${nutrition.transFat?.toStringAsFixed(1) ?? '0'}g',
          null, // No DV for trans fat
          'MACRO',
        ),
        
        const Divider(thickness: 1, color: Colors.grey, height: 8),
        
        // Cholesterol (BOLD)
        _buildBoldNutrient(
          'Cholesterol',
          '${nutrition.cholesterol?.toStringAsFixed(0) ?? '0'}mg',
          nutrition.cholesterol != null 
            ? _calculateDV(nutrition.cholesterol!, 300) 
            : null,
          'MICRO',
        ),
        
        const Divider(thickness: 1, color: Colors.grey, height: 8),
        
        // Sodium (BOLD)
        _buildBoldNutrient(
          'Sodium',
          '${nutrition.sodium.toStringAsFixed(0)}mg',
          _calculateDV(nutrition.sodium, 2300),
          'MICRO',
        ),
        
        const Divider(thickness: 1, color: Colors.grey, height: 8),
        
        // Total Carbohydrates (BOLD)
        _buildBoldNutrient(
          'Total Carbohydrates',
          '${nutrition.carbs.toStringAsFixed(1)}g',
          _calculateDV(nutrition.carbs, 275),
          'MACRO',
        ),
        
        // Fiber (indented)
        _buildIndentedNutrient(
          'Dietary Fiber',
          '${nutrition.fiber?.toStringAsFixed(1) ?? '0'}g',
          nutrition.fiber != null 
            ? _calculateDV(nutrition.fiber!, 28) 
            : null,
          'MACRO',
        ),
        
        // Total Sugars (indented)
        _buildIndentedNutrient(
          'Total Sugars',
          '${nutrition.sugar.toStringAsFixed(1)}g',
          null, // No DV for total sugars
          'MACRO',
        ),
        
        // Net Carbs (indented, calculated)
        _buildIndentedNutrient(
          'Net Carbohydrates',
          '${nutrition.netCarbs.toStringAsFixed(1)}g',
          null,
          'MACRO',
          isCalculated: true,
        ),
        
        const Divider(thickness: 1, color: Colors.grey, height: 8),
        
        // Protein (BOLD)
        _buildBoldNutrient(
          'Protein',
          '${nutrition.protein.toStringAsFixed(1)}g',
          _calculateDV(nutrition.protein, 50),
          'MACRO',
        ),
      ],
    );
  }

  Widget _buildMicronutrientsSection() {
    return Column(
      children: [
        // Section header
        _buildSectionHeader('MICRONUTRIENTS'),
        const SizedBox(height: 8),

        // Potassium
        _buildRegularNutrient(
          'Potassium',
          '${nutrition.potassium?.toStringAsFixed(0) ?? '0'}mg',
          nutrition.potassium != null 
            ? _calculateDV(nutrition.potassium!, 4700) 
            : null,
          'MICRO',
        ),
        
        const Divider(thickness: 1, color: Colors.grey, height: 8),
        
        // Iron
        _buildRegularNutrient(
          'Iron',
          '${nutrition.iron?.toStringAsFixed(1) ?? '0'}mg',
          nutrition.iron != null 
            ? _calculateDV(nutrition.iron!, 18) 
            : null,
          'MICRO',
        ),
        
        const Divider(thickness: 1, color: Colors.grey, height: 8),
        
        // Cobalt
        _buildRegularNutrient(
          'Cobalt',
          '${nutrition.cobalt?.toStringAsFixed(1) ?? '0'}mcg',
          null, // No established DV for cobalt
          'MICRO',
        ),

        // OTHER NUTRIENTS (if present)
        if (_hasOtherNutrients()) ...[
          const SizedBox(height: 12),
          const Divider(thickness: 2, color: Colors.grey, height: 12),
          const SizedBox(height: 8),
          _buildSectionHeader('OTHER NUTRIENTS'),
          const SizedBox(height: 8),
          
          if (nutrition.vitaminA != null) ...[
            _buildRegularNutrient(
              'Vitamin A',
              '${nutrition.vitaminA!.toStringAsFixed(1)} mcg',
              null,
              'MICRO',
            ),
            const Divider(thickness: 1, color: Colors.grey, height: 8),
          ],
          
          if (nutrition.vitaminC != null) ...[
            _buildRegularNutrient(
              'Vitamin C',
              '${nutrition.vitaminC!.toStringAsFixed(1)} mg',
              null,
              'MICRO',
            ),
            const Divider(thickness: 1, color: Colors.grey, height: 8),
          ],
          
          if (nutrition.vitaminD != null) ...[
            _buildRegularNutrient(
              'Vitamin D',
              '${nutrition.vitaminD!.toStringAsFixed(1)} mcg',
              null,
              'MICRO',
            ),
            const Divider(thickness: 1, color: Colors.grey, height: 8),
          ],
          
          if (nutrition.calcium != null)
            _buildRegularNutrient(
              'Calcium',
              '${nutrition.calcium!.toStringAsFixed(0)} mg',
              null,
              'MICRO',
            ),
        ],
      ],
    );
  }

  Widget _buildFooter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '* The % Daily Value (DV) tells you how much a nutrient in a serving of food contributes to a daily diet. 2,000 calories a day is used for general nutrition advice.',
          style: TextStyle(
            fontSize: 9,
            height: 1.3,
            color: Colors.grey.shade800,
          ),
        ),
        if (nutrition.netCarbs != nutrition.carbs) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.calculate, size: 14, color: Colors.blue.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Net Carbs = Total Carbs - Fiber',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.blue.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
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
        border: Border.all(color: Colors.orange.shade300, width: 1.5),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.orange.shade900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ========================================
  // NUTRIENT ROW BUILDERS
  // ========================================

  Widget _buildBoldNutrient(String label, String amount, int? dv, String type) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900, // BOLD for macros
                    decoration: TextDecoration.underline,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  amount,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900, // BOLD for macros
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              if (dv != null)
                Text(
                  '$dv%',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900, // BOLD for macros
                  ),
                ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: type == 'MACRO' ? Colors.blue.shade100 : Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  type,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: type == 'MACRO' ? Colors.blue.shade900 : Colors.orange.shade900,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIndentedNutrient(String label, String amount, int? dv, String type, {bool isCalculated = false}) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 2, bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontStyle: isCalculated ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  amount,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontStyle: isCalculated ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              if (dv != null)
                Text(
                  '$dv%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: type == 'MACRO' ? Colors.blue.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  type,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: type == 'MACRO' ? Colors.blue.shade700 : Colors.orange.shade700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRegularNutrient(String label, String amount, int? dv, String type) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  amount,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              if (dv != null)
                Text(
                  '$dv%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: type == 'MACRO' ? Colors.blue.shade100 : Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  type,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: type == 'MACRO' ? Colors.blue.shade900 : Colors.orange.shade900,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Calculate % Daily Value
  int? _calculateDV(double amount, double dailyValue) {
    if (dailyValue == 0) return null;
    return ((amount / dailyValue) * 100).round();
  }
}