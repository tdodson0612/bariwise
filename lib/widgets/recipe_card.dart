// lib/widgets/recipe_card.dart - UPDATED: Added Cookbook button
import 'package:flutter/material.dart';
import 'package:bari_wise/services/ratings_service.dart';
import 'package:bari_wise/services/submitted_recipes_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/submitted_recipe.dart';
import '../services/auth_service.dart';
import '../services/error_handling_service.dart';
import '../widgets/rating_dialog.dart';
import '../widgets/add_to_cookbook_button.dart'; // 🔥 ADD THIS

class RecipeCard extends StatefulWidget {
  final SubmittedRecipe recipe;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onRatingChanged;

  const RecipeCard({
    super.key,
    required this.recipe,
    required this.onDelete,
    required this.onEdit,
    required this.onRatingChanged,
  });

  @override
  State<RecipeCard> createState() => _RecipeCardState();
}

class _RecipeCardState extends State<RecipeCard> {
  double _averageRating = 0.0;
  int _ratingCount = 0;
  bool _isLoadingRating = true;
  int? _userRating;

  // Cache keys
  static const String _ratingCachePrefix = 'recipe_rating_';
  static const String _userRatingCachePrefix = 'recipe_user_rating_';
  static const Duration _cacheDuration = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _loadRating();
  }

  // FIX #2: Check if this recipe belongs to the current user
  bool get _isOwnRecipe {
    final currentUserId = AuthService.currentUserId;
    return widget.recipe.userId == currentUserId;
  }

  /// Get cache key for recipe ratings
  String _getRatingCacheKey() => '$_ratingCachePrefix${widget.recipe.id}';
  String _getUserRatingCacheKey() => '$_userRatingCachePrefix${widget.recipe.id}';

  /// Load rating from cache first, then database if stale
  Future<void> _loadRating() async {
    if (!mounted) return;

    // Check if recipe ID is valid
    if (widget.recipe.id == null) {
      if (mounted) {
        setState(() {
          _averageRating = 0.0;
          _ratingCount = 0;
          _isLoadingRating = false;
        });
      }
      return;
    }

    setState(() {
      _isLoadingRating = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Try to load from cache first
      final cachedRatingData = prefs.getString(_getRatingCacheKey());
      final cachedUserRating = prefs.getInt(_getUserRatingCacheKey());
      
      bool usedCache = false;
      
      if (cachedRatingData != null) {
        final ratingData = json.decode(cachedRatingData);
        final cacheTime = ratingData['timestamp'] as int?;
        
        if (cacheTime != null) {
          final cacheAge = DateTime.now().millisecondsSinceEpoch - cacheTime;
          
          if (cacheAge < _cacheDuration.inMilliseconds) {
            // Cache is valid, use it
            if (mounted) {
              setState(() {
                _averageRating = (ratingData['average'] as num?)?.toDouble() ?? 0.0;
                _ratingCount = ratingData['count'] as int? ?? 0;
                _userRating = cachedUserRating;
                _isLoadingRating = false;
              });
            }
            usedCache = true;
            return;
          }
        }
      }
      
      // Cache miss or stale, fetch from database
      final ratingData = await RatingsService.getRecipeAverageRating(widget.recipe.id!);
      final userRating = await RatingsService.getUserRecipeRating(widget.recipe.id!);

      // Cache the results
      final cacheData = {
        'average': ratingData['average'] ?? 0.0,
        'count': ratingData['count'] ?? 0,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      await prefs.setString(_getRatingCacheKey(), json.encode(cacheData));
      if (userRating != null) {
        await prefs.setInt(_getUserRatingCacheKey(), userRating);
      } else {
        await prefs.remove(_getUserRatingCacheKey());
      }

      if (mounted) {
        setState(() {
          _averageRating = ratingData['average'] ?? 0.0;
          _ratingCount = ratingData['count'] ?? 0;
          _userRating = userRating;
          _isLoadingRating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        // On error, try to use cached value even if stale
        try {
          final prefs = await SharedPreferences.getInstance();
          final cachedRatingData = prefs.getString(_getRatingCacheKey());
          final cachedUserRating = prefs.getInt(_getUserRatingCacheKey());
          
          if (cachedRatingData != null) {
            final ratingData = json.decode(cachedRatingData);
            setState(() {
              _averageRating = (ratingData['average'] as num?)?.toDouble() ?? 0.0;
              _ratingCount = ratingData['count'] as int? ?? 0;
              _userRating = cachedUserRating;
              _isLoadingRating = false;
            });
            return;
          }
        } catch (_) {}
        
        // Fall back to zero state
        setState(() {
          _averageRating = 0.0;
          _ratingCount = 0;
          _isLoadingRating = false;
        });
      }
    }
  }

  /// Invalidate cache for a specific recipe (call after rating)
  static Future<void> invalidateRecipeCache(int recipeId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_ratingCachePrefix$recipeId');
    await prefs.remove('$_userRatingCachePrefix$recipeId');
  }

  /// Clear all recipe rating caches (for debugging or logout)
  static Future<void> clearAllRatingCaches() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(_ratingCachePrefix) || key.startsWith(_userRatingCachePrefix)) {
        await prefs.remove(key);
      }
    }
  }

  Future<void> _deleteRecipe() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Recipe'),
          content: Text(
            'Are you sure you want to delete "${widget.recipe.recipeName}"? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      // Invalidate cache when deleting
      if (widget.recipe.id != null) {
        await invalidateRecipeCache(widget.recipe.id!);
      }
      widget.onDelete();
    }
  }

  Future<void> _shareRecipe() async {
    try {
      final recipeText = SubmittedRecipesService.generateShareableRecipeText({
        'recipe_name': widget.recipe.recipeName,
        'ingredients': widget.recipe.ingredients,
        'directions': widget.recipe.directions,
      });

      await Share.share(
        recipeText,
        subject: 'Recipe: ${widget.recipe.recipeName}',
      );
    } catch (e) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'Unable to share recipe',
        );
      }
    }
  }

  // FIX #2: Prevent rating own recipes
  Future<void> _rateRecipe() async {
    // Check if this is the user's own recipe
    if (_isOwnRecipe) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'You cannot rate your own recipe',
        );
      }
      return;
    }

    // Check if recipe ID is valid
    if (widget.recipe.id == null) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'Invalid recipe ID',
        );
      }
      return;
    }

    final result = await showDialog<int>(
      context: context,
      builder: (BuildContext context) {
        return RatingDialog(
          recipeId: widget.recipe.id!,
          recipeName: widget.recipe.recipeName,
          currentRating: _userRating,
        );
      },
    );

    if (result != null) {
      // Invalidate cache after rating change
      await invalidateRecipeCache(widget.recipe.id!);
      await _loadRating(); // Reload with fresh data
      widget.onRatingChanged();
    }
  }

  String _getIngredientPreview() {
    final lines = widget.recipe.ingredients
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();

    if (lines.isEmpty) return 'No ingredients listed';
    if (lines.length <= 3) return lines.join('\n');

    return '${lines.take(3).join('\n')}\n...';
  }

  Widget _buildStarRating() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(5, (index) {
          final starValue = index + 1;
          if (starValue <= _averageRating.floor()) {
            return const Icon(Icons.star, size: 16, color: Colors.amber);
          } else if (starValue - 1 < _averageRating && _averageRating < starValue) {
            return const Icon(Icons.star_half, size: 16, color: Colors.amber);
          } else {
            return Icon(Icons.star_border, size: 16, color: Colors.grey.shade400);
          }
        }),
        const SizedBox(width: 4),
        Text(
          _ratingCount > 0 
              ? '$_averageRating ($_ratingCount)' 
              : 'No ratings',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Recipe Name
            Row(
              children: [
                if (widget.recipe.isVerified)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.verified,
                      size: 20,
                      color: Colors.blue,
                    ),
                  ),
                
                Expanded(
                  child: Text(
                    widget.recipe.recipeName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    widget.recipe.recipeName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // FIX #2: Show "Your Recipe" badge instead of user rating for own recipes
                if (_isOwnRecipe)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 14, color: Colors.orange.shade700),
                        const SizedBox(width: 4),
                        Text(
                          'Your Recipe',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_userRating != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star, size: 14, color: Colors.blue),
                        const SizedBox(width: 4),
                        Text(
                          'You: $_userRating',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Rating Display
            if (_isLoadingRating)
              const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              _buildStarRating(),

            const SizedBox(height: 12),

            // Ingredients Preview
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.restaurant_menu, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        'Ingredients:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _getIngredientPreview(),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 🔥 UPDATED: Action Buttons with Cookbook
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onEdit,
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Edit'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                
                // 🔥 NEW: Cookbook button
                AddToCookbookButton(
                  recipeName: widget.recipe.recipeName,
                  ingredients: widget.recipe.ingredients,
                  directions: widget.recipe.directions,
                  recipeId: widget.recipe.id,
                  compact: true,
                ),
                const SizedBox(width: 8),
                
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _shareRecipe,
                    icon: const Icon(Icons.share, size: 16),
                    label: const Text('Share'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // FIX #2: Hide rate button for own recipes
                if (!_isOwnRecipe)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _rateRecipe,
                      icon: const Icon(Icons.star, size: 16),
                      label: Text(_userRating != null ? 'Update Rating' : 'Rate'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.amber.shade700,
                        side: BorderSide(color: Colors.amber.shade700),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                if (!_isOwnRecipe) const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _deleteRecipe,
                    icon: const Icon(Icons.delete, size: 16),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}