// lib/pages/my_cookbook_page.dart
// User's private draft recipes (Sprint 2)
// iOS 14 Compatible | Production Ready
// MERGED VERSION - Enhanced UI with premium limits

import 'package:flutter/material.dart';
import 'package:bari_wise/widgets/nutrition_facts_label.dart';
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
  String _searchQuery = '';

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

  Future<void> _deleteRecipe(String recipeId, String recipeName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Recipe?'),
        content: Text('Delete "$recipeName"? This action cannot be undone.'),
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

  Future<void> _submitRecipeForReview(DraftRecipe recipe) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit to Community'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Submit "${recipe.title}" for bariatric expert review?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                      const SizedBox(width: 6),
                      Text(
                        'What happens next:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• Our bariatric experts will review your recipe\n'
                    '• If approved, it will be shared with the community\n'
                    '• You\'ll be notified of the decision\n'
                    '• Your recipe stays in your cookbook either way',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
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
            child: const Text('Submit for Review'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Show loading
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      await SubmittedRecipesService.submitRecipeForReview(recipe.id!);

      if (mounted) {
        Navigator.pop(context); // Dismiss loading
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Recipe submitted for review!'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
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
        Navigator.pop(context); // Dismiss loading
        
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          customMessage: e.toString().replaceAll('Exception: ', ''),
        );
      }
    }
  }

  void _showRecipeDetails(DraftRecipe recipe) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            recipe.title,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (recipe.hasNutrition) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
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
                                    'Health Score: ${recipe.healthScore}/100',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _getScoreColor(recipe.healthScore),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              
              const Divider(height: 1),
              
              // Content with tabs if nutrition available
              Expanded(
                child: recipe.hasNutrition && recipe.totalNutrition != null
                  ? DefaultTabController(
                      length: 3,
                      child: Column(
                        children: [
                          TabBar(
                            labelColor: Colors.orange,
                            unselectedLabelColor: Colors.grey,
                            indicatorColor: Colors.orange,
                            tabs: const [
                              Tab(text: 'Recipe'),
                              Tab(text: 'Nutrition'),
                              Tab(text: 'Details'),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _buildRecipeTab(recipe, scrollController),
                                _buildNutritionTab(recipe, scrollController),
                                _buildDetailsTab(recipe, scrollController),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  : _buildRecipeTab(recipe, scrollController),
              ),
              
              // Actions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 4,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      // Submit to Community button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _submitRecipeForReview(recipe);
                          },
                          icon: const Icon(Icons.send, color: Colors.white),
                          label: const Text(
                            'Submit to Community',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 8),
                      
                      // Remove button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _deleteRecipe(recipe.id!, recipe.title);
                          },
                          icon: const Icon(Icons.delete, color: Colors.red),
                          label: const Text(
                            'Remove from Cookbook',
                            style: TextStyle(color: Colors.red, fontSize: 16),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecipeTab(DraftRecipe recipe, ScrollController scrollController) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        // Description
        if (recipe.description != null && recipe.description!.isNotEmpty) ...[
          _buildSection(
            'Description',
            const Icon(Icons.description, color: Colors.orange),
            Text(
              recipe.description!,
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
          ),
          const SizedBox(height: 24),
        ],
        
        // Ingredients
        _buildSection(
          'Ingredients',
          const Icon(Icons.shopping_basket, color: Colors.orange),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: recipe.ingredients.map((ingredient) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(fontSize: 16)),
                    Expanded(
                      child: Text(
                        '${ingredient.quantity} ${ingredient.unit} ${ingredient.productName}',
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Instructions
        if (recipe.instructions != null && recipe.instructions!.isNotEmpty) ...[
          _buildSection(
            'Instructions',
            const Icon(Icons.format_list_numbered, color: Colors.orange),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: recipe.instructions!
                  .split('.')
                  .where((step) => step.trim().isNotEmpty)
                  .toList()
                  .asMap()
                  .entries
                  .map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(
                                color: Colors.orange,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${entry.key + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${entry.value.trim()}.',
                                style: const TextStyle(fontSize: 15, height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNutritionTab(DraftRecipe recipe, ScrollController scrollController) {
    if (!recipe.hasNutrition || recipe.totalNutrition == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.restaurant_menu, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No nutrition data available',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        NutritionFactsLabel(
          nutrition: recipe.totalNutrition!,
          servings: recipe.servings,
          showbariScore: true,
        ),
        
        const SizedBox(height: 16),
        
        // Quick insights
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.insights, size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 6),
                  Text(
                    'Quick Insights',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              _buildInsightRow(
                'Per Serving',
                '${(recipe.totalNutrition!.calories / recipe.servings).toStringAsFixed(0)} calories',
                recipe.totalNutrition!.calories / recipe.servings < 300 
                  ? Colors.green 
                  : recipe.totalNutrition!.calories / recipe.servings < 500
                    ? Colors.orange
                    : Colors.red,
              ),
              
              if (recipe.totalNutrition!.protein > 0)
                _buildInsightRow(
                  'Protein',
                  '${recipe.totalNutrition!.protein.toStringAsFixed(1)}g total',
                  recipe.totalNutrition!.protein >= 20 ? Colors.green : Colors.grey,
                ),
              
              if (recipe.totalNutrition!.fiber != null && recipe.totalNutrition!.fiber! > 0)
                _buildInsightRow(
                  'Fiber',
                  '${recipe.totalNutrition!.fiber!.toStringAsFixed(1)}g total',
                  recipe.totalNutrition!.fiber! >= 5 ? Colors.green : Colors.grey,
                ),
              
              if (recipe.totalNutrition!.sodium > 0)
                _buildInsightRow(
                  'Sodium',
                  '${recipe.totalNutrition!.sodium.toStringAsFixed(0)}mg total',
                  recipe.totalNutrition!.sodium < 400 
                    ? Colors.green 
                    : recipe.totalNutrition!.sodium < 800
                      ? Colors.orange
                      : Colors.red,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsTab(DraftRecipe recipe, ScrollController scrollController) {
    final dateFormat = DateFormat('MMM d, yyyy \'at\' h:mm a');
    
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        _buildDetailRow('Servings', '${recipe.servings}'),
        _buildDetailRow('Ingredients', '${recipe.ingredientCount}'),
        if (recipe.hasNutrition)
          _buildDetailRow('Health Score', '${recipe.healthScore}/100'),
        _buildDetailRow('Created', dateFormat.format(recipe.createdAt)),
        _buildDetailRow('Last Updated', dateFormat.format(recipe.updatedAt)),
        
        if (recipe.hasNutrition) ...[
          const SizedBox(height: 24),
          const Text(
            'Nutrition Summary',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              children: [
                _buildNutrientRow('Calories', '${recipe.totalNutrition!.calories.toStringAsFixed(0)}'),
                _buildNutrientRow('Protein', '${recipe.totalNutrition!.protein.toStringAsFixed(1)}g'),
                _buildNutrientRow('Carbs', '${recipe.totalNutrition!.carbs.toStringAsFixed(1)}g'),
                _buildNutrientRow('Fat', '${recipe.totalNutrition!.fat.toStringAsFixed(1)}g'),
                if (recipe.totalNutrition!.fiber != null)
                  _buildNutrientRow('Fiber', '${recipe.totalNutrition!.fiber!.toStringAsFixed(1)}g'),
                _buildNutrientRow('Sodium', '${recipe.totalNutrition!.sodium.toStringAsFixed(0)}mg'),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSection(String title, Icon icon, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            icon,
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        content,
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNutrientRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Color _getScoreColor(int score) {
    if (score >= 70) return Colors.green;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  List<DraftRecipe> get _filteredRecipes {
    if (_searchQuery.isEmpty) return _recipes;
    
    final query = _searchQuery.toLowerCase();
    return _recipes.where((recipe) {
      return recipe.title.toLowerCase().contains(query) ||
             recipe.ingredients.any((ing) => 
               ing.productName.toLowerCase().contains(query));
    }).toList();
  }

  Widget _buildRecipeCard(DraftRecipe recipe) {
    final dateFormat = DateFormat('MMM d, yyyy');
    final ingredientCount = recipe.ingredients.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _showRecipeDetails(recipe),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Recipe icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.restaurant,
                  color: Colors.orange.shade700,
                  size: 28,
                ),
              ),
              
              const SizedBox(width: 16),
              
              // Recipe info
              Expanded(
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
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (recipe.hasNutrition) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getScoreColor(recipe.healthScore).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: _getScoreColor(recipe.healthScore),
                              ),
                            ),
                            child: Text(
                              '${recipe.healthScore}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _getScoreColor(recipe.healthScore),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    
                    const SizedBox(height: 4),
                    
                    // Metadata
                    Row(
                      children: [
                        Icon(Icons.restaurant, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text(
                          '$ingredientCount ingredient${ingredientCount == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        if (recipe.hasNutrition && recipe.totalNutrition != null) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.local_fire_department, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            '${recipe.totalNutrition!.calories.toStringAsFixed(0)} cal',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ],
                    ),
                    
                    const SizedBox(height: 4),
                    
                    Text(
                      dateFormat.format(recipe.updatedAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Arrow icon
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Cookbook'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRecipes,
            tooltip: 'Refresh',
          ),
        ],
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

          // Search bar
          if (_recipes.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search recipes...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
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
                                Navigator.pushNamed(context, '/submit-recipe').then((_) {
                                  _loadRecipes();
                                });
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
                    : _filteredRecipes.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                                const SizedBox(height: 16),
                                const Text(
                                  'No recipes found',
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Try a different search term',
                                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadRecipes,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _filteredRecipes.length,
                              itemBuilder: (context, index) {
                                return _buildRecipeCard(_filteredRecipes[index]);
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