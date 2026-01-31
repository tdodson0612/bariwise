// lib/models/recipe_submission.dart
// Recipe submission model for compliance review system
// iOS 14 Compatible | Production Ready

import 'draft_recipe.dart';

/// Represents a recipe submission for community review
/// Links DraftRecipe to the compliance review workflow
class RecipeSubmission {
  final String id; // UUID from database
  final String userId;
  final String draftRecipeId;
  final SubmissionStatus status;
  final DateTime submittedAt;
  final DateTime? reviewedAt;
  final String? reviewedBy; // Admin user ID
  final String? reviewerNotes;
  final String? rejectionReason;
  final ComplianceReport? complianceChecks;
  final String? publishedRecipeId; // Links to community recipe when approved

  // Optional: Include the draft recipe data for display
  final DraftRecipe? recipe;

  RecipeSubmission({
    required this.id,
    required this.userId,
    required this.draftRecipeId,
    required this.status,
    required this.submittedAt,
    this.reviewedAt,
    this.reviewedBy,
    this.reviewerNotes,
    this.rejectionReason,
    this.complianceChecks,
    this.publishedRecipeId,
    this.recipe,
  });

  // ============================================================
  // FROM JSON (Database → Dart)
  // ============================================================
  factory RecipeSubmission.fromJson(Map<String, dynamic> json) {
    // Parse status
    final statusStr = json['status'] as String? ?? 'pending';
    final status = SubmissionStatus.values.firstWhere(
      (e) => e.toString().split('.').last == statusStr,
      orElse: () => SubmissionStatus.pending,
    );

    // Parse compliance checks
    ComplianceReport? compliance;
    if (json['compliance_checks'] != null) {
      try {
        compliance = ComplianceReport.fromJson(
          json['compliance_checks'] as Map<String, dynamic>,
        );
      } catch (e) {
        print('⚠️ Error parsing compliance checks: $e');
      }
    }

    // Parse nested recipe if present
    DraftRecipe? recipe;
    if (json['recipe'] != null) {
      try {
        recipe = DraftRecipe.fromJson(
          json['recipe'] as Map<String, dynamic>,
        );
      } catch (e) {
        print('⚠️ Error parsing recipe: $e');
      }
    }

    return RecipeSubmission(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      draftRecipeId: json['draft_recipe_id'] as String,
      status: status,
      submittedAt: DateTime.parse(json['submitted_at'] as String),
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
      reviewedBy: json['reviewed_by'] as String?,
      reviewerNotes: json['reviewer_notes'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
      complianceChecks: compliance,
      publishedRecipeId: json['published_recipe_id'] as String?,
      recipe: recipe,
    );
  }

  // ============================================================
  // TO JSON (Dart → Database)
  // ============================================================
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'draft_recipe_id': draftRecipeId,
      'status': status.toString().split('.').last,
      'submitted_at': submittedAt.toIso8601String(),
      if (reviewedAt != null) 'reviewed_at': reviewedAt!.toIso8601String(),
      if (reviewedBy != null) 'reviewed_by': reviewedBy,
      if (reviewerNotes != null) 'reviewer_notes': reviewerNotes,
      if (rejectionReason != null) 'rejection_reason': rejectionReason,
      if (complianceChecks != null)
        'compliance_checks': complianceChecks!.toJson(),
      if (publishedRecipeId != null) 'published_recipe_id': publishedRecipeId,
      // Don't serialize nested recipe to avoid duplication
    };
  }

  // ============================================================
  // COPY WITH
  // ============================================================
  RecipeSubmission copyWith({
    String? id,
    String? userId,
    String? draftRecipeId,
    SubmissionStatus? status,
    DateTime? submittedAt,
    DateTime? reviewedAt,
    String? reviewedBy,
    String? reviewerNotes,
    String? rejectionReason,
    ComplianceReport? complianceChecks,
    String? publishedRecipeId,
    DraftRecipe? recipe,
  }) {
    return RecipeSubmission(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      draftRecipeId: draftRecipeId ?? this.draftRecipeId,
      status: status ?? this.status,
      submittedAt: submittedAt ?? this.submittedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewerNotes: reviewerNotes ?? this.reviewerNotes,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      complianceChecks: complianceChecks ?? this.complianceChecks,
      publishedRecipeId: publishedRecipeId ?? this.publishedRecipeId,
      recipe: recipe ?? this.recipe,
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  /// Check if submission is pending review
  bool get isPending => status == SubmissionStatus.pending;

  /// Check if submission was approved
  bool get isApproved => status == SubmissionStatus.approved;

  /// Check if submission was rejected
  bool get isRejected => status == SubmissionStatus.rejected;

  /// Check if submission can be resubmitted
  bool get canResubmit => isRejected;

  /// Get status display text
  String get statusText {
    switch (status) {
      case SubmissionStatus.pending:
        return 'Pending Review';
      case SubmissionStatus.approved:
        return 'Approved';
      case SubmissionStatus.rejected:
        return 'Rejected';
    }
  }

  /// Get status color for UI
  String get statusColor {
    switch (status) {
      case SubmissionStatus.pending:
        return 'orange';
      case SubmissionStatus.approved:
        return 'green';
      case SubmissionStatus.rejected:
        return 'red';
    }
  }

  @override
  String toString() {
    return 'RecipeSubmission(id: $id, status: $status, recipe: ${recipe?.title})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RecipeSubmission && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

// ============================================================
// SUBMISSION STATUS ENUM
// ============================================================

enum SubmissionStatus {
  pending,
  approved,
  rejected,
}

// ============================================================
// COMPLIANCE REPORT MODEL
// ============================================================

/// Automated compliance check results for a recipe submission
class ComplianceReport {
  final bool hasCompleteNutrition;
  final bool isbariSafe;
  final bool contentAppropriate;
  final int? healthScore; // 0-100 from bariHealthBar
  final List<String> warnings;
  final List<String> errors;

  ComplianceReport({
    required this.hasCompleteNutrition,
    required this.isbariSafe,
    required this.contentAppropriate,
    this.healthScore,
    this.warnings = const [],
    this.errors = const [],
  });

  /// Check if all compliance checks passed
  bool get allChecksPassed =>
      hasCompleteNutrition && isbariSafe && contentAppropriate;

  /// Check if there are any errors
  bool get hasErrors => errors.isNotEmpty;

  /// Check if there are any warnings
  bool get hasWarnings => warnings.isNotEmpty;

  /// Get total issue count
  int get issueCount => errors.length + warnings.length;

  /// Get pass rate (percentage of checks passed)
  double get passRate {
    int passed = 0;
    if (hasCompleteNutrition) passed++;
    if (isbariSafe) passed++;
    if (contentAppropriate) passed++;
    return (passed / 3.0) * 100;
  }

  // ============================================================
  // FROM JSON
  // ============================================================
  factory ComplianceReport.fromJson(Map<String, dynamic> json) {
    return ComplianceReport(
      hasCompleteNutrition: json['has_complete_nutrition'] as bool? ?? false,
      isbariSafe: json['is_bari_safe'] as bool? ?? false,
      contentAppropriate: json['content_appropriate'] as bool? ?? false,
      healthScore: json['health_score'] as int?,
      warnings: (json['warnings'] as List?)?.cast<String>() ?? [],
      errors: (json['errors'] as List?)?.cast<String>() ?? [],
    );
  }

  // ============================================================
  // TO JSON
  // ============================================================
  Map<String, dynamic> toJson() {
    return {
      'has_complete_nutrition': hasCompleteNutrition,
      'is_bari_safe': isbariSafe,
      'content_appropriate': contentAppropriate,
      if (healthScore != null) 'health_score': healthScore,
      'warnings': warnings,
      'errors': errors,
    };
  }

  // ============================================================
  // COPY WITH
  // ============================================================
  ComplianceReport copyWith({
    bool? hasCompleteNutrition,
    bool? isbariSafe,
    bool? contentAppropriate,
    int? healthScore,
    List<String>? warnings,
    List<String>? errors,
  }) {
    return ComplianceReport(
      hasCompleteNutrition: hasCompleteNutrition ?? this.hasCompleteNutrition,
      isbariSafe: isbariSafe ?? this.isbariSafe,
      contentAppropriate: contentAppropriate ?? this.contentAppropriate,
      healthScore: healthScore ?? this.healthScore,
      warnings: warnings ?? this.warnings,
      errors: errors ?? this.errors,
    );
  }

  @override
  String toString() {
    return 'ComplianceReport(passed: $allChecksPassed, score: $healthScore, issues: $issueCount)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ComplianceReport &&
        other.hasCompleteNutrition == hasCompleteNutrition &&
        other.isbariSafe == isbariSafe &&
        other.contentAppropriate == contentAppropriate &&
        other.healthScore == healthScore;
  }

  @override
  int get hashCode {
    return hasCompleteNutrition.hashCode ^
        isbariSafe.hashCode ^
        contentAppropriate.hashCode ^
        healthScore.hashCode;
  }
}

// ============================================================
// HELPER EXTENSIONS
// ============================================================

extension SubmissionStatusExtension on SubmissionStatus {
  /// Get icon for status
  String get icon {
    switch (this) {
      case SubmissionStatus.pending:
        return '⏳';
      case SubmissionStatus.approved:
        return '✓';
      case SubmissionStatus.rejected:
        return '✗';
    }
  }

  /// Get display name
  String get displayName {
    switch (this) {
      case SubmissionStatus.pending:
        return 'Pending Review';
      case SubmissionStatus.approved:
        return 'Approved';
      case SubmissionStatus.rejected:
        return 'Rejected';
    }
  }
}