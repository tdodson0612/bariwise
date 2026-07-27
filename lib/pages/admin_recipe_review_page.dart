// lib/pages/admin_recipe_review_page.dart
// Admin queue for reviewing pending community recipe submissions.
// Wrap this page with AdminGuard at the route level (see main.dart wiring below).
// iOS 14 Compatible | Production Ready

import 'package:flutter/material.dart';
import '../services/recipe_compliance_service.dart';
import '../services/draft_recipes_service.dart';
import '../models/draft_recipe.dart';
import '../models/recipe_submission.dart';
import '../services/recent_activity_tracker.dart';

class AdminRecipeReviewPage extends StatefulWidget {
  const AdminRecipeReviewPage({super.key});

  @override
  State<AdminRecipeReviewPage> createState() => _AdminRecipeReviewPageState();
}

class _ReviewItem {
  final RecipeSubmission submission;
  final DraftRecipe? recipe;
  final ComplianceReport? liveReport;
  final String? loadError;

  _ReviewItem({
    required this.submission,
    this.recipe,
    this.liveReport,
    this.loadError,
  });
}

class _AdminRecipeReviewPageState extends State<AdminRecipeReviewPage> {
  bool _loading = true;
  List<_ReviewItem> _items = [];
  final Set<String> _processingIds = {}; // submission ids currently approving/rejecting

  @override
  void initState() {
    super.initState();
    RecentActivityTracker.recordScreen(
        label: 'Admin Recipe Review', route: '/admin-recipe-review');
    _loadPending();
  }

  Future<void> _loadPending() async {
    setState(() => _loading = true);
    try {
      final rows = await RecipeComplianceService.getPendingSubmissions();
      final items = <_ReviewItem>[];

      for (final row in rows) {
        RecipeSubmission submission;
        try {
          submission = RecipeSubmission.fromJson(row);
        } catch (e) {
          continue; // Skip malformed rows rather than crash the whole queue
        }

        DraftRecipe? recipe;
        ComplianceReport? report;
        String? loadError;
        try {
          recipe = await DraftRecipesService.getDraftRecipe(
              submission.draftRecipeId);
          if (recipe != null) {
            final result = await RecipeComplianceService.checkCompliance(
                recipe);
            report = result;
          } else {
            loadError = 'Linked recipe not found (may have been deleted)';
          }
        } catch (e) {
          loadError = 'Error loading recipe: $e';
        }

        items.add(_ReviewItem(
          submission: submission,
          recipe: recipe,
          liveReport: report,
          loadError: loadError,
        ));
      }

      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load submissions: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDateTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) {
      if (diff.inHours == 0) return '${diff.inMinutes} min ago';
      return '${diff.inHours} hr ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    }
    return '${date.month}/${date.day}/${date.year}';
  }

  Future<void> _approve(_ReviewItem item) async {
    final notesController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve Recipe'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.recipe?.title ?? 'Untitled Recipe',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reviewer Notes (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
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
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _processingIds.add(item.submission.id));
    try {
      await RecipeComplianceService.approveSubmission(
        item.submission.id,
        notes: notesController.text.trim().isNotEmpty
            ? notesController.text.trim()
            : null,
      );
      if (mounted) {
        setState(() {
          _items.removeWhere((i) => i.submission.id == item.submission.id);
          _processingIds.remove(item.submission.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Approved "${item.recipe?.title ?? item.submission.id}"'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _processingIds.remove(item.submission.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to approve: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _reject(_ReviewItem item) async {
    final reasonController = TextEditingController();
    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Reject Recipe'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.recipe?.title ?? 'Untitled Recipe',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Rejection Reason (required)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Internal Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (reasonController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Rejection reason is required'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                  Navigator.pop(context, true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Reject'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;
    if (reasonController.text.trim().isEmpty) return;

    setState(() => _processingIds.add(item.submission.id));
    try {
      await RecipeComplianceService.rejectSubmission(
        item.submission.id,
        reasonController.text.trim(),
        notes: notesController.text.trim().isNotEmpty
            ? notesController.text.trim()
            : null,
      );
      if (mounted) {
        setState(() {
          _items.removeWhere((i) => i.submission.id == item.submission.id);
          _processingIds.remove(item.submission.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rejected "${item.recipe?.title ?? item.submission.id}"'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _processingIds.remove(item.submission.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reject: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showDetail(_ReviewItem item) {
    final recipe = item.recipe;
    final report = item.liveReport;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(recipe?.title ?? 'Untitled Recipe'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.loadError != null) ...[
                Text(item.loadError!,
                    style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
              ],
              if (recipe != null) ...[
                Text('Submitted by: ${item.submission.userId}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                Text('Submitted: ${_formatDateTime(item.submission.submittedAt)}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                const SizedBox(height: 12),
                if (recipe.description != null &&
                    recipe.description!.isNotEmpty) ...[
                  Text(recipe.description!,
                      style: const TextStyle(fontStyle: FontStyle.italic)),
                  const SizedBox(height: 12),
                ],
                const Text('Ingredients:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                ...recipe.ingredients.map((i) => Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 2),
                      child: Text('• ${i.displayString}'),
                    )),
                const SizedBox(height: 12),
                const Text('Directions:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(recipe.instructions ?? 'No directions provided'),
                const SizedBox(height: 12),
              ],
              if (report != null) ...[
                const Divider(),
                const SizedBox(height: 8),
                Text('Compliance Report',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(
                    report.hasCompleteNutrition
                        ? Icons.check_circle
                        : Icons.cancel,
                    size: 16,
                    color: report.hasCompleteNutrition
                        ? Colors.green
                        : Colors.red,
                  ),
                  const SizedBox(width: 6),
                  const Text('Complete nutrition data'),
                ]),
                Row(children: [
                  Icon(
                    report.isbariSafe ? Icons.check_circle : Icons.cancel,
                    size: 16,
                    color: report.isbariSafe ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 6),
                  Text('Bariatric-safe${report.healthScore != null ? " (score: ${report.healthScore})" : ""}'),
                ]),
                Row(children: [
                  Icon(
                    report.contentAppropriate
                        ? Icons.check_circle
                        : Icons.cancel,
                    size: 16,
                    color: report.contentAppropriate
                        ? Colors.green
                        : Colors.red,
                  ),
                  const SizedBox(width: 6),
                  const Text('Content appropriate'),
                ]),
                if (report.errors.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Errors:',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.red)),
                  ...report.errors.map((e) => Padding(
                        padding: const EdgeInsets.only(left: 8, top: 2),
                        child: Text('• $e',
                            style: const TextStyle(color: Colors.red)),
                      )),
                ],
                if (report.warnings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Warnings:',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.orange)),
                  ...report.warnings.map((w) => Padding(
                        padding: const EdgeInsets.only(left: 8, top: 2),
                        child: Text('• $w',
                            style: const TextStyle(color: Colors.orange)),
                      )),
                ],
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildComplianceChips(ComplianceReport? report, String? loadError) {
    if (loadError != null) {
      return _chip('Load Error', Colors.red);
    }
    if (report == null) {
      return _chip('No report', Colors.grey);
    }
    final chips = <Widget>[];
    if (report.errors.isNotEmpty) {
      chips.add(_chip('${report.errors.length} error${report.errors.length == 1 ? '' : 's'}',
          Colors.red));
    }
    if (report.warnings.isNotEmpty) {
      chips.add(_chip(
          '${report.warnings.length} warning${report.warnings.length == 1 ? '' : 's'}',
          Colors.orange));
    }
    if (report.healthScore != null) {
      chips.add(_chip('Score: ${report.healthScore}',
          report.healthScore! >= 50 ? Colors.green : Colors.red));
    }
    if (chips.isEmpty) {
      chips.add(_chip('All checks passed', Colors.green));
    }
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: color)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recipe Review Queue'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadPending,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      const Text('All caught up!',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('No pending recipe submissions to review.',
                          style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadPending,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final isProcessing =
                          _processingIds.contains(item.submission.id);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showDetail(item),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.recipe?.title ??
                                            'Recipe unavailable',
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    Text(
                                      _formatDateTime(
                                          item.submission.submittedAt),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                                if (item.recipe != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '${item.recipe!.ingredientCount} ingredient${item.recipe!.ingredientCount == 1 ? '' : 's'}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                _buildComplianceChips(
                                    item.liveReport, item.loadError),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: isProcessing || item.recipe == null
                                            ? null
                                            : () => _reject(item),
                                        icon: const Icon(Icons.close, size: 16),
                                        label: const Text('Reject'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red,
                                          side: const BorderSide(color: Colors.red),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: isProcessing || item.recipe == null
                                            ? null
                                            : () => _approve(item),
                                        icon: isProcessing
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.white),
                                              )
                                            : const Icon(Icons.check, size: 16),
                                        label: const Text('Approve'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}