// lib/pages/sprint1_test_page.dart
// Test page for Sprint 1 features
// iOS 14 Compatible | Complete Testing Interface

import 'package:flutter/material.dart';
import '../services/ingredient_database_service.dart';
import '../services/custom_ingredients_service.dart';
import '../services/profile_service.dart';
import '../services/auth_service.dart';
import '../models/ingredient_search_result.dart';
import '../models/nutrition_info.dart';
import '../config/app_config.dart';

class Sprint1TestPage extends StatefulWidget {
  const Sprint1TestPage({super.key});

  @override
  State<Sprint1TestPage> createState() => _Sprint1TestPageState();
}

class _Sprint1TestPageState extends State<Sprint1TestPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Search tab
  final TextEditingController _searchController = TextEditingController();
  List<IngredientSearchResult> _searchResults = [];
  bool _isSearching = false;
  
  // Custom ingredients tab
  List<Map<String, dynamic>> _customIngredients = [];
  bool _isLoadingCustom = false;
  int _remainingSlots = 0;
  bool _isPremium = false;
  
  // Add custom ingredient form
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _brandController = TextEditingController();
  final TextEditingController _caloriesController = TextEditingController();
  final TextEditingController _fatController = TextEditingController();
  final TextEditingController _sodiumController = TextEditingController();
  final TextEditingController _sugarController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadCustomIngredients();
    _checkPremiumStatus();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _nameController.dispose();
    _brandController.dispose();
    _caloriesController.dispose();
    _fatController.dispose();
    _sodiumController.dispose();
    _sugarController.dispose();
    super.dispose();
  }

  Future<void> _checkPremiumStatus() async {
    try {
      final isPremium = await ProfileService.isPremiumUser();
      if (mounted) {
        setState(() {
          _isPremium = isPremium;
        });
      }
    } catch (e) {
      AppConfig.debugPrint('Error checking premium status: $e');
    }
  }

  // ============================================================
  // SEARCH TAB
  // ============================================================

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an ingredient name to search')),
      );
      return;
    }

    setState(() {
      _isSearching = true;
      _searchResults = [];
    });

    try {
      final results = await IngredientDatabaseService.searchIngredient(
        query,
        includeNutrition: true,
      );

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });

        if (results.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No results found. Try a different search term.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      }
    }
  }

  Widget _buildSearchTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Search bar
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Search ingredients',
              hintText: 'e.g., cheese, milk, chicken',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _searchResults = [];
                        });
                      },
                    )
                  : null,
            ),
            onSubmitted: (_) => _performSearch(),
            onChanged: (value) => setState(() {}),
          ),

          const SizedBox(height: 12),

          // Search button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSearching ? null : _performSearch,
              icon: _isSearching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.search),
              label: Text(_isSearching ? 'Searching...' : 'Search'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Results
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _searchResults.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No results yet',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Try searching for "cheese" or "milk"',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final result = _searchResults[index];
                          return _buildSearchResultCard(result);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultCard(IngredientSearchResult result) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _getSourceColor(result.source),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            result.sourceBadge,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          result.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: result.brand != null
            ? Text(
                result.brand!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              )
            : null,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.barcode != null) ...[
                  _infoRow('Barcode', result.barcode!),
                  const SizedBox(height: 8),
                ],
                if (result.servingSizeDisplay != null) ...[
                  _infoRow('Serving', result.servingSizeDisplay!),
                  const SizedBox(height: 8),
                ],
                if (result.hasNutrition) ...[
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text(
                    'Nutrition (per serving)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildNutritionGrid(result.nutrition!),
                  const SizedBox(height: 12),
                  _buildbariScore(result.nutrition!),
                ] else ...[
                  const Text(
                    'No nutrition data available',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNutritionGrid(NutritionInfo nutrition) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        _nutritionItem('Calories', nutrition.calories.toStringAsFixed(0)),
        _nutritionItem('Fat', '${nutrition.fat.toStringAsFixed(1)}g'),
        _nutritionItem('Sodium', '${nutrition.sodium.toStringAsFixed(0)}mg'),
        _nutritionItem('Sugar', '${nutrition.sugar.toStringAsFixed(1)}g'),
        _nutritionItem('Protein', '${nutrition.protein.toStringAsFixed(1)}g'),
        if (nutrition.fiber != null)
          _nutritionItem('Fiber', '${nutrition.fiber!.toStringAsFixed(1)}g'),
      ],
    );
  }

  Widget _nutritionItem(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildbariScore(NutritionInfo nutrition) {
    final score = nutrition.calculatebariScore();
    final color = score >= 70
        ? Colors.orange
        : score >= 40
            ? Colors.orange
            : Colors.red;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Icon(Icons.favorite, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            'bari Health Score: $score/100',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _getSourceColor(String source) {
    switch (source.toLowerCase()) {
      case 'open food facts':
        return Colors.blue;
      case 'usda':
      case 'usda fooddata central':
        return Colors.orange;
      case 'custom':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // CUSTOM INGREDIENTS TAB
  // ============================================================

  Future<void> _loadCustomIngredients() async {
    if (!AuthService.isLoggedIn) return;

    setState(() {
      _isLoadingCustom = true;
    });

    try {
      final userId = AuthService.currentUserId!;
      final ingredients =
          await CustomIngredientsService.getUserCustomIngredients(userId);
      final remaining =
          await CustomIngredientsService.getRemainingSlots(userId);

      if (mounted) {
        setState(() {
          _customIngredients = ingredients;
          _remainingSlots = remaining;
          _isLoadingCustom = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingCustom = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading ingredients: $e')),
        );
      }
    }
  }

  Future<void> _addCustomIngredient() async {
    if (!AuthService.isLoggedIn) return;

    // Validate form
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an ingredient name')),
      );
      return;
    }

    try {
      final nutrition = NutritionInfo(
        productName: _nameController.text.trim(),
        calories: double.tryParse(_caloriesController.text) ?? 0,
        fat: double.tryParse(_fatController.text) ?? 0,
        sodium: double.tryParse(_sodiumController.text) ?? 0,
        carbs: 0.0,  // ✅ FIXED: Added required parameter
        sugar: double.tryParse(_sugarController.text) ?? 0,
        protein: 0.0,  // ✅ FIXED: Added required parameter
      );

      await CustomIngredientsService.addCustomIngredient(
        name: _nameController.text.trim(),
        nutrition: nutrition,
        brand: _brandController.text.trim().isNotEmpty
            ? _brandController.text.trim()
            : null,
      );

      // Clear form
      _nameController.clear();
      _brandController.clear();
      _caloriesController.clear();
      _fatController.clear();
      _sodiumController.clear();
      _sugarController.clear();

      // Reload list
      await _loadCustomIngredients();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Custom ingredient added!'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteCustomIngredient(String id) async {
    try {
      await CustomIngredientsService.deleteCustomIngredient(id);
      await _loadCustomIngredients();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Custom ingredient deleted'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  Widget _buildCustomIngredientsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with limit info
          _buildLimitHeader(),
          const SizedBox(height: 20),

          // Add form
          _buildAddForm(),
          const SizedBox(height: 20),

          // List of custom ingredients
          const Text(
            'My Custom Ingredients',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          Expanded(
            child: _isLoadingCustom
                ? const Center(child: CircularProgressIndicator())
                : _customIngredients.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_circle_outline,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No custom ingredients yet',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _customIngredients.length,
                        itemBuilder: (context, index) {
                          final ingredient = _customIngredients[index];
                          return _buildCustomIngredientCard(ingredient);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildLimitHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isPremium ? Colors.amber.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isPremium ? Colors.amber.shade200 : Colors.blue.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isPremium ? Icons.star : Icons.info_outline,
            color: _isPremium ? Colors.amber : Colors.blue,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isPremium ? 'Premium User' : 'Free User',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _isPremium ? Colors.amber.shade900 : Colors.blue.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isPremium
                      ? 'Unlimited custom ingredients'
                      : 'Custom Ingredients: ${_customIngredients.length}/3',
                  style: TextStyle(
                    fontSize: 12,
                    color: _isPremium ? Colors.amber.shade700 : Colors.blue.shade700,
                  ),
                ),
                if (!_isPremium && _remainingSlots >= 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '$_remainingSlots slots remaining',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
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
    );
  }

  Widget _buildAddForm() {
    final canAdd = _isPremium || _remainingSlots > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add Custom Ingredient',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _nameController,
            enabled: canAdd,
            decoration: InputDecoration(
              labelText: 'Name *',
              hintText: 'e.g., My Special Cheese',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _brandController,
            enabled: canAdd,
            decoration: InputDecoration(
              labelText: 'Brand (optional)',
              hintText: 'e.g., Organic Valley',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _caloriesController,
                  enabled: canAdd,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Calories',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _fatController,
                  enabled: canAdd,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Fat (g)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _sodiumController,
                  enabled: canAdd,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Sodium (mg)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _sugarController,
                  enabled: canAdd,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Sugar (g)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: canAdd ? _addCustomIngredient : null,
              icon: const Icon(Icons.add),
              label: Text(canAdd ? 'Add Ingredient' : 'Limit Reached'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          if (!canAdd) ...[
            const SizedBox(height: 8),
            Text(
              'You\'ve reached your limit. Upgrade to Premium for unlimited custom ingredients.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange.shade700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCustomIngredientCard(Map<String, dynamic> ingredient) {
    final nutrition = NutritionInfo.fromDatabaseJson(ingredient['nutrition']);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.purple,
          child: Icon(Icons.restaurant, color: Colors.white, size: 20),
        ),
        title: Text(
          ingredient['name'],
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ingredient['brand'] != null) ...[
              const SizedBox(height: 4),
              Text(
                ingredient['brand'],
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              '${nutrition.calories.toStringAsFixed(0)} cal • '
              '${nutrition.fat.toStringAsFixed(1)}g fat',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () => _deleteCustomIngredient(ingredient['id']),
        ),
      ),
    );
  }

  // ============================================================
  // LIMITS TAB
  // ============================================================

  Widget _buildLimitsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          _buildLimitCard(
            title: 'Custom Ingredients',
            icon: Icons.restaurant,
            iconColor: Colors.purple,
            freeLimit: '3 total',
            premiumLimit: 'Unlimited',
            currentUsage: '${_customIngredients.length}/3',
            implemented: true,
          ),
          _buildLimitCard(
            title: 'Draft Recipes',
            icon: Icons.book,
            iconColor: Colors.blue,
            freeLimit: '5 max',
            premiumLimit: 'Unlimited',
            currentUsage: 'Coming in Sprint 2',
            implemented: false,
          ),
          _buildLimitCard(
            title: 'Grocery List Items',
            icon: Icons.shopping_cart,
            iconColor: Colors.orange,
            freeLimit: '2 items',
            premiumLimit: 'Unlimited',
            currentUsage: 'Coming in Sprint 4',
            implemented: false,
          ),
          _buildLimitCard(
            title: 'Auto-populate Quantities',
            icon: Icons.auto_fix_high,
            iconColor: Colors.orange,
            freeLimit: '5 uses/week',
            premiumLimit: 'Unlimited',
            currentUsage: 'Coming in Sprint 4',
            implemented: false,
          ),
          _buildLimitCard(
            title: 'Substitute Searches',
            icon: Icons.swap_horiz,
            iconColor: Colors.teal,
            freeLimit: '3/day',
            premiumLimit: 'Unlimited',
            currentUsage: 'Coming in Sprint 5',
            implemented: false,
          ),
          _buildLimitCard(
            title: 'Recipe Submissions',
            icon: Icons.send,
            iconColor: Colors.indigo,
            freeLimit: '2/month',
            premiumLimit: 'Unlimited',
            currentUsage: 'Coming in Sprint 3',
            implemented: false,
          ),
        ],
      ),
    );
  }

  Widget _buildLimitCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String freeLimit,
    required String premiumLimit,
    required String currentUsage,
    required bool implemented,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (implemented)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'ACTIVE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'COMING SOON',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildLimitBadge(
                    label: 'Free',
                    value: freeLimit,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildLimitBadge(
                    label: 'Premium',
                    value: premiumLimit,
                    color: Colors.amber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Current: $currentUsage',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLimitBadge({
    required String label,
    required String value,
    required Color color,
  }) {
    // Get darker shade for text
    final textColor = HSLColor.fromColor(color)
        .withLightness(0.3)
        .toColor();
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUILD METHOD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sprint 1 Test Page'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(
              icon: Icon(Icons.search),
              text: 'Search',
            ),
            Tab(
              icon: Icon(Icons.restaurant),
              text: 'Custom',
            ),
            Tab(
              icon: Icon(Icons.info),
              text: 'Limits',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSearchTab(),
          _buildCustomIngredientsTab(),
          _buildLimitsTab(),
        ],
      ),
    );
  }
}