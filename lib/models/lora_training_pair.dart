// lib/models/lora_training_pair.dart
// Canonical training pair model for LoRA dataset generation.
// Every field maps exactly to existing models:
//   - ingredients  → IngredientRow / RecipeIngredient
//   - nutrition    → NutritionInfo.fromDatabaseJson() keys (camelCase)
//   - compliance   → ComplianceReport fields
// DO NOT change field names — downstream JSON must match these exactly.

import 'dart:convert';
import 'package:bari_wise/models/nutrition_info.dart';
import 'package:bari_wise/models/recipe_submission.dart';

// ─────────────────────────────────────────────
// TRAINING PAIR  (instruction → output)
// ─────────────────────────────────────────────
class LoraTrainingPair {
  final String id;
  final LoraTaskType taskType;
  final String instruction;
  final LoraInput input;
  final LoraOutput output;
  final String datasetVersion;
  final DateTime createdAt;
  final bool isNegativeExample;

  LoraTrainingPair({
    required this.id,
    required this.taskType,
    required this.instruction,
    required this.input,
    required this.output,
    this.datasetVersion = 'v1.0',
    DateTime? createdAt,
    this.isNegativeExample = false,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'task_type': taskType.name,
        'instruction': instruction,
        'input': input.toJson(),
        'output': output.toJson(),
        'dataset_version': datasetVersion,
        'created_at': createdAt.toIso8601String(),
        'is_negative_example': isNegativeExample,
      };

  factory LoraTrainingPair.fromJson(Map<String, dynamic> json) =>
      LoraTrainingPair(
        id: json['id'] as String,
        taskType: LoraTaskType.values.byName(json['task_type'] as String),
        instruction: json['instruction'] as String,
        input: LoraInput.fromJson(json['input'] as Map<String, dynamic>),
        output: LoraOutput.fromJson(json['output'] as Map<String, dynamic>),
        datasetVersion: json['dataset_version'] as String? ?? 'v1.0',
        createdAt: DateTime.parse(json['created_at'] as String),
        isNegativeExample: json['is_negative_example'] as bool? ?? false,
      );

  String toJsonLine() => jsonEncode(toJson());
}

// ─────────────────────────────────────────────
// TASK TYPE
// ─────────────────────────────────────────────
enum LoraTaskType {
  recipeGenerator,
  complianceReviewer,
  foodClassifier,
}

// ─────────────────────────────────────────────
// INPUT
// ─────────────────────────────────────────────
class LoraInput {
  final String? surgeryType;         // e.g. "gastric_bypass" | "sleeve" | null
  final LoraConstraints? constraints;
  final List<String>? availableIngredients;
  final LoraRawRecipe? rawRecipe;
  final String? word;

  LoraInput({
    this.surgeryType,
    this.constraints,
    this.availableIngredients,
    this.rawRecipe,
    this.word,
  });

  Map<String, dynamic> toJson() => {
        if (surgeryType != null) 'surgery_type': surgeryType,
        if (constraints != null) 'constraints': constraints!.toJson(),
        if (availableIngredients != null)
          'available_ingredients': availableIngredients,
        if (rawRecipe != null) 'raw_recipe': rawRecipe!.toJson(),
        if (word != null) 'word': word,
      };

  factory LoraInput.fromJson(Map<String, dynamic> json) => LoraInput(
        surgeryType: json['surgery_type'] as String?,
        constraints: json['constraints'] != null
            ? LoraConstraints.fromJson(
                json['constraints'] as Map<String, dynamic>)
            : null,
        availableIngredients:
            (json['available_ingredients'] as List?)?.cast<String>(),
        rawRecipe: json['raw_recipe'] != null
            ? LoraRawRecipe.fromJson(
                json['raw_recipe'] as Map<String, dynamic>)
            : null,
        word: json['word'] as String?,
      );
}

// ─────────────────────────────────────────────
// CONSTRAINTS
// ─────────────────────────────────────────────
class LoraConstraints {
  final double? maxSodiumMg;
  final double? maxSugarG;
  final double? maxFatG;
  final double? minProteinG;
  final int? minHealthScore;
  final int? maxCalories;
  final bool? requireHighFiber;

  const LoraConstraints({
    this.maxSodiumMg,
    this.maxSugarG,
    this.maxFatG,
    this.minProteinG,
    this.minHealthScore,
    this.maxCalories,
    this.requireHighFiber,
  });

  Map<String, dynamic> toJson() => {
        if (maxSodiumMg != null) 'max_sodium_mg': maxSodiumMg,
        if (maxSugarG != null) 'max_sugar_g': maxSugarG,
        if (maxFatG != null) 'max_fat_g': maxFatG,
        if (minProteinG != null) 'min_protein_g': minProteinG,
        if (minHealthScore != null) 'min_health_score': minHealthScore,
        if (maxCalories != null) 'max_calories': maxCalories,
        if (requireHighFiber != null) 'require_high_fiber': requireHighFiber,
      };

  factory LoraConstraints.fromJson(Map<String, dynamic> json) =>
      LoraConstraints(
        maxSodiumMg: (json['max_sodium_mg'] as num?)?.toDouble(),
        maxSugarG: (json['max_sugar_g'] as num?)?.toDouble(),
        maxFatG: (json['max_fat_g'] as num?)?.toDouble(),
        minProteinG: (json['min_protein_g'] as num?)?.toDouble(),
        minHealthScore: json['min_health_score'] as int?,
        maxCalories: json['max_calories'] as int?,
        requireHighFiber: json['require_high_fiber'] as bool?,
      );

  /// Post-bariatric baseline: safe macros for all surgery types
  static const LoraConstraints bariSafe = LoraConstraints(
    maxSodiumMg: 1500,
    maxSugarG: 25,
    maxFatG: 45,
    minProteinG: 60,
    minHealthScore: 50,
  );

  /// Strict: early post-op or dumping-syndrome-prone patients
  static const LoraConstraints strict = LoraConstraints(
    maxSodiumMg: 800,
    maxSugarG: 10,
    maxFatG: 20,
    minProteinG: 70,
    minHealthScore: 70,
    requireHighFiber: true,
  );
}

// ─────────────────────────────────────────────
// RAW RECIPE
// ─────────────────────────────────────────────
class LoraRawRecipe {
  final String recipeName;
  final List<Map<String, dynamic>> ingredients;
  final String directions;
  final String? description;
  final Map<String, dynamic>? nutrition;

  LoraRawRecipe({
    required this.recipeName,
    required this.ingredients,
    required this.directions,
    this.description,
    this.nutrition,
  });

  Map<String, dynamic> toJson() => {
        'recipe_name': recipeName,
        'ingredients': ingredients,
        'directions': directions,
        if (description != null) 'description': description,
        if (nutrition != null) 'nutrition': nutrition,
      };

  factory LoraRawRecipe.fromJson(Map<String, dynamic> json) => LoraRawRecipe(
        recipeName: json['recipe_name'] as String,
        ingredients: (json['ingredients'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        directions: json['directions'] as String,
        description: json['description'] as String?,
        nutrition: json['nutrition'] != null
            ? Map<String, dynamic>.from(json['nutrition'] as Map)
            : null,
      );

  String get ingredientsAsPlainText {
    return ingredients
        .where((i) =>
            (i['quantity'] as String? ?? '').isNotEmpty &&
            (i['name'] as String? ?? '').isNotEmpty)
        .map((i) {
          final qty = i['quantity'] as String? ?? '';
          final meas = i['measurement'] == 'other'
              ? (i['customMeasurement'] as String? ?? '')
              : (i['measurement'] as String? ?? '');
          final name = i['name'] as String? ?? '';
          return '$qty $meas $name'.trim();
        })
        .join('\n');
  }

  NutritionInfo? get parsedNutrition {
    if (nutrition == null) return null;
    try {
      return NutritionInfo.fromDatabaseJson(nutrition!);
    } catch (_) {
      return null;
    }
  }
}

// ─────────────────────────────────────────────
// OUTPUT
// ─────────────────────────────────────────────
class LoraOutput {
  final LoraGeneratedRecipe? generatedRecipe;
  final LoraComplianceResult? complianceResult;
  final LoraClassificationResult? classificationResult;

  LoraOutput({
    this.generatedRecipe,
    this.complianceResult,
    this.classificationResult,
  });

  Map<String, dynamic> toJson() => {
        if (generatedRecipe != null)
          'generated_recipe': generatedRecipe!.toJson(),
        if (complianceResult != null)
          'compliance_result': complianceResult!.toJson(),
        if (classificationResult != null)
          'classification_result': classificationResult!.toJson(),
      };

  factory LoraOutput.fromJson(Map<String, dynamic> json) => LoraOutput(
        generatedRecipe: json['generated_recipe'] != null
            ? LoraGeneratedRecipe.fromJson(
                json['generated_recipe'] as Map<String, dynamic>)
            : null,
        complianceResult: json['compliance_result'] != null
            ? LoraComplianceResult.fromJson(
                json['compliance_result'] as Map<String, dynamic>)
            : null,
        classificationResult: json['classification_result'] != null
            ? LoraClassificationResult.fromJson(
                json['classification_result'] as Map<String, dynamic>)
            : null,
      );
}

// ─────────────────────────────────────────────
// GENERATED RECIPE OUTPUT
// ─────────────────────────────────────────────
class LoraGeneratedRecipe {
  final String recipeName;
  final String description;
  final List<Map<String, dynamic>> ingredients;
  final String directions;
  final int servings;
  final Map<String, dynamic> nutrition;
  final LoraComplianceSnapshot compliance;

  LoraGeneratedRecipe({
    required this.recipeName,
    required this.description,
    required this.ingredients,
    required this.directions,
    required this.servings,
    required this.nutrition,
    required this.compliance,
  });

  Map<String, dynamic> toJson() => {
        'recipe_name': recipeName,
        'description': description,
        'ingredients': ingredients,
        'directions': directions,
        'servings': servings,
        'nutrition': nutrition,
        'compliance': compliance.toJson(),
      };

  factory LoraGeneratedRecipe.fromJson(Map<String, dynamic> json) =>
      LoraGeneratedRecipe(
        recipeName: json['recipe_name'] as String,
        description: json['description'] as String,
        ingredients: (json['ingredients'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        directions: json['directions'] as String,
        servings: json['servings'] as int,
        nutrition: Map<String, dynamic>.from(json['nutrition'] as Map),
        compliance: LoraComplianceSnapshot.fromJson(
            json['compliance'] as Map<String, dynamic>),
      );

  NutritionInfo get nutritionInfo => NutritionInfo.fromDatabaseJson(nutrition);

  String get ingredientsPlainText {
    return ingredients
        .where((i) =>
            (i['quantity'] as String? ?? '').isNotEmpty &&
            (i['name'] as String? ?? '').isNotEmpty)
        .map((i) {
          final qty = i['quantity'] as String? ?? '';
          final meas = i['measurement'] == 'other'
              ? (i['customMeasurement'] as String? ?? '')
              : (i['measurement'] as String? ?? '');
          final name = i['name'] as String? ?? '';
          return '$qty $meas $name'.trim();
        })
        .join('\n');
  }
}

// ─────────────────────────────────────────────
// COMPLIANCE SNAPSHOT
// ─────────────────────────────────────────────
class LoraComplianceSnapshot {
  final int healthScore;
  final bool isBariSafe;             // renamed from isLiverSafe
  final List<String> dietaryFlags;
  final List<String> warnings;

  LoraComplianceSnapshot({
    required this.healthScore,
    required this.isBariSafe,
    this.dietaryFlags = const [],
    this.warnings = const [],
  });

  Map<String, dynamic> toJson() => {
        'health_score': healthScore,
        'is_bari_safe': isBariSafe,
        'dietary_flags': dietaryFlags,
        'warnings': warnings,
      };

  factory LoraComplianceSnapshot.fromJson(Map<String, dynamic> json) =>
      LoraComplianceSnapshot(
        healthScore: json['health_score'] as int,
        isBariSafe: (json['is_bari_safe'] ?? json['is_liver_safe']) as bool,
        dietaryFlags:
            (json['dietary_flags'] as List?)?.cast<String>() ?? [],
        warnings: (json['warnings'] as List?)?.cast<String>() ?? [],
      );

  ComplianceReport toComplianceReport() => ComplianceReport(
        hasCompleteNutrition: true,
        isbariSafe: isBariSafe,
        contentAppropriate: true,
        healthScore: healthScore,
        warnings: warnings,
        errors: [],
      );
}

// ─────────────────────────────────────────────
// COMPLIANCE RESULT
// ─────────────────────────────────────────────
class LoraComplianceResult {
  final List<String> complianceErrors;
  final List<String> complianceWarnings;
  final bool passedCompliance;
  final LoraRawRecipe? correctedRecipe;
  final String? correctionNotes;

  LoraComplianceResult({
    required this.complianceErrors,
    required this.complianceWarnings,
    required this.passedCompliance,
    this.correctedRecipe,
    this.correctionNotes,
  });

  Map<String, dynamic> toJson() => {
        'compliance_errors': complianceErrors,
        'compliance_warnings': complianceWarnings,
        'passed_compliance': passedCompliance,
        if (correctedRecipe != null)
          'corrected_recipe': correctedRecipe!.toJson(),
        if (correctionNotes != null) 'correction_notes': correctionNotes,
      };

  factory LoraComplianceResult.fromJson(Map<String, dynamic> json) =>
      LoraComplianceResult(
        complianceErrors:
            (json['compliance_errors'] as List?)?.cast<String>() ?? [],
        complianceWarnings:
            (json['compliance_warnings'] as List?)?.cast<String>() ?? [],
        passedCompliance: json['passed_compliance'] as bool,
        correctedRecipe: json['corrected_recipe'] != null
            ? LoraRawRecipe.fromJson(
                json['corrected_recipe'] as Map<String, dynamic>)
            : null,
        correctionNotes: json['correction_notes'] as String?,
      );
}

// ─────────────────────────────────────────────
// CLASSIFICATION RESULT
// ─────────────────────────────────────────────
class LoraClassificationResult {
  final bool isFood;
  final String category;
  final double confidence;
  final List<String> bariFlags;      // renamed from liverFlags
  final List<String> preferredFor;

  LoraClassificationResult({
    required this.isFood,
    required this.category,
    required this.confidence,
    this.bariFlags = const [],
    this.preferredFor = const [],
  });

  Map<String, dynamic> toJson() => {
        'is_food': isFood,
        'category': category,
        'confidence': confidence,
        'bari_flags': bariFlags,
        'preferred_for': preferredFor,
      };

  factory LoraClassificationResult.fromJson(Map<String, dynamic> json) =>
      LoraClassificationResult(
        isFood: json['is_food'] as bool,
        category: json['category'] as String,
        confidence: (json['confidence'] as num).toDouble(),
        bariFlags: ((json['bari_flags'] ?? json['liver_flags']) as List?)
                ?.cast<String>() ??
            [],
        preferredFor:
            (json['preferred_for'] as List?)?.cast<String>() ?? [],
      );
}