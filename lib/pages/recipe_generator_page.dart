// lib/pages/recipe_generator_page.dart
// Section 8 — Recipe Generator Workspace (COMPLETE)
// Standalone screen accessible via route '/recipe-generator'.
// Supports:
//   • Manual keyword entry
//   • Pre-population from scan results (passed via route arguments)
//   • Keyword chip toggling
//   • Cloudflare Worker recipe search (same logic as RecipeGenerator in home_screen.dart)
//   • Inline save to favorites, cookbook, grocery list
//   • Build Recipe Flow — links to existing submit_recipe.dart flow
//   • Recipe Nutrition Panel — matches saved ingredients, same logic as submit_recipe.dart
//   • Bariatric Phase Labeling — Liquid / Puree / Soft Foods / Regular
//   • Open Existing Recipe Flow — pick a saved favorite and load it into this view
// Route: '/recipe-generator'
// Arguments (optional): Map<String, dynamic> with key 'keywords' (List<String>)
//   and optional 'productName' (String)

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../services/favorite_recipes_service.dart';
import '../services/grocery_service.dart';
import '../services/error_handling_service.dart';
import '../services/recent_activity_tracker.dart';
import '../services/recipe_nutrition_service.dart';
import '../services/saved_ingredients_service.dart';
import '../widgets/add_to_cookbook_button.dart';
import '../widgets/recipe_nutrition_display.dart';
import '../models/favorite_recipe.dart';
import '../models/nutrition_info.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────

class _Recipe {
  final String title;
  final String description;
  final List<String> ingredients;
  final String instructions;

  const _Recipe({
    required this.title,
    required this.description,
    required this.ingredients,
    required this.instructions,
  });

  factory _Recipe.fromJson(Map<String, dynamic> json) => _Recipe(
        title: json['title'] ?? json['name'] ?? '',
        description: json['description'] ?? '',
        ingredients: json['ingredients'] is String
            ? (json['ingredients'] as String)
                .split(',')
                .map((e) => e.trim())
                .toList()
            : List<String>.from(json['ingredients'] ?? []),
        instructions: json['instructions'] ?? json['directions'] ?? '',
      );
}

// ── Open Existing Recipe Flow (Section 8) ───────────────────────────────────
// Converts a saved FavoriteRecipe back into a _Recipe for display.
// Mirrors the ingredient-parsing fallback chain used in favorite_recipes_page.dart
// (structured JSON list → newline-split → comma-split → raw string).

List<String> _parseIngredientsField(String raw) {
  if (raw.trim().isEmpty) return [];
  try {
    final parsed = jsonDecode(raw);
    if (parsed is List) {
      final lines = parsed
          .map((item) {
            if (item is Map) {
              final qty = item['quantity'] ?? '';
              final unit = item['measurement'] ?? item['unit'] ?? '';
              final name = item['name'] ?? item['product_name'] ?? '';
              return '$qty $unit $name'.trim();
            }
            return item.toString();
          })
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (lines.isNotEmpty) return lines;
    }
  } catch (_) {
    // Not JSON — fall through to text splitting below.
  }

  final byNewline =
      raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
  if (byNewline.length > 1) return byNewline;

  final byComma = raw.split(',').where((l) => l.trim().isNotEmpty).toList();
  if (byComma.isNotEmpty) return byComma;

  return [raw];
}

_Recipe _recipeFromFavorite(FavoriteRecipe fav) {
  return _Recipe(
    title: fav.recipeName,
    description: fav.description ?? '',
    ingredients: _parseIngredientsField(fav.ingredients),
    instructions: fav.directions,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// BARIATRIC PHASE LABELING (Section 8)
// ─────────────────────────────────────────────────────────────────────────────
// Heuristic, keyword-based classification. Not a medical determination —
// purely a UI convenience label based on recipe text content.

enum _BariPhase { liquid, puree, soft, regular }

class _PhaseInfo {
  final String label;
  final Color color;
  final IconData icon;
  const _PhaseInfo(this.label, this.color, this.icon);
}

const Map<_BariPhase, _PhaseInfo> _phaseInfo = {
  _BariPhase.liquid: _PhaseInfo(
      'Liquid Phase', Color(0xFF1976D2), Icons.local_drink_rounded),
  _BariPhase.puree: _PhaseInfo(
      'Puree Phase', Color(0xFF7B1FA2), Icons.blender_rounded),
  _BariPhase.soft: _PhaseInfo(
      'Soft Foods Phase', Color(0xFFEF6C00), Icons.rice_bowl_rounded),
  _BariPhase.regular: _PhaseInfo(
      'Regular Foods Phase', Color(0xFF2E7D32), Icons.restaurant_rounded),
};

_BariPhase _classifyPhase(_Recipe recipe) {
  final text = ('${recipe.title} ${recipe.description} '
          '${recipe.ingredients.join(' ')} ${recipe.instructions}')
      .toLowerCase();

  const liquidWords = ['broth', 'shake', 'smoothie', 'liquid diet', 'strained juice'];
  const pureeWords = ['puree', 'pureed', 'blended', 'pureeing', 'strained'];
  const softWords = ['soft food', 'mashed', 'ground', 'minced', 'soft diet'];

  if (liquidWords.any((w) => text.contains(w))) return _BariPhase.liquid;
  if (pureeWords.any((w) => text.contains(w))) return _BariPhase.puree;
  if (softWords.any((w) => text.contains(w))) return _BariPhase.soft;
  return _BariPhase.regular;
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE
// ─────────────────────────────────────────────────────────────────────────────

class RecipeGeneratorPage extends StatefulWidget {
  const RecipeGeneratorPage({super.key});

  @override
  State<RecipeGeneratorPage> createState() => _RecipeGeneratorPageState();
}

class _RecipeGeneratorPageState extends State<RecipeGeneratorPage> {
  final TextEditingController _keywordCtrl = TextEditingController();
  final FocusNode _keywordFocus = FocusNode();

  List<String> _keywordTokens = [];
  Set<String> _selectedKeywords = {};
  List<_Recipe> _results = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  String? _productName;

  // Pagination
  int _currentPage = 0;
  static const int _perPage = 3;

  // Favorites cache (to show filled heart + power Open Existing Recipe Flow)
  List<FavoriteRecipe> _favorites = [];

  @override
  void initState() {
    super.initState();
    RecentActivityTracker.recordScreen(
        label: 'Recipe Generator', route: '/recipe-generator');
    _loadFavorites();
    // Arguments are read in didChangeDependencies once context is available
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      final keywords = args['keywords'];
      final productName = args['productName'] as String?;
      if (keywords is List && keywords.isNotEmpty) {
        final tokens = keywords
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (_keywordTokens.isEmpty) {
          // Only pre-populate once
          setState(() {
            _keywordTokens = tokens;
            _selectedKeywords = tokens.toSet();
            _productName = productName;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _keywordCtrl.dispose();
    _keywordFocus.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    try {
      final favs = await FavoriteRecipesService.getFavoriteRecipes();
      if (mounted) setState(() => _favorites = favs);
    } catch (e) {
      AppConfig.debugPrint('⚠️ Could not load favorites: $e');
    }
  }

  bool _isFavorited(String title) =>
      _favorites.any((f) => f.recipeName == title);

  // ── Build Recipe Flow (Section 8) ───────────────────────────────────────
  // Reuses the existing build-a-recipe flow rather than duplicating it here.
  void _navigateToBuildRecipe() {
    try {
      Navigator.pushNamed(context, '/submit-recipe');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recipe builder unavailable')),
        );
      }
    }
  }

  // ── Open Existing Recipe Flow (Section 8) ───────────────────────────────
  void _showOpenSavedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open Saved Recipe'),
        content: SizedBox(
          width: double.maxFinite,
          child: _favorites.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('You have no saved favorites yet.'),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _favorites.length,
                  itemBuilder: (context, index) {
                    final fav = _favorites[index];
                    return ListTile(
                      leading: const Icon(Icons.restaurant,
                          color: Colors.red),
                      title: Text(fav.recipeName),
                      subtitle: fav.description != null &&
                              fav.description!.trim().isNotEmpty
                          ? Text(
                              fav.description!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        _openSavedRecipe(fav);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _openSavedRecipe(FavoriteRecipe fav) {
    setState(() {
      _results = [_recipeFromFavorite(fav)];
      _hasSearched = true;
      _currentPage = 0;
      _keywordTokens = [];
      _selectedKeywords = {};
      _productName = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opened "${fav.recipeName}"'),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Keyword management ────────────────────────────────────────────────────

  void _addKeyword(String raw) {
    final words = raw
        .split(RegExp(r'[\s,]+'))
        .map((w) => w.trim())
        .where((w) => w.length > 1)
        .toList();
    if (words.isEmpty) return;
    setState(() {
      for (final w in words) {
        if (!_keywordTokens.contains(w)) {
          _keywordTokens.add(w);
        }
        _selectedKeywords.add(w);
      }
    });
    _keywordCtrl.clear();
  }

  void _toggleKeyword(String word) {
    setState(() {
      if (_selectedKeywords.contains(word)) {
        _selectedKeywords.remove(word);
      } else {
        _selectedKeywords.add(word);
      }
    });
  }

  void _removeKeyword(String word) {
    setState(() {
      _keywordTokens.remove(word);
      _selectedKeywords.remove(word);
    });
  }

  void _clearAll() {
    setState(() {
      _keywordTokens.clear();
      _selectedKeywords.clear();
      _results.clear();
      _hasSearched = false;
      _currentPage = 0;
      _productName = null;
    });
  }

  // ── Search ─────────────────────────────────────────────────────────────────

  Future<void> _search() async {
    if (_selectedKeywords.isEmpty) {
      ErrorHandlingService.showSimpleError(
          context, 'Please select at least one keyword.');
      return;
    }

    setState(() {
      _isSearching = true;
      _hasSearched = false;
      _results.clear();
      _currentPage = 0;
    });

    try {
      final keywords = _selectedKeywords
          .map((w) => w.trim().toLowerCase())
          .where((w) => w.isNotEmpty)
          .toList();

      AppConfig.debugPrint('🔎 Recipe Generator searching: $keywords');

      final response = await http
          .post(
            Uri.parse(AppConfig.cloudflareWorkerQueryEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'action': 'search_recipes',
              'keyword': keywords,
              'limit': 50,
            }),
          )
          .timeout(Duration(seconds: AppConfig.apiTimeoutSeconds));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          final results = data['results'] as List? ?? [];
          final recipes = results
              .map((item) => _Recipe.fromJson(item as Map<String, dynamic>))
              .where((r) => r.title.isNotEmpty)
              .toList();

          if (mounted) {
            setState(() {
              _results = recipes;
              _hasSearched = true;
            });
          }
          AppConfig.debugPrint('✅ Found ${recipes.length} recipes');
        }
      } else {
        throw Exception('Search failed (${response.statusCode})');
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Recipe search error: $e');
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          customMessage: 'Error searching recipes. Please try again.',
          onRetry: _search,
        );
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  // ── Pagination ─────────────────────────────────────────────────────────────

  List<_Recipe> get _currentPageRecipes {
    if (_results.isEmpty) return [];
    final start = _currentPage * _perPage;
    final end = (start + _perPage).clamp(0, _results.length);
    return _results.sublist(start, end);
  }

  int get _totalPages => (_results.length / _perPage).ceil();

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _toggleFavorite(_Recipe recipe) async {
    try {
      final existing = await FavoriteRecipesService.findExistingFavorite(
          recipeName: recipe.title);
      if (existing != null && existing.id != null) {
        await FavoriteRecipesService.removeFavoriteRecipe(existing.id!);
        // ignore: use_build_context_synchronously
        ErrorHandlingService.showSuccess(context, 'Removed from favorites');
      } else {
        await FavoriteRecipesService.addFavoriteRecipe(
          recipe.title,
          recipe.ingredients.join(', '),
          recipe.instructions,
        );
        // ignore: use_build_context_synchronously
        ErrorHandlingService.showSuccess(context, 'Added to favorites!');
      }
      await _loadFavorites();
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          customMessage: 'Error updating favorites',
        );
      }
    }
  }

  Future<void> _addIngredientsToGrocery(_Recipe recipe) async {
    try {
      int count = 0;
      for (final ing in recipe.ingredients) {
        await GroceryService.addToGroceryList(ing);
        count++;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Added $count ingredients to grocery list!'),
          backgroundColor: Colors.orange,
          action: SnackBarAction(
            label: 'VIEW',
            textColor: Colors.white,
            onPressed: () => Navigator.pushNamed(context, '/grocery-list'),
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          customMessage: 'Failed to add to grocery list',
        );
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recipe Generator'),
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_rounded),
            tooltip: 'Open Saved Recipe',
            onPressed: _showOpenSavedDialog,
          ),
          IconButton(
            icon: const Icon(Icons.edit_note_rounded),
            tooltip: 'Build Your Own Recipe',
            onPressed: _navigateToBuildRecipe,
          ),
          if (_keywordTokens.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all_rounded),
              tooltip: 'Clear all',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Keyword input area ─────────────────────────────────────────
          _buildKeywordInput(),

          // ── Results ───────────────────────────────────────────────────
          Expanded(child: _buildResultsArea()),
        ],
      ),
    );
  }

  Widget _buildKeywordInput() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product name banner (if pre-populated from scan)
          if (_productName != null) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.qr_code_scanner_rounded,
                      size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Based on: $_productName',
                      style: TextStyle(
                          fontSize: 13, color: Colors.orange.shade900),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _productName = null),
                    child: Icon(Icons.close,
                        size: 16, color: Colors.orange.shade700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Text input row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keywordCtrl,
                  focusNode: _keywordFocus,
                  decoration: InputDecoration(
                    hintText: 'Add keyword (e.g. chicken, low-carb)…',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: Colors.orange.shade700, width: 2),
                    ),
                    suffixIcon: _keywordCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _keywordCtrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (value) {
                    _addKeyword(value);
                    _keywordFocus.requestFocus();
                  },
                  textInputAction: TextInputAction.done,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _keywordCtrl.text.trim().isEmpty
                    ? null
                    : () => _addKeyword(_keywordCtrl.text),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 13),
                ),
                child: const Icon(Icons.add_rounded, size: 22),
              ),
            ],
          ),

          // Keyword chips
          if (_keywordTokens.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _keywordTokens.map((word) {
                final selected = _selectedKeywords.contains(word);
                return InputChip(
                  label: Text(word),
                  selected: selected,
                  selectedColor: Colors.orange.shade100,
                  checkmarkColor: Colors.orange.shade700,
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: selected
                        ? Colors.orange.shade900
                        : Colors.grey.shade700,
                    fontWeight: selected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: selected
                        ? Colors.orange.shade400
                        : Colors.grey.shade300,
                  ),
                  onSelected: (_) => _toggleKeyword(word),
                  onDeleted: () => _removeKeyword(word),
                  deleteIconColor: Colors.grey.shade500,
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
          ],

          // Search button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_isSearching || _selectedKeywords.isEmpty)
                  ? null
                  : _search,
              icon: _isSearching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search_rounded),
              label: Text(
                _isSearching
                    ? 'Searching…'
                    : _selectedKeywords.isEmpty
                        ? 'Add keywords to search'
                        : 'Find Recipes (${_selectedKeywords.length} keyword${_selectedKeywords.length == 1 ? '' : 's'})',
                style: const TextStyle(fontSize: 15),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),

          const SizedBox(height: 4),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _buildResultsArea() {
    if (_isSearching) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Finding recipes…',
                style: TextStyle(color: Colors.grey, fontSize: 15)),
          ],
        ),
      );
    }

    if (!_hasSearched) {
      return _buildEmptyState();
    }

    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off_rounded,
                  size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'No recipes found',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Try different keywords or fewer selections.',
                style: TextStyle(
                    fontSize: 14, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Result count + pagination info
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '${_results.length} recipe${_results.length == 1 ? '' : 's'} found',
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade600),
              ),
              const Spacer(),
              if (_totalPages > 1)
                Text(
                  'Page ${_currentPage + 1} of $_totalPages',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade600),
                ),
            ],
          ),
        ),

        // Recipe cards
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              ..._currentPageRecipes
                  .map((recipe) => _RecipeCard(
                        recipe: recipe,
                        isFavorited: _isFavorited(recipe.title),
                        onToggleFavorite: () => _toggleFavorite(recipe),
                        onAddToGrocery: () =>
                            _addIngredientsToGrocery(recipe),
                      )),

              // Pagination buttons
              if (_totalPages > 1) _buildPaginationRow(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaginationRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _currentPage > 0
                  ? () => setState(() => _currentPage--)
                  : null,
              icon: const Icon(Icons.chevron_left_rounded),
              label: const Text('Previous'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange.shade700,
                side: BorderSide(color: Colors.orange.shade300),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: _currentPage < _totalPages - 1
                  ? () => setState(() => _currentPage++)
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
              label: const Text('Next'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.restaurant_rounded,
                  size: 56, color: Colors.orange.shade400),
            ),
            const SizedBox(height: 24),
            const Text(
              'Find Bariatric Recipes',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Type keywords like ingredients, dietary goals, or food types and tap Search.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.5),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _navigateToBuildRecipe,
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text('Build Your Own Recipe'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade800,
                    side: BorderSide(color: Colors.orange.shade300),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _favorites.isEmpty ? null : _showOpenSavedDialog,
                  icon: const Icon(Icons.bookmark_rounded, size: 18),
                  label: const Text('Open Saved Recipe'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                'high protein',
                'low sugar',
                'soft foods',
                'chicken',
                'Greek yogurt',
                'post-op',
              ].map((suggestion) {
                return ActionChip(
                  label: Text(suggestion),
                  onPressed: () {
                    _addKeyword(suggestion);
                  },
                  backgroundColor: Colors.orange.shade50,
                  side: BorderSide(color: Colors.orange.shade200),
                  labelStyle:
                      TextStyle(color: Colors.orange.shade800),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RECIPE CARD (stateful — owns its own nutrition-panel state)
// ─────────────────────────────────────────────────────────────────────────────

class _RecipeCard extends StatefulWidget {
  final _Recipe recipe;
  final bool isFavorited;
  final VoidCallback onToggleFavorite;
  final VoidCallback onAddToGrocery;

  const _RecipeCard({
    required this.recipe,
    required this.isFavorited,
    required this.onToggleFavorite,
    required this.onAddToGrocery,
  });

  @override
  State<_RecipeCard> createState() => _RecipeCardState();
}

class _RecipeCardState extends State<_RecipeCard> {
  bool _isAnalyzingNutrition = false;
  RecipeNutrition? _nutrition;
  int _matchedCount = 0;

  // ── Recipe Nutrition Panel (Section 8) ──────────────────────────────────
  // Same matching approach as submit_recipe.dart: fuzzy-match this recipe's
  // ingredient strings against the user's saved ingredients, then sum totals.
  Future<void> _analyzeNutrition() async {
    setState(() {
      _isAnalyzingNutrition = true;
      _nutrition = null;
      _matchedCount = 0;
    });

    try {
      final saved = await SavedIngredientsService.loadSavedIngredients();
      if (saved.isEmpty) {
        if (mounted) {
          setState(() => _isAnalyzingNutrition = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'No saved ingredients yet. Scan and save products first to enable nutrition analysis.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final List<NutritionInfo> matches = [];
      for (final ingredientText in widget.recipe.ingredients) {
        final name = ingredientText.trim().toLowerCase();
        if (name.length < 3) continue;

        final found = saved.where((item) {
          final itemName = item.productName.toLowerCase();
          final nameWords = name.split(' ');
          final itemWords = itemName.split(' ');
          if (itemName.contains(name) || name.contains(itemName)) return true;
          for (final word in nameWords) {
            if (word.length >= 3 && itemWords.any((iw) => iw.contains(word))) {
              return true;
            }
          }
          return false;
        }).toList();

        for (final item in found) {
          if (!matches.any((m) =>
              m.productName.toLowerCase() == item.productName.toLowerCase())) {
            matches.add(item);
          }
        }
      }

      if (matches.isEmpty) {
        if (mounted) {
          setState(() => _isAnalyzingNutrition = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Could not match these ingredients to your saved items.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final totals = RecipeNutritionService.calculateTotals(matches);
      if (mounted) {
        setState(() {
          _nutrition = totals;
          _matchedCount = matches.length;
          _isAnalyzingNutrition = false;
        });
      }
    } catch (e) {
      AppConfig.debugPrint('⚠️ Nutrition analysis error: $e');
      if (mounted) setState(() => _isAnalyzingNutrition = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phase = _classifyPhase(widget.recipe);
    final info = _phaseInfo[phase]!;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ExpansionTile(
        tilePadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: EdgeInsets.zero,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.recipe.title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: info.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: info.color.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(info.icon, size: 12, color: info.color),
                  const SizedBox(width: 4),
                  Text(info.label,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: info.color)),
                ],
              ),
            ),
          ],
        ),
        subtitle: widget.recipe.description.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  widget.recipe.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600),
                ),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                widget.isFavorited
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: widget.isFavorited ? Colors.red : Colors.grey.shade400,
                size: 22,
              ),
              onPressed: widget.onToggleFavorite,
              tooltip: widget.isFavorited
                  ? 'Remove from favorites'
                  : 'Add to favorites',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
            Icon(Icons.expand_more_rounded,
                color: Colors.grey.shade500),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(height: 8),

                // Ingredients
                Row(
                  children: [
                    Icon(Icons.shopping_basket_rounded,
                        size: 16,
                        color: Colors.orange.shade700),
                    const SizedBox(width: 6),
                    Text(
                      'Ingredients (${widget.recipe.ingredients.length})',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade800),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...widget.recipe.ingredients.map((ing) => Padding(
                      padding:
                          const EdgeInsets.only(left: 8, bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('• ',
                              style: TextStyle(
                                  color: Colors.orange.shade600,
                                  fontWeight: FontWeight.bold)),
                          Expanded(
                            child: Text(ing,
                                style: const TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    )),

                const SizedBox(height: 14),

                // Instructions
                Row(
                  children: [
                    Icon(Icons.format_list_numbered_rounded,
                        size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 6),
                    Text(
                      'Instructions',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.recipe.instructions,
                  style: const TextStyle(
                      fontSize: 13, height: 1.5),
                ),

                const SizedBox(height: 16),

                // ── Recipe Nutrition Panel (Section 8) ──────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.analytics_rounded,
                              size: 16, color: Colors.teal.shade700),
                          const SizedBox(width: 6),
                          Text(
                            'Nutrition Panel',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal.shade800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_nutrition == null) ...[
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _isAnalyzingNutrition
                                ? null
                                : _analyzeNutrition,
                            icon: _isAnalyzingNutrition
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.calculate_outlined,
                                    size: 16),
                            label: Text(_isAnalyzingNutrition
                                ? 'Analyzing…'
                                : 'Analyze Nutrition'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.teal.shade700,
                              side: BorderSide(color: Colors.teal.shade300),
                            ),
                          ),
                        ),
                      ] else ...[
                        Text(
                          'Matched $_matchedCount saved ingredient${_matchedCount == 1 ? '' : 's'}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 8),
                        RecipeNutritionDisplay(nutrition: _nutrition!),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Action buttons
                Row(
                  children: [
                    // Favorite
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: widget.onToggleFavorite,
                        icon: Icon(
                          widget.isFavorited
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 16,
                          color: widget.isFavorited
                              ? Colors.red
                              : Colors.grey.shade600,
                        ),
                        label: Text(
                          widget.isFavorited ? 'Saved' : 'Favorite',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: widget.isFavorited
                              ? Colors.red
                              : Colors.grey.shade700,
                          side: BorderSide(
                            color: widget.isFavorited
                                ? Colors.red.shade300
                                : Colors.grey.shade300,
                          ),
                          padding: const EdgeInsets.symmetric(
                              vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Add to Cookbook
                    Expanded(
                      child: AddToCookbookButton(
                        recipeName: widget.recipe.title,
                        ingredients: widget.recipe.ingredients.join(', '),
                        directions: widget.recipe.instructions,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Grocery list
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: widget.onAddToGrocery,
                        icon: const Icon(Icons.add_shopping_cart_rounded,
                            size: 16),
                        label: const Text('Grocery',
                            style: TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.orange.shade700,
                          padding:
                              const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}