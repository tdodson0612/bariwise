// lib/pages/submission_status_page.dart
// User's recipe submission tracking page
// iOS 14 Compatible | Production Ready

import 'package:flutter/material.dart';
import '../models/recipe_submission.dart';
import '../services/submitted_recipes_service.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../services/error_handling_service.dart';
import '../widgets/submission_status_badge.dart';
import 'package:intl/intl.dart';

class SubmissionStatusPage extends StatefulWidget {
  const SubmissionStatusPage({super.key});

  @override
  _SubmissionStatusPageState createState() => _SubmissionStatusPageState();
}

class _SubmissionStatusPageState extends State<SubmissionStatusPage> {
  List<RecipeSubmission> _allSubmissions = [];
  List<RecipeSubmission> _filteredSubmissions = [];
  String _filterStatus = 'all'; // 'all', 'pending', 'approved', 'rejected'
  bool _isLoading = true;
  int _remainingSubmissions = 0;
  bool _isPremium = false;

  @override
  void initState() {
    super.initState();
    _loadSubmissions();
  }

  Future<void> _loadSubmissions() async {
    setState(() => _isLoading = true);

    try {
      final userId = AuthService.currentUserId;
      if (userId == null) {
        throw Exception('Not authenticated');
      }

      // Load submissions
      final submissions = await SubmittedRecipesService.getUserSubmissions(userId);

      // Get remaining submission count
      final remaining = await SubmittedRecipesService.getRemainingSubmissions(userId);
      final isPremium = await ProfileService.isPremiumUser();

      setState(() {
        _allSubmissions = submissions;
        _filteredSubmissions = submissions;
        _remainingSubmissions = remaining;
        _isPremium = isPremium;
        _isLoading = false;
      });

      _applyFilter();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          customMessage: 'Failed to load submissions',
        );
      }
    }
  }

  void _applyFilter() {
    setState(() {
      if (_filterStatus == 'all') {
        _filteredSubmissions = _allSubmissions;
      } else {
        final status = SubmissionStatus.values.firstWhere(
          (s) => s.toString().split('.').last == _filterStatus,
        );
        _filteredSubmissions = _allSubmissions
            .where((submission) => submission.status == status)
            .toList();
      }
    });
  }

  Future<void> _resubmitRecipe(String submissionId) async {
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Resubmit Recipe?'),
          content: const Text(
            'This will create a new submission for review. '
            'Make sure you\'ve addressed the rejection feedback.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Resubmit'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      final newSubmissionId = await SubmittedRecipesService.resubmitRejectedRecipe(submissionId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Recipe resubmitted for review!'),
            backgroundColor: Colors.orange,
          ),
        );

        // Reload submissions
        _loadSubmissions();
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          customMessage: 'Failed to resubmit recipe',
        );
      }
    }
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filterStatus == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _filterStatus = value;
            _applyFilter();
          });
        },
        backgroundColor: Colors.grey.shade200,
        selectedColor: Colors.orange,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.black87,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildSubmissionCard(RecipeSubmission submission) {
    final dateFormat = DateFormat('MMM d, yyyy');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _showSubmissionDetails(submission),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status badge
              Row(
                children: [
                  SubmissionStatusBadge(status: submission.status),
                  const Spacer(),
                  if (submission.canResubmit)
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.orange),
                      onPressed: () => _resubmitRecipe(submission.id),
                      tooltip: 'Resubmit',
                    ),
                ],
              ),
              
              const SizedBox(height: 12),

              // Recipe title
              Text(
                submission.recipe?.title ?? 'Recipe',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              // Submission date
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'Submitted: ${dateFormat.format(submission.submittedAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),

              // Review date (if reviewed)
              if (submission.reviewedAt != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.check_circle, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      'Reviewed: ${dateFormat.format(submission.reviewedAt!)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],

              // Compliance checks preview
              if (submission.complianceChecks != null) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                _buildCompliancePreview(submission.complianceChecks!),
              ],

              // Rejection reason
              if (submission.isRejected && submission.rejectionReason != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rejection Reason:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              submission.rejectionReason!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.red.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Reviewer notes
              if (submission.reviewerNotes != null) ...[
                const SizedBox(height: 8),
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
                      Icon(Icons.notes, color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reviewer Notes:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              submission.reviewerNotes!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompliancePreview(ComplianceReport report) {
    return Row(
      children: [
        _buildComplianceIcon(report.hasCompleteNutrition, 'Nutrition'),
        const SizedBox(width: 12),
        _buildComplianceIcon(report.isbariSafe, 'bari Safe'),
        const SizedBox(width: 12),
        _buildComplianceIcon(report.contentAppropriate, 'Content'),
        if (report.healthScore != null) ...[
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getScoreColor(report.healthScore!).withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _getScoreColor(report.healthScore!),
              ),
            ),
            child: Text(
              'Score: ${report.healthScore}/100',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: _getScoreColor(report.healthScore!),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildComplianceIcon(bool passed, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          passed ? Icons.check_circle : Icons.cancel,
          size: 16,
          color: passed ? Colors.orange : Colors.red,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  Color _getScoreColor(int score) {
    if (score >= 70) return Colors.orange;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  void _showSubmissionDetails(RecipeSubmission submission) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                submission.recipe?.title ?? 'Recipe Details',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              SubmissionStatusBadge(status: submission.status, showIcon: true),
              const SizedBox(height: 24),
              
              // Full compliance report
              if (submission.complianceChecks != null) ...[
                const Text(
                  'Compliance Checks',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _buildFullComplianceReport(submission.complianceChecks!),
              ],

              // Action button
              if (submission.canResubmit) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _resubmitRecipe(submission.id);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Resubmit Recipe'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFullComplianceReport(ComplianceReport report) {
    return Column(
      children: [
        _buildComplianceCheckTile(
          'Complete Nutrition Data',
          report.hasCompleteNutrition,
        ),
        _buildComplianceCheckTile(
          'bari-Safe (Score: ${report.healthScore ?? 'N/A'})',
          report.isbariSafe,
        ),
        _buildComplianceCheckTile(
          'Content Appropriate',
          report.contentAppropriate,
        ),
        
        if (report.hasWarnings) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Warnings',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...report.warnings.map((warning) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $warning', style: const TextStyle(fontSize: 12)),
                )),
              ],
            ),
          ),
        ],

        if (report.hasErrors) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.error, color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Errors',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...report.errors.map((error) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $error', style: const TextStyle(fontSize: 12)),
                )),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildComplianceCheckTile(String label, bool passed) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        passed ? Icons.check_circle : Icons.cancel,
        color: passed ? Colors.orange : Colors.red,
      ),
      title: Text(label),
      dense: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Recipe Submissions'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Submission counter
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.orange.shade50,
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isPremium
                              ? 'Premium: Unlimited submissions'
                              : 'Remaining: $_remainingSubmissions/2 submissions this month',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (!_isPremium)
                        TextButton(
                          onPressed: () {
                            Navigator.pushNamed(context, '/purchase');
                          },
                          child: const Text('Upgrade'),
                        ),
                    ],
                  ),
                ),

                // Filter chips
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('All', 'all'),
                        _buildFilterChip('Pending', 'pending'),
                        _buildFilterChip('Approved', 'approved'),
                        _buildFilterChip('Rejected', 'rejected'),
                      ],
                    ),
                  ),
                ),

                // Submissions list
                Expanded(
                  child: _filteredSubmissions.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.inbox,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _filterStatus == 'all'
                                    ? 'No submissions yet'
                                    : 'No $_filterStatus submissions',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Submit a recipe to get started!',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadSubmissions,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredSubmissions.length,
                            itemBuilder: (context, index) {
                              return _buildSubmissionCard(_filteredSubmissions[index]);
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}