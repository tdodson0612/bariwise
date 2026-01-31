// lib/services/recipe_compliance_service.dart
// Automated compliance checks and admin review actions
// iOS 14 Compatible | Production Ready

import '../models/recipe_submission.dart';
import '../models/draft_recipe.dart';
import '../config/app_config.dart';
import 'database_service_core.dart';
import 'auth_service.dart';

class RecipeComplianceService {
  // ============================================================
  // AUTOMATED COMPLIANCE CHECKS
  // ============================================================

  /// Run all compliance checks on a recipe
  static Future<ComplianceReport> checkCompliance(DraftRecipe recipe) async {
    try {
      final warnings = <String>[];
      final errors = <String>[];

      // 1. Nutrition Check
      final hasNutrition = checkHasCompleteNutrition(recipe);
      if (!hasNutrition) {
        errors.add('Recipe missing complete nutrition data');
      }

      // 2. bari Safety Check
      int? healthScore;
      bool isbariSafe = true;

      if (recipe.totalNutrition != null) {
        healthScore = recipe.healthScore;
        
        if (healthScore < 50) {
          isbariSafe = false;
          warnings.add('Recipe has low health score ($healthScore/100)');
        }

        // Check specific nutrients
        final nutrition = recipe.totalNutrition!;
        if (nutrition.sodium > 2000) {
          warnings.add('Very high sodium content (${nutrition.sodium.toStringAsFixed(0)}mg)');
        }
        if (nutrition.sugar > 50) {
          warnings.add('Very high sugar content (${nutrition.sugar.toStringAsFixed(0)}g)');
        }
        if (nutrition.fat > 50) {
          warnings.add('Very high fat content (${nutrition.fat.toStringAsFixed(0)}g)');
        }
      } else {
        isbariSafe = false;
        warnings.add('Cannot calculate health score - missing nutrition data');
      }

      // 3. Content Appropriateness Check
      final contentOk = checkContentAppropriate(recipe);
      if (!contentOk) {
        if (recipe.title.trim().length < 3) {
          errors.add('Title too short (minimum 3 characters)');
        }
        if (recipe.ingredients.isEmpty) {
          errors.add('No ingredients listed');
        }
        if ((recipe.instructions?.length ?? 0) < 20) {
          errors.add('Instructions too brief (minimum 20 characters)');
        }
      }

      return ComplianceReport(
        hasCompleteNutrition: hasNutrition,
        isbariSafe: isbariSafe,
        contentAppropriate: contentOk,
        healthScore: healthScore,
        warnings: warnings,
        errors: errors,
      );
    } catch (e) {
      AppConfig.debugPrint('❌ Error checking compliance: $e');
      return ComplianceReport(
        hasCompleteNutrition: false,
        isbariSafe: false,
        contentAppropriate: false,
        errors: ['Error running compliance checks: $e'],
      );
    }
  }

  /// Check if recipe has complete nutrition data
  static bool checkHasCompleteNutrition(DraftRecipe recipe) {
    if (recipe.totalNutrition == null) return false;
    
    final nutrition = recipe.totalNutrition!;
    
    // Check if basic nutrition fields are present
    return nutrition.calories > 0 &&
           nutrition.fat >= 0 &&
           nutrition.sodium >= 0 &&
           nutrition.sugar >= 0;
  }

  /// Check if recipe is bari-safe
  static bool checkIsbariSafe(DraftRecipe recipe) {
    if (recipe.totalNutrition == null) return false;
    
    final healthScore = recipe.healthScore;
    return healthScore >= 50; // Minimum acceptable score
  }

  /// Check if content is appropriate
  static bool checkContentAppropriate(DraftRecipe recipe) {
    // Title check
    if (recipe.title.trim().length < 3) return false;
    
    // Ingredients check
    if (recipe.ingredients.isEmpty) return false;
    
    // Instructions check
    if (recipe.instructions == null || recipe.instructions!.trim().length < 20) {
      return false;
    }
    
    // Could add profanity filter here if needed
    
    return true;
  }

  // ============================================================
  // ADMIN ACTIONS
  // ============================================================

  /// Approve a recipe submission
  static Future<void> approveSubmission(
    String submissionId, {
    String? notes,
  }) async {
    try {
      final adminUserId = AuthService.currentUserId;
      if (adminUserId == null) {
        throw Exception('Admin not authenticated');
      }

      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'recipe_submissions',
        filters: {'id': submissionId},
        data: {
          'status': 'approved',
          'reviewed_at': DateTime.now().toIso8601String(),
          'reviewed_by': adminUserId,
          if (notes != null) 'reviewer_notes': notes,
        },
      );

      AppConfig.debugPrint('✅ Recipe approved: $submissionId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error approving recipe: $e');
      throw Exception('Failed to approve recipe: $e');
    }
  }

  /// Reject a recipe submission
  static Future<void> rejectSubmission(
    String submissionId,
    String reason, {
    String? notes,
  }) async {
    try {
      final adminUserId = AuthService.currentUserId;
      if (adminUserId == null) {
        throw Exception('Admin not authenticated');
      }

      if (reason.trim().isEmpty) {
        throw Exception('Rejection reason is required');
      }

      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'recipe_submissions',
        filters: {'id': submissionId},
        data: {
          'status': 'rejected',
          'reviewed_at': DateTime.now().toIso8601String(),
          'reviewed_by': adminUserId,
          'rejection_reason': reason,
          if (notes != null) 'reviewer_notes': notes,
        },
      );

      AppConfig.debugPrint('❌ Recipe rejected: $submissionId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error rejecting recipe: $e');
      throw Exception('Failed to reject recipe: $e');
    }
  }

  /// Get all pending submissions for admin review
  static Future<List<Map<String, dynamic>>> getPendingSubmissions() async {
    try {
      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'recipe_submissions',
        filters: {'status': 'pending'},
        orderBy: 'submitted_at',
        ascending: true, // Oldest first
      );

      if (result == null || (result as List).isEmpty) {
        return [];
      }

      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      AppConfig.debugPrint('❌ Error loading pending submissions: $e');
      throw Exception('Failed to load pending submissions: $e');
    }
  }
}