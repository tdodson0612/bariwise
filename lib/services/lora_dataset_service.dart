// lib/services/lora_dataset_service.dart
// Generates, validates, deduplicates, and exports LoRA training pairs.
//
// LORA_INTEGRATION_POINT: Python pipeline will call the exported JSONL
// files from this service as input to the training loop.
//
// Phase 1 targets:
//   - 1,000 recipe training pairs (Model A)
//   - 500 negative/compliance examples (Model B)
//   - 300 food classifier examples (Model C)

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bari_wise/models/lora_training_pair.dart';
import 'package:bari_wise/models/ingredient_matrix_entry.dart';
import 'package:bari_wise/models/nutrition_info.dart';
import 'package:bari_wise/config/app_config.dart';
import 'database_service_core.dart';

class LoraDatasetService {
  // ── Storage keys ──────────────────────────────────────────────
  static const String _statsKey        = 'lora_dataset_stats';

  // ── Phase targets ─────────────────────────────────────────────
  static const int phase1RecipeTarget     = 1000;
  static const int phase1NegativeTarget   = 500;
  static const int phase1ClassifierTarget = 300;

  // ── Compliance thresholds (mirrors RecipeComplianceService) ───
  static const double _sodiumWarningThreshold = 1500;  // post-bariatric target
  static const double _sugarWarningThreshold  = 25;    // dumping prevention
  static const double _fatWarningThreshold    = 45;    // post-bariatric target
  static const int    _minHealthScore         = 50;

  // ═══════════════════════════════════════════════════════════════
  // SECTION 1 — RECIPE GENERATOR TRAINING PAIRS  (Model A)
  // ═══════════════════════════════════════════════════════════════

  /// Build a positive training pair from an approved community recipe.
  static LoraTrainingPair buildRecipeGeneratorPair({
    required String recipeId,
    required String recipeName,
    required String description,
    required List<Map<String, dynamic>> ingredients,
    required String directions,
    required int servings,
    required NutritionInfo nutrition,
    required String? surgeryType,
  }) {
    final healthScore = nutrition.calculateBariScore(surgeryType: surgeryType);
    final isBariSafe  = healthScore >= _minHealthScore;

    final flags = <String>[];
    if (nutrition.isHighProtein) flags.add('High Protein');
    if (nutrition.isLowCarb)     flags.add('Low Carb');
    if (nutrition.isLowFat)      flags.add('Low Fat');
    if (nutrition.isHighFiber)   flags.add('High Fiber');
    if (nutrition.isLowSodium)   flags.add('Low Sodium');

    final warnings = <String>[];
    if (nutrition.sodium > 800) {
      warnings.add(
          'Moderate sodium (${nutrition.sodium.toStringAsFixed(0)}mg)');
    }
    if (nutrition.sugar > 10) {
      warnings.add(
          'Moderate sugar (${nutrition.sugar.toStringAsFixed(1)}g) — '
          'monitor for dumping syndrome');
    }

    final instruction =
        _buildRecipeInstruction(surgeryType, nutrition, flags);

    return LoraTrainingPair(
      id: recipeId,
      taskType: LoraTaskType.recipeGenerator,
      instruction: instruction,
      input: LoraInput(
        surgeryType: surgeryType,
        constraints: _constraintsFromSurgeryType(surgeryType),
      ),
      output: LoraOutput(
        generatedRecipe: LoraGeneratedRecipe(
          recipeName: recipeName,
          description: description,
          ingredients: ingredients,
          directions: _normalizeDirections(directions),
          servings: servings,
          nutrition: nutrition.toJson(),
          compliance: LoraComplianceSnapshot(
            healthScore: healthScore,
            isBariSafe: isBariSafe,
            dietaryFlags: flags,
            warnings: warnings,
          ),
        ),
      ),
      isNegativeExample: false,
    );
  }

  /// Export all approved recipes from the database as training pairs.
  static Future<List<LoraTrainingPair>>
      exportApprovedRecipesAsTrainingPairs() async {
    final pairs = <LoraTrainingPair>[];
    try {
      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'recipe_submissions',
        filters: {'status': 'approved'},
        orderBy: 'reviewed_at',
        ascending: true,
      );

      if (result == null || (result as List).isEmpty) {
        AppConfig.debugPrint(
            '⚠️ No approved recipes found for export');
        return [];
      }

      for (final row in result) {
        try {
          final submission = row as Map<String, dynamic>;
          final draftId = submission['draft_recipe_id'] as String?;
          if (draftId == null) continue;

          final draftResult = await DatabaseServiceCore.workerQuery(
            action: 'select',
            table: 'draft_recipes',
            filters: {'id': draftId},
            limit: 1,
          );
          if (draftResult == null ||
              (draftResult as List).isEmpty) {
            continue;
          }

          final draft         = draftResult[0] as Map<String, dynamic>;
          final nutritionJson =
              draft['total_nutrition'] as Map<String, dynamic>?;
          if (nutritionJson == null) continue;

          final nutrition       = NutritionInfo.fromDatabaseJson(nutritionJson);
          final ingredientsList = (draft['ingredients'] as List? ?? [])
              .map((e) => {
                    'quantity':    (e['quantity'] as num? ?? 1.0).toString(),
                    'measurement': e['unit'] as String? ?? 'piece',
                    'name':        e['product_name'] as String? ?? '',
                  })
              .toList();

          final pair = buildRecipeGeneratorPair(
            recipeId:    draftId,
            recipeName:  draft['title'] as String? ?? '',
            description: draft['description'] as String? ?? '',
            ingredients: ingredientsList,
            directions:  draft['instructions'] as String? ?? '',
            servings:    draft['servings'] as int? ?? 1,
            nutrition:   nutrition,
            surgeryType: null,
          );
          pairs.add(pair);
        } catch (e) {
          AppConfig.debugPrint('⚠️ Skipping malformed recipe: $e');
        }
      }
      AppConfig.debugPrint(
          '✅ Exported ${pairs.length} recipe training pairs');
    } catch (e) {
      AppConfig.debugPrint('❌ Export failed: $e');
    }
    return pairs;
  }

  // ═══════════════════════════════════════════════════════════════
  // SECTION 2 — COMPLIANCE REVIEWER TRAINING PAIRS  (Model B)
  // ═══════════════════════════════════════════════════════════════

  static LoraTrainingPair buildNegativeCompliancePair({
    required String id,
    required NegativeViolationType violationType,
    required LoraRawRecipe violatingRecipe,
    required LoraRawRecipe correctedRecipe,
    required String correctionNotes,
  }) {
    final errors =
        _buildComplianceErrors(violationType, violatingRecipe);
    final warnings =
        _buildComplianceWarnings(violationType, violatingRecipe);

    return LoraTrainingPair(
      id: id,
      taskType: LoraTaskType.complianceReviewer,
      instruction:
          'Review this recipe for post-bariatric nutrition compliance. '
          'Identify all violations and return the corrected version '
          'with explanation.',
      input: LoraInput(rawRecipe: violatingRecipe),
      output: LoraOutput(
        complianceResult: LoraComplianceResult(
          complianceErrors:   errors,
          complianceWarnings: warnings,
          passedCompliance:   false,
          correctedRecipe:    correctedRecipe,
          correctionNotes:    correctionNotes,
        ),
      ),
      isNegativeExample: true,
    );
  }

  /// Generate the 500 negative example dataset.
  static List<LoraTrainingPair> generateNegativeExamplesDataset() {
    final pairs = <LoraTrainingPair>[];
    pairs.addAll(_generateSodiumViolations());
    pairs.addAll(_generateSugarViolations());
    pairs.addAll(_generateFatViolations());
    pairs.addAll(_generateMissingNutritionExamples());
    pairs.addAll(_generateStructuralErrorExamples());
    AppConfig.debugPrint(
        '✅ Generated ${pairs.length} negative compliance examples');
    return pairs;
  }

  static List<LoraTrainingPair> _generateSodiumViolations() {
    const templates = [
      (
        name: 'Teriyaki Chicken Bowl',
        sodiumMg: 2400.0,
        highSodiumIngredient: 'soy sauce',
        replacement: 'low-sodium soy sauce (1 tbsp)',
        expectedReduction: '2400mg → ~650mg'
      ),
      (
        name: 'Canned Soup Noodle Bowl',
        sodiumMg: 3100.0,
        highSodiumIngredient: 'canned chicken broth',
        replacement: 'low-sodium homemade broth',
        expectedReduction: '3100mg → ~400mg'
      ),
      (
        name: 'Salted Cracker Casserole',
        sodiumMg: 2800.0,
        highSodiumIngredient: 'salted crackers',
        replacement: 'unsalted whole grain crackers',
        expectedReduction: '2800mg → ~500mg'
      ),
      (
        name: 'Processed Sausage Stir-Fry',
        sodiumMg: 2600.0,
        highSodiumIngredient: 'processed sausage',
        replacement: 'lean chicken breast',
        expectedReduction: '2600mg → ~300mg'
      ),
      (
        name: 'Deli Wrap',
        sodiumMg: 2200.0,
        highSodiumIngredient: 'deli turkey',
        replacement: 'fresh roasted chicken',
        expectedReduction: '2200mg → ~400mg'
      ),
    ];

    final pairs = <LoraTrainingPair>[];
    for (int t = 0; t < templates.length; t++) {
      final tmpl = templates[t];
      for (int i = 0; i < 20; i++) {
        final actualSodium = tmpl.sodiumMg + (i * 15);

        final violating = LoraRawRecipe(
          recipeName:  tmpl.name,
          ingredients: [
            {'quantity': '4', 'measurement': 'oz',   'name': 'lean protein'},
            {'quantity': '3', 'measurement': 'tbsp', 'name': tmpl.highSodiumIngredient},
            {'quantity': '1', 'measurement': 'cup',  'name': 'white rice'},
          ],
          directions:
              '1. Prepare protein.\n'
              '2. Add ${tmpl.highSodiumIngredient}.\n'
              '3. Serve over rice.',
          nutrition: {
            'productName':  tmpl.name,
            'calories':     580.0 + (i * 5),
            'fat':          18.0,
            'saturatedFat': 6.0,
            'sodium':       actualSodium,
            'carbs':        55.0,
            'sugar':        12.0,
            'protein':      28.0,
          },
        );

        final corrected = LoraRawRecipe(
          recipeName:  'Reduced-Sodium ${tmpl.name}',
          ingredients: [
            {'quantity': '4', 'measurement': 'oz',   'name': 'lean protein'},
            {'quantity': '1', 'measurement': 'tbsp', 'name': tmpl.replacement},
            {'quantity': '1', 'measurement': 'cup',  'name': 'brown rice'},
            {'quantity': '1', 'measurement': 'cup',  'name': 'steamed broccoli'},
          ],
          directions:
              '1. Prepare protein.\n'
              '2. Add ${tmpl.replacement}.\n'
              '3. Serve over brown rice with broccoli.',
          nutrition: {
            'productName':  'Reduced-Sodium ${tmpl.name}',
            'calories':     420.0,
            'fat':          12.0,
            'saturatedFat': 3.0,
            'sodium':       actualSodium - 1800,
            'carbs':        42.0,
            'fiber':        4.0,
            'sugar':        6.0,
            'protein':      32.0,
          },
        );

        pairs.add(buildNegativeCompliancePair(
          id:               'neg_sodium_${t}_$i',
          violationType:    NegativeViolationType.sodium,
          violatingRecipe:  violating,
          correctedRecipe:  corrected,
          correctionNotes:
              'Sodium exceeded ${_sodiumWarningThreshold.toInt()}mg '
              'post-bariatric limit (actual: ${actualSodium.toInt()}mg). '
              'Replaced ${tmpl.highSodiumIngredient} with ${tmpl.replacement}. '
              'Reduction: ${tmpl.expectedReduction}.',
        ));
      }
    }
    return pairs;
  }

  static List<LoraTrainingPair> _generateSugarViolations() {
    const templates = [
      (
        name: 'Chocolate Brownie Cake',
        sugarG: 85.0,
        highSugarIngredient: 'white sugar',
        replacement: '2 tbsp honey + unsweetened applesauce',
        reduction: '85g → 18g'
      ),
      (
        name: 'Sweetened Granola Bowl',
        sugarG: 62.0,
        highSugarIngredient: 'brown sugar',
        replacement: 'cinnamon + vanilla extract',
        reduction: '62g → 8g'
      ),
      (
        name: 'Fruit Punch Smoothie',
        sugarG: 70.0,
        highSugarIngredient: 'fruit punch mix',
        replacement: 'plain water + fresh lemon',
        reduction: '70g → 12g'
      ),
      (
        name: 'BBQ Glazed Chicken',
        sugarG: 58.0,
        highSugarIngredient: 'bbq sauce',
        replacement: 'sugar-free herb marinade',
        reduction: '58g → 4g'
      ),
      (
        name: 'Sweetened Oatmeal',
        sugarG: 52.0,
        highSugarIngredient: 'flavored oatmeal packet',
        replacement: 'plain rolled oats with cinnamon',
        reduction: '52g → 2g'
      ),
    ];

    final pairs = <LoraTrainingPair>[];
    for (int t = 0; t < templates.length; t++) {
      final tmpl = templates[t];
      for (int i = 0; i < 20; i++) {
        final actualSugar = tmpl.sugarG + (i * 1.5);

        final violating = LoraRawRecipe(
          recipeName:  tmpl.name,
          ingredients: [
            {'quantity': '1', 'measurement': 'cup', 'name': tmpl.highSugarIngredient},
            {'quantity': '2', 'measurement': 'cup', 'name': 'flour'},
          ],
          directions:
              '1. Mix ingredients.\n2. Cook until done.',
          nutrition: {
            'productName':  tmpl.name,
            'calories':     450.0,
            'fat':          12.0,
            'saturatedFat': 4.0,
            'sodium':       180.0,
            'carbs':        88.0,
            'sugar':        actualSugar,
            'protein':      6.0,
          },
        );

        final corrected = LoraRawRecipe(
          recipeName:  'Low-Sugar ${tmpl.name}',
          ingredients: [
            {'quantity': '1', 'measurement': 'tbsp', 'name': tmpl.replacement},
            {'quantity': '2', 'measurement': 'cup',  'name': 'whole wheat flour'},
          ],
          directions:
              '1. Mix ingredients with replacement sweetener.\n'
              '2. Cook until done.',
          nutrition: {
            'productName':  'Low-Sugar ${tmpl.name}',
            'calories':     280.0,
            'fat':          8.0,
            'saturatedFat': 2.0,
            'sodium':       160.0,
            'carbs':        44.0,
            'fiber':        5.0,
            'sugar':        actualSugar - 48.0,
            'protein':      8.0,
          },
        );

        pairs.add(buildNegativeCompliancePair(
          id:               'neg_sugar_${t}_$i',
          violationType:    NegativeViolationType.sugar,
          violatingRecipe:  violating,
          correctedRecipe:  corrected,
          correctionNotes:
              'Sugar exceeded ${_sugarWarningThreshold.toInt()}g '
              'post-bariatric limit (actual: ${actualSugar.toStringAsFixed(1)}g). '
              'High sugar triggers dumping syndrome in bypass/sleeve patients. '
              'Replaced ${tmpl.highSugarIngredient} with ${tmpl.replacement}. '
              'Reduction: ${tmpl.reduction}.',
        ));
      }
    }
    return pairs;
  }

  static List<LoraTrainingPair> _generateFatViolations() {
    const templates = [
      (
        name: 'Deep-Fried Chicken',
        fatG: 65.0,
        issue: 'deep frying',
        fix: 'oven-baked with light olive oil spray'
      ),
      (
        name: 'Creamy Alfredo Pasta',
        fatG: 58.0,
        issue: 'heavy cream and butter',
        fix: 'pureed cauliflower cream sauce'
      ),
      (
        name: 'Bacon Cheeseburger',
        fatG: 72.0,
        issue: 'bacon and full-fat cheese',
        fix: 'lean turkey patty with avocado'
      ),
      (
        name: 'Butter-Basted Steak',
        fatG: 55.0,
        issue: 'butter basting',
        fix: 'herb-crusted lean sirloin, no butter'
      ),
      (
        name: 'Full-Fat Cheese Quesadilla',
        fatG: 60.0,
        issue: 'full-fat cheddar',
        fix: 'reduced-fat cheese + extra vegetables'
      ),
    ];

    final pairs = <LoraTrainingPair>[];
    for (int t = 0; t < templates.length; t++) {
      final tmpl = templates[t];
      for (int i = 0; i < 20; i++) {
        final actualFat = tmpl.fatG + (i * 0.8);

        final violating = LoraRawRecipe(
          recipeName:  tmpl.name,
          ingredients: [
            {'quantity': '6', 'measurement': 'oz',   'name': 'main protein'},
            {'quantity': '4', 'measurement': 'tbsp', 'name': 'butter'},
          ],
          directions:
              '1. Prepare with ${tmpl.issue}.\n2. Serve hot.',
          nutrition: {
            'productName':  tmpl.name,
            'calories':     680.0,
            'fat':          actualFat,
            'saturatedFat': actualFat * 0.4,
            'sodium':       580.0,
            'carbs':        28.0,
            'sugar':        4.0,
            'protein':      34.0,
          },
        );

        final corrected = LoraRawRecipe(
          recipeName:  'Bari-Friendly ${tmpl.name}',
          ingredients: [
            {'quantity': '6', 'measurement': 'oz',  'name': 'lean protein'},
            {'quantity': '1', 'measurement': 'tsp', 'name': 'olive oil'},
            {'quantity': '1', 'measurement': 'cup', 'name': 'steamed vegetables'},
          ],
          directions:
              '1. Prepare using ${tmpl.fix}.\n'
              '2. Serve with steamed vegetables.\n'
              '3. Eat protein portion first.',
          nutrition: {
            'productName':  'Bari-Friendly ${tmpl.name}',
            'calories':     380.0,
            'fat':          14.0,
            'saturatedFat': 3.0,
            'sodium':       320.0,
            'carbs':        20.0,
            'fiber':        4.0,
            'sugar':        4.0,
            'protein':      38.0,
          },
        );

        pairs.add(buildNegativeCompliancePair(
          id:               'neg_fat_${t}_$i',
          violationType:    NegativeViolationType.fat,
          violatingRecipe:  violating,
          correctedRecipe:  corrected,
          correctionNotes:
              'Fat exceeded ${_fatWarningThreshold.toInt()}g '
              'post-bariatric limit (actual: ${actualFat.toStringAsFixed(1)}g). '
              'High fat intake can cause nausea and malabsorption post-surgery. '
              'Issue: ${tmpl.issue}. Fix: ${tmpl.fix}.',
        ));
      }
    }
    return pairs;
  }

  static List<LoraTrainingPair> _generateMissingNutritionExamples() {
    final pairs      = <LoraTrainingPair>[];
    final recipeNames = [
      'Protein Power Bowl',
      'Grilled Fish Tacos',
      'Lentil Curry',
      'Chicken Stir-Fry',
      'Greek Yogurt Parfait',
    ];

    for (int t = 0; t < recipeNames.length; t++) {
      for (int i = 0; i < 20; i++) {
        final name = recipeNames[t];

        final violating = LoraRawRecipe(
          recipeName:  name,
          ingredients: [
            {'quantity': '1', 'measurement': 'cup', 'name': 'main ingredient'},
          ],
          directions: '1. Prepare.\n2. Serve.',
          nutrition:  null,
        );

        final corrected = LoraRawRecipe(
          recipeName:  name,
          ingredients: [
            {'quantity': '1', 'measurement': 'cup', 'name': 'main ingredient'},
          ],
          directions: '1. Prepare.\n2. Serve.',
          nutrition:  {
            'productName':  name,
            'calories':     280.0 + (i * 10),
            'fat':          8.0,
            'saturatedFat': 2.0,
            'sodium':       240.0,
            'carbs':        18.0,
            'fiber':        4.0,
            'sugar':        4.0,
            'protein':      28.0,
          },
        );

        pairs.add(buildNegativeCompliancePair(
          id:               'neg_nutrition_${t}_$i',
          violationType:    NegativeViolationType.missingNutrition,
          violatingRecipe:  violating,
          correctedRecipe:  corrected,
          correctionNotes:
              'Recipe missing required nutrition data. '
              'RecipeComplianceService.checkHasCompleteNutrition() returns '
              'false when totalNutrition is null. Nutrition must include '
              'calories, fat, sodium, sugar, and protein — especially '
              'important for post-bariatric patients tracking protein intake.',
        ));
      }
    }
    return pairs;
  }

  static List<LoraTrainingPair> _generateStructuralErrorExamples() {
    final pairs = <LoraTrainingPair>[];

    // 50 pairs: free-text ingredients instead of structured objects
    for (int i = 0; i < 50; i++) {
      final violating = LoraRawRecipe(
        recipeName:  'Protein Pasta Dish $i',
        ingredients: [
          {
            'quantity':    '',
            'measurement': '',
            'name':
                '2 cups chickpea pasta, 1 tbsp olive oil, 1 clove garlic',
          },
        ],
        directions: 'Cook everything together.',
        nutrition: {
          'productName':  'Protein Pasta Dish $i',
          'calories':     350.0,
          'fat':          8.0,
          'saturatedFat': 1.5,
          'sodium':       180.0,
          'carbs':        40.0,
          'sugar':        3.0,
          'protein':      18.0,
        },
      );

      final corrected = LoraRawRecipe(
        recipeName:  'Protein Pasta Dish $i',
        ingredients: [
          {'quantity': '2', 'measurement': 'cups', 'name': 'chickpea pasta'},
          {'quantity': '1', 'measurement': 'tbsp', 'name': 'olive oil'},
          {'quantity': '1', 'measurement': 'piece', 'name': 'garlic clove'},
        ],
        directions:
            '1. Cook chickpea pasta according to package directions.\n'
            '2. Heat olive oil in pan.\n'
            '3. Add minced garlic and sauté 1 minute.\n'
            '4. Toss with cooked pasta.\n'
            '5. Eat protein-rich pasta first before any sides.',
        nutrition: {
          'productName':  'Protein Pasta Dish $i',
          'calories':     350.0,
          'fat':          8.0,
          'saturatedFat': 1.5,
          'sodium':       180.0,
          'carbs':        40.0,
          'sugar':        3.0,
          'protein':      18.0,
        },
      );

      pairs.add(buildNegativeCompliancePair(
        id:               'neg_struct_ingredients_$i',
        violationType:    NegativeViolationType.structuralError,
        violatingRecipe:  violating,
        correctedRecipe:  corrected,
        correctionNotes:
            'Ingredients must be a JSON array of objects with keys: '
            '"quantity" (string), "measurement" (string), "name" (string). '
            'Free-text combined strings break IngredientRow.fromJson() '
            'deserialization.',
      ));
    }

    // 50 pairs: directions without step numbers
    for (int i = 0; i < 50; i++) {
      final violating = LoraRawRecipe(
        recipeName:  'Protein Soup $i',
        ingredients: [
          {'quantity': '2', 'measurement': 'cups', 'name': 'vegetable broth'},
          {'quantity': '1', 'measurement': 'cup',  'name': 'lentils'},
        ],
        directions:
            'Boil the broth add lentils cook for 20 minutes '
            'season with herbs serve hot',
        nutrition: {
          'productName':  'Protein Soup $i',
          'calories':     220.0,
          'fat':          2.0,
          'saturatedFat': 0.5,
          'sodium':       380.0,
          'carbs':        28.0,
          'fiber':        8.0,
          'sugar':        4.0,
          'protein':      14.0,
        },
      );

      final corrected = LoraRawRecipe(
        recipeName:  'Protein Soup $i',
        ingredients: [
          {'quantity': '2', 'measurement': 'cups', 'name': 'vegetable broth'},
          {'quantity': '1', 'measurement': 'cup',  'name': 'lentils'},
        ],
        directions:
            '1. Bring vegetable broth to a boil in a medium pot.\n'
            '2. Add lentils and reduce heat to medium.\n'
            '3. Cook for 20 minutes until lentils are tender.\n'
            '4. Season with herbs and spices to taste.\n'
            '5. Serve hot — sip broth slowly to avoid overfilling the pouch.',
        nutrition: {
          'productName':  'Protein Soup $i',
          'calories':     220.0,
          'fat':          2.0,
          'saturatedFat': 0.5,
          'sodium':       380.0,
          'carbs':        28.0,
          'fiber':        8.0,
          'sugar':        4.0,
          'protein':      14.0,
        },
      );

      pairs.add(buildNegativeCompliancePair(
        id:               'neg_struct_directions_$i',
        violationType:    NegativeViolationType.structuralError,
        violatingRecipe:  violating,
        correctedRecipe:  corrected,
        correctionNotes:
            'Directions must use \\n as step separator and each step '
            'must start with "N. " format. This matches how '
            'RecipeDetailPage renders Text(widget.directions).',
      ));
    }

    return pairs;
  }

  // ═══════════════════════════════════════════════════════════════
  // SECTION 3 — FOOD CLASSIFIER TRAINING PAIRS  (Model C)
  // ═══════════════════════════════════════════════════════════════

  static List<LoraTrainingPair> generateClassifierDataset() {
    final pairs = <LoraTrainingPair>[];

    for (final entry in IngredientMatrix.entries) {
      pairs.add(_buildClassifierPair(
        word:        entry.name,
        isFood:      true,
        category:    entry.category.name,
        bariFlags:   entry.bariFlags,
        preferredFor: entry.preferredFor,
      ));
      for (final alias in entry.aliases) {
        pairs.add(_buildClassifierPair(
          word:        alias,
          isFood:      true,
          category:    entry.category.name,
          bariFlags:   entry.bariFlags,
          preferredFor: entry.preferredFor,
        ));
      }
    }

    const knownNonFoodWords = [
      'oz', 'ounce', 'ounces', 'lb', 'lbs', 'pound', 'pounds',
      'kg', 'gram', 'grams', 'g', 'ml', 'liter', 'liters', 'cup', 'cups',
      'tbsp', 'tsp', 'tablespoon', 'teaspoon', 'can', 'jar', 'bottle', 'box',
      'organic', 'natural', 'fresh', 'frozen', 'dried', 'raw', 'cooked',
      'whole', 'sliced', 'diced', 'chopped', 'minced', 'crushed', 'ground',
      'reduced', 'low', 'high', 'free', 'light', 'lite', 'extra', 'pure',
      'premium', 'grade', 'style', 'flavored', 'seasoned', 'unseasoned',
      'salted', 'unsalted', 'sweetened', 'unsweetened', 'plain', 'original',
    ];

    for (final word in knownNonFoodWords) {
      pairs.add(_buildClassifierPair(
        word:        word,
        isFood:      false,
        category:    'measurement_or_modifier',
        bariFlags:   [],
        preferredFor: [],
      ));
    }

    AppConfig.debugPrint(
        '✅ Generated ${pairs.length} classifier training pairs');
    return pairs;
  }

  static LoraTrainingPair _buildClassifierPair({
    required String word,
    required bool isFood,
    required String category,
    required List<String> bariFlags,
    required List<String> preferredFor,
  }) {
    return LoraTrainingPair(
      id: 'classifier_${word.replaceAll(' ', '_')}',
      taskType: LoraTaskType.foodClassifier,
      instruction:
          'Classify the following word. Return whether it is a food '
          'ingredient, its category, bariatric health flags, and '
          'confidence score.',
      input: LoraInput(word: word),
      output: LoraOutput(
        classificationResult: LoraClassificationResult(
          isFood:      isFood,
          category:    category,
          confidence:  0.98,
          bariFlags:   bariFlags,
          preferredFor: preferredFor,
        ),
      ),
      isNegativeExample: !isFood,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SECTION 4 — EXPORT & DEDUPLICATION
  // ═══════════════════════════════════════════════════════════════

  static Map<String, String> exportToJsonl(List<LoraTrainingPair> pairs) {
    final recipeLines     = <String>[];
    final complianceLines = <String>[];
    final classifierLines = <String>[];

    for (final pair in pairs) {
      final line = pair.toJsonLine();
      switch (pair.taskType) {
        case LoraTaskType.recipeGenerator:
          recipeLines.add(line);
          break;
        case LoraTaskType.complianceReviewer:
          complianceLines.add(line);
          break;
        case LoraTaskType.foodClassifier:
          classifierLines.add(line);
          break;
      }
    }

    return {
      'lora_recipes_v1.jsonl':    recipeLines.join('\n'),
      'lora_compliance_v1.jsonl': complianceLines.join('\n'),
      'lora_classifier_v1.jsonl': classifierLines.join('\n'),
    };
  }

  static List<LoraTrainingPair> deduplicate(
      List<LoraTrainingPair> pairs) {
    final seen   = <String>{};
    final deduped = <LoraTrainingPair>[];

    for (final pair in pairs) {
      final key = _buildDeduplicationKey(pair);
      if (!seen.contains(key)) {
        seen.add(key);
        deduped.add(pair);
      }
    }

    final removed = pairs.length - deduped.length;
    if (removed > 0) {
      AppConfig.debugPrint(
          '🧹 Deduplication removed $removed duplicate pairs');
    }
    return deduped;
  }

  static String _buildDeduplicationKey(LoraTrainingPair pair) {
    if (pair.taskType == LoraTaskType.recipeGenerator &&
        pair.output.generatedRecipe != null) {
      final recipe           = pair.output.generatedRecipe!;
      final sortedIngredients = recipe.ingredients
          .map((i) => (i['name'] as String? ?? '').toLowerCase().trim())
          .where((n) => n.isNotEmpty)
          .toList()
        ..sort();
      return '${pair.taskType.name}_'
          '${recipe.recipeName.toLowerCase()}_'
          '${sortedIngredients.join("_")}';
    }
    if (pair.taskType == LoraTaskType.foodClassifier &&
        pair.input.word != null) {
      return '${pair.taskType.name}_${pair.input.word!.toLowerCase()}';
    }
    return '${pair.taskType.name}_${pair.id}';
  }

  static Future<Map<String, dynamic>> getDatasetStats() async {
    try {
      final prefs     = await SharedPreferences.getInstance();
      final statsJson = prefs.getString(_statsKey);
      if (statsJson != null) {
        return Map<String, dynamic>.from(
            jsonDecode(statsJson) as Map);
      }
    } catch (_) {}

    return {
      'recipe_pairs':              0,
      'negative_pairs':            0,
      'classifier_pairs':          0,
      'total_pairs':               0,
      'phase1_recipe_target':      phase1RecipeTarget,
      'phase1_negative_target':    phase1NegativeTarget,
      'phase1_classifier_target':  phase1ClassifierTarget,
    };
  }

  static Future<void> saveDatasetStats(
      List<LoraTrainingPair> pairs) async {
    final stats = {
      'recipe_pairs': pairs
          .where((p) => p.taskType == LoraTaskType.recipeGenerator)
          .length,
      'negative_pairs': pairs
          .where((p) =>
              p.taskType == LoraTaskType.complianceReviewer &&
              p.isNegativeExample)
          .length,
      'classifier_pairs': pairs
          .where((p) => p.taskType == LoraTaskType.foodClassifier)
          .length,
      'total_pairs':              pairs.length,
      'phase1_recipe_target':     phase1RecipeTarget,
      'phase1_negative_target':   phase1NegativeTarget,
      'phase1_classifier_target': phase1ClassifierTarget,
      'last_updated':             DateTime.now().toIso8601String(),
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_statsKey, jsonEncode(stats));
  }

  // ═══════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ═══════════════════════════════════════════════════════════════

  static String _buildRecipeInstruction(
    String? surgeryType,
    NutritionInfo nutrition,
    List<String> flags,
  ) {
    final buffer = StringBuffer(
        'Generate a bariatric-safe, high-protein recipe');
    if (surgeryType != null &&
        surgeryType != 'Other (default scoring)') {
      buffer.write(' suitable for a patient who has had $surgeryType');
    }
    if (flags.isNotEmpty) {
      buffer.write('. Requirements: ${flags.join(", ")}');
    }
    buffer.write(
        '. Protein should be eaten first. Provide complete structured '
        'ingredients (quantity, measurement, name), numbered directions, '
        'and full nutrition data.');
    return buffer.toString();
  }

  static LoraConstraints? _constraintsFromSurgeryType(
      String? surgeryType) {
    if (surgeryType == null) return LoraConstraints.bariSafe;
    switch (surgeryType) {
      case 'gastric_bypass':
        return const LoraConstraints(
          maxSodiumMg:    1200,
          maxSugarG:      15,
          maxFatG:        30,
          minProteinG:    60,
          minHealthScore: 65,
        );
      case 'sleeve':
        return const LoraConstraints(
          maxSodiumMg:    1500,
          maxSugarG:      20,
          maxFatG:        40,
          minProteinG:    60,
          minHealthScore: 60,
        );
      case 'lap_band':
        return const LoraConstraints(
          maxSodiumMg:    1500,
          maxSugarG:      25,
          maxFatG:        45,
          minProteinG:    60,
          minHealthScore: 55,
          requireHighFiber: false, // fibrous foods can cause obstruction
        );
      case 'revision':
        return const LoraConstraints(
          maxSodiumMg:    1000,
          maxSugarG:      10,
          maxFatG:        25,
          minProteinG:    70,
          minHealthScore: 70,
        );
      default:
        return LoraConstraints.bariSafe;
    }
  }

  static List<String> _buildComplianceErrors(
    NegativeViolationType type,
    LoraRawRecipe recipe,
  ) {
    switch (type) {
      case NegativeViolationType.sodium:
        final sodium =
            (recipe.nutrition?['sodium'] as num?)?.toDouble() ?? 0;
        return [
          'Sodium ${sodium.toInt()}mg exceeds '
              '${_sodiumWarningThreshold.toInt()}mg post-bariatric limit '
              '(RecipeComplianceService threshold)',
        ];
      case NegativeViolationType.sugar:
        final sugar =
            (recipe.nutrition?['sugar'] as num?)?.toDouble() ?? 0;
        return [
          'Sugar ${sugar.toStringAsFixed(1)}g exceeds '
              '${_sugarWarningThreshold.toInt()}g limit — '
              'dumping syndrome risk for bypass/sleeve patients',
        ];
      case NegativeViolationType.fat:
        final fat =
            (recipe.nutrition?['fat'] as num?)?.toDouble() ?? 0;
        return [
          'Fat ${fat.toStringAsFixed(1)}g exceeds '
              '${_fatWarningThreshold.toInt()}g post-bariatric limit',
        ];
      case NegativeViolationType.missingNutrition:
        return [
          'Recipe missing complete nutrition data — '
              'checkHasCompleteNutrition() returns false'
        ];
      case NegativeViolationType.structuralError:
        return ['Structural formatting error in recipe data'];
    }
  }

  static List<String> _buildComplianceWarnings(
    NegativeViolationType type,
    LoraRawRecipe recipe,
  ) {
    final healthScore =
        recipe.parsedNutrition?.calculateBariScore() ?? 0;
    final warnings = <String>[];
    if (healthScore < _minHealthScore) {
      warnings.add(
          'Health score $healthScore/100 below minimum '
          'threshold of $_minHealthScore');
    }
    return warnings;
  }

  static String _normalizeDirections(String raw) {
    if (raw.isEmpty) return raw;
    if (RegExp(r'^\d+\.\s').hasMatch(raw)) return raw;
    final steps = raw
        .split(RegExp(r'\n|\r\n|\.\s+(?=\S)'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return steps
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value}')
        .join('\n');
  }
}

// ─────────────────────────────────────────────
// VIOLATION TYPE ENUM
// ─────────────────────────────────────────────
enum NegativeViolationType {
  sodium,
  sugar,
  fat,
  missingNutrition,
  structuralError,
}