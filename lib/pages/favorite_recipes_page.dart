// lib/pages/favorite_recipes_page.dart - UPDATED: Added 4-button action bar
// Uses Cloudflare Worker for database queries
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/favorite_recipe.dart';
import '../widgets/app_drawer.dart';
import '../services/error_handling_service.dart';
import '../services/auth_service.dart';
import '../services/favorite_recipes_service.dart';
import '../services/feed_posts_service.dart';
import '../config/app_config.dart';

class FavoriteRecipesPage extends StatefulWidget {
  final List<FavoriteRecipe> favoriteRecipes;

  const FavoriteRecipesPage({
    super.key,
    required this.favoriteRecipes,
  });

  @override
  _FavoriteRecipesPageState createState() => _FavoriteRecipesPageState();
}

class _FavoriteRecipesPageState extends State<FavoriteRecipesPage> {
  List<FavoriteRecipe> _favoriteRecipes = [];
  bool _isLoading = false;

  static const Duration _cacheDuration = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    _favoriteRecipes = List.from(widget.favoriteRecipes);
    _loadFavoriteRecipes(forceRefresh: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (mounted) {
      _loadFavoriteRecipes(forceRefresh: false);
    }
  }

  Future<List<FavoriteRecipe>?> _getCachedFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final cachedData = prefs.getString('favorite_recipes_cached');
      if (cachedData != null) {
        final data = json.decode(cachedData);
        final timestamp = data['_cached_at'] as int?;
        
        if (timestamp != null) {
          final age = DateTime.now().millisecondsSinceEpoch - timestamp;
          final isCacheValid = age < _cacheDuration.inMilliseconds;
          
          if (isCacheValid) {
            final recipes = (data['recipes'] as List)
                .map((jsonString) {
                  try {
                    return FavoriteRecipe.fromJson(json.decode(jsonString));
                  } catch (e) {
                    return null;
                  }
                })
                .where((recipe) => recipe != null)
                .cast<FavoriteRecipe>()
                .toList();
            
            print('📦 Using cached favorites (${recipes.length} recipes)');
            return recipes;
          }
        }
      }
      
      final favoriteRecipesJson = prefs.getStringList('favorite_recipes_detailed') ?? [];
      if (favoriteRecipesJson.isEmpty) return null;
      
      final recipes = favoriteRecipesJson
          .map((jsonString) {
            try {
              return FavoriteRecipe.fromJson(json.decode(jsonString));
            } catch (e) {
              return null;
            }
          })
          .where((recipe) => recipe != null)
          .cast<FavoriteRecipe>()
          .toList();
      
      await _cacheFavorites(recipes);
      print('📦 Loaded from old cache format and migrated (${recipes.length} recipes)');
      return recipes;
    } catch (e) {
      print('Error loading cached favorites: $e');
      return null;
    }
  }

  Future<void> _cacheFavorites(List<FavoriteRecipe> recipes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final cacheData = {
        'recipes': recipes.map((recipe) => json.encode(recipe.toJson())).toList(),
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
      };
      
      await prefs.setString('favorite_recipes_cached', json.encode(cacheData));
      
      final favoriteRecipesJson = recipes
          .map((recipe) => json.encode(recipe.toJson()))
          .toList();
      await prefs.setStringList('favorite_recipes_detailed', favoriteRecipesJson);
      
      print('💾 Cached ${recipes.length} favorite recipes');
    } catch (e) {
      print('Error caching favorites: $e');
    }
  }

  Future<void> _invalidateFavoritesCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('favorite_recipes_cached');
      print('🗑️ Invalidated favorites cache');
    } catch (e) {
      print('Error invalidating favorites cache: $e');
    }
  }

  static Future<void> invalidateCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('favorite_recipes_cached');
    } catch (e) {
      print('Error invalidating favorites cache: $e');
    }
  }

  Future<void> _loadFavoriteRecipes({bool forceRefresh = false}) async {
    try {
      setState(() => _isLoading = true);

      final currentUserId = AuthService.currentUserId;
      if (currentUserId == null) {
        if (mounted) {
          setState(() => _isLoading = false);
          ErrorHandlingService.showSimpleError(context, 'Please log in to view favorites');
        }
        return;
      }

      if (!forceRefresh) {
        final cachedRecipes = await _getCachedFavorites();
        if (cachedRecipes != null) {
          if (mounted) {
            setState(() {
              _favoriteRecipes = cachedRecipes;
              _isLoading = false;
            });
          }
          return;
        }
      }

      final recipes = await FavoriteRecipesService.getFavoriteRecipes();

      if (mounted) {
        setState(() {
          _favoriteRecipes = recipes;
          _isLoading = false;
        });

        await _cacheFavorites(recipes);
        print('✅ Loaded ${recipes.length} favorites from database');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          showSnackBar: true,
          customMessage: 'Unable to load favorite recipes',
          onRetry: () => _loadFavoriteRecipes(forceRefresh: true),
        );
      }
    }
  }

  Future<void> _removeFavoriteRecipe(FavoriteRecipe recipe) async {
    try {
      final currentUserId = AuthService.currentUserId;
      if (currentUserId == null) return;

      String? favoriteId = recipe.id?.toString();

      if (favoriteId == null) {
        final searchResponse = await http.post(
          Uri.parse(AppConfig.cloudflareWorkerQueryEndpoint),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': 'select',
            'table': 'favorite_recipes_with_details',
            'filters': {
              'user_id': currentUserId,
              'title': recipe.recipeName,
            },
          }),
        );

        final favorites = jsonDecode(searchResponse.body) as List;
        if (favorites.isEmpty) {
          if (mounted) {
            ErrorHandlingService.showSimpleError(context, 'Recipe not found in favorites');
          }
          return;
        }

        favoriteId = favorites[0]['id'];
      }

      final removedRecipe = recipe;
      final removedIndex = _favoriteRecipes.indexOf(recipe);

      setState(() {
        _favoriteRecipes.remove(recipe);
      });

      await _invalidateFavoritesCache();

      final deleteResponse = await http.post(
        Uri.parse(AppConfig.cloudflareWorkerQueryEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'delete',
          'table': 'favorite_recipes',
          'filters': {'id': favoriteId},
        }),
      );

      if (deleteResponse.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed "${recipe.recipeName}" from favorites'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
            action: SnackBarAction(
              label: 'UNDO',
              textColor: Colors.white,
              onPressed: () => _undoRemoveFavorite(removedRecipe, removedIndex),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to remove recipe from favorites',
        );
      }
    }
  }

  Future<void> _undoRemoveFavorite(FavoriteRecipe recipe, int index) async {
    try {
      final currentUserId = AuthService.currentUserId;
      final currentUsername = await AuthService.fetchCurrentUsername();

      if (currentUserId == null || currentUsername == null) {
        if (mounted) {
          ErrorHandlingService.showSimpleError(context, 'Unable to restore: User not found');
        }
        return;
      }

      final searchResponse = await http.post(
        Uri.parse(AppConfig.cloudflareWorkerQueryEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'select',
          'table': 'recipes',
          'filters': {'title': recipe.recipeName},
          'limit': 1,
        }),
      );

      final recipes = jsonDecode(searchResponse.body) as List;
      if (recipes.isEmpty) {
        if (mounted) {
          ErrorHandlingService.showSimpleError(context, 'Recipe not found in database');
        }
        return;
      }

      final recipeId = recipes[0]['id'];

      final readdResponse = await http.post(
        Uri.parse(AppConfig.cloudflareWorkerQueryEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'insert',
          'table': 'favorite_recipes',
          'data': {
            'user_id': currentUserId,
            'recipe_id': recipeId,
            'username': currentUsername,
            'title': recipe.recipeName,
            'description': recipe.description ?? '',
            'ingredients': recipe.ingredients,
            'directions': recipe.directions,
          },
        }),
      );

      if (readdResponse.statusCode == 200 || readdResponse.statusCode == 201) {
        await _invalidateFavoritesCache();

        setState(() {
          _favoriteRecipes.insert(index, recipe);
        });

        if (mounted) {
          ErrorHandlingService.showSuccess(context, 'Recipe restored to favorites');
        }
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to restore recipe',
        );
      }
    }
  }

  Future<void> _shareRecipeToFeed(FavoriteRecipe recipe) async {
    try {
      await FeedPostsService.shareRecipeToFeed(
        recipeName: recipe.recipeName,
        description: 'Shared from favorites',
        ingredients: recipe.ingredients,
        directions: recipe.directions,
        visibility: 'public', // or show a dialog to let user choose
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Recipe shared to your feed!'),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
            action: SnackBarAction(
              label: 'View Feed',
              textColor: Colors.white,
              onPressed: () {
                Navigator.pushNamed(context, '/home');
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
          category: ErrorHandlingService.databaseError,
          customMessage: 'Failed to share recipe',
        );
      }
    }
  }

  void _showRecipeDetails(FavoriteRecipe recipe) {
    List<String> ingredientsList = [];
    try {
      if (recipe.ingredients.trim().isEmpty) {
        ingredientsList = ['No ingredients listed'];
      } else {
        try {
          final parsed = jsonDecode(recipe.ingredients);
          if (parsed is List) {
            ingredientsList = parsed.map((item) {
              if (item is Map) {
                final qty = item['quantity'] ?? '';
                final unit = item['measurement'] ?? item['unit'] ?? '';
                final name = item['name'] ?? item['product_name'] ?? '';
                return '$qty $unit $name'.trim();
              }
              return item.toString();
            }).where((line) => line.trim().isNotEmpty).toList();
          }
        } catch (e) {
          ingredientsList = recipe.ingredients
              .split('\n')
              .where((line) => line.trim().isNotEmpty)
              .toList();
          
          if (ingredientsList.isEmpty) {
            ingredientsList = recipe.ingredients
                .split(',')
                .where((line) => line.trim().isNotEmpty)
                .toList();
          }
        }
        
        if (ingredientsList.isEmpty && recipe.ingredients.trim().isNotEmpty) {
          ingredientsList = [recipe.ingredients];
        }
      }
    } catch (e) {
      print('❌ Error parsing ingredients: $e');
      ingredientsList = [recipe.ingredients.isNotEmpty ? recipe.ingredients : 'No ingredients listed'];
    }

    List<String> directionsList = [];
    try {
      if (recipe.directions.trim().isEmpty) {
        directionsList = ['No directions provided'];
      } else {
        directionsList = recipe.directions
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .toList();
        
        if (directionsList.isEmpty) {
          directionsList = [recipe.directions];
        }
      }
    } catch (e) {
      print('❌ Error parsing directions: $e');
      directionsList = [recipe.directions.isNotEmpty ? recipe.directions : 'No directions provided'];
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
            maxWidth: 500,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.restaurant, color: Colors.white, size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        recipe.recipeName,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.orange.shade200,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.restaurant_menu, 
                              size: 24, 
                              color: Colors.orange.shade700
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                recipe.recipeName,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 16),

                      if (recipe.description != null && recipe.description!.trim().isNotEmpty) ...[
                        Container(
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.blue.shade200,
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.info_outline, 
                                    size: 20, 
                                    color: Colors.blue.shade700
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'About This Recipe',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Text(
                                recipe.description!,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 16),
                      ],

                      Row(
                        children: [
                          Icon(Icons.shopping_cart, 
                            size: 24, 
                            color: Colors.orange.shade700
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Ingredients',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.orange.shade200,
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: ingredientsList.map((ingredient) {
                            return Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '• ',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange.shade700,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      ingredient.trim(),
                                      style: TextStyle(
                                        fontSize: 15,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      SizedBox(height: 24),

                      Row(
                        children: [
                          Icon(Icons.format_list_numbered, 
                            size: 24, 
                            color: Colors.blue.shade700
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Instructions',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.blue.shade200,
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: directionsList.asMap().entries.map((entry) {
                            int idx = entry.key;
                            String direction = entry.value;
                            return Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade700,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${idx + 1}',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      direction.trim(),
                                      style: TextStyle(
                                        fontSize: 15,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _shareRecipeToFeed(recipe);
                        },
                        icon: Icon(Icons.share, size: 20),
                        label: Text(
                          'Share to Feed',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade600,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'Close',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: onPressed == null ? Colors.grey : color,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: Icon(icon, color: Colors.white, size: 28),
            onPressed: onPressed,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Favorite Recipes (${_favoriteRecipes.length})'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () async {
              try {
                await _loadFavoriteRecipes(forceRefresh: true);
                if (mounted) {
                  ErrorHandlingService.showSuccess(context, 'Recipes refreshed');
                }
              } catch (e) {
                if (mounted) {
                  await ErrorHandlingService.handleError(
                    context: context,
                    error: e,
                    category: ErrorHandlingService.databaseError,
                    showSnackBar: true,
                    customMessage: 'Failed to refresh recipes',
                  );
                }
              }
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      drawer: AppDrawer(currentPage: 'favorite_recipes'),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Loading favorite recipes...',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            )
          : _favoriteRecipes.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: () => _loadFavoriteRecipes(forceRefresh: true),
                  child: ListView.builder(
                    padding: EdgeInsets.all(16),
                    itemCount: _favoriteRecipes.length,
                    itemBuilder: (context, index) {
                      final recipe = _favoriteRecipes[index];
                      return Card(
                        margin: EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          onTap: () => _showRecipeDetails(recipe),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.restaurant,
                                    color: Colors.red,
                                    size: 28,
                                  ),
                                ),
                                SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        recipe.recipeName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Tap to view recipe details',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'view',
                                      child: Row(
                                        children: [
                                          Icon(Icons.visibility, size: 20, color: Colors.blue),
                                          SizedBox(width: 12),
                                          Text('View Recipe'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'share',
                                      child: Row(
                                        children: [
                                          Icon(Icons.share, size: 20, color: Colors.orange),
                                          SizedBox(width: 12),
                                          Text('Share to Feed'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'remove',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete, size: 20, color: Colors.red),
                                          SizedBox(width: 12),
                                          Text('Remove', style: TextStyle(color: Colors.red)),
                                        ],
                                      ),
                                    ),
                                  ],
                                  onSelected: (value) {
                                    if (value == 'view') {
                                      _showRecipeDetails(recipe);
                                    } else if (value == 'share') {
                                      _shareRecipeToFeed(recipe);
                                    } else if (value == 'remove') {
                                      _removeFavoriteRecipe(recipe);
                                    }
                                  },
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

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.favorite_outline,
                size: 80,
                color: Colors.red.shade300,
              ),
            ),
            SizedBox(height: 24),
            Text(
              'No Favorite Recipes Yet',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'When you find recipes you love while scanning products, save them here for easy access anytime!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            SizedBox(height: 32),
            
            // 🔥 NEW: 4-Button Action Bar (replacing the 2 buttons)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildActionButton(
                    icon: Icons.qr_code_scanner,
                    label: 'Auto',
                    color: Colors.purple.shade600,
                    onPressed: () => Navigator.pushNamed(context, '/home'),
                  ),
                  _buildActionButton(
                    icon: Icons.camera_alt,
                    label: 'Scan',
                    color: Colors.orange.shade600,
                    onPressed: () => Navigator.pushNamed(context, '/home'),
                  ),
                  _buildActionButton(
                    icon: Icons.edit_outlined,
                    label: 'Code',
                    color: Colors.blue.shade600,
                    onPressed: () => Navigator.pushNamed(context, '/manual-barcode-entry'),
                  ),
                  _buildActionButton(
                    icon: Icons.search,
                    label: 'Search',
                    color: Colors.orange.shade800,
                    onPressed: () => Navigator.pushNamed(context, '/nutrition-search'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}