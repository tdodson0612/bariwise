// lib/services/submitted_recipes_service.dart
// MERGED: Handles both old simple submissions AND new compliance review system
// iOS 14 Compatible | Production Ready

import 'dart:convert';

import '../models/submitted_recipe.dart';
import '../models/recipe_submission.dart';
import '../models/draft_recipe.dart';
import '../config/app_config.dart';

import 'auth_service.dart';
import 'database_service_core.dart';
import 'profile_service.dart';

class SubmittedRecipesService {
  static const String _CACHE_KEY = 'cache_submitted_recipes';

  // ============================================================
  // OLD SYSTEM: SIMPLE TEXT-BASED SUBMISSIONS
  // ============================================================

  /// Get user's simple submitted recipes (old system)
  static Future<List<SubmittedRecipe>> getSubmittedRecipes() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return [];

    try {
      // Try cache
      final cached = await DatabaseServiceCore.getCachedData(_CACHE_KEY);
      if (cached != null) {
        final decoded = jsonDecode(cached) as List;
        return decoded
            .map((json) => SubmittedRecipe.fromJson(json))
            .toList();
      }

      // Fetch from Worker
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'submitted_recipes',
        columns: ['*'],
        filters: {'user_id': userId},
        orderBy: 'created_at',
        ascending: false,
      );

      final recipes = (response as List)
          .map((r) => SubmittedRecipe.fromJson(r))
          .toList();

      // Cache result
      await DatabaseServiceCore.cacheData(_CACHE_KEY, jsonEncode(response));

      return recipes;
    } catch (e) {
      throw Exception('Failed to load submitted recipes: $e');
    }
  }

  /// Submit new simple recipe (old system with email notification)
  static Future<void> submitRecipe(
    String recipeName,
    String ingredients,
    String directions,
  ) async {
    AuthService.ensureLoggedIn();

    try {
      // Insert recipe
      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'submitted_recipes',
        data: {
          'user_id': AuthService.currentUserId!,
          'recipe_name': recipeName,
          'ingredients': ingredients,
          'directions': directions,
          'is_verified': false,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      // Send email notification
      try {
        await _sendRecipeSubmissionEmail(
          recipeName: recipeName,
          ingredients: ingredients,
          directions: directions,
        );
      } catch (e) {
        AppConfig.debugPrint('⚠️ Failed to send email notification: $e');
      }

      // Clear cache
      await DatabaseServiceCore.clearCache(_CACHE_KEY);

    } catch (e) {
      throw Exception('Failed to submit recipe: $e');
    }
  }

  /// Send email notification for recipe submission with Accept/Decline buttons
  static Future<void> _sendRecipeSubmissionEmail({
    required String recipeName,
    required String ingredients,
    required String directions,
  }) async {
    try {
      final userId = AuthService.currentUserId;
      final userEmail = AuthService.currentUser?.email ?? 'Unknown';
      
      // Get full user profile (username, first name, last name)
      String userName = 'User';
      String firstName = '';
      String lastName = '';
      
      try {
        final profile = await DatabaseServiceCore.workerQuery(
          action: 'select',
          table: 'profiles',
          columns: ['username', 'first_name', 'last_name'],
          filters: {'id': userId},
          limit: 1,
        );
        if (profile != null && (profile as List).isNotEmpty) {
          userName = profile[0]['username'] ?? 'User';
          firstName = profile[0]['first_name'] ?? '';
          lastName = profile[0]['last_name'] ?? '';
        }
      } catch (_) {}

      // Send email via Cloudflare Worker
      await DatabaseServiceCore.workerQuery(
        action: 'send_recipe_submission_email',
        table: 'email_notifications',
        data: {
          // Email settings
          'recipientEmail': 'brittsbistrocafe.mealplanning@gmail.com',
          'subject': 'Recipe Submission: bariWise',
          
          // User information
          'userId': userId,
          'userName': userName,
          'firstName': firstName,
          'lastName': lastName,
          'userEmail': userEmail,
          
          // Recipe information
          'recipeName': recipeName,
          'ingredients': ingredients,
          'directions': directions,
          
          // For callback URLs in Accept/Decline buttons
          'recipeId': null, // Will be set by backend after recipe is created
        },
      );
      
      AppConfig.debugPrint('✅ Recipe submission email sent successfully');
    } catch (e) {
      AppConfig.debugPrint('❌ Email notification failed: $e');
    }
  }

  /// Update simple submitted recipe (old system)
  static Future<void> updateRecipe({
    required int recipeId,
    required String recipeName,
    required String ingredients,
    required String directions,
  }) async {
    AuthService.ensureLoggedIn();

    try {
      // Check ownership
      final recipeData = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'submitted_recipes',
        columns: ['user_id'],
        filters: {'id': recipeId},
        limit: 1,
      );

      if (recipeData == null || (recipeData as List).isEmpty) {
        throw Exception('Recipe not found');
      }

      if (recipeData[0]['user_id'] != AuthService.currentUserId) {
        throw Exception('You can only edit your own recipes');
      }

      // Update recipe
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'submitted_recipes',
        filters: {'id': recipeId},
        data: {
          'recipe_name': recipeName,
          'ingredients': ingredients,
          'directions': directions,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      await DatabaseServiceCore.clearCache(_CACHE_KEY);
    } catch (e) {
      throw Exception('Failed to update recipe: $e');
    }
  }

  /// Delete simple recipe (old system)
  static Future<void> deleteRecipe(int recipeId) async {
    AuthService.ensureLoggedIn();

    try {
      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'submitted_recipes',
        filters: {'id': recipeId},
      );

      await DatabaseServiceCore.clearCache(_CACHE_KEY);
    } catch (e) {
      throw Exception('Failed to delete recipe: $e');
    }
  }

  /// Get single simple recipe by ID (old system)
  static Future<Map<String, dynamic>?> getRecipeById(int recipeId) async {
    try {
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'submitted_recipes',
        columns: ['*'],
        filters: {'id': recipeId},
        limit: 1,
      );

      if (response == null || (response as List).isEmpty) {
        return null;
      }

      return response[0];
    } catch (e) {
      throw Exception('Failed to get recipe: $e');
    }
  }

  /// Generate shareable text format (old system)
  static String generateShareableRecipeText(Map<String, dynamic> recipe) {
    final name = recipe['recipe_name'] ?? 'Unnamed Recipe';
    final ingredients = recipe['ingredients'] ?? 'No ingredients listed';
    final directions = recipe['directions'] ?? 'No directions provided';

    return '''
🍽️ Recipe: $name

📋 Ingredients:
$ingredients

👨‍🍳 Directions:
$directions

---
Shared from Recipe Scanner App
''';
  }

  // ============================================================
  // NEW SYSTEM: COMPLIANCE REVIEW WORKFLOW (SPRINT 3)
  // ============================================================

  /// Submit a draft recipe for community review with compliance checks
  static Future<String> submitRecipeForReview(String draftRecipeId) async {
    try {
      final userId = AuthService.currentUserId;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Check if user can submit
      final canSubmit = await canSubmitRecipe(userId);
      if (!canSubmit) {
        final isPremium = await ProfileService.isPremiumUser();
        if (!isPremium) {
          throw Exception(
            'Monthly submission limit reached. '
            'Free users can submit 2 recipes per month. '
            'Upgrade to Premium for unlimited submissions.',
          );
        }
      }

      // Get the draft recipe
      final recipeResult = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'draft_recipes',
        filters: {'id': draftRecipeId},
        limit: 1,
      );

      if (recipeResult == null || (recipeResult as List).isEmpty) {
        throw Exception('Recipe not found');
      }

      final recipe = DraftRecipe.fromJson(recipeResult[0]);

      // Run compliance checks
      final compliance = await checkCompliance(recipe);

      // Create submission
      final result = await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'recipe_submissions',
        data: {
          'user_id': userId,
          'draft_recipe_id': draftRecipeId,
          'status': 'pending',
          'compliance_checks': compliance.toJson(),
          'submitted_at': DateTime.now().toIso8601String(),
        },
      );

      final submissionId = (result as List)[0]['id'] as String;
      AppConfig.debugPrint('✅ Recipe submitted for review: $submissionId');

      return submissionId;
    } catch (e) {
      AppConfig.debugPrint('❌ Error submitting recipe: $e');
      throw Exception('Failed to submit recipe: $e');
    }
  }

  /// Get all compliance review submissions for a user
  static Future<List<RecipeSubmission>> getUserSubmissions(String userId) async {
    try {
      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'recipe_submissions',
        filters: {'user_id': userId},
        orderBy: 'submitted_at',
        ascending: false,
      );

      if (result == null || (result as List).isEmpty) {
        return [];
      }

      return (result)
          .map((json) => RecipeSubmission.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppConfig.debugPrint('❌ Error loading submissions: $e');
      throw Exception('Failed to load submissions: $e');
    }
  }

  /// Get single submission status
  static Future<RecipeSubmission?> getSubmissionStatus(String submissionId) async {
    try {
      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'recipe_submissions',
        filters: {'id': submissionId},
        limit: 1,
      );

      if (result == null || (result as List).isEmpty) {
        return null;
      }

      return RecipeSubmission.fromJson(result[0] as Map<String, dynamic>);
    } catch (e) {
      AppConfig.debugPrint('❌ Error loading submission: $e');
      return null;
    }
  }

  /// Check if user can submit (2/month free, unlimited premium)
  static Future<bool> canSubmitRecipe(String userId) async {
    try {
      final isPremium = await ProfileService.isPremiumUser();
      if (isPremium) {
        return true;
      }

      final count = await getSubmissionCountThisMonth(userId);
      return count < 2;
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error checking submission limit: $e');
      return false;
    }
  }

  /// Get submission count for current calendar month
  static Future<int> getSubmissionCountThisMonth(String userId) async {
    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);

      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'recipe_submissions',
        filters: {
          'user_id': userId,
          'submitted_at__gte': startOfMonth.toIso8601String(),
        },
        columns: ['COUNT(*) as count'],
      );

      if (result == null || (result as List).isEmpty) {
        return 0;
      }

      return result[0]['count'] as int? ?? 0;
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error getting submission count: $e');
      return 0;
    }
  }

  /// Get remaining submission slots
  static Future<int> getRemainingSubmissions(String userId) async {
    try {
      final isPremium = await ProfileService.isPremiumUser();
      if (isPremium) {
        return -1; // Unlimited
      }

      final count = await getSubmissionCountThisMonth(userId);
      return (2 - count).clamp(0, 2);
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error getting remaining submissions: $e');
      return 0;
    }
  }

  /// Resubmit a rejected recipe
  static Future<String> resubmitRejectedRecipe(String submissionId) async {
    try {
      final userId = AuthService.currentUserId;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final submission = await getSubmissionStatus(submissionId);
      if (submission == null) {
        throw Exception('Submission not found');
      }

      if (!submission.isRejected) {
        throw Exception('Can only resubmit rejected recipes');
      }

      if (submission.userId != userId) {
        throw Exception('Can only resubmit your own recipes');
      }

      return await submitRecipeForReview(submission.draftRecipeId);
    } catch (e) {
      AppConfig.debugPrint('❌ Error resubmitting recipe: $e');
      throw Exception('Failed to resubmit recipe: $e');
    }
  }

  // ============================================================
  // COMPLIANCE CHECKS
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

      // 3. Content Check
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

  /// Check if recipe has complete nutrition
  static bool checkHasCompleteNutrition(DraftRecipe recipe) {
    if (recipe.totalNutrition == null) return false;
    
    final nutrition = recipe.totalNutrition!;
    return nutrition.calories > 0 &&
           nutrition.fat >= 0 &&
           nutrition.sodium >= 0 &&
           nutrition.sugar >= 0;
  }

  /// Check if recipe is bari-safe
  static bool checkIsbariSafe(DraftRecipe recipe) {
    if (recipe.totalNutrition == null) return false;
    return recipe.healthScore >= 50;
  }

  /// Check if content is appropriate
  static bool checkContentAppropriate(DraftRecipe recipe) {
    if (recipe.title.trim().length < 3) return false;
    if (recipe.ingredients.isEmpty) return false;
    if (recipe.instructions == null || recipe.instructions!.trim().length < 20) {
      return false;
    }
    return true;
  }

  // ============================================================
  // EMAIL CALLBACK HANDLERS (Accept/Decline buttons)
  // ============================================================

  /// Accept recipe from email - marks as verified
  static Future<void> acceptRecipeViaEmail(int recipeId) async {
    try {
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'submitted_recipes',
        filters: {'id': recipeId},
        data: {
          'is_verified': true,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      await DatabaseServiceCore.clearCache(_CACHE_KEY);
      AppConfig.debugPrint('✅ Recipe accepted and verified: $recipeId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error accepting recipe: $e');
      throw Exception('Failed to accept recipe: $e');
    }
  }

  /// Decline recipe from email - sends rejection message to user
  static Future<void> declineRecipeViaEmail(int recipeId) async {
    try {
      // Get recipe details to find the user
      final recipe = await getRecipeById(recipeId);
      if (recipe == null) {
        throw Exception('Recipe not found');
      }

      final userId = recipe['user_id'];
      final recipeName = recipe['recipe_name'];

      // Send rejection email to user
      await _sendRejectionEmailToUser(
        userId: userId,
        recipeName: recipeName,
      );

      // Mark recipe as not verified (keep it in database but not verified)
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'submitted_recipes',
        filters: {'id': recipeId},
        data: {
          'is_verified': false,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      await DatabaseServiceCore.clearCache(_CACHE_KEY);
      AppConfig.debugPrint('✅ Recipe declined: $recipeId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error declining recipe: $e');
      throw Exception('Failed to decline recipe: $e');
    }
  }

  /// Send rejection email to user
  static Future<void> _sendRejectionEmailToUser({
    required String userId,
    required String recipeName,
  }) async {
    try {
      // Get user's email
      final user = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'profiles',
        columns: ['email', 'username'],
        filters: {'id': userId},
        limit: 1,
      );

      if (user == null || (user as List).isEmpty) {
        throw Exception('User not found');
      }

      final userEmail = user[0]['email'];
      final userName = user[0]['username'] ?? 'User';

      // Send polite rejection email
      await DatabaseServiceCore.workerQuery(
        action: 'send_rejection_email',
        table: 'email_notifications',
        data: {
          'recipientEmail': userEmail,
          'subject': 'Recipe Submission Update - bariWise',
          'userName': userName,
          'recipeName': recipeName,
          'message': '''
Dear $userName,

Thank you for submitting your recipe "$recipeName" to bariWise!

After careful review, we're unable to approve this recipe at this time. We encourage you to review and edit your recipe, then submit it again.

If you'd like to know more about why your recipe wasn't approved, please don't hesitate to reach out to us using the Contact Us button in the app.

We appreciate your contribution to the bariWise community!

Best regards,
The bariWise Team
''',
        },
      );

      AppConfig.debugPrint('✅ Rejection email sent to user');
    } catch (e) {
      AppConfig.debugPrint('❌ Error sending rejection email: $e');
    }
  }

  // ============================================================
  // ADMIN ACTIONS
  // ============================================================

  /// Approve a recipe submission (admin only)
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

  /// Reject a recipe submission (admin only)
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