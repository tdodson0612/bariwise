// lib/home_screen.dart - FULLY FIXED VERSION WITH POST COMPOSER oh yeah!
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:bari_wise/services/local_draft_service.dart';
import 'package:bari_wise/services/saved_ingredients_service.dart';  
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:bari_wise/services/grocery_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bari_wise/widgets/add_to_cookbook_button.dart';
import 'package:bari_wise/models/nutrition_info.dart';
import 'package:bari_wise/widgets/premium_gate.dart';
import 'package:bari_wise/controllers/premium_gate_controller.dart';
import 'package:bari_wise/barihealthbar.dart';
import 'package:bari_wise/services/auth_service.dart';
import 'package:bari_wise/services/error_handling_service.dart';
import 'package:bari_wise/models/favorite_recipe.dart';
import 'package:bari_wise/pages/search_users_page.dart';
import 'package:bari_wise/widgets/app_drawer.dart';
import 'package:bari_wise/config/app_config.dart';
import 'package:bari_wise/widgets/menu_icon_with_badge.dart';
import 'package:bari_wise/services/favorite_recipes_service.dart';
import 'widgets/auto_barcode_scanner.dart';
import 'widgets/day7_congrats_popup.dart';
import 'services/tracker_service.dart';
import 'package:bari_wise/services/feed_posts_service.dart';
import 'package:bari_wise/models/draft_recipe.dart';
import 'package:bari_wise/services/draft_recipes_service.dart';
import 'services/picture_service.dart';
import 'package:bari_wise/widgets/tutorial_overlay.dart';


class Recipe {
  final String title;
  final String description;
  final List<String> ingredients;
  final String instructions;

  Recipe({
    required this.title,
    required this.description,
    required this.ingredients,
    required this.instructions,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'ingredients': ingredients,
        'instructions': instructions,
      };

  factory Recipe.fromJson(Map<String, dynamic> json) => Recipe(
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

class RecipeGenerator {
  static Future<List<Recipe>> searchByKeywords(List<String> rawKeywords) async {
    final keywords = rawKeywords
        .map((w) => w.trim().toLowerCase())
        .where((w) => w.isNotEmpty)
        .toSet()
        .toList();

    AppConfig.debugPrint('🔎 Selected keywords: $keywords');

    if (keywords.isEmpty) {
      AppConfig.debugPrint('⚠️ No keywords selected, falling back to healthy defaults.');
      return _getHealthyRecipes();
    }

    try {
      AppConfig.debugPrint('📡 Sending multi-keyword search: $keywords');

      final response = await http.post(
        Uri.parse(AppConfig.cloudflareWorkerQueryEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'search_recipes',
          'keyword': keywords,
          'limit': 50,
        }),
      );

      AppConfig.debugPrint('📡 Response status: ${response.statusCode}');
      AppConfig.debugPrint('📡 Response body: ${response.body}');

      if (response.statusCode != 200) {
        AppConfig.debugPrint('❌ Non-200 status: ${response.statusCode}');
        return _getHealthyRecipes();
      }

      final data = jsonDecode(response.body);

      if (data is Map<String, dynamic>) {
        final results = data['results'] as List? ?? [];
        final matchType = data['matchType'] ?? 'UNKNOWN';
        final searchedKeywords = data['searchedKeywords'] as List? ?? [];
        final totalResults = data['totalResults'] ?? 0;

        AppConfig.debugPrint('✅ Search complete: $matchType match, $totalResults total results');
        AppConfig.debugPrint('🔍 Searched keywords: $searchedKeywords');

        if (results.isEmpty) {
          AppConfig.debugPrint('⚠️ No recipes found, using healthy defaults');
          return _getHealthyRecipes();
        }

        final recipes = results
            .map((item) => Recipe.fromJson(item as Map<String, dynamic>))
            .where((r) => r.title.isNotEmpty)
            .toList();

        AppConfig.debugPrint('✅ Parsed ${recipes.length} recipes');
        return recipes;
      }

      AppConfig.debugPrint('⚠️ Unexpected response format, using defaults');
      return _getHealthyRecipes();

    } catch (e) {
      AppConfig.debugPrint('❌ Error searching recipes: $e');
      return _getHealthyRecipes();
    }
  }

  static List<Recipe> generateSuggestions(int bariHealthScore) {
    if (bariHealthScore >= 75) {
      return _getHealthyRecipes();
    } else if (bariHealthScore >= 50) {
      return _getModerateRecipes();
    } else {
      return _getDetoxRecipes();
    }
  }

  static List<Recipe> _getHealthyRecipes() => [
        Recipe(
          title: 'Mediterranean Salmon Bowl',
          description: 'Heart-healthy salmon with fresh vegetables',
          ingredients: ['Fresh salmon', 'Mixed greens', 'Olive oil', 'Lemon', 'Cherry tomatoes'],
          instructions: 'Grill salmon, serve over greens with olive oil and lemon dressing.',
        ),
        Recipe(
          title: 'Quinoa Vegetable Stir-fry',
          description: 'Protein-rich quinoa with colorful vegetables',
          ingredients: ['Quinoa', 'Bell peppers', 'Broccoli', 'Carrots', 'Soy sauce'],
          instructions: 'Cook quinoa, stir-fry vegetables, combine and season.',
        ),
      ];

  static List<Recipe> _getModerateRecipes() => [
        Recipe(
          title: 'Baked Chicken with Sweet Potato',
          description: 'Lean protein with nutrient-rich sweet potato',
          ingredients: ['Chicken breast', 'Sweet potato', 'Herbs', 'Olive oil'],
          instructions: 'Season chicken, bake with sweet potato slices until golden.',
        ),
        Recipe(
          title: 'Lentil Soup',
          description: 'Fiber-rich soup to support bari health',
          ingredients: ['Red lentils', 'Carrots', 'Celery', 'Onions', 'Vegetable broth'],
          instructions: 'Sauté vegetables, add lentils and broth, simmer until tender.',
        ),
      ];

  static List<Recipe> _getDetoxRecipes() => [
        Recipe(
          title: 'Green Detox Smoothie',
          description: 'bari-cleansing green smoothie',
          ingredients: ['Spinach', 'Green apple', 'Lemon juice', 'Ginger', 'Water'],
          instructions: 'Blend all ingredients until smooth, serve immediately.',
        ),
        Recipe(
          title: 'Steamed Vegetables with Brown Rice',
          description: 'Simple, clean eating option',
          ingredients: ['Brown rice', 'Broccoli', 'Carrots', 'Zucchini', 'Herbs'],
          instructions: 'Steam vegetables, serve over cooked brown rice with herbs.',
        ),
      ];
}

class NutritionApiService {
  static String get baseUrl => AppConfig.openFoodFactsUrl;

  static Future<NutritionInfo?> fetchNutritionInfo(String barcode) async {
    if (barcode.isEmpty) return null;
    final url = '$baseUrl/$barcode.json';

    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {'User-Agent': 'FlutterApp/1.0'},
          )
          .timeout(Duration(seconds: AppConfig.apiTimeoutSeconds));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (AppConfig.enableDebugPrints) {
          print('📡 OpenFoodFacts API Response:');
          print('  Status: ${data['status']}');
          print('  Product name: ${data['product']?['product_name']}');
          print('  Nutriments keys: ${data['product']?['nutriments']?.keys.toList()}');
          print('  Sample nutriment: ${data['product']?['nutriments']?['energy-kcal_100g']}');
        }
        
        if (data['status'] == 1) {
          return NutritionInfo.fromJson(data);
        }
      }
      
      return null;
    } catch (e) {
      if (AppConfig.enableDebugPrints) {
        print('Nutrition API Error: $e');
      }
      return null;
    }
  }
}

class BarcodeScannerService {
  static Future<String?> scanBarcode(String imagePath) async {
    if (imagePath.isEmpty) return null;
    final inputImage = InputImage.fromFilePath(imagePath);
    final barcodeScanner = BarcodeScanner();

    try {
      final barcodes = await barcodeScanner.processImage(inputImage);
      if (barcodes.isNotEmpty) {
        return barcodes.first.rawValue;
      }
      return null;
    } catch (e) {
      print('Barcode Scanner Error: $e');
      return null;
    } finally {
      await barcodeScanner.close();
    }
  }

  static Future<NutritionInfo?> scanAndLookup(String imagePath) async {
    final barcode = await scanBarcode(imagePath);
    if (barcode == null) return null;
    return await NutritionApiService.fetchNutritionInfo(barcode);
  }
}

class HomePage extends StatefulWidget {
  final bool isPremium;
  const HomePage({super.key, this.isPremium = false});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
  bool _isScanning = false;
  List<Map<String, String>> _scannedRecipes = [];
  File? _imageFile;
  String _nutritionText = '';
  int? _bariHealthScore;
  bool _showbariBar = false;
  bool _isLoading = false;
  List<Recipe> _recipeSuggestions = [];
  List<FavoriteRecipe> _favoriteRecipes = [];
  bool _showInitialView = true;
  NutritionInfo? _currentNutrition;
  bool _showTutorial = false;

  String _defaultPostVisibility = 'public'; // Default visibility for new posts

  // Feed pagination state
  bool _isLoadingMorePosts = false;
  bool _hasMorePosts = true;
  int _currentFeedOffset = 0;
  static const int _postsPerPage = 10;

  // Scroll controller for feed
  final ScrollController _feedScrollController = ScrollController();

  // Like state tracking
  Map<String, bool> _postLikeStatus = {};
  Map<String, int> _postLikeCounts = {};
  Map<String, bool> _expandedComments = {};
  Map<String, List<Map<String, dynamic>>> _postComments = {};
  Map<String, bool> _savedPosts = {};
  final Map<String, TextEditingController> _commentControllers = {};



  late final PremiumGateController _premiumController;

  bool _isPremium = false;
  int _remainingScans = 3;
  bool _hasUsedAllFreeScans = false;

  InterstitialAd? _interstitialAd;
  bool _isAdReady = false;

  RewardedAd? _rewardedAd;
  bool _isRewardedAdReady = false;

  bool _isDisposed = false;

  final ImagePicker _picker = ImagePicker();
  final TextEditingController _searchController = TextEditingController();

  List<String> _keywordTokens = [];
  Set<String> _selectedKeywords = {};
  bool _isSearchingRecipes = false;

  int _currentRecipeIndex = 0;
  static const int _recipesPerPage = 2;

  // NEW: GlobalKeys for tutorial highlights
  final GlobalKey _autoButtonKey = GlobalKey();
  final GlobalKey _scanButtonKey = GlobalKey();
  final GlobalKey _manualButtonKey = GlobalKey();
  final GlobalKey _lookupButtonKey = GlobalKey();

  // NEW: Feed state
  List<Map<String, dynamic>> _feedPosts = [];
  bool _isLoadingFeed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializePremiumController();
    _initializeAsync();
    _checkDay7Achievement();
    _loadFeed();
    _feedScrollController.addListener(_onFeedScroll);

  }

  bool _didPrecache = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didPrecache) {
      _didPrecache = true;
      _precacheImages();
    }
  }

  /// Check if user has reached 7-day streak and show popup
  Future<void> _checkDay7Achievement() async {
    try {
      final userId = AuthService.currentUserId;
      if (userId == null) return;
      
      final hasReachedDay7 = await TrackerService.hasReachedDay7Streak(userId);
      final hasShownPopup = await TrackerService.hasShownDay7Popup(userId);
      
      if (hasReachedDay7 && !hasShownPopup && mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (mounted) {
          await showDay7CongratsPopup(context);
          await TrackerService.markDay7PopupShown(userId);
        }
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Error checking day 7 achievement: $e');
    }
  }

  Future<void> _precacheImages() async {
    await precacheImage(
      const AssetImage('assets/backgrounds/home_background.jpeg'),
      context,
    );

    await precacheImage(
      const AssetImage('assets/backgrounds/login_background.jpeg'),
      context,
    );

    if (MediaQuery.of(context).size.width > 600) {
      await precacheImage(
        const AssetImage('assets/backgrounds/ipad_background.jpeg'),
        context,
      );
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _premiumController.removeListener(_onPremiumStateChanged);
    _interstitialAd?.dispose();
    _rewardedAd?.dispose();
    _searchController.dispose();
    _feedScrollController.dispose(); // 🔥 NEW
    super.dispose();
  }

  void _initializePremiumController() {
    _premiumController = PremiumGateController();
    _premiumController.addListener(_onPremiumStateChanged);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onPremiumStateChanged();
    });
  }

  void _onPremiumStateChanged() {
    if (!mounted || _isDisposed) return;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isDisposed) {
        final wasPremium = _isPremium;
        final isPremiumNow = _premiumController.isPremium;
        
        setState(() {
          _isPremium = isPremiumNow;
          _remainingScans = _premiumController.remainingScans;
          _hasUsedAllFreeScans = _premiumController.hasUsedAllFreeScans;
        });
        
        if (!wasPremium && isPremiumNow) {
          if (AppConfig.enableDebugPrints) {
            print("🎉 User became PREMIUM - disposing all ads");
          }
          
          _interstitialAd?.dispose();
          _interstitialAd = null;
          _isAdReady = false;
          
          _rewardedAd?.dispose();
          _rewardedAd = null;
          _isRewardedAdReady = false;
        }
        
        if (wasPremium && !isPremiumNow) {
          if (AppConfig.enableDebugPrints) {
            print("⬇️ User lost PREMIUM - loading ads");
          }
          
          _loadInterstitialAd();
          _loadRewardedAd();
        }
      }
    });
  }

  Future<void> _initializeAsync() async {
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      
      if (!mounted || _isDisposed) return;
      
      await _premiumController.refresh();
      
      if (AppConfig.enableDebugPrints) {
        print("🔐 Premium status after refresh: $_isPremium");
      }
      
      if (!_isPremium) {
        if (AppConfig.enableDebugPrints) {
          print("📺 Loading ads for FREE user");
        }
        _loadInterstitialAd();
        _loadRewardedAd();
      } else {
        if (AppConfig.enableDebugPrints) {
          print("🚫 Skipping ads for PREMIUM user");
        }
      }
      
      await _loadFavoriteRecipes();
      // Disabled auto-sync - only sync when user manually refreshes
      // await _syncFavoritesFromDatabase();

    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.initializationError,
          showSnackBar: true,
          customMessage: 'Failed to initialize home screen',
        );
      }
    }
  }

  void _loadInterstitialAd() {
    if (_isDisposed || _isPremium) {
      if (AppConfig.enableDebugPrints && _isPremium) {
        print("🚫 Not loading interstitial - user is PREMIUM");
      }
      return;
    }

    InterstitialAd.load(
      adUnitId: AppConfig.interstitialAdId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          final isPremiumNow = _premiumController.isPremium;
          
          if (!_isDisposed && !isPremiumNow) {
            _interstitialAd = ad;
            _isAdReady = true;
            ad.setImmersiveMode(true);
            
            if (AppConfig.enableDebugPrints) {
              print("✅ Interstitial ad loaded (FREE user)");
            }
          } else {
            ad.dispose();
            if (AppConfig.enableDebugPrints) {
              print("🚫 Disposed ad - user is PREMIUM (became premium during load)");
            }
          }
        },
        onAdFailedToLoad: (error) {
          _isAdReady = false;
          if (AppConfig.enableDebugPrints) {
            print("❌ Interstitial failed to load: $error");
          }
        },
      ),
    );
  }

  void _loadRewardedAd() {
    if (_isDisposed || _isPremium) {
      if (AppConfig.enableDebugPrints && _isPremium) {
        print("🚫 Not loading rewarded ad - user is PREMIUM");
      }
      return;
    }

    RewardedAd.load(
      adUnitId: AppConfig.rewardedAdId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          final isPremiumNow = _premiumController.isPremium;
          
          if (!_isDisposed && !isPremiumNow) {
            _rewardedAd = ad;
            _isRewardedAdReady = true;
            
            if (AppConfig.enableDebugPrints) {
              print("✅ Rewarded ad loaded (FREE user)");
            }
          } else {
            ad.dispose();
            if (AppConfig.enableDebugPrints) {
              print("🚫 Disposed rewarded ad - user is PREMIUM (became premium during load)");
            }
          }
        },
        onAdFailedToLoad: (error) {
          _isRewardedAdReady = false;
          if (AppConfig.enableDebugPrints) {
            print("❌ Rewarded ad failed to load: $error");
          }
        },
      ),
    );
  }

  void _showInterstitialAd(VoidCallback onAdClosed) {
    final isPremiumNow = _premiumController.isPremium;
    
    if (_isDisposed || isPremiumNow || !_isAdReady || _interstitialAd == null) {
      if (AppConfig.enableDebugPrints) {
        if (isPremiumNow) {
          print("🚫 BLOCKED AD: User is PREMIUM");
        } else if (!_isAdReady) {
          print("⚠️ Ad not ready");
        } else if (_interstitialAd == null) {
          print("⚠️ No ad loaded");
        }
      }
      onAdClosed();
      return;
    }

    if (AppConfig.enableDebugPrints) {
      print("📺 Showing interstitial ad to FREE user");
    }

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!_premiumController.isPremium) {
          _loadInterstitialAd();
        }
        onAdClosed();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!_premiumController.isPremium) {
          _loadInterstitialAd();
        }
        onAdClosed();
      },
    );

    _interstitialAd!.show();
    _isAdReady = false;
  }

  Future<void> _syncFavoritesFromDatabase() async {
    try {
      final currentUserId = AuthService.currentUserId;
      if (currentUserId == null) {
        if (AppConfig.enableDebugPrints) {
          print('⏭️ Skipping favorites sync - no user logged in');
        }
        return;
      }

      final response = await http.post(
        Uri.parse(AppConfig.cloudflareWorkerQueryEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'select',
          'table': 'favorite_recipes_with_details',
          'filters': {'user_id': currentUserId},
          'orderBy': 'created_at',
          'ascending': false,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;

        final favoriteRecipes = data.map((json) {
          return FavoriteRecipe(
            id: json['id'],
            userId: json['user_id'] ?? '',
            recipeName: json['recipe_name'] ?? json['title'] ?? '',
            ingredients: json['ingredients'] ?? '',
            directions: json['directions'] ?? '',
            createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
            updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at']) : null,
          );
        }).toList();

        if (mounted && !_isDisposed) {
          setState(() => _favoriteRecipes = favoriteRecipes);
        }

        await _saveFavoritesToLocalCache(favoriteRecipes);
        if (AppConfig.enableDebugPrints) {
          print('✅ Synced ${favoriteRecipes.length} favorites from database');
        }
      }
    } catch (e) {
      // Silent fail - don't show error popup on home screen load
      if (AppConfig.enableDebugPrints) {
        print('⚠️ Error syncing favorites (non-critical): $e');
      }
      // Continue without favorites - not critical for home screen
    }
  }

  void _initKeywordButtonsFromProductName(String productName) {
    final tokens = productName
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll(RegExp(r'[^\w]'), ''))
        .where((w) => w.length > 2)
        .toList();

    setState(() {
      _keywordTokens = tokens;
      _selectedKeywords = tokens.toSet();
    });
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

  Future<void> _searchRecipesBySelectedKeywords() async {
    if (_selectedKeywords.isEmpty) {
      ErrorHandlingService.showSimpleError(
        context,
        'Please select at least one keyword.',
      );
      return;
    }

    try {
      setState(() {
        _isSearchingRecipes = true;
        _currentRecipeIndex = 0;
      });

      final recipes = await RecipeGenerator.searchByKeywords(_selectedKeywords.toList());

      if (mounted && !_isDisposed) {
        setState(() => _recipeSuggestions = recipes);
      }

      if (recipes.isEmpty) {
        ErrorHandlingService.showSimpleError(
          context,
          'No recipes found for those ingredients.',
        );
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Error searching recipes',
        );
      }
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _isSearchingRecipes = false);
      }
    }
  }

  void _loadNextRecipeSuggestions() {
    if (_recipeSuggestions.isEmpty) return;
    
    setState(() {
      _currentRecipeIndex += _recipesPerPage;
      if (_currentRecipeIndex >= _recipeSuggestions.length) {
        _currentRecipeIndex = 0;
      }
    });
  }

  List<Recipe> _getCurrentPageRecipes() {
    if (_recipeSuggestions.isEmpty) return [];
    
    final endIndex = (_currentRecipeIndex + _recipesPerPage).clamp(0, _recipeSuggestions.length);
    
    return _recipeSuggestions.sublist(_currentRecipeIndex, endIndex);
  }

  Future<void> _loadFavoriteRecipes() async {
    try {
      final recipes = await FavoriteRecipesService.getFavoriteRecipes();

      if (mounted && !_isDisposed) {
        setState(() => _favoriteRecipes = recipes);
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          showSnackBar: true,
          customMessage: 'Failed to load favorite recipes',
        );
      }
    }
  }

  Future<void> _saveFavoritesToLocalCache(List<FavoriteRecipe> favorites) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serialized = favorites.map((recipe) => jsonEncode(recipe.toCache())).toList();

      await prefs.setStringList('favorite_recipes_detailed', serialized);
      print('✅ Synced favorites to cache');
    } catch (e) {
      print('⚠️ Error saving favorites locally: $e');
    }
  }

  Future<void> _toggleFavoriteRecipe(Recipe recipe) async {
    try {
      final name = recipe.title;
      final ingredients = recipe.ingredients.join(', ');
      final directions = recipe.instructions;

      final existing = await FavoriteRecipesService.findExistingFavorite(recipeName: name);

      if (existing != null) {
        if (existing.id == null) {
          throw Exception('Favorite recipe has no ID — cannot remove');
        }

        await FavoriteRecipesService.removeFavoriteRecipe(existing.id!);

        setState(() {
          _favoriteRecipes.removeWhere((r) => r.recipeName == name);
        });

        if (mounted) {
          ErrorHandlingService.showSuccess(context, 'Removed from favorites');
        }
      } else {
        try {
          final created = await FavoriteRecipesService.addFavoriteRecipe(
            name,
            ingredients,
            directions,
          );

          setState(() => _favoriteRecipes.add(created));
          await _saveFavoritesToLocalCache(_favoriteRecipes);

          if (mounted) {
            ErrorHandlingService.showSuccess(context, 'Added to favorites!');
          }
        } catch (e) {
          if (e.toString().contains('already in your favorites')) {
            if (mounted) {
              ErrorHandlingService.showSimpleError(
                context,
                'This recipe is already in your favorites',
              );
            }
            return;
          }
          rethrow;
        }
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Error saving recipe',
        );
      }
    }
  }

  bool _isRecipeFavorited(String recipeTitle) {
    return _favoriteRecipes.any((fav) => fav.recipeName == recipeTitle);
  }

  void _resetToHome() {
    if (!mounted || _isDisposed) return;

    setState(() {
      _showInitialView = true;
      _nutritionText = '';
      _showbariBar = false;
      _imageFile = null;
      _recipeSuggestions = [];
      _bariHealthScore = null;
      _isLoading = false;
      _scannedRecipes = [];
      _currentNutrition = null;
      _keywordTokens = [];
      _selectedKeywords = {};
      _currentRecipeIndex = 0;
    });
  }

  Future<void> _debugCheckAllCaches() async {
    print('\n========================================');
    print('🔍 DEBUG: Checking ALL cache keys...');
    print('========================================\n');
    
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys().toList()..sort();
    
    final relevantKeys = allKeys.where((key) => 
      key.toLowerCase().contains('unread') ||
      key.toLowerCase().contains('message') ||
      key.toLowerCase().contains('badge') ||
      key.toLowerCase().contains('cached')
    ).toList();
    
    print('📊 Total cache keys: ${allKeys.length}');
    print('📬 Message/badge related keys: ${relevantKeys.length}\n');
    
    if (relevantKeys.isEmpty) {
      print('✅ No message/badge cache keys found (this is suspicious!)\n');
    } else {
      print('🔎 RELEVANT CACHE KEYS:\n');
      
      for (final key in relevantKeys) {
        final value = prefs.get(key);
        print('Key: $key');
        print('  Type: ${value.runtimeType}');
        
        if (value is String) {
          try {
            final decoded = jsonDecode(value);
            final preview = decoded.toString();
            print('  Value (parsed): ${preview.length > 200 ? '${preview.substring(0, 200)}...' : preview}');
          } catch (_) {
            final preview = value.length > 100 ? '${value.substring(0, 100)}...' : value;
            print('  Value: $preview');
          }
        } else {
          print('  Value: $value');
        }
        print('');
      }
    }
    
    print('\n🎯 CHECKING SPECIFIC BADGE CACHE KEYS:\n');
    
    final knownKeys = [
      'cached_unread_count',
      'cached_unread_count_time',
      'cache_messages_${AuthService.currentUserId}',
      'user_chats',
      'friend_requests',
    ];
    
    for (final key in knownKeys) {
      final value = prefs.get(key);
      if (value != null) {
        print('✅ Found: $key');
        print('   Value: $value');
        print('   Type: ${value.runtimeType}\n');
      } else {
        print('❌ Missing: $key\n');
      }
    }
    
    final cachedTime = prefs.getInt('cached_unread_count_time');
    if (cachedTime != null) {
      final age = DateTime.now().millisecondsSinceEpoch - cachedTime;
      final ageSeconds = (age / 1000).round();
      print('⏰ Badge cache age: $ageSeconds seconds');
      print('   Fresh?: ${age < 3000 ? "YES ✅" : "NO ❌ (stale!)"}\n');
    }
    
    print('========================================');
    print('🔍 DEBUG CHECK COMPLETE');
    print('========================================\n');
  }

  Future<void> _debugClearAllCaches() async {
    print('\n🗑️ NUCLEAR OPTION: Clearing ALL caches...\n');
    
    final prefs = await SharedPreferences.getInstance();
    
    final keys = prefs.getKeys().where((key) => 
      key.toLowerCase().contains('unread') ||
      key.toLowerCase().contains('message') ||
      key.toLowerCase().contains('badge') ||
      key.toLowerCase().contains('cached') ||
      key.toLowerCase().contains('chat')
    ).toList();
    
    print('Found ${keys.length} cache keys to clear:');
    for (final key in keys) {
      print('  - $key');
      await prefs.remove(key);
    }
    
    print('\n✅ All message/badge caches cleared!');
    print('🔄 Now force refresh the badge...\n');
    
    await MenuIconWithBadge.invalidateCache();
    await AppDrawer.invalidateUnreadCache();
    
    MenuIconWithBadge.globalKey.currentState?.refresh();
    
    print('✅ Badge refresh triggered!\n');
  }

  Future<void> _performScan() async {
    try {
      if (!_premiumController.canAccessFeature(PremiumFeature.scan)) {
        Navigator.pushNamed(context, '/purchase');
        return;
      }

      final isPremiumNow = _premiumController.isPremium;
      
      if (AppConfig.enableDebugPrints) {
        print("🔍 Scan requested - Premium: $isPremiumNow, Ad Ready: $_isAdReady");
      }

      if (!isPremiumNow && _isAdReady) {
        if (AppConfig.enableDebugPrints) {
          print("📺 Showing ad before scan (FREE user)");
        }
        _showInterstitialAd(() => _executePerformScan());
      } else {
        if (AppConfig.enableDebugPrints) {
          if (isPremiumNow) {
            print("✅ Skipping ad (PREMIUM user)");
          } else {
            print("⚠️ Skipping ad (no ad ready)");
          }
        }
        _executePerformScan();
      }

    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.scanError,
          customMessage: 'Unable to start scan',
        );
      }
    }
  }

  Future<void> _executePerformScan() async {
    if (_isDisposed) return;

    try {
      setState(() => _isScanning = true);

      final success = await _premiumController.useScan();
      if (!success) {
        Navigator.pushNamed(context, '/purchase');
        return;
      }

      await Future.delayed(Duration(seconds: 2));

      if (mounted && !_isDisposed) {
        setState(() {
          _scannedRecipes = [
            {
              'name': 'Tomato Pasta',
              'ingredients': '2 cups pasta, 4 tomatoes, 1 onion, garlic, olive oil',
              'directions': '1. Cook pasta. 2. Sauté onion and garlic. 3. Add tomatoes. 4. Mix with pasta.',
            },
            {
              'name': 'Vegetable Stir Fry',
              'ingredients': '2 cups mixed vegetables, soy sauce, ginger, garlic, oil',
              'directions': '1. Heat oil in pan. 2. Add ginger and garlic. 3. Add vegetables. 4. Stir fry with soy sauce.',
            },
          ];
        });

        ErrorHandlingService.showSuccess(
          context,
          'Scan successful! ${_premiumController.remainingScans} scans remaining today.',
        );
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.scanError,
          customMessage: 'Error during scanning',
        );
      }
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _isScanning = false);
      }
    }
  }

  Future<void> _takePhoto() async {
    try {
      if (!_premiumController.canAccessFeature(PremiumFeature.scan)) {
        Navigator.pushNamed(context, '/purchase');
        return;
      }

      final isPremiumNow = _premiumController.isPremium;
      
      if (AppConfig.enableDebugPrints) {
        print("📸 Photo requested - Premium: $isPremiumNow, Ad Ready: $_isAdReady");
      }

      if (!isPremiumNow && _isAdReady) {
        if (AppConfig.enableDebugPrints) {
          print("📺 Showing ad before photo (FREE user)");
        }
        _showInterstitialAd(() => _executeTakePhoto());
      } else {
        if (AppConfig.enableDebugPrints) {
          if (isPremiumNow) {
            print("✅ Skipping ad (PREMIUM user)");
          } else {
            print("⚠️ Skipping ad (no ad ready)");
          }
        }
        _executeTakePhoto();
      }

    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.imageError,
          customMessage: 'Unable to access camera',
        );
      }
    }
  }

  Future<void> _executeTakePhoto() async {
    if (_isDisposed) return;

    if (_imageFile != null) {
      try {
        if (await _imageFile!.exists()) {
          await _imageFile!.delete();
          AppConfig.debugPrint('🗑️ Deleted old image file');
        }
      } catch (e) {
        AppConfig.debugPrint('⚠️ Could not delete old image: $e');
      }
    }

    try {
      if (mounted) {
        setState(() {
          _showInitialView = false;
          _nutritionText = '';
          _showbariBar = false;
          _imageFile = null;
          _recipeSuggestions = [];
          _isLoading = false;
          _scannedRecipes = [];
          _keywordTokens = [];
          _selectedKeywords = {};
          _currentNutrition = null;
        });
      }

      XFile? pickedFile;
      
      try {
        pickedFile = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 70,
          maxWidth: 1024,
          maxHeight: 1024,
          preferredCameraDevice: CameraDevice.rear,
        ).timeout(
          const Duration(seconds: 90),
          onTimeout: () {
            throw TimeoutException('Camera timed out after 90 seconds');
          },
        );
      } on TimeoutException {
        throw TimeoutException(
          'Camera operation timed out.\n\n'
          'Tips:\n'
          '• Close any background apps using the camera\n'
          '• Ensure sufficient device storage\n'
          '• Restart the app if problem persists'
        );
      } catch (e) {
        final errorString = e.toString().toLowerCase();
        
        if (errorString.contains('camera_access_denied') || errorString.contains('permission')) {
          throw Exception(
            'Camera permission denied.\n\n'
            'Please enable camera access in your device Settings:\n'
            'Settings > Apps > bari Wise > Permissions > Camera'
          );
        } else if (errorString.contains('no camera available')) {
          throw Exception('No camera found on this device');
        } else if (errorString.contains('already in use')) {
          throw Exception(
            'Camera is already in use by another app.\n\n'
            'Please close other camera apps and try again.'
          );
        }
        
        rethrow;
      }

      if (pickedFile == null) {
        if (mounted && !_isDisposed) {
          _resetToHome();
        }
        return;
      }

      final file = File(pickedFile.path);
      
      try {
        final exists = await file.exists();
        if (!exists) {
          throw Exception('Image file not found after capture');
        }

        final fileSize = await file.length();
        
        if (fileSize == 0) {
          throw Exception('Captured image is empty. Please try again.');
        }
        
        if (fileSize < 1024) {
          throw Exception('Captured image is too small. Please try again.');
        }
        
        if (fileSize > 10 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Image is large (${(fileSize / (1024 * 1024)).toStringAsFixed(1)}MB). Processing may take longer.'
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }

        if (mounted && !_isDisposed) {
          setState(() {
            _imageFile = file;
            _showInitialView = false;
          });
          
          AppConfig.debugPrint('✅ Image captured: ${(fileSize / 1024).toStringAsFixed(1)}KB');
          
          if (mounted && !_isDisposed) {
            await Future.delayed(Duration(milliseconds: 500));
            
            if (mounted && !_isDisposed && _imageFile != null) {
              AppConfig.debugPrint('📤 Starting photo submission...');
              await _submitPhoto();
            } else {
              AppConfig.debugPrint('⚠️ Photo submission cancelled - state changed');
            }
          }
        }
        
      } catch (e) {
        try {
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
        rethrow;
      }

    } on TimeoutException catch (e) {
      if (mounted) {
        await _showCameraTimeoutDialog(e.message ?? 'Camera operation timed out');
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = e.toString().replaceFirst('Exception: ', '');
        
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(child: Text('Camera Error')),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(errorMessage),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tip: Make sure no other apps are using the camera',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _resetToHome();
                },
                child: Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _executeTakePhoto();
                },
                icon: Icon(Icons.camera_alt),
                label: Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _showCameraTimeoutDialog(String message) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.wifi_off, color: Colors.orange),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Connection Issue')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
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
                      Icon(Icons.lightbulb_outline, 
                        color: Colors.blue.shade700, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Tips for Better Results:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  _buildTipRow('Close background apps'),
                  _buildTipRow('Ensure sufficient storage space'),
                  _buildTipRow('Check WiFi or cellular connection'),
                  _buildTipRow('Restart the app if needed'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetToHome();
            },
            child: Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _executeTakePhoto();
            },
            icon: Icon(Icons.refresh),
            label: Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipRow(String text) {
    return Padding(
      padding: EdgeInsets.only(left: 8, top: 4),
      child: Row(
        children: [
          Icon(Icons.arrow_right, size: 16, color: Colors.blue.shade700),
          SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: Colors.blue.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitPhoto() async {
    if (_imageFile == null || _isDisposed) return;

    final fileExists = await _imageFile!.exists();
    if (!fileExists) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'Image file not found. Please take a new photo.',
        );
        _resetToHome();
      }
      return;
    }

    try {
      final success = await _premiumController.useScan();
      if (!success) {
        Navigator.pushNamed(context, '/purchase');
        return;
      }

      if (mounted) {
        setState(() {
          _isLoading = true;
          _nutritionText = '';
          _showbariBar = false;
          _recipeSuggestions = [];
          _keywordTokens = [];
          _selectedKeywords = {};
        });
      }

      NutritionInfo? nutrition;
      
      try {
        nutrition = await BarcodeScannerService.scanAndLookup(_imageFile!.path).timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            throw TimeoutException('Barcode scanning is taking too long. This may be due to:\n• Poor barcode quality\n• Poor lighting conditions\n• Network connection issues');
          },
        );
      } catch (e) {
        if (e is TimeoutException) {
          rethrow;
        }
        
        if (e.toString().contains('network')) {
          throw Exception('Network error while looking up product. Please check your connection and try again.');
        }
        
        throw Exception('Error scanning barcode: ${e.toString()}');
      }

      if (nutrition != null) {
        AppConfig.debugPrint('✅ Nutrition data received:');
        AppConfig.debugPrint('  Product: ${nutrition.productName}');
        AppConfig.debugPrint('  Calories: ${nutrition.calories}');
        AppConfig.debugPrint('  Fat: ${nutrition.fat}');
        AppConfig.debugPrint('  Sugar: ${nutrition.sugar}');
        AppConfig.debugPrint('  Sodium: ${nutrition.sodium}');
      } else {
        AppConfig.debugPrint('❌ Nutrition is null');
      }

      if (nutrition == null) {
        if (mounted && !_isDisposed) {
          setState(() {
            _isLoading = false;
          });
          
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.orange,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Sorry, please try again',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _executeTakePhoto();
                        },
                        icon: Icon(Icons.camera_alt),
                        label: Text('Retake'),
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
                    SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _resetToHome();
                        },
                        child: Text('Cancel'),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        }
        return;
      }

      final score = BariHealthCalculator.calculate(
        fat: nutrition.fat,
        sodium: nutrition.sodium,
        sugar: nutrition.sugar,
        calories: nutrition.calories,
      );

      _initKeywordButtonsFromProductName(nutrition.productName);

      if (_keywordTokens.isNotEmpty) {
        _searchRecipesBySelectedKeywords();
      }

      if (mounted && !_isDisposed) {
        setState(() {
          _nutritionText = _buildNutritionDisplay(nutrition!);
          _bariHealthScore = score;
          _showbariBar = true;
          _isLoading = false;
          _currentNutrition = nutrition;
        });

        String message;
        if (_premiumController.isPremium) {
          message = '✅ Analysis successful! You have unlimited scans.';
        } else {
          final remaining = _premiumController.remainingScans.clamp(0, 3);
          message = '✅ Analysis successful! $remaining scan${remaining == 1 ? '' : 's'} remaining today.';
        }
        
        ErrorHandlingService.showSuccess(context, message);
      }

    } on TimeoutException catch (e) {
      if (mounted) {
        setState(() {
          _nutritionText = "Scanning timed out. Please try again.";
          _showbariBar = false;
          _isLoading = false;
        });

        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.scanError,
          customMessage: e.message ?? 'Scanning operation timed out',
          onRetry: _submitPhoto,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _nutritionText = "Error: ${e.toString()}";
          _showbariBar = false;
          _isLoading = false;
        });

        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.scanError,
          customMessage: 'Failed to analyze image',
          onRetry: _submitPhoto,
        );
      }
    }
  }

  String _buildNutritionDisplay(NutritionInfo nutrition) {
    return "Product: ${nutrition.productName}\n"
          "Energy: ${nutrition.calories.toStringAsFixed(1)} kcal/100g\n"
          "Fat: ${nutrition.fat.toStringAsFixed(1)} g/100g\n"
          "Sugar: ${nutrition.sugar.toStringAsFixed(1)} g/100g\n"
          "Sodium: ${nutrition.sodium.toStringAsFixed(1)} mg/100g";
  }

  // 🔥 NEW: Show photo upload dialog with camera/gallery options
  Future<void> _showPhotoUploadDialog() async {
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.add_photo_alternate, color: Colors.orange),
            SizedBox(width: 12),
            Text('Add Photo'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blue.shade50,
                child: Icon(Icons.camera_alt, color: Colors.blue.shade700),
              ),
              title: Text('Take Photo'),
              subtitle: Text('Use camera', style: TextStyle(fontSize: 12)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            SizedBox(height: 8),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.orange.shade50,
                child: Icon(Icons.photo_library, color: Colors.orange.shade700),
              ),
              title: Text('Choose from Gallery'),
              subtitle: Text('Pick existing photo', style: TextStyle(fontSize: 12)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
        ],
      ),
    );

    if (source == null) return;

    await _pickAndUploadPhoto(source);
  }

  // 🔥 NEW: Pick photo and show upload dialog
  Future<void> _pickAndUploadPhoto(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (pickedFile == null) return;

      final File imageFile = File(pickedFile.path);
      
      // Verify file exists and has content
      if (!await imageFile.exists()) {
        throw Exception('Image file not found');
      }

      final fileSize = await imageFile.length();
      if (fileSize == 0) {
        throw Exception('Image file is empty');
      }

      // Show upload dialog with preview
      if (mounted) {
        await _showPhotoPostDialog(imageFile);
      }

    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.imageError,
          customMessage: 'Failed to pick photo',
        );
      }
    }
  }

  // 🔥 NEW: Show dialog to create post with photo
  Future<void> _showPhotoPostDialog(File imageFile) async {
    final TextEditingController captionController = TextEditingController();
    bool isPosting = false;
    String selectedVisibility = _defaultPostVisibility;

    final posted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.add_photo_alternate, color: Colors.orange),
              SizedBox(width: 8),
              Text('Share Photo'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Photo preview
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      imageFile,
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.cover,
                    ),
                  ),
                  
                  SizedBox(height: 16),
                  
                  // Caption field
                  TextField(
                    controller: captionController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: "Add a caption...",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.orange, width: 2),
                      ),
                    ),
                  ),
                  
                  SizedBox(height: 16),
                  
                  // Visibility dropdown
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selectedVisibility == 'public' ? Icons.public : Icons.people,
                          size: 20,
                          color: Colors.grey.shade700,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Visible to:',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<String>(
                            value: selectedVisibility,
                            isExpanded: true,
                            underline: SizedBox(),
                            items: [
                              DropdownMenuItem(
                                value: 'public',
                                child: Row(
                                  children: [
                                    Icon(Icons.public, size: 18, color: Colors.blue),
                                    SizedBox(width: 8),
                                    Text('Everyone (Public)'),
                                  ],
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'friends',
                                child: Row(
                                  children: [
                                    Icon(Icons.people, size: 18, color: Colors.orange),
                                    SizedBox(width: 8),
                                    Text('Friends Only'),
                                  ],
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => selectedVisibility = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  SizedBox(height: 8),
                  
                  // Visibility info
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: selectedVisibility == 'public' 
                        ? Colors.blue.shade50 
                        : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selectedVisibility == 'public' 
                          ? Colors.blue.shade200 
                          : Colors.orange.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: selectedVisibility == 'public' 
                            ? Colors.blue.shade700 
                            : Colors.orange.shade700,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            selectedVisibility == 'public'
                              ? 'Anyone can see this photo'
                              : 'Only your friends can see this photo',
                            style: TextStyle(
                              fontSize: 12,
                              color: selectedVisibility == 'public' 
                                ? Colors.blue.shade900 
                                : Colors.orange.shade900,
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
          actions: [
            TextButton(
              onPressed: isPosting ? null : () => Navigator.pop(context, false),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isPosting
                  ? null
                  : () async {
                      setState(() => isPosting = true);

                      try {
                        // 🔥 Upload to R2 storage using your existing PictureService
                        AppConfig.debugPrint('📤 Uploading feed photo to R2...');
                        final photoUrl = await PictureService.uploadFeedPhoto(imageFile);
                        
                        AppConfig.debugPrint('✅ Photo uploaded: $photoUrl');
                        
                        // Create photo post with R2 URL
                        await FeedPostsService.createPhotoPost(
                          caption: captionController.text.trim(),
                          photoUrl: photoUrl,
                          visibility: selectedVisibility,
                        );

                        _defaultPostVisibility = selectedVisibility;

                        Navigator.pop(context, true);

                      } catch (e) {
                        setState(() => isPosting = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to upload photo: ${e.toString()}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: isPosting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text('Post'),
            ),
          ],
        ),
      ),
    );

    if (posted == true && mounted) {
      await _loadFeed(isRefresh: true);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Photo posted successfully!'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _loadFeed({bool isRefresh = false}) async {
    if (isRefresh) {
      setState(() {
        _currentFeedOffset = 0;
        _hasMorePosts = true;
        _feedPosts.clear();
      });
    }
    
    setState(() => _isLoadingFeed = true);

    try {
      AppConfig.debugPrint('🔄 Starting feed load (offset: $_currentFeedOffset)...');
      
      final posts = await FeedPostsService.getFeedPosts(
        limit: _postsPerPage,
        offset: _currentFeedOffset,
      );
      
      AppConfig.debugPrint('📊 Feed loaded: ${posts.length} posts');
      
      if (mounted) {
        setState(() {
          if (isRefresh) {
            _feedPosts = posts;
          } else {
            _feedPosts.addAll(posts);
          }
          _isLoadingFeed = false;
          
          // If we got fewer posts than requested, we've reached the end
          if (posts.length < _postsPerPage) {
            _hasMorePosts = false;
            AppConfig.debugPrint('📍 Reached end of feed');
          }
        });
        // Load like data for new posts
        await _loadLikeDataForPosts(posts);  // <-- ADD THIS LINE
        AppConfig.debugPrint('✅ Feed state updated with ${_feedPosts.length} total posts');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingFeed = false);
      }
      AppConfig.debugPrint('❌ Error loading feed: $e');
      print('Error loading feed: $e');
    }
  }

  /// Listen for scroll to bottom and load more posts
  void _onFeedScroll() {
    if (_feedScrollController.position.pixels >=
        _feedScrollController.position.maxScrollExtent - 200) {
      // User is near bottom (200px threshold)
      if (!_isLoadingMorePosts && _hasMorePosts) {
        _loadMorePosts();
      }
    }
  }

  /// Load like status and counts for a list of posts
  Future<void> _loadLikeDataForPosts(List<Map<String, dynamic>> posts) async {
    try {
      for (final post in posts) {
        final postId = post['id']?.toString();
        if (postId == null) continue;

        // Load like status and count in parallel
        final results = await Future.wait([
          FeedPostsService.hasUserLikedPost(postId),
          FeedPostsService.getPostLikeCount(postId),
        ]);

        if (mounted) {
          setState(() {
            _postLikeStatus[postId] = results[0] as bool;
            _postLikeCounts[postId] = results[1] as int;
          });
        }
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Error loading like data: $e');
    }
  }

  /// Toggle like/unlike for a post
  Future<void> _toggleLike(String postId) async {
    try {
      final isCurrentlyLiked = _postLikeStatus[postId] ?? false;
      final currentCount = _postLikeCounts[postId] ?? 0;

      // Optimistic update
      setState(() {
        _postLikeStatus[postId] = !isCurrentlyLiked;
        _postLikeCounts[postId] = isCurrentlyLiked 
          ? (currentCount - 1).clamp(0, 999999) 
          : currentCount + 1;
      });

      // Perform the actual like/unlike
      if (isCurrentlyLiked) {
        await FeedPostsService.unlikePost(postId);
      } else {
        await FeedPostsService.likePost(postId);
      }

      // Refresh the actual count from server
      final actualCount = await FeedPostsService.getPostLikeCount(postId);
      if (mounted) {
        setState(() {
          _postLikeCounts[postId] = actualCount;
        });
      }

    } catch (e) {
      // Revert optimistic update on error
      final isCurrentlyLiked = _postLikeStatus[postId] ?? false;
      final currentCount = _postLikeCounts[postId] ?? 0;
      
      setState(() {
        _postLikeStatus[postId] = !isCurrentlyLiked;
        _postLikeCounts[postId] = isCurrentlyLiked 
          ? currentCount + 1 
          : (currentCount - 1).clamp(0, 999999);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update like: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleComments(String postId) async {
    final isCurrentlyExpanded = _expandedComments[postId] ?? false;
    
    if (!isCurrentlyExpanded) {
      await _loadComments(postId);
    }
    
    setState(() {
      _expandedComments[postId] = !isCurrentlyExpanded;
    });
  }

  Future<void> _loadComments(String postId) async {
    try {
      final comments = await FeedPostsService.getPostComments(postId);
      
      if (mounted) {
        setState(() {
          _postComments[postId] = comments;
        });
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Error loading comments: $e');
    }
  }

  Future<void> _postComment(String postId) async {
    final controller = _commentControllers[postId];
    if (controller == null || controller.text.trim().isEmpty) return;

    try {
      await FeedPostsService.addComment(
        postId: postId,
        content: controller.text.trim(),
      );

      controller.clear();
      await _loadComments(postId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Comment posted!'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to post comment: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleSavePost(String postId) async {
    try {
      final isCurrentlySaved = _savedPosts[postId] ?? false;

      setState(() {
        _savedPosts[postId] = !isCurrentlySaved;
      });

      if (isCurrentlySaved) {
        await FeedPostsService.unsavePost(postId);
      } else {
        await FeedPostsService.savePost(postId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isCurrentlySaved ? 'Post unsaved' : 'Post saved!'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      final isCurrentlySaved = _savedPosts[postId] ?? false;
      
      setState(() {
        _savedPosts[postId] = !isCurrentlySaved;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save post: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildCommentsSection(String postId) {
    final comments = _postComments[postId] ?? [];
    _commentControllers.putIfAbsent(postId, () => TextEditingController());
    final controller = _commentControllers[postId]!;

    return Container(
      color: Colors.grey.shade50,
      padding: EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (comments.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  'No comments yet. Be the first!',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ),
            )
          else
            ...comments.map((comment) => _buildCommentItem(comment, postId)),
          
          Divider(),
          
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: 'Write a comment...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _postComment(postId),
                ),
              ),
              SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.send, color: Colors.orange),
                onPressed: () => _postComment(postId),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommentItem(Map<String, dynamic> comment, String postId) {
    final currentUserId = AuthService.currentUserId;
    final isOwnComment = comment['user_id'] == currentUserId;

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: Colors.orange.shade100,
                child: Icon(Icons.person, size: 16, color: Colors.orange.shade700),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comment['username'] ?? 'Anonymous',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      _formatPostTime(comment['created_at']),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (isOwnComment)
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  onPressed: () => _deleteComment(postId, comment['id'].toString()),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
            ],
          ),
          SizedBox(height: 6),
          Text(
            comment['content'] ?? '',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteComment(String postId, String commentId) async {
    try {
      await FeedPostsService.deleteComment(commentId);
      await _loadComments(postId);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Comment deleted'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete comment'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  Future<void> _loadMorePosts() async {
    if (_isLoadingMorePosts || !_hasMorePosts) return;

    setState(() => _isLoadingMorePosts = true);

    try {
      AppConfig.debugPrint('📥 Loading more posts (offset: ${_currentFeedOffset + _postsPerPage})...');
      
      final newPosts = await FeedPostsService.getFeedPosts(
        limit: _postsPerPage,
        offset: _currentFeedOffset + _postsPerPage,
      );
      
      AppConfig.debugPrint('📊 Loaded ${newPosts.length} more posts');
      
      if (mounted) {
        setState(() {
          _feedPosts.addAll(newPosts);
          _currentFeedOffset += _postsPerPage;
          _isLoadingMorePosts = false;
          
          // If we got fewer posts than requested, we've reached the end
          if (newPosts.length < _postsPerPage) {
            _hasMorePosts = false;
            AppConfig.debugPrint('📍 Reached end of feed');
          }
        });
        // Load like status and counts for new posts
        await _loadLikeDataForPosts(newPosts);  // <-- ADD THIS LINE
        AppConfig.debugPrint('✅ Total posts now: ${_feedPosts.length}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMorePosts = false);
      }
      AppConfig.debugPrint('❌ Error loading more posts: $e');
    }
  }



  // 🔥 NEW: Report harassment
  Future<void> _reportPost(Map<String, dynamic> post) async {
    final reasons = [
      'Harassment or bullying',
      'Spam',
      'Hate speech',
      'Violence or dangerous content',
      'False information',
      'Other',
    ];

    String? selectedReason;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.flag, color: Colors.red),
              SizedBox(width: 8),
              Text('Report Post'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Why are you reporting this post?',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 16),
              ...reasons.map((reason) {
                return RadioListTile<String>(
                  title: Text(reason, style: TextStyle(fontSize: 14)),
                  value: reason,
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setState(() => selectedReason = value);
                  },
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                );
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selectedReason == null
                  ? null
                  : () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: Text('Report'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && selectedReason != null) {
      try {
        await FeedPostsService.reportPost(
          postId: post['id'].toString(),
          reason: selectedReason!,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Report submitted. Thank you for helping keep our community safe.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to submit report. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // 🔥 NEW: Show post creation dialog
  void _showPostDialog() {
    final TextEditingController postController = TextEditingController();
    bool isPosting = false;
    String selectedVisibility = _defaultPostVisibility;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.edit, color: Colors.orange),
              SizedBox(width: 8),
              Text('Create Post'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: postController,
                  maxLines: 8,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: "What's on your mind?",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.orange, width: 2),
                    ),
                  ),
                ),
                
                SizedBox(height: 16),
                
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selectedVisibility == 'public' 
                          ? Icons.public 
                          : Icons.people,
                        size: 20,
                        color: Colors.grey.shade700,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Visible to:',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: DropdownButton<String>(
                          value: selectedVisibility,
                          isExpanded: true,
                          underline: SizedBox(),
                          items: [
                            DropdownMenuItem(
                              value: 'public',
                              child: Row(
                                children: [
                                  Icon(Icons.public, size: 18, color: Colors.blue),
                                  SizedBox(width: 8),
                                  Text('Everyone (Public)'),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'friends',
                              child: Row(
                                children: [
                                  Icon(Icons.people, size: 18, color: Colors.orange),
                                  SizedBox(width: 8),
                                  Text('Friends Only'),
                                ],
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => selectedVisibility = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 8),
                
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: selectedVisibility == 'public' 
                      ? Colors.blue.shade50 
                      : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selectedVisibility == 'public' 
                        ? Colors.blue.shade200 
                        : Colors.orange.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: selectedVisibility == 'public' 
                          ? Colors.blue.shade700 
                          : Colors.orange.shade700,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          selectedVisibility == 'public'
                            ? 'Anyone can see this post'
                            : 'Only your friends can see this post',
                          style: TextStyle(
                            fontSize: 12,
                            color: selectedVisibility == 'public' 
                              ? Colors.blue.shade900 
                              : Colors.orange.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isPosting ? null : () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isPosting
                  ? null
                  : () async {
                      if (postController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Please write something first'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }

                      setState(() => isPosting = true);

                      try {
                        await FeedPostsService.createTextPost(
                          content: postController.text.trim(),
                          visibility: selectedVisibility,
                        );

                        _defaultPostVisibility = selectedVisibility;

                        Navigator.pop(context);
                        
                        // 🔥 CHANGED: Refresh feed instead of just loading
                        await _loadFeed(isRefresh: true);

                        if (mounted) {
                          final visibilityText = selectedVisibility == 'public' 
                            ? 'publicly' 
                            : 'to friends only';
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Post shared $visibilityText!'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      } catch (e) {
                        setState(() => isPosting = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to create post: ${e.toString()}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: isPosting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text('Post'),
            ),
          ],
        ),
      ),
    );
  }
  // 🔥 FIXED: Show recipe selection dialog with highlight and share
  Future<void> _showShareRecipeDialog() async {
    // Load favorite recipes
    final recipes = await FavoriteRecipesService.getFavoriteRecipes();
    
    if (recipes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No favorite recipes yet. Add some recipes first!'),
          backgroundColor: Colors.orange,
          action: SnackBarAction(
            label: 'Go to Favorites',
            textColor: Colors.white,
            onPressed: () {
              Navigator.pushNamed(context, '/favorite-recipes');
            },
          ),
        ),
      );
      return;
    }

    FavoriteRecipe? selectedRecipe;
    String selectedVisibility = _defaultPostVisibility;
    TextEditingController captionController = TextEditingController();
    bool isPosting = false;

    final posted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.restaurant, color: Colors.orange),
              SizedBox(width: 8),
              Text('Share Recipe'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select a recipe:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  SizedBox(height: 12),
                  
                  // Recipe list
                  Container(
                    constraints: BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: recipes.length,
                      itemBuilder: (context, index) {
                        final recipe = recipes[index];
                        final isSelected = selectedRecipe?.id == recipe.id;
                        
                        return InkWell(
                          onTap: () {
                            setState(() {
                              selectedRecipe = recipe;
                            });
                          },
                          child: Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected 
                                ? Colors.orange.shade50 
                                : Colors.transparent,
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.grey.shade200,
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected 
                                    ? Icons.check_circle 
                                    : Icons.circle_outlined,
                                  color: isSelected 
                                    ? Colors.orange 
                                    : Colors.grey.shade400,
                                  size: 20,
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    recipe.recipeName,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: isSelected 
                                        ? FontWeight.bold 
                                        : FontWeight.normal,
                                      color: isSelected 
                                        ? Colors.orange.shade900 
                                        : Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  
                  // Caption field (only shows when recipe selected)
                  if (selectedRecipe != null) ...[
                    SizedBox(height: 16),
                    TextField(
                      controller: captionController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: "Add a caption (optional)...",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.orange, width: 2),
                        ),
                      ),
                    ),
                  ],
                  
                  SizedBox(height: 16),
                  
                  // Visibility dropdown
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selectedVisibility == 'public' ? Icons.public : Icons.people,
                          size: 20,
                          color: Colors.grey.shade700,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Visible to:',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<String>(
                            value: selectedVisibility,
                            isExpanded: true,
                            underline: SizedBox(),
                            items: [
                              DropdownMenuItem(
                                value: 'public',
                                child: Row(
                                  children: [
                                    Icon(Icons.public, size: 18, color: Colors.blue),
                                    SizedBox(width: 8),
                                    Text('Everyone (Public)'),
                                  ],
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'friends',
                                child: Row(
                                  children: [
                                    Icon(Icons.people, size: 18, color: Colors.orange),
                                    SizedBox(width: 8),
                                    Text('Friends Only'),
                                  ],
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => selectedVisibility = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isPosting ? null : () => Navigator.pop(context, false),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: (selectedRecipe == null || isPosting)
                  ? null
                  : () async {
                      setState(() => isPosting = true);

                      try {
                        await FeedPostsService.shareRecipeToFeed(
                          recipeName: selectedRecipe!.recipeName,
                          description: captionController.text.trim(),
                          ingredients: selectedRecipe!.ingredients,
                          directions: selectedRecipe!.directions,
                          visibility: selectedVisibility,
                        );

                        _defaultPostVisibility = selectedVisibility;

                        Navigator.pop(context, true);

                      } catch (e) {
                        setState(() => isPosting = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to share recipe: ${e.toString()}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: selectedRecipe == null 
                  ? Colors.grey 
                  : Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: isPosting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text('Share'),
            ),
          ],
        ),
      ),
    );

    if (posted == true && mounted) {
      await _loadFeed(isRefresh: true);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Recipe shared successfully!'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // 🔥 NEW: Post Composer Widget
  Widget _buildPostComposer() {
    return Container(
      margin: EdgeInsets.all(12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            offset: Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.orange.shade100,
                child: Icon(Icons.person, color: Colors.orange.shade700),
              ),
              SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => _showPostDialog(),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      "What's on your mind?",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          SizedBox(height: 12),
          Divider(height: 1),
          SizedBox(height: 8),
          
          // 🔥 UPDATED: Two rows of buttons
          Column(
            children: [
              // Row 1: Post and Recipe
              Row(
                children: [
                  _buildComposerAction(
                    icon: Icons.edit,
                    label: 'Post',
                    color: Colors.blue,
                    onTap: () => _showPostDialog(),
                  ),
                  SizedBox(width: 8),
                  _buildComposerAction(
                    icon: Icons.restaurant,
                    label: 'Recipe',
                    color: Colors.orange,
                    onTap: () => _showShareRecipeDialog(),
                  ),
                ],
              ),
              SizedBox(height: 8),
              // Row 2: Photo
              Row(
                children: [
                  _buildComposerAction(
                    icon: Icons.image,
                    label: 'Photo',
                    color: Colors.orange,
                    onTap: () => _showPhotoUploadDialog(), // ✅ Just this line
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComposerAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please enter a search term'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SearchUsersPage(initialQuery: query),
        ),
      );
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.navigationError,
          customMessage: 'Error opening user search',
        );
      }
    }
  }

  Future<void> _addNutritionToGroceryList() async {
    if (_currentNutrition == null) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'No nutrition data available',
        );
      }
      return;
    }

    try {
      final productName = _currentNutrition!.productName;

      await GroceryService.addToGroceryList(productName);

      if (mounted) {
        ErrorHandlingService.showSuccess(
          context,
          'Added "$productName" to grocery list!',
        );
        Navigator.pushNamed(context, '/grocery-list');
      }

    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.navigationError,
          customMessage: 'Error adding to grocery list',
        );
      }
    }
  }

  Future<void> _saveCurrentIngredient() async {
    if (_currentNutrition == null) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'No nutrition data available to save',
        );
      }
      return;
    }

    try {
      final alreadySaved = await SavedIngredientsService.isSaved(
        _currentNutrition!.productName,
      );

      if (alreadySaved) {
        if (mounted) {
          final shouldUpdate = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Already Saved'),
              content: Text(
                '"${_currentNutrition!.productName}" is already in your saved ingredients.\n\n'
                'Do you want to update it?'
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
                  child: const Text('Update'),
                ),
              ],
            ),
          );

          if (shouldUpdate != true) return;
        }
      }

      await SavedIngredientsService.saveIngredient(_currentNutrition!);

      if (mounted) {
        ErrorHandlingService.showSuccess(
          context,
          '✅ Saved "${_currentNutrition!.productName}" to ingredients!',
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ingredient saved successfully'),
            backgroundColor: Colors.orange,
            action: SnackBarAction(
              label: 'VIEW',
              textColor: Colors.white,
              onPressed: () {
                Navigator.pushNamed(context, '/saved-ingredients');
              },
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Failed to save ingredient',
        );
      }
    }
  }

  Future<void> _saveRecipeDraft() async {
    if (_recipeSuggestions.isEmpty || _currentNutrition == null) {
      ErrorHandlingService.showSimpleError(
        context,
        'No recipe to save. Please scan a product first.',
      );
      return;
    }

    final selectedRecipe = await showDialog<Recipe>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Recipe to Save'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose a recipe:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ..._getCurrentPageRecipes().map((recipe) {
              return ListTile(
                title: Text(recipe.title),
                subtitle: Text(
                  '${recipe.ingredients.length} ingredients',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, recipe),
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selectedRecipe == null) return;

    try {
      final draftsList = await LocalDraftService.getDraftsList();
      
      if (draftsList.isEmpty) {
        await _saveDraftAsNew(selectedRecipe);
        return;
      }

      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.save_outlined, color: Colors.blue),
              SizedBox(width: 12),
              Expanded(child: Text('Save Recipe Draft')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You have ${draftsList.length} existing draft${draftsList.length == 1 ? '' : 's'}.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
              SizedBox(height: 16),
              Text(
                'Would you like to:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, 'update'),
              icon: Icon(Icons.update),
              label: Text('Update Existing'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, 'new'),
              icon: Icon(Icons.add),
              label: Text('Save as New'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );

      if (choice == null) return;

      if (choice == 'new') {
        await _saveDraftAsNew(selectedRecipe);
      } else if (choice == 'update') {
        await _updateExistingDraft(selectedRecipe, draftsList);
      }

    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Failed to save recipe draft',
        );
      }
    }
  }

  Future<void> _saveDraftAsNew(Recipe recipe) async {
    try {
      final ingredientsJson = recipe.ingredients
          .map((ing) => {
                'quantity': '',
                'measurement': '',
                'name': ing,
              })
          .toList();

      await LocalDraftService.saveDraft(
        name: recipe.title,
        ingredients: jsonEncode(ingredientsJson),
        directions: recipe.instructions,
      );

      if (mounted) {
        ErrorHandlingService.showSuccess(
          context,
          '✅ Recipe "${recipe.title}" saved as new draft!',
        );

        final shouldEdit = await _askToEditDraft(recipe.title);
        
        if (shouldEdit == true && mounted) {
          Navigator.pushNamed(context, '/submit-recipe');
        }
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Failed to save new draft',
        );
      }
    }
  }

  Future<void> _updateExistingDraft(Recipe recipe, List<Map<String, dynamic>> draftsList) async {
    final selectedDraft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Draft to Update'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose which draft to replace:',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
            SizedBox(height: 12),
            Container(
              constraints: BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                child: Column(
                  children: draftsList.map((draft) {
                    return ListTile(
                      title: Text(
                        draft['name'] ?? 'Untitled Draft',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Last modified: ${_formatDate(draft['updated_at'])}',
                        style: TextStyle(fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, draft),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selectedDraft == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 12),
            Expanded(child: Text('Confirm Update')),
          ],
        ),
        content: Text(
          'This will replace "${selectedDraft['name']}" with "${recipe.title}".\n\n'
          'The original draft will be overwritten. Continue?',
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
            child: const Text('Update Draft'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final ingredientsJson = recipe.ingredients
          .map((ing) => {
                'quantity': '',
                'measurement': '',
                'name': ing,
              })
          .toList();

      await LocalDraftService.updateDraft(
        id: selectedDraft['id'],
        name: recipe.title,
        ingredients: jsonEncode(ingredientsJson),
        directions: recipe.instructions,
      );

      if (mounted) {
        ErrorHandlingService.showSuccess(
          context,
          '✅ Draft updated: "${recipe.title}"',
        );

        final shouldEdit = await _askToEditDraft(recipe.title);
        
        if (shouldEdit == true && mounted) {
          Navigator.pushNamed(context, '/submit-recipe');
        }
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Failed to update draft',
        );
      }
    }
  }

  Future<bool?> _askToEditDraft(String recipeName) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Draft Saved'),
        content: Text(
          'Recipe "$recipeName" has been saved.\n\n'
          'Would you like to edit it now?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Edit Now'),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic timestamp) {
    try {
      if (timestamp == null) return 'Unknown';
      
      DateTime date;
      if (timestamp is String) {
        date = DateTime.parse(timestamp);
      } else if (timestamp is DateTime) {
        date = timestamp;
      } else {
        return 'Unknown';
      }
      
      final now = DateTime.now();
      final diff = now.difference(date);
      
      if (diff.inDays == 0) {
        if (diff.inHours == 0) {
          return '${diff.inMinutes} min ago';
        }
        return '${diff.inHours} hr ago';
      } else if (diff.inDays < 7) {
        return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
      } else {
        return '${date.month}/${date.day}/${date.year}';
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  Future<void> _addRecipeIngredientsToGroceryList(dynamic recipe) async {
    try {
      List<String> ingredients = [];

      if (recipe is Recipe) {
        ingredients = recipe.ingredients;
      } else if (recipe is Map<String, String>) {
        ingredients = recipe['ingredients']!
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } else {
        throw Exception("Unsupported recipe type");
      }

      if (ingredients.isEmpty) {
        ErrorHandlingService.showSimpleError(
          context,
          'No ingredients found for this recipe.',
        );
        return;
      }

      int addedCount = 0;

      for (String item in ingredients) {
        await GroceryService.addToGroceryList(item);
        addedCount++;
      }

      if (mounted) {
        ErrorHandlingService.showSuccess(
          context,
          'Added $addedCount ingredients to grocery list!',
        );
        Navigator.pushNamed(context, '/grocery-list');
      }
    } catch (e) {
      await ErrorHandlingService.handleError(
        context: context,
        error: e,
        category: ErrorHandlingService.databaseError,
        customMessage: 'Failed to add ingredients to grocery list',
      );
    }
  }

  Future<void> _makeRecipeFromNutrition() async {
    if (_currentNutrition == null) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'No nutrition data available',
        );
      }
      return;
    }

    try {
      final productName = _currentNutrition!.productName;

      _initKeywordButtonsFromProductName(productName);

      final keywordString = _keywordTokens.join(', ');

      final recipeDraft = {
        'initialIngredients': keywordString.isNotEmpty ? keywordString : productName,
        'productName': productName,
        'initialTitle': "$productName Recipe",
        'initialDescription': "A recipe idea based on $productName.",
      };

      if (mounted) {
        final result = await Navigator.pushNamed(
          context,
          '/submit-recipe',
          arguments: recipeDraft,
        );

        if (result == true && mounted) {
          ErrorHandlingService.showSuccess(
            context,
            'Recipe submitted successfully!',
          );
          _resetToHome();
        }
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.navigationError,
          customMessage: 'Error opening recipe submission',
        );
      }
    }
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
    BorderRadius? borderRadius,
    GlobalKey? key,
  }) {
    final effectiveRadius = borderRadius ?? BorderRadius.circular(12);

    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: onPressed == null ? Colors.grey : color,
            borderRadius: effectiveRadius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: effectiveRadius,
              onTap: onPressed,
              child: Center(
                child: Icon(icon, color: Colors.white, size: 28),
              ),
            ),
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

  Widget _buildNutritionRecipeCard(Recipe recipe) {
    final isFavorite = _isRecipeFavorited(recipe.title);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        title: Text(
          recipe.title,
          style: const TextStyle(
            fontSize: 16,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PremiumGate(
              feature: PremiumFeature.favoriteRecipes,
              featureName: 'Favorite Recipes',
              child: IconButton(
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: isFavorite ? Colors.red : Colors.white,
                  size: 20,
                ),
                onPressed: () => _toggleFavoriteRecipe(recipe),
              ),
            ),
            const Icon(Icons.expand_more, color: Colors.white),
          ],
        ),
        iconColor: Colors.white,
        collapsedIconColor: Colors.white,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recipe.description,
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ingredients: ${recipe.ingredients.join(', ')}',
                  style: const TextStyle(fontSize: 12, color: Colors.white60),
                ),
                const SizedBox(height: 8),
                Text(
                  'Instructions: ${recipe.instructions}',
                  style: const TextStyle(fontSize: 12, color: Colors.white60),
                ),
                const SizedBox(height: 12),
                
                // 🔥 UPDATED: Button layout with new "Save as Template" button
                Column(
                  children: [
                    // Row 1: Favorite and Cookbook
                    Row(
                      children: [
                        Expanded(
                          child: PremiumGate(
                            feature: PremiumFeature.favoriteRecipes,
                            featureName: 'Favorite Recipes',
                            child: ElevatedButton.icon(
                              onPressed: () => _toggleFavoriteRecipe(recipe),
                              icon: const Icon(Icons.favorite, size: 16),
                              label: const Text('Favorite', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        
                        Expanded(
                          child: AddToCookbookButton(
                            recipeName: recipe.title,
                            ingredients: recipe.ingredients.join(', '),
                            directions: recipe.instructions,
                            compact: true,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Row 2: Save as Template and Grocery List
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _saveRecipeAsTemplate(recipe),
                            icon: const Icon(Icons.save_outlined, size: 16),
                            label: const Text('Save Template', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        
                        Expanded(
                          child: PremiumGate(
                            feature: PremiumFeature.groceryList,
                            featureName: 'Grocery List',
                            child: ElevatedButton.icon(
                              onPressed: () => _addRecipeIngredientsToGroceryList(recipe),
                              icon: const Icon(Icons.add_shopping_cart, size: 16),
                              label: const Text('Grocery', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                        ),
                      ],
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

  Future<void> _deletePost(Map<String, dynamic> post) async {
    final postId = post['id']?.toString();
    
    if (postId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid post ID'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 12),
            Text('Delete Post'),
          ],
        ),
        content: Text('Are you sure you want to delete this post? This action cannot be undone.'),
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
      ),
    );

    if (confirmed != true) return;

    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Deleting post...'),
              ],
            ),
          ),
        ),
      );

      // Delete the post
      await FeedPostsService.deletePost(postId);

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      // Remove post from local list
      setState(() {
        _feedPosts.removeWhere((p) => p['id']?.toString() == postId);
      });

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Post deleted successfully'),
              ],
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      // Close loading dialog if still open
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Failed to delete post: ${e.toString().replaceFirst("Exception: ", "")}',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Widget _buildFeedPost(Map<String, dynamic> post) {
    final currentUserId = AuthService.currentUserId;
    final isOwnPost = post['user_id'] == currentUserId;
    final visibility = post['visibility']?.toString() ?? 'public';
    final postId = post['id']?.toString();
    final isLiked = _postLikeStatus[postId] ?? false;
    final likeCount = _postLikeCounts[postId] ?? 0;
    final isExpanded = _expandedComments[postId] ?? false;
    final comments = _postComments[postId] ?? [];
    final isSaved = _savedPosts[postId] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha((0.95 * 255).toInt()),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.orange.shade100,
                  backgroundImage: post['avatar_url'] != null && post['avatar_url'].toString().isNotEmpty
                      ? NetworkImage(post['avatar_url'])
                      : null,
                  child: (post['avatar_url'] == null || post['avatar_url'].toString().isEmpty)
                      ? Icon(Icons.person, color: Colors.orange.shade700)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            post['username'] ?? 'Anonymous',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: visibility == 'public' 
                                ? Colors.blue.shade50 
                                : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: visibility == 'public' 
                                  ? Colors.blue.shade200 
                                  : Colors.orange.shade200,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  visibility == 'public' ? Icons.public : Icons.people,
                                  size: 10,
                                  color: visibility == 'public' 
                                    ? Colors.blue.shade700 
                                    : Colors.orange.shade700,
                                ),
                                SizedBox(width: 3),
                                Text(
                                  visibility == 'public' ? 'Public' : 'Friends',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: visibility == 'public' 
                                      ? Colors.blue.shade700 
                                      : Colors.orange.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _formatPostTime(post['created_at']),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz, color: Colors.grey.shade600),
                  onSelected: (value) {
                    if (value == 'report') {
                      _reportPost(post);
                    } else if (value == 'delete') {
                      _deletePost(post);
                    }
                  },
                  itemBuilder: (context) => [
                    if (!isOwnPost)
                      PopupMenuItem(
                        value: 'report',
                        child: Row(
                          children: const [
                            Icon(Icons.flag, color: Colors.red, size: 20),
                            SizedBox(width: 8),
                            Text('Report Post'),
                          ],
                        ),
                      ),
                    if (isOwnPost)
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: const [
                            Icon(Icons.delete, color: Colors.red, size: 20),
                            SizedBox(width: 8),
                            Text('Delete Post'),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (post['content'] != null && post['content'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      post['content'],
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                
                if (post['photo_url'] != null && post['photo_url'].toString().isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      post['photo_url'],
                      width: double.infinity,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          height: 200,
                          color: Colors.grey.shade200,
                          child: Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 200,
                          color: Colors.grey.shade200,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.broken_image, size: 48, color: Colors.grey.shade400),
                                SizedBox(height: 8),
                                Text(
                                  'Failed to load image',
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                InkWell(
                  onTap: () => _toggleLike(postId!),
                  child: Row(
                    children: [
                      Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        size: 20,
                        color: isLiked ? Colors.orange : Colors.grey.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        likeCount > 0 ? likeCount.toString() : '',
                        style: TextStyle(
                          fontSize: 12,
                          color: isLiked ? Colors.orange : Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                InkWell(
                  onTap: () => _toggleComments(postId!),
                  child: Row(
                    children: [
                      Icon(Icons.comment_outlined, size: 20, color: Colors.grey.shade700),
                      const SizedBox(width: 4),
                      Text(
                        comments.isNotEmpty ? '${comments.length}' : 'Comment',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                InkWell(
                  onTap: () => _toggleSavePost(postId!),
                  child: Row(
                    children: [
                      Icon(
                        isSaved ? Icons.bookmark : Icons.bookmark_border,
                        size: 20,
                        color: isSaved ? Colors.blue : Colors.grey.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Save',
                        style: TextStyle(
                          fontSize: 12,
                          color: isSaved ? Colors.blue : Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          if (isExpanded) _buildCommentsSection(postId!),
        ],
      ),
    );
  }

  Widget _buildFeedActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade700),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedLikeButton(Map<String, dynamic> post) {
    final postId = post['id']?.toString();
    if (postId == null) {
      return SizedBox.shrink();
    }

    final isLiked = _postLikeStatus[postId] ?? false;
    final likeCount = _postLikeCounts[postId] ?? 0;

    return InkWell(
      onTap: () => _toggleLike(postId),
      child: Row(
        children: [
          Icon(
            isLiked ? Icons.favorite : Icons.favorite_border,
            size: 20,
            color: isLiked ? Colors.orange : Colors.grey.shade700,
          ),
          const SizedBox(width: 4),
          Text(
            likeCount > 0 ? likeCount.toString() : '',
            style: TextStyle(
              fontSize: 12,
              color: isLiked ? Colors.orange : Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }


  String _formatPostTime(dynamic timestamp) {
    try {
      final DateTime postTime = timestamp is String 
          ? DateTime.parse(timestamp) 
          : DateTime.fromMillisecondsSinceEpoch(timestamp);
      final now = DateTime.now();
      final difference = now.difference(postTime);
      
      if (difference.inMinutes < 1) return 'Just now';
      if (difference.inHours < 1) return '${difference.inMinutes}m ago';
      if (difference.inDays < 1) return '${difference.inHours}h ago';
      if (difference.inDays < 7) return '${difference.inDays}d ago';
      return '${postTime.month}/${postTime.day}/${postTime.year}';
    } catch (e) {
      return 'Recently';
    }
  }

    Widget _buildInitialView() {
      return Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(
              MediaQuery.of(context).size.width > 600
                  ? 'assets/backgrounds/ipad_background.jpeg'
                  : 'assets/backgrounds/home_background.jpeg',
            ),
            fit: BoxFit.cover,
          ),
        ),
        child: SingleChildScrollView(
          controller: _feedScrollController,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search users...',
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                    prefixIcon: Icon(Icons.person_search, color: Colors.orange),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search, color: Colors.orange),
                      onPressed: () => _searchUsers(_searchController.text),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.transparent,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  ),
                  onSubmitted: (value) => _searchUsers(value),
                ),
              ),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha((0.9 * 255).toInt()),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Welcome to bariwise',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Scan products, look up foods, and get nutrition insights!',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha((0.95 * 255).toInt()),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    if (!_isPremium)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: _hasUsedAllFreeScans
                              ? Colors.red.shade50
                              : Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _hasUsedAllFreeScans
                                ? Colors.red.shade200
                                : Colors.blue.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _hasUsedAllFreeScans
                                  ? Icons.warning_rounded
                                  : Icons.info_outline,
                              color: _hasUsedAllFreeScans
                                  ? Colors.red.shade700
                                  : Colors.blue.shade700,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _hasUsedAllFreeScans
                                    ? 'Daily free scans used. Upgrade for unlimited!'
                                    : '$_remainingScans free scan${_remainingScans == 1 ? '' : 's'} remaining today',
                                style: TextStyle(
                                  color: _hasUsedAllFreeScans
                                      ? Colors.red.shade900
                                      : Colors.blue.shade900,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      SingleChildScrollView(
                        controller: _feedScrollController,
                        child: Column(
                          children: [
                            // Your 4 buttons row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildActionButton(
                                  key: _autoButtonKey,
                                  icon: Icons.qr_code_scanner,
                                  label: 'Auto',
                                  color: Colors.purple.shade600,
                                  onPressed: _isScanning ? null : _autoScanBarcode,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                _buildActionButton(
                                  key: _scanButtonKey,
                                  icon: Icons.camera_alt,
                                  label: 'Scan',
                                  color: Colors.orange.shade600,
                                  onPressed: _isScanning ? null : _takePhoto,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                _buildActionButton(
                                  key: _manualButtonKey,
                                  icon: Icons.edit_outlined,
                                  label: 'Code',
                                  color: Colors.blue.shade600,
                                  onPressed: () => Navigator.pushNamed(context, '/manual-barcode-entry'),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                _buildActionButton(
                                  key: _lookupButtonKey,
                                  icon: Icons.search,
                                  label: 'Search',
                                  color: Colors.orange.shade800,
                                  onPressed: () => Navigator.pushNamed(context, '/nutrition-search'),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // Tutorial button
                            ElevatedButton.icon(
                              onPressed: () {
                                print('🎓 Tutorial button pressed');
                                // Scroll to top before showing tutorial
                                _feedScrollController.animateTo(
                                  0,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                                setState(() {
                                  _showTutorial = true;
                                });
                              },
                              icon: const Icon(Icons.help_outline),
                              label: const Text('Tutorial'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(25),
                                ),
                              ),
                            ),

                            // ... rest of your homepage content
                          ],
                        ),
                      )

                  ],
                ),
              ),
              const SizedBox(height: 16),
    
              ElevatedButton.icon(
                onPressed: () {
                  print('🎓 Tutorial button pressed');
                  print('📍 Current _showTutorial state: $_showTutorial');
                  setState(() {
                    _showTutorial = true;
                  });
                  print('✅ Tutorial state set to: $_showTutorial');
                },
                icon: const Icon(Icons.help_outline),
                label: const Text('Tutorial'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // 🔥 UPDATED: Feed Section with Infinite Scroll
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha((0.9 * 255).toInt()),
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: BoxConstraints(
                  minHeight: 200,
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.public, color: Colors.orange, size: 24),
                        const SizedBox(width: 12),
                        const Text(
                          "Community Feed",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.public, size: 14, color: Colors.blue.shade700),
                              SizedBox(width: 4),
                              Text(
                                'Public',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Post Composer
                    _buildPostComposer(),
                    const SizedBox(height: 16),
                    
                    // 🔥 NEW: Feed with infinite scroll
                    if (_isLoadingFeed && _feedPosts.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_feedPosts.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              Icon(Icons.rss_feed, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                'No posts yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Be the first to share something!',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      // 🔥 Feed list with scroll controller
                      ListView.builder(
                        shrinkWrap: true,
                        physics: NeverScrollableScrollPhysics(), // Parent scrolls
                        itemCount: _feedPosts.length + (_hasMorePosts ? 1 : 0),
                        itemBuilder: (context, index) {
                          // Show loading indicator at bottom if loading more
                          if (index == _feedPosts.length) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: _isLoadingMorePosts
                                    ? CircularProgressIndicator()
                                    : SizedBox.shrink(),
                              ),
                            );
                          }
                          
                          return _buildFeedPost(_feedPosts[index]);
                        },
                      ),
                      
                    // End of feed indicator
                    if (!_hasMorePosts && _feedPosts.isNotEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            '✨ You\'ve seen all posts',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              if (_scannedRecipes.isNotEmpty)
                PremiumGate(
                  feature: PremiumFeature.viewRecipes,
                  featureName: "Recipe Details",
                  featureDescription:
                      "View full recipe details with ingredients and directions.",
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha((0.9 * 255).toInt()),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.restaurant, color: Colors.orange, size: 24),
                            SizedBox(width: 12),
                            Text(
                              "Recipe Suggestions",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._scannedRecipes.map((recipe) =>
                          _buildScannedRecipeCard(recipe)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }
  Widget _buildScanningView() {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage(
            MediaQuery.of(context).size.width > 600
                ? 'assets/backgrounds/ipad_background.jpeg'
                : 'assets/backgrounds/home_background.jpeg',
          ),
          fit: BoxFit.cover,
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 20),

            if (_imageFile != null)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    _imageFile!,
                    height: 300,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),

            const SizedBox(height: 20),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _takePhoto,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text("Retake"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),

                  if (_imageFile != null && !_isLoading)
                    ElevatedButton.icon(
                      onPressed: _submitPhoto,
                      icon: const Icon(Icons.send),
                      label: const Text("Analyze"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  const SizedBox(width: 8),

                  if (_currentNutrition != null && _nutritionText.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: _saveCurrentIngredient,
                      icon: const Icon(Icons.bookmark_add),
                      label: const Text("Save Ingredient"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  const SizedBox(width: 8),

                  if (_nutritionText.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: _addNutritionToGroceryList,
                      icon: const Icon(Icons.add_shopping_cart),
                      label: const Text("Grocery List"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  const SizedBox(width: 8),

                  if (_recipeSuggestions.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: _saveRecipeDraft,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text("Save Draft"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  const SizedBox(width: 8),

                  ElevatedButton.icon(
                    onPressed: _resetToHome,
                    icon: const Icon(Icons.home),
                    label: const Text("Home"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            if (_isLoading)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text("Analyzing nutrition information..."),
                  ],
                ),
              ),

            if (_nutritionText.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade700,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _nutritionText,
                  style: const TextStyle(color: Colors.white),
                ),
              ),

            const SizedBox(height: 20),

            if (_showbariBar && _bariHealthScore != null)
              BariHealthBar(healthScore: _bariHealthScore!),

            const SizedBox(height: 20),

            _buildNutritionRecipeSuggestions(),
          ],
        ),
      ),
    );
  }

  Widget _buildScannedRecipeCard(Map<String, String> recipe) {
    final isFavorite = _isRecipeFavorited(recipe['name']!);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ExpansionTile(
        title: Row(
          children: [
            const Icon(Icons.restaurant, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                recipe['name']!,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PremiumGate(
              feature: PremiumFeature.favoriteRecipes,
              featureName: 'Favorite Recipes',
              child: IconButton(
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: isFavorite ? Colors.red : Colors.grey,
                  size: 20,
                ),
                onPressed: () {
                  final recipeObj = Recipe(
                    title: recipe['name']!,
                    description: 'Scanned recipe',
                    ingredients: recipe['ingredients']!.split(', '),
                    instructions: recipe['directions']!,
                  );
                  _toggleFavoriteRecipe(recipeObj);
                },
              ),
            ),
            AddToCookbookButton(
              recipeName: recipe['name']!,
              ingredients: recipe['ingredients']!,
              directions: recipe['directions']!,
              compact: true,
            ),
            const Icon(Icons.expand_more),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ingredients:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Text(recipe['ingredients']!),
                const SizedBox(height: 16),
                const Text('Directions:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Text(recipe['directions']!),
                const SizedBox(height: 16),
                
                Row(
                  children: [
                    Expanded(
                      child: PremiumGate(
                        feature: PremiumFeature.favoriteRecipes,
                        featureName: 'Favorite Recipes',
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final recipeObj = Recipe(
                              title: recipe['name']!,
                              description: 'Scanned recipe',
                              ingredients: recipe['ingredients']!.split(', '),
                              instructions: recipe['directions']!,
                            );
                            _toggleFavoriteRecipe(recipeObj);
                          },
                          icon: const Icon(Icons.favorite),
                          label: const Text('Favorite'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    
                    AddToCookbookButton(
                      recipeName: recipe['name']!,
                      ingredients: recipe['ingredients']!,
                      directions: recipe['directions']!,
                      compact: true,
                    ),
                    const SizedBox(width: 8),
                    
                    Expanded(
                      child: PremiumGate(
                        feature: PremiumFeature.groceryList,
                        featureName: 'Grocery List',
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              _addRecipeIngredientsToGroceryList(recipe),
                          icon: const Icon(Icons.add_shopping_cart),
                          label: const Text('Grocery'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
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

  Widget _buildNutritionRecipeSuggestions() {
    final hasKeywords = _keywordTokens.isNotEmpty;
    final hasRecipes = _recipeSuggestions.isNotEmpty;

    if (!hasKeywords && !hasRecipes) return const SizedBox.shrink();

    return PremiumGate(
      feature: PremiumFeature.viewRecipes,
      featureName: 'Recipe Details',
      featureDescription:
          'View full recipe details with ingredients and directions.',
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue.shade800,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Health-Based Recipe Suggestions:',
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (hasRecipes)
                  IconButton(
                    icon: const Icon(Icons.save_outlined, color: Colors.white),
                    tooltip: 'Save Recipe as Draft',
                    onPressed: _saveRecipeDraft,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            if (hasKeywords) ...[
              const Text(
                'Select your key search word(s):',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _keywordTokens.map((word) {
                  final selected = _selectedKeywords.contains(word);
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _toggleKeyword(word),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: selected 
                              ? Colors.orange 
                              : Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected ? Colors.white : Colors.white30,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          word,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 14),

              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed:
                      _isSearchingRecipes ? null : _searchRecipesBySelectedKeywords,
                  icon: _isSearchingRecipes
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.search),
                  label: Text(
                      _isSearchingRecipes ? 'Searching...' : 'Search Recipes'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 18),

              if (!hasRecipes)
                const Text(
                  'No recipes yet. Select words above and tap Search.',
                  style: TextStyle(fontSize: 12, color: Colors.white60),
                ),
            ],

            if (hasRecipes) ...[
              const SizedBox(height: 8),
              
              ..._getCurrentPageRecipes().map((r) => _buildNutritionRecipeCard(r)),
              
              if (_recipeSuggestions.length > _recipesPerPage) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Showing ${_currentRecipeIndex + 1}-${(_currentRecipeIndex + _recipesPerPage).clamp(0, _recipeSuggestions.length)} of ${_recipeSuggestions.length} recipes',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _loadNextRecipeSuggestions,
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: const Text('Next Suggestions'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _autoScanBarcode() async {
    try {
      if (!_premiumController.canAccessFeature(PremiumFeature.scan)) {
        Navigator.pushNamed(context, '/purchase');
        return;
      }

      final isPremiumNow = _premiumController.isPremium;
      
      if (!isPremiumNow && _isAdReady) {
        _showInterstitialAd(() => _executeAutoScan());
      } else {
        _executeAutoScan();
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.scanError,
          customMessage: 'Unable to start auto-scan',
        );
      }
    }
  }

  Future<void> _executeAutoScan() async {
    if (_isDisposed) return;

    try {
      final success = await _premiumController.useScan();
      if (!success) {
        Navigator.pushNamed(context, '/purchase');
        return;
      }

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AutoBarcodeScanner(
            onBarcodeDetected: (imagePath, barcode) async {
              Navigator.pop(context);
              
              final file = File(imagePath);
              if (await file.exists()) {
                setState(() {
                  _imageFile = file;
                  _showInitialView = false;
                });
                
                await Future.delayed(Duration(milliseconds: 500));
                if (mounted && !_isDisposed) {
                  await _submitPhoto();
                }
              }
            },
            onCancel: () {
              Navigator.pop(context);
              _resetToHome();
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.scanError,
          customMessage: 'Error during auto-scan',
        );
      }
    }
  }
  @override
  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('bariWise'),
        backgroundColor: Colors.orange,
        leading: Builder(
          builder: (context) => IconButton(
            icon: MenuIconWithBadge(key: MenuIconWithBadge.globalKey),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      drawer: const AppDrawer(currentPage: 'home'),
      body: Stack(
        children: [
          // Main content - show initial view or scanning view
          _showInitialView ? _buildInitialView() : _buildScanningView(),

          // Tutorial overlay on top when active
          if (_showTutorial)
            TutorialOverlay(
              autoButtonKey: _autoButtonKey,
              scanButtonKey: _scanButtonKey,
              manualButtonKey: _manualButtonKey,
              lookupButtonKey: _lookupButtonKey,
              onComplete: () {
                setState(() {
                  _showTutorial = false;
                });
              },
            ),
        ],
      ),
    );
  }

  Future<void> _saveRecipeAsTemplate(Recipe recipe) async {
    try {
      final userId = AuthService.currentUserId;
      if (userId == null) {
        if (mounted) {
          ErrorHandlingService.showSimpleError(
            context,
            'Please log in to save recipes',
          );
        }
        return;
      }

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Saving recipe template...'),
              ],
            ),
          ),
        ),
      );

      // Convert Recipe ingredients (strings) to RecipeIngredient objects
      final recipeIngredients = recipe.ingredients.map((ingredientText) {
        // Parse ingredient text to extract quantity, unit, and name
        final parsed = _parseIngredientText(ingredientText);
        
        return RecipeIngredient(
          productName: parsed['name']!,
          quantity: double.tryParse(parsed['quantity']!) ?? 1.0,
          unit: parsed['unit']!,
          source: 'template',
        );
      }).toList();

      // Create draft recipe
      final draftRecipe = DraftRecipe(
        userId: userId,
        title: recipe.title,
        description: recipe.description,
        ingredients: recipeIngredients,
        instructions: recipe.instructions,
        servings: 1,
        isbariFriendly: true,
      );

      // Save to database
      final draftRecipeId = await DraftRecipesService.createDraftRecipe(draftRecipe);

      // Close loading dialog
      if (mounted) {
        Navigator.pop(context);
      }

      // Show success dialog with options
      if (mounted) {
        final shouldEdit = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.orange),
                SizedBox(width: 12),
                Expanded(child: Text('Recipe Saved!')),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recipe "${recipe.title}" has been saved as a template.',
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You can now customize ingredients, add nutrition data, and submit to the community!',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('View Later'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: Icon(Icons.edit),
                label: Text('Edit Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );

        if (shouldEdit == true && mounted) {
          // Navigate to submit recipe page with the draft pre-loaded
          Navigator.pushNamed(
            context,
            '/submit-recipe',
            arguments: {
              'draftRecipeId': draftRecipeId,
              'fromTemplate': true,
            },
          );
        }
      }
    } catch (e) {
      // Close loading dialog if still open
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Failed to save recipe template',
          onRetry: () => _saveRecipeAsTemplate(recipe),
        );
      }
    }
  }

  // 🔥 NEW: Parse ingredient text into quantity, unit, and name
  Map<String, String> _parseIngredientText(String text) {
    // Default values
    String quantity = '1';
    String unit = 'piece';
    String name = text.trim();

    // Common units to look for
    final units = [
      'cup', 'cups',
      'tbsp', 'tablespoon', 'tablespoons',
      'tsp', 'teaspoon', 'teaspoons',
      'oz', 'ounce', 'ounces',
      'lb', 'pound', 'pounds',
      'g', 'gram', 'grams',
      'kg', 'kilogram', 'kilograms',
      'ml', 'milliliter', 'milliliters',
      'l', 'liter', 'liters',
      'piece', 'pieces',
      'slice', 'slices',
      'pinch', 'dash',
      'clove', 'cloves',
      'can', 'cans',
      'package', 'packages',
    ];

    // Try to parse "number unit ingredient" pattern
    final words = text.trim().split(RegExp(r'\s+'));
    
    if (words.length >= 2) {
      // Check if first word is a number
      final potentialQuantity = double.tryParse(words[0]);
      if (potentialQuantity != null) {
        quantity = words[0];
        
        // Check if second word is a unit
        final potentialUnit = words[1].toLowerCase();
        if (units.contains(potentialUnit)) {
          unit = potentialUnit;
          // Rest is the ingredient name
          name = words.skip(2).join(' ');
        } else {
          // No unit found, everything after quantity is the name
          name = words.skip(1).join(' ');
        }
      } else if (words[0].toLowerCase() == 'a' || words[0].toLowerCase() == 'an') {
        // Handle "a cup of flour" or "an onion"
        quantity = '1';
        if (words.length >= 2 && units.contains(words[1].toLowerCase())) {
          unit = words[1].toLowerCase();
          name = words.skip(2).join(' ');
        } else {
          name = words.skip(1).join(' ');
        }
      }
    }

    // Clean up the name (remove "of" if present at start)
    if (name.toLowerCase().startsWith('of ')) {
      name = name.substring(3);
    }

    return {
      'quantity': quantity,
      'unit': unit,
      'name': name.trim(),
    };
  }
}