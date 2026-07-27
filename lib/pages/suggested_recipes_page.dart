
// lib/pages/suggested_recipes_page.dart
// PATCHED FOR LORA INTEGRATION
//
// Changes from original:
//   1. _loadRecipes(): tries LoraInferenceService.searchRecipes() FIRST.
//      Returns null when disabled → existing Worker DB path unchanged.
//   2. _checkIngredientsExist(): tries LoraInferenceService.checkIngredientExists() first.
//      Returns null when disabled → existing Worker path unchanged.
//   3. Recipe model and all UI widgets unchanged.
//   4. All original comments preserved.

import 'package:flutter/material.dart';
import 'package:bari_wise/services/favorite_recipes_service.dart';
import 'package:bari_wise/services/grocery_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../widgets/premium_gate.dart';
import '../controllers/premium_gate_controller.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
// LORA_INTEGRATION_POINT: New import
import 'package:bari_wise/services/lora_inference_service.dart';

class Recipe {
  final String id;
  final String title;
  final String description;
  final List<String> ingredients;
  final String instructions;
  final int? healthScore;

  Recipe({
    required this.id,
    required this.title,
    required this.description,
    required this.ingredients,
    required this.instructions,
    this.healthScore,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'ingredients': ingredients,
    'instructions': instructions,
    'health_score': healthScore,
  };

  factory Recipe.fromJson(Map<String, dynamic> json) => Recipe(
    id: json['id']?.toString() ?? '',
    title: json['title'] ?? 'Unknown Recipe',
    description: json['description'] ?? 'No description available',
    ingredients: List<String>.from(json['ingredients'] ?? []),
    instructions: json['instructions'] ?? 'No instructions available',
    healthScore: json['health_score'],
  );
}

class SuggestedRecipesPage extends StatefulWidget {
  final List<String> productIngredients;
  final int bariHealthScore;

  const SuggestedRecipesPage({
    super.key,
    required this.productIngredients,
    required this.bariHealthScore,
  });

  @override
  State<SuggestedRecipesPage> createState() => _SuggestedRecipesPageState();
}

class _SuggestedRecipesPageState extends State<SuggestedRecipesPage> {
  List<Recipe> _allRecipes     = [];
  List<Recipe> _currentRecipes = [];
  bool _isLoading         = false;
  bool _hasMore           = true;
  int  _currentPage       = 0;
  bool _ingredientsExist  = false;
  final ScrollController _scrollController = ScrollController();

  // Cache for favorite status
  final Map<String, bool> _favoriteStatusCache = {};

  // Cache durations
  static const Duration _recipeCacheDuration   = Duration(hours: 1);
  static const Duration _favoriteCacheDuration = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    _loadRecipes();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      _loadMoreRecipes();
    }
  }

  String _getRecipeCacheKey() {
    final sortedIngredients =
        List<String>.from(widget.productIngredients)..sort();
    return 'recipes_${sortedIngredients.join('_')}';
  }

  Future<List<Recipe>?> _getCachedRecipes() async {
    try {
      final prefs  = await SharedPreferences.getInstance();
      final cached = prefs.getString(_getRecipeCacheKey());
      if (cached == null) return null;

      final data      = json.decode(cached);
      final timestamp = data['_cached_at'] as int?;
      if (timestamp == null) return null;

      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > _recipeCacheDuration.inMilliseconds) return null;

      final recipes = (data['recipes'] as List)
          .map((e) => Recipe.fromJson(e))
          .toList();

debugPrint('📦 Using cached recipes (${recipes.length} found)');
      return recipes;
    } catch (e) {

      return null;
    }
  }

  Future<void> _cacheRecipes(List<Recipe> recipes) async {
    try {
      final prefs     = await SharedPreferences.getInstance();
      final cacheData = {
        'recipes':     recipes.map((r) => r.toJson()).toList(),
        '_cached_at':  DateTime.now().millisecondsSinceEpoch,
        'ingredients': widget.productIngredients,
      };
      await prefs.setString(_getRecipeCacheKey(), json.encode(cacheData));

    // ignore: empty_catches
    } catch (e) {

    }
  }

  Future<bool> _getCachedFavoriteStatus(String recipeName) async {
    if (_favoriteStatusCache.containsKey(recipeName)) {
      return _favoriteStatusCache[recipeName]!;
    }
    try {
      final prefs  = await SharedPreferences.getInstance();
      final cached = prefs.getString('favorite_status_$recipeName');
      if (cached == null) return false;

      final data       = json.decode(cached);
      final timestamp  = data['_cached_at'] as int?;
      final isFavorite = data['is_favorite'] as bool? ?? false;
      if (timestamp == null) return false;

      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > _favoriteCacheDuration.inMilliseconds) return false;

      _favoriteStatusCache[recipeName] = isFavorite;
      return isFavorite;
    } catch (e) {
      return false;
    }
  }

  Future<void> _cacheFavoriteStatus(
      String recipeName, bool isFavorite) async {
    try {
      _favoriteStatusCache[recipeName] = isFavorite;
      final prefs     = await SharedPreferences.getInstance();
      final cacheData = {
        'is_favorite': isFavorite,
        '_cached_at':  DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(
          'favorite_status_$recipeName', json.encode(cacheData));
    // ignore: empty_catches
    } catch (e) {

    }
  }

  // ── LORA_INTEGRATION_POINT: LoRA search inserted before DB query ──────
  Future<void> _loadRecipes() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      // 1. Try SharedPreferences cache first (unchanged)
      final cachedRecipes = await _getCachedRecipes();
      if (cachedRecipes != null && cachedRecipes.isNotEmpty) {
        if (mounted) {
          setState(() {
            _allRecipes     = cachedRecipes;
            _currentRecipes = cachedRecipes;
            _hasMore        = false;
            _isLoading      = false;
            _ingredientsExist = true;
          });
        }
        return;
      }

      // 2. LORA_INTEGRATION_POINT: Try LoRA Model A before DB query.
      // Returns null when _loraEnabled = false → falls through to DB.
      final loraRecipes = await LoraInferenceService.searchRecipes(
        ingredients:    widget.productIngredients,
        limit:          2,
        offset:         _currentPage * 2,
        bariHealthScore: widget.bariHealthScore,
      );

      if (loraRecipes != null && loraRecipes.isNotEmpty) {
        await _cacheRecipes(loraRecipes);
        if (mounted) {
          setState(() {
            _allRecipes     = loraRecipes;
            _currentRecipes = loraRecipes;
            _hasMore        = false;
            _isLoading      = false;
            _ingredientsExist = true;
          });
        }
        return;
      }
      // ── End LoRA insert ──────────────────────────────────────────────

      // 3. Existing DB path (unchanged)
      bool hasMatchingIngredients = await _checkIngredientsExist();
      if (!hasMatchingIngredients) {
        if (mounted) {
          setState(() {
            _allRecipes     = [];
            _currentRecipes = [];
            _hasMore        = false;
            _isLoading      = false;
            _ingredientsExist = false;
          });
        }
        return;
      }

      // FIXED: Use dedicated Worker search endpoint
      final response = await http.post(
        Uri.parse(
            '${AppConfig.cloudflareWorkerQueryEndpoint}/recipes/search'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ingredients': widget.productIngredients,
          'orderBy':     'health_score',
          'limit':       2,
          'offset':      _currentPage * 2,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Recipe search failed: ${response.body}');
      }

      final data       = jsonDecode(response.body);
      List<Recipe> newRecipes = (data['recipes'] as List)
          .map<Recipe>((r) => Recipe.fromJson(r))
          .toList();

      if (newRecipes.isNotEmpty) await _cacheRecipes(newRecipes);

      if (mounted) {
        setState(() {
          if (_currentPage == 0) {
            _allRecipes     = newRecipes;
            _currentRecipes = newRecipes;
          }
          _hasMore          = newRecipes.length == 2;
          _isLoading        = false;
          _ingredientsExist = true;
        });
      }
    } catch (e) {

      if (await _checkIngredientsExist()) {
        _loadFallbackRecipes();
      } else {
        if (mounted) {
          setState(() {
            _allRecipes     = [];
            _currentRecipes = [];
            _hasMore        = false;
            _isLoading      = false;
            _ingredientsExist = false;
          });
        }
      }
    }
  }

  // ── LORA_INTEGRATION_POINT: LoRA Model C check inserted before DB ─────
  Future<bool> _checkIngredientsExist() async {
    try {
      for (String ingredient in widget.productIngredients) {
        // LORA_INTEGRATION_POINT: Try LoRA classifier first.
        // Returns null when disabled → falls through to Worker.
        final loraExists =
            await LoraInferenceService.checkIngredientExists(ingredient);
        if (loraExists == true)  return true;
        if (loraExists == false) continue; // LoRA says no — try next

        // loraExists == null means LoRA disabled or failed → use Worker
        // ── End LoRA insert ──────────────────────────────────────────

        // Existing Worker check (unchanged)
        final response = await http.post(
          Uri.parse(
              '${AppConfig.cloudflareWorkerQueryEndpoint}/recipes/check-ingredient'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'ingredient': ingredient}),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['exists'] == true) return true;
        }
      }
      return false;
    } catch (e) {

      return false;
    }
  }

  // ── _loadMoreRecipes: same LoRA-first pattern ─────────────────────────
  Future<void> _loadMoreRecipes() async {
    if (_isLoading || !_hasMore || !_ingredientsExist) return;
    _currentPage++;
    setState(() => _isLoading = true);

    try {
      // LORA_INTEGRATION_POINT: Try LoRA for pagination too.
      final loraRecipes = await LoraInferenceService.searchRecipes(
        ingredients:    widget.productIngredients,
        limit:          2,
        offset:         _currentPage * 2,
        bariHealthScore: widget.bariHealthScore,
      );

      if (loraRecipes != null) {
        if (mounted) {
          setState(() {
            _allRecipes.addAll(loraRecipes);
            _currentRecipes = _allRecipes;
            _hasMore        = loraRecipes.length == 2;
            _isLoading      = false;
          });
          await _cacheRecipes(_allRecipes);
        }
        return;
      }

      // Existing Worker path (unchanged)
      final response = await http.post(
        Uri.parse(
            '${AppConfig.cloudflareWorkerQueryEndpoint}/recipes/search'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ingredients': widget.productIngredients,
          'orderBy':     'health_score',
          'limit':       2,
          'offset':      _currentPage * 2,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Recipe search failed: ${response.body}');
      }

      final data       = jsonDecode(response.body);
      List<Recipe> newRecipes = (data['recipes'] as List)
          .map<Recipe>((r) => Recipe.fromJson(r))
          .toList();

      if (mounted) {
        setState(() {
          _allRecipes.addAll(newRecipes);
          _currentRecipes = _allRecipes;
          _hasMore        = newRecipes.length == 2;
          _isLoading      = false;
        });
        await _cacheRecipes(_allRecipes);
      }
    } catch (e) {

      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasMore   = false;
        });
      }
    }
  }

  // ── All remaining methods unchanged from original ─────────────────────

  void _loadFallbackRecipes() {
    List<Recipe> fallbackRecipes;
    if (widget.bariHealthScore >= 75) {
      fallbackRecipes = _getHealthyFallbackRecipes();
    } else if (widget.bariHealthScore >= 50) {
      fallbackRecipes = _getModerateFallbackRecipes();
    } else {
      fallbackRecipes = _getDetoxFallbackRecipes();
    }

    if (mounted) {
      setState(() {
        _allRecipes     = fallbackRecipes;
        _currentRecipes = fallbackRecipes;
        _hasMore        = false;
        _isLoading      = false;
        _ingredientsExist = true;
      });
      _cacheRecipes(fallbackRecipes);
    }
  }

  List<Recipe> _getHealthyFallbackRecipes() => [
    Recipe(
      id: 'fallback_1',
      title: "Mediterranean Salmon Bowl",
      description: "Heart-healthy salmon with fresh vegetables",
      ingredients: [
        "Fresh salmon", "Mixed greens", "Olive oil", "Lemon",
        "Cherry tomatoes"
      ],
      instructions:
          "1. Season salmon with herbs and lemon\n"
          "2. Grill salmon for 6-8 minutes per side\n"
          "3. Arrange mixed greens in a bowl\n"
          "4. Top with grilled salmon and cherry tomatoes\n"
          "5. Drizzle with olive oil and lemon dressing",
      healthScore: 90,
    ),
    Recipe(
      id: 'fallback_2',
      title: "Quinoa Vegetable Stir-fry",
      description: "Protein-rich quinoa with colorful vegetables",
      ingredients: [
        "Quinoa", "Bell peppers", "Broccoli", "Carrots",
        "Low-sodium soy sauce"
      ],
      instructions:
          "1. Cook quinoa according to package directions\n"
          "2. Heat oil in a large pan\n"
          "3. Stir-fry vegetables until crisp-tender\n"
          "4. Add cooked quinoa and toss\n"
          "5. Season with low-sodium soy sauce",
      healthScore: 85,
    ),
  ];

  List<Recipe> _getModerateFallbackRecipes() => [
    Recipe(
      id: 'fallback_3',
      title: "Baked Chicken with Sweet Potato",
      description: "Lean protein with nutrient-rich sweet potato",
      ingredients: ["Chicken breast", "Sweet potato", "Herbs", "Olive oil"],
      instructions:
          "1. Preheat oven to 400°F\n"
          "2. Season chicken with herbs\n"
          "3. Slice sweet potatoes\n"
          "4. Drizzle everything with olive oil\n"
          "5. Bake for 25-30 minutes until cooked through",
      healthScore: 75,
    ),
    Recipe(
      id: 'fallback_4',
      title: "Lentil Soup",
      description: "Fiber-rich soup to support bari health",
      ingredients: [
        "Red lentils", "Carrots", "Celery", "Onions",
        "Low-sodium vegetable broth"
      ],
      instructions:
          "1. Sauté diced onions, carrots, and celery\n"
          "2. Add lentils and broth\n"
          "3. Bring to a boil, then simmer\n"
          "4. Cook for 20-25 minutes until lentils are tender\n"
          "5. Season with herbs and spices",
      healthScore: 80,
    ),
  ];

  List<Recipe> _getDetoxFallbackRecipes() => [
    Recipe(
      id: 'fallback_5',
      title: "Green Detox Smoothie",
      description: "Bari-cleansing green smoothie",
      ingredients: [
        "Spinach", "Green apple", "Lemon juice", "Fresh ginger", "Water"
      ],
      instructions:
          "1. Wash spinach thoroughly\n"
          "2. Core and chop apple\n"
          "3. Peel and slice ginger\n"
          "4. Add all ingredients to blender\n"
          "5. Blend until smooth and serve immediately",
      healthScore: 95,
    ),
    Recipe(
      id: 'fallback_6',
      title: "Steamed Vegetables with Brown Rice",
      description: "Simple, clean eating option",
      ingredients: [
        "Brown rice", "Broccoli", "Carrots", "Zucchini", "Fresh herbs"
      ],
      instructions:
          "1. Cook brown rice according to package directions\n"
          "2. Steam vegetables until tender-crisp\n"
          "3. Season vegetables with fresh herbs\n"
          "4. Serve vegetables over brown rice\n"
          "5. Add a squeeze of lemon if desired",
      healthScore: 88,
    ),
  ];

  Future<void> _addToShoppingList(Recipe recipe) async {
    try {
      final result = await GroceryService.addRecipeToShoppingList(
        recipe.title,
        recipe.ingredients.join(', '),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${result['added']} ingredients added to shopping list! '
              '${result['skipped']} duplicates skipped.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding to shopping list: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleFavorite(Recipe recipe) async {
    try {
      bool isFavorited = await _getCachedFavoriteStatus(recipe.title);

      if (isFavorited) {
        final favorites =
            await FavoriteRecipesService.getFavoriteRecipes();
        final favoriteRecipe = favorites.firstWhere(
          (fav) => fav.recipeName == recipe.title,
        );

        if (favoriteRecipe.id != null) {
          await FavoriteRecipesService.removeFavoriteRecipe(
              favoriteRecipe.id!);
          await _cacheFavoriteStatus(recipe.title, false);

          if (mounted) {
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Recipe removed from favorites'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } else {
        await FavoriteRecipesService.addFavoriteRecipe(
          recipe.title,
          recipe.ingredients.join(', '),
          recipe.instructions,
        );
        await _cacheFavoriteStatus(recipe.title, true);

        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recipe added to favorites!'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating favorites: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recipe Suggestions'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          // LORA_INTEGRATION_POINT: Show LoRA indicator in debug mode
          if (AppConfig.isDevelopment && LoraInferenceService.isLoraEnabled)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade700,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('LoRA',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
            ),
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            onPressed: () {
              try {
                Navigator.pushNamed(context, '/grocery-list');
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Grocery list unavailable')),
                );
              }
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/background.jpeg'),
            fit: BoxFit.cover,
          ),
        ),
        child: PremiumGate(
          feature: PremiumFeature.viewRecipes,
          featureName: 'Recipe Suggestions',
          featureDescription:
              'View detailed recipe suggestions based on your scanned products.',
          child: _buildRecipesList(),
        ),
      ),
    );
  }

  Widget _buildRecipesList() {
    if (_isLoading && _currentRecipes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              LoraInferenceService.isLoraEnabled
                  ? 'Generating personalized recipes with LoRA...'
                  : 'Loading personalized recipes...',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }

    if (_currentRecipes.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha((0.9 * 255).toInt()),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.restaurant_menu, size: 64, color: Colors.grey[600]),
              const SizedBox(height: 16),
              const Text(
                'No Recipes Found',
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "We couldn't find any recipes matching the ingredients "
                "from your scanned product.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Scan Another Product'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_getRecipeCacheKey());
        _currentPage = 0;
        await _loadRecipes();
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _currentRecipes.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _currentRecipes.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            );
          }
          return _buildRecipeCard(_currentRecipes[index]);
        },
      ),
    );
  }

  Widget _buildRecipeCard(Recipe recipe) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
        ),
        child: PremiumGate(
          feature: PremiumFeature.fullRecipes,
          featureName: 'Full Recipe Details',
          featureDescription:
              'Access complete ingredients list and cooking instructions.',
          showSoftPreview: true,
          child: _buildFullRecipeCard(recipe),
        ),
      ),
    );
  }

  Widget _buildFullRecipeCard(Recipe recipe) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (recipe.healthScore != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getHealthScoreColor(recipe.healthScore!),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Health Score: ${recipe.healthScore}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FutureBuilder<bool>(
                    future: _getCachedFavoriteStatus(recipe.title),
                    builder: (context, snapshot) {
                      final isFavorited = snapshot.data ?? false;
                      return IconButton(
                        icon: Icon(
                          isFavorited
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color:
                              isFavorited ? Colors.red : Colors.grey,
                        ),
                        onPressed: () => _toggleFavorite(recipe),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_shopping_cart,
                        color: Colors.blue),
                    onPressed: () => _addToShoppingList(recipe),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          Text(
            recipe.description,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[700],
              fontStyle: FontStyle.italic,
            ),
          ),

          const SizedBox(height: 16),

          const Text('Ingredients:',
              style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...recipe.ingredients.map((ingredient) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(child: Text(ingredient)),
                  ],
                ),
              )),

          const SizedBox(height: 16),

          const Text('Instructions:',
              style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(recipe.instructions,
              style: const TextStyle(fontSize: 16, height: 1.5)),
        ],
      ),
    );
  }

  Color _getHealthScoreColor(int score) {
    if (score >= 80) return Colors.orange;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }
}
