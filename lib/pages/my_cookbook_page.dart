// lib/pages/my_cookbook_page.dart
// User's private draft recipes (Sprint 2)
// iOS 14 Compatible | Production Ready

import 'package:flutter/material.dart';
import '../models/draft_recipe.dart';
import '../services/draft_recipes_service.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../services/error_handling_service.dart';
import 'package:intl/intl.dart';
import '../services/submitted_recipes_service.dart';

class MyCookbookPage extends StatefulWidget {
  const MyCookbookPage({super.key});

  @override
  _MyCookbookPageState createState() => _MyCookbookPageState();
}

class _MyCookbookPageState extends State<MyCookbookPage> {
  List<DraftRecipe> _recipes = [];
  bool _isLoading = true;
  bool _isPremium = false;
  int _remainingSlots = 0;

  @override
  void initState() {
    super.initState();
    _loadRecipes();
    _checkPremiumStatus();
  }

  Future<void> _loadRecipes() async {
    setState(() => _isLoading = true);

    try {
      final userId = AuthService.currentUserId;
      if (userId == null) {
        throw Exception('Not authenticated');
      }

      final recipes = await DraftRecipesService.getUserDraftRecipes(userId);
      final remaining = await DraftRecipesService.getRemainingSlots(userId);

      if (mounted) {
        setState(() {
          _recipes = recipes;
          _remainingSlots = remaining;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          customMessage: 'Failed to load recipes',
        );
      }
    }
  }

  Future<void> _checkPremiumStatus() async {
    try {
      final isPremium = await ProfileService.isPremiumUser();
      if (mounted) {
        setState(() => _isPremium = isPremium);
      }
    } catch (e) {
      print('Error checking premium status: $e');
    }
  }

  Future<void> _deleteRecipe(String recipeId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Recipe?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await DraftRecipesService.deleteDraftRecipe(recipeId);
      await _loadRecipes();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recipe deleted'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          customMessage: 'Failed to delete recipe',
        );
      }
    }
  }

  Future<void> _submitRecipeForReview(String recipeId) async {
    try {
      await SubmittedRecipesService.submitRecipeForReview(recipeId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Recipe submitted for review!'),
            backgroundColor: Colors.orange,
            action: SnackBarAction(
              label: 'View Status',
              textColor: Colors.white,
              onPressed: () {
                Navigator.pushNamed(context, '/submission-status');
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          customMessage: e.toString().replaceAll('Exception: ', ''),
        );
      }
    }
  }

  Widget _buildRecipeCard(DraftRecipe recipe) {
    final dateFormat = DateFormat('MMM d, yyyy');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          // TODO: Navigate to recipe detail/edit page
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title and health score
              Row(
                children: [
                  Expanded(
                    child: Text(
                      recipe.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (recipe.hasNutrition) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getScoreColor(recipe.healthScore).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _getScoreColor(recipe.healthScore),
                        ),
                      ),
                      child: Text(
                        '${recipe.healthScore}/100',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _getScoreColor(recipe.healthScore),
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 12),

              // Metadata
              Row(
                children: [
                  Icon(Icons.restaurant, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '${recipe.ingredientCount} ingredients',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    dateFormat.format(recipe.updatedAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _submitRecipeForReview(recipe.id!),
                      icon: const Icon(Icons.send, size: 16),
                      label: const Text('Submit for Review'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.orange),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteRecipe(recipe.id!),
                    tooltip: 'Delete',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getScoreColor(int score) {
    if (score >= 70) return Colors.orange;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Cookbook'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Limit info header
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
                        ? 'Premium: Unlimited recipes'
                        : 'Recipes: ${_recipes.length}/5${_remainingSlots > 0 ? ' ($_remainingSlots remaining)' : ''}',
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

          // Recipe list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _recipes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.book,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No recipes yet',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Create your first recipe!',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pushNamed(context, '/submit-recipe');
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Create Recipe'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadRecipes,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _recipes.length,
                          itemBuilder: (context, index) {
                            return _buildRecipeCard(_recipes[index]);
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: !_isLoading && (_isPremium || _remainingSlots > 0)
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.pushNamed(context, '/submit-recipe').then((_) {
                  _loadRecipes();
                });
              },
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('New Recipe'),
            )
          : null,
    );
  }
}