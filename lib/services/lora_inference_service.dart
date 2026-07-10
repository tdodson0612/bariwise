// lib/services/lora_inference_service.dart
// Drop-in LoRA inference layer.
//
// ARCHITECTURE:
//   Current flow:  SuggestedRecipesPage → Cloudflare Worker → D1 DB
//   Future flow:   SuggestedRecipesPage → LoraInferenceService → Worker /lora/* endpoint
//
// The LoRA inference server exposes the SAME REST shape as the existing
// Worker recipe endpoints so SuggestedRecipesPage requires zero changes
// when we flip the feature flag.
//
// LORA_INTEGRATION_POINT: When _loraEnabled = true, this service intercepts
// recipe search calls and routes them to the LoRA inference endpoint instead
// of the D1 database query.
//
// FoodClassifierService integration:
//   _tryLoRA() is inserted BEFORE _tryGroq() in the LLM fallback chain.
//   It uses the same interface: returns bool? (null = fallback to next provider).

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:bari_wise/config/app_config.dart';
import 'package:bari_wise/models/lora_training_pair.dart';
import 'package:bari_wise/pages/suggested_recipes_page.dart' show Recipe;

class LoraInferenceService {
  // ── Feature flag — flip to true once Model A passes validation ─
  // LORA_INTEGRATION_POINT: Change this to true when LoRA is ready
  static bool _loraEnabled = false;

  // ── LoRA inference endpoint (matches Worker URL pattern) ───────
  // When deployed: ${AppConfig.cloudflareWorkerUrl}/lora/...
  static String get _loraBaseUrl =>
      '${AppConfig.cloudflareWorkerUrl}/lora';

  static const Duration _loraTimeout = Duration(seconds: 10);

  // ═══════════════════════════════════════════════════════════════
  // PUBLIC API — matches existing Worker endpoint shapes exactly
  // ═══════════════════════════════════════════════════════════════

  /// Enable or disable LoRA inference (can be toggled at runtime)
  static void setLoraEnabled(bool enabled) {
    _loraEnabled = enabled;
    AppConfig.debugPrint(
        '${enabled ? "✅" : "⚠️"} LoRA inference '
        '${enabled ? "ENABLED" : "DISABLED"}');
  }

  static bool get isLoraEnabled => _loraEnabled;

  /// Search recipes using LoRA Model A.
  /// Signature mirrors the existing Worker call in
  /// SuggestedRecipesPage._loadRecipes().
  /// Returns null if LoRA is disabled or fails — caller falls back
  /// to DB query.
  static Future<List<Recipe>?> searchRecipes({
    required List<String> ingredients,
    required int limit,
    required int offset,
    String? surgeryType,
    int? bariHealthScore,
  }) async {
    if (!_loraEnabled) return null;

    try {
      AppConfig.debugPrint(
          '🤖 LoRA: searching recipes for '
          '${ingredients.length} ingredients');

      final response = await http
          .post(
            Uri.parse('$_loraBaseUrl/recipes/search'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'ingredients': ingredients,
              'limit':       limit,
              'offset':      offset,
              if (surgeryType != null)   'surgery_type':     surgeryType,
              if (bariHealthScore != null) 'bari_health_score': bariHealthScore,
              // Tell the Worker to use LoRA model, not D1 query
              'use_lora': true,
            }),
          )
          .timeout(_loraTimeout);

      if (response.statusCode != 200) {
        AppConfig.debugPrint(
            '⚠️ LoRA search failed: ${response.statusCode}');
        return null;
      }

      final data        = jsonDecode(response.body) as Map<String, dynamic>;
      final recipesList = data['recipes'] as List? ?? [];
      return recipesList
          .map((r) => Recipe.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppConfig.debugPrint(
          '⚠️ LoRA inference error (falling back to DB): $e');
      return null;
    }
  }

  /// Check ingredient existence using LoRA Model C.
  /// Mirrors Worker /recipes/check-ingredient endpoint shape.
  /// Returns null on failure so caller falls back to DB check.
  static Future<bool?> checkIngredientExists(String ingredient) async {
    if (!_loraEnabled) return null;

    try {
      final response = await http
          .post(
            Uri.parse('$_loraBaseUrl/recipes/check-ingredient'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'ingredient': ingredient}),
          )
          .timeout(_loraTimeout);

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['exists'] as bool?;
    } catch (e) {
      AppConfig.debugPrint(
          '⚠️ LoRA ingredient check failed: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // FOOD CLASSIFIER INTEGRATION  (Model C)
  // Insert this as first step in FoodClassifierService.isWordFood()
  // BEFORE _tryGroq() — add this method call at line:
  //   result = await LoraInferenceService.tryClassifyWord(word);
  //   if (result != null) {
  //     await _cacheResult(word, result);
  //     return result;
  //   }
  // ═══════════════════════════════════════════════════════════════

  /// Classify a single word as food/non-food using LoRA Model C.
  /// Returns null if LoRA is disabled or unavailable
  /// (fallback to Groq).
  static Future<bool?> tryClassifyWord(String word) async {
    if (!_loraEnabled) return null;

    try {
      final response = await http
          .post(
            Uri.parse('$_loraBaseUrl/classify/food'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'word': word.toLowerCase().trim()}),
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode != 200) return null;

      final data   = jsonDecode(response.body) as Map<String, dynamic>;
      final result = data['result'] as Map<String, dynamic>?;
      if (result == null) return null;

      final classification = LoraClassificationResult.fromJson(result);

      // Only trust high-confidence results from LoRA
      if (classification.confidence < 0.85) {
        AppConfig.debugPrint(
            '⚠️ LoRA classifier low confidence '
            '(${classification.confidence}) for "$word" — falling back');
        return null;
      }

      AppConfig.debugPrint(
          '✅ LoRA classified "$word": '
          'isFood=${classification.isFood} '
          '(${(classification.confidence * 100).toStringAsFixed(0)}% '
          'confidence)');
      return classification.isFood;
    } catch (e) {
      AppConfig.debugPrint('⚠️ LoRA classifier error: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // COMPLIANCE PRE-SCREENING  (Model B)
  // LORA_INTEGRATION_POINT: Call this in SubmitRecipePage._submitRecipe()
  // BEFORE the existing SubmittedRecipesService.checkCompliance() call.
  // If LoRA flags a violation, show the corrected recipe to the user
  // before they submit, reducing admin review load.
  // ═══════════════════════════════════════════════════════════════

  /// Pre-screen a recipe for post-bariatric compliance violations
  /// before submission.
  /// Returns null if LoRA is disabled — caller proceeds with
  /// existing flow.
  static Future<LoraComplianceResult?> prescreenCompliance({
    required String recipeName,
    required List<Map<String, dynamic>> ingredients,
    required String directions,
    required Map<String, dynamic>? nutrition,
  }) async {
    if (!_loraEnabled) return null;

    try {
      AppConfig.debugPrint(
          '🤖 LoRA: pre-screening compliance for "$recipeName"');

      final rawRecipe = LoraRawRecipe(
        recipeName:  recipeName,
        ingredients: ingredients,
        directions:  directions,
        nutrition:   nutrition,
      );

      final response = await http
          .post(
            Uri.parse('$_loraBaseUrl/compliance/check'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'recipe': rawRecipe.toJson()}),
          )
          .timeout(_loraTimeout);

      if (response.statusCode != 200) return null;

      final data       = jsonDecode(response.body) as Map<String, dynamic>;
      final resultData = data['result'] as Map<String, dynamic>?;
      if (resultData == null) return null;

      return LoraComplianceResult.fromJson(resultData);
    } catch (e) {
      AppConfig.debugPrint(
          '⚠️ LoRA compliance pre-screen failed: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // VALIDATION  (post-training quality check)
  // Run after each LoRA model training cycle to verify outputs
  // still pass RecipeComplianceService thresholds.
  // ═══════════════════════════════════════════════════════════════

  /// Validate a batch of LoRA-generated recipes against
  /// post-bariatric compliance rules.
  /// Returns validation report with pass/fail counts.
  static Future<LoraValidationReport> validateGeneratedRecipes(
    List<LoraGeneratedRecipe> recipes,
  ) async {
    int passed  = 0;
    int failed  = 0;
    final failures = <LoraValidationFailure>[];

    for (final recipe in recipes) {
      final violations = <String>[];

      // Check sodium — post-bariatric limit
      final sodium =
          (recipe.nutrition['sodium'] as num?)?.toDouble() ?? 0;
      if (sodium > 1500) {
        violations.add(
            'Sodium ${sodium.toInt()}mg > 1500mg post-bariatric limit');
      }

      // Check sugar — dumping syndrome prevention
      final sugar =
          (recipe.nutrition['sugar'] as num?)?.toDouble() ?? 0;
      if (sugar > 25) {
        violations.add(
            'Sugar ${sugar.toStringAsFixed(1)}g > 25g limit — '
            'dumping syndrome risk');
      }

      // Check fat
      final fat =
          (recipe.nutrition['fat'] as num?)?.toDouble() ?? 0;
      if (fat > 45) {
        violations.add(
            'Fat ${fat.toStringAsFixed(1)}g > 45g post-bariatric limit');
      }

      // Check health score
      if (recipe.compliance.healthScore < 50) {
        violations.add(
            'Health score ${recipe.compliance.healthScore} < 50 minimum');
      }

      // Check protein — post-bariatric minimum
      final protein =
          (recipe.nutrition['protein'] as num?)?.toDouble() ?? 0;
      if (protein < 15) {
        violations.add(
            'Protein ${protein.toStringAsFixed(1)}g < 15g per serving — '
            'post-bariatric patients need high protein');
      }

      // Check ingredient structure
      final malformedIngredients = recipe.ingredients
          .where((i) =>
              (i['quantity'] as String? ?? '').isEmpty ||
              (i['name'] as String? ?? '').isEmpty)
          .length;
      if (malformedIngredients > 0) {
        violations.add(
            '$malformedIngredients ingredient(s) missing required '
            'quantity/name fields');
      }

      // Check directions format
      if (!recipe.directions.contains('\n') ||
          !RegExp(r'^\d+\.').hasMatch(recipe.directions)) {
        violations.add(
            'Directions not in required "N. step\\n" format');
      }

      // Check required nutrition fields
      const requiredNutritionKeys = [
        'calories', 'fat', 'saturatedFat', 'sodium',
        'carbs', 'sugar', 'protein',
      ];
      for (final key in requiredNutritionKeys) {
        if (!recipe.nutrition.containsKey(key)) {
          violations.add('Missing required nutrition field: $key');
        }
      }

      if (violations.isEmpty) {
        passed++;
      } else {
        failed++;
        failures.add(LoraValidationFailure(
          recipeName: recipe.recipeName,
          violations: violations,
        ));
      }
    }

    return LoraValidationReport(
      totalTested: recipes.length,
      passed:      passed,
      failed:      failed,
      passRate:    recipes.isEmpty ? 0.0 : passed / recipes.length,
      failures:    failures,
    );
  }
}

// ─────────────────────────────────────────────
// VALIDATION REPORT MODELS
// ─────────────────────────────────────────────
class LoraValidationReport {
  final int totalTested;
  final int passed;
  final int failed;
  final double passRate;
  final List<LoraValidationFailure> failures;

  LoraValidationReport({
    required this.totalTested,
    required this.passed,
    required this.failed,
    required this.passRate,
    required this.failures,
  });

  bool get meetsProductionThreshold => passRate >= 0.95;

  String get summary =>
      'LoRA Validation: $passed/$totalTested passed '
      '(${(passRate * 100).toStringAsFixed(1)}%) '
      '${meetsProductionThreshold ? "✅ READY" : "❌ NEEDS WORK"}';

  Map<String, dynamic> toJson() => {
        'total_tested':                totalTested,
        'passed':                      passed,
        'failed':                      failed,
        'pass_rate':                   passRate,
        'meets_production_threshold':  meetsProductionThreshold,
        'failures': failures.map((f) => f.toJson()).toList(),
      };
}

class LoraValidationFailure {
  final String recipeName;
  final List<String> violations;

  LoraValidationFailure({
    required this.recipeName,
    required this.violations,
  });

  Map<String, dynamic> toJson() => {
        'recipe_name': recipeName,
        'violations':  violations,
      };
}