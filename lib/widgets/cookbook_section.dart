// lib/widgets/cookbook_section.dart - COMPLETE WITH NUTRITION TABS
import 'package:flutter/material.dart';
import 'package:bari_wise/widgets/nutrition_facts_label.dart';
import 'package:bari_wise/models/nutrition_info.dart';
import '../models/cookbook_recipe.dart';
import '../services/cookbook_service.dart';
import '../config/app_config.dart';

class CookbookSection extends StatefulWidget {
  const CookbookSection({super.key});

  @override
  State<CookbookSection> createState() => _CookbookSectionState();
}

class _CookbookSectionState extends State<CookbookSection> {
  List<CookbookRecipe> _recipes = [];
  bool _isLoading = true;
  bool _isExpanded = true;

  @override
  void initState() {
    super.initState();
    _loadRecipes();
  }

  Future<void> _loadRecipes() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final recipes = await CookbookService.getCookbookRecipes();
      
      if (mounted) {
        setState(() {
          _recipes = recipes;
          _isLoading = false;
        });
      }
    } catch (e) {
      AppConfig.debugPrint('Error loading cookbook: $e');
      
      if (mounted) {
        setState(() {
          _recipes = [];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteRecipe(int recipeId, String recipeName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Recipe'),
        content: Text('Remove "$recipeName" from your cookbook?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await CookbookService.removeFromCookbook(recipeId);
        await _loadRecipes();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recipe removed from cookbook'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to remove: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showRecipeDetails(CookbookRecipe recipe) {
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
                      child: Text(
                        recipe.recipeName,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
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
                child: recipe.nutrition != null
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
                              Tab(text: 'Notes'),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                // Tab 1: Recipe
                                _buildRecipeTab(recipe, scrollController),
                                
                                // Tab 2: Nutrition
                                _buildNutritionTab(recipe, scrollController),
                                
                                // Tab 3: Notes
                                _buildNotesTab(recipe, scrollController),
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
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _deleteRecipe(recipe.id, recipe.recipeName);
                    },
                    icon: const Icon(Icons.delete, color: Colors.white),
                    label: const Text(
                      'Remove from Cookbook',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecipeTab(CookbookRecipe recipe, ScrollController scrollController) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        // Ingredients
        _buildSection(
          'Ingredients',
          const Icon(Icons.shopping_basket, color: Colors.orange),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: recipe.ingredients
                .split(',')
                .map((ingredient) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ', style: TextStyle(fontSize: 16)),
                          Expanded(
                            child: Text(
                              ingredient.trim(),
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Directions
        _buildSection(
          'Directions',
          const Icon(Icons.format_list_numbered, color: Colors.orange),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: recipe.directions
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
    );
  }

  Widget _buildNutritionTab(CookbookRecipe recipe, ScrollController scrollController) {
    if (recipe.nutrition == null) {
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
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Nutrition facts will appear here when available',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
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
          nutrition: recipe.nutrition!,
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
              
              if (recipe.servings != null)
                _buildInsightRow(
                  'Per Serving',
                  '${(recipe.nutrition!.calories / recipe.servings!).toStringAsFixed(0)} calories',
                  recipe.nutrition!.calories / recipe.servings! < 300 
                    ? Colors.orange 
                    : recipe.nutrition!.calories / recipe.servings! < 500
                      ? Colors.orange
                      : Colors.red,
                ),
              
              if (recipe.nutrition!.protein > 0)
                _buildInsightRow(
                  'Protein content',
                  '${recipe.nutrition!.protein.toStringAsFixed(1)}g total',
                  recipe.nutrition!.protein >= 20 ? Colors.orange : Colors.grey,
                ),
              
              if (recipe.nutrition!.fiber != null && recipe.nutrition!.fiber! > 0)
                _buildInsightRow(
                  'Fiber content',
                  '${recipe.nutrition!.fiber!.toStringAsFixed(1)}g total',
                  recipe.nutrition!.fiber! >= 5 ? Colors.orange : Colors.grey,
                ),
              
              if (recipe.nutrition!.sodium > 0)
                _buildInsightRow(
                  'Sodium',
                  '${recipe.nutrition!.sodium.toStringAsFixed(0)}mg total',
                  recipe.nutrition!.sodium < 400 
                    ? Colors.orange 
                    : recipe.nutrition!.sodium < 800
                      ? Colors.orange
                      : Colors.red,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotesTab(CookbookRecipe recipe, ScrollController scrollController) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        if (recipe.notes != null && recipe.notes!.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.yellow[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.yellow[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.note, color: Colors.orange, size: 24),
                    const SizedBox(width: 8),
                    const Text(
                      'My Notes',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  recipe.notes!,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          )
        else
          Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.note_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No notes yet',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
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
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
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
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        content,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha((0.9 * 255).toInt()),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: () {
              setState(() => _isExpanded = !_isExpanded);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.menu_book, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text(
                      'My Cookbook (${_recipes.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.grey[600],
                ),
              ],
            ),
          ),
          
          // Content
          if (_isExpanded) ...[
            const SizedBox(height: 16),
            
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_recipes.isEmpty)
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.menu_book,
                      size: 50,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No recipes in your cookbook yet',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add recipes by clicking the bookmark button',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recipes.length,
                itemBuilder: (context, index) {
                  final recipe = _recipes[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      onTap: () => _showRecipeDetails(recipe),
                      leading: const CircleAvatar(
                        backgroundColor: Colors.orange,
                        child: Icon(Icons.restaurant, color: Colors.white, size: 20),
                      ),
                      title: Text(
                        recipe.recipeName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${recipe.ingredients.split(',').take(2).join(', ')}...',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                            onPressed: () => _deleteRecipe(recipe.id, recipe.recipeName),
                          ),
                          const Icon(Icons.arrow_forward_ios, size: 14),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }
}