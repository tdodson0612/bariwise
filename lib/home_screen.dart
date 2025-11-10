// lib/home_screen.dart - Complete architectural rebuild with proper error handling
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../widgets/premium_gate.dart';
import '../controllers/premium_gate_controller.dart';
import 'liverhealthbar.dart';
import '../pages/profile_screen.dart';
import 'contact_screen.dart';
import '../services/auth_service.dart';
import '../services/error_handling_service.dart';
import '../models/favorite_recipe.dart';
import '../pages/messages_page.dart';
import '../pages/search_users_page.dart';
import '../pages/favorite_recipes_page.dart';
import '../pages/user_profile_page.dart';
import '../widgets/app_drawer.dart';
import '../config/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/menu_icon_with_badge.dart';

// Add this class right after your imports in home_screen.dart
class IngredientKeywordExtractor {
  // Words to remove from product names
  static final List<String> _removeWords = [
    // Measurements
    'oz', 'ounce', 'ounces', 'lb', 'lbs', 'pound', 'pounds', 'kg', 'kilogram', 'kilograms',
    'gram', 'grams', 'g', 'ml', 'milliliter', 'milliliters', 'liter', 'liters', 'l',
    'gallon', 'gallons', 'quart', 'quarts', 'pint', 'pints', 'cup', 'cups', 'tbsp', 'tsp',
    'tablespoon', 'tablespoons', 'teaspoon', 'teaspoons', 'fl', 'fluid',
    
    // Packaging
    'can', 'canned', 'jar', 'bottle', 'bottled', 'box', 'boxed', 'bag', 'bagged',
    'pack', 'package', 'packaged', 'carton', 'container', 'pouch', 'tube', 'tin',
    
    // Common prefixes/descriptors
    'organic', 'natural', 'fresh', 'frozen', 'dried', 'raw', 'cooked', 'prepared',
    'whole', 'sliced', 'diced', 'chopped', 'minced', 'crushed', 'ground',
    'reduced', 'low', 'high', 'fat', 'free', 'sodium', 'sugar', 'calorie', 'diet',
    'light', 'lite', 'extra', 'pure', 'premium', 'grade', 'quality',
    
    // Colors (often not essential for recipes)
    'red', 'green', 'yellow', 'white', 'black', 'brown',
    
    // Brand/style descriptors
    'style', 'flavored', 'flavour', 'seasoned', 'unseasoned', 'salted', 'unsalted',
    'sweetened', 'unsweetened', 'plain', 'original',
    
    // Common food preparation states
    'peeled', 'unpeeled', 'pitted', 'unpitted', 'seeded', 'unseeded',
    'bone-in', 'boneless', 'skin-on', 'skinless', 'roasted',
  ];

  /// Extract the main ingredient keyword from a product name
  /// Example: "12 oz can red roasted tomatoes" -> "tomatoes"
  static String extract(String productName) {
    if (productName.trim().isEmpty) return productName;

    // Convert to lowercase for processing
    String processed = productName.toLowerCase().trim();
    
    // Remove special characters but keep spaces and hyphens
    processed = processed.replaceAll(RegExp(r'[^\w\s-]'), ' ');
    
    // Remove numbers and measurements (e.g., "12", "12oz")
    processed = processed.replaceAll(RegExp(r'\b\d+\.?\d*\s*(oz|lb|g|kg|ml|l)?\b'), '');
    processed = processed.replaceAll(RegExp(r'\d+'), '');
    
    // Split into words
    List<String> words = processed.split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    
    // Remove common filler words
    words = words.where((word) {
      // Keep the word if it's not in the remove list
      return !_removeWords.contains(word.toLowerCase());
    }).toList();
    
    // If nothing left, return original
    if (words.isEmpty) {
      return productName.trim();
    }
    
    // Return the last remaining word (usually the main ingredient)
    // For "roasted tomatoes" it will return "tomatoes"
    // For "chicken breast" it will return "chicken"
    return words.last;
  }
}


/// --- NutritionInfo Data Model ---
class NutritionInfo {
  final String productName;
  final double fat;
  final double sodium;
  final double sugar;
  final double calories;

  NutritionInfo({
    required this.productName,
    required this.fat,
    required this.sodium,
    required this.sugar,
    required this.calories,
  });

  factory NutritionInfo.fromJson(Map<String, dynamic> json) {
    final product = json['product'] ?? {};
    final nutriments = product['nutriments'] ?? {};

    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      return double.tryParse(value.toString()) ?? 0.0;
    }

    return NutritionInfo(
      productName: product['product_name'] ?? 'Unknown product',
      calories: parseDouble(nutriments['energy-kcal_100g']),
      fat: parseDouble(nutriments['fat_100g']),
      sugar: parseDouble(nutriments['sugars_100g']),
      sodium: parseDouble(nutriments['sodium_100g']),
    );
  }
}

/// --- Recipe Data Model ---
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
    title: json['title'] ?? '',
    description: json['description'] ?? '',
    ingredients: List<String>.from(json['ingredients'] ?? []),
    instructions: json['instructions'] ?? '',
  );
}

/// --- Liver Health Score Calculator ---
class LiverHealthCalculator {
  static const double fatMax = 20.0;
  static const double sodiumMax = 500.0;
  static const double sugarMax = 20.0;
  static const double calMax = 400.0;

  static int calculate({
    required double fat,
    required double sodium,
    required double sugar,
    required double calories,
  }) {
    double fatScore = 1 - (fat / fatMax).clamp(0, 1);
    double sodiumScore = 1 - (sodium / sodiumMax).clamp(0, 1);
    double sugarScore = 1 - (sugar / sugarMax).clamp(0, 1);
    double calScore = 1 - (calories / calMax).clamp(0, 1);

    double finalScore = (fatScore * 0.3) +
                        (sodiumScore * 0.25) +
                        (sugarScore * 0.25) +
                        (calScore * 0.2);

    return (finalScore * 100).round().clamp(0, 100);
  }
}

/// --- Recipe Generator ---
class RecipeGenerator {
  static Future<List<Recipe>> generateSuggestionsFromProduct(String productName) async {
  final keyword = IngredientKeywordExtractor.extract(productName);
  AppConfig.debugPrint('Product: $productName -> Keyword: $keyword');
  
  try {
    // Query Supabase for recipes containing the keyword in ingredients
    final response = await Supabase.instance.client
      .from('recipes')
      .select()
      .ilike('ingredients', '%$keyword%')
      .limit(5);
    
    // Convert response to Recipe objects
    final recipes = (response as List)
        .map((json) => Recipe.fromJson(json))
        .toList();
    
    AppConfig.debugPrint('Found ${recipes.length} recipes for keyword: $keyword');
    
    return recipes.isEmpty ? _getHealthyRecipes() : recipes;
  } catch (e) {
    AppConfig.debugPrint('Error fetching recipes from Supabase: $e');
    // Fallback to default recipes on error
    return _getHealthyRecipes();
  }
}

  static List<Recipe> generateSuggestions(int liverHealthScore) {
    if (liverHealthScore >= 75) {
      return _getHealthyRecipes();
    } else if (liverHealthScore >= 50) {
      return _getModerateRecipes();
    } else {
      return _getDetoxRecipes();
    }
  }

  static List<Recipe> _getHealthyRecipes() => [
    Recipe(
      title: "Mediterranean Salmon Bowl",
      description: "Heart-healthy salmon with fresh vegetables",
      ingredients: ["Fresh salmon", "Mixed greens", "Olive oil", "Lemon", "Cherry tomatoes"],
      instructions: "Grill salmon, serve over greens with olive oil and lemon dressing.",
    ),
    Recipe(
      title: "Quinoa Vegetable Stir-fry",
      description: "Protein-rich quinoa with colorful vegetables",
      ingredients: ["Quinoa", "Bell peppers", "Broccoli", "Carrots", "Soy sauce"],
      instructions: "Cook quinoa, stir-fry vegetables, combine and season.",
    ),
  ];

  static List<Recipe> _getModerateRecipes() => [
    Recipe(
      title: "Baked Chicken with Sweet Potato",
      description: "Lean protein with nutrient-rich sweet potato",
      ingredients: ["Chicken breast", "Sweet potato", "Herbs", "Olive oil"],
      instructions: "Season chicken, bake with sweet potato slices until golden.",
    ),
    Recipe(
      title: "Lentil Soup",
      description: "Fiber-rich soup to support liver health",
      ingredients: ["Red lentils", "Carrots", "Celery", "Onions", "Vegetable broth"],
      instructions: "Sauté vegetables, add lentils and broth, simmer until tender.",
    ),
  ];

  static List<Recipe> _getDetoxRecipes() => [
    Recipe(
      title: "Green Detox Smoothie",
      description: "Liver-cleansing green smoothie",
      ingredients: ["Spinach", "Green apple", "Lemon juice", "Ginger", "Water"],
      instructions: "Blend all ingredients until smooth, serve immediately.",
    ),
    Recipe(
      title: "Steamed Vegetables with Brown Rice",
      description: "Simple, clean eating option",
      ingredients: ["Brown rice", "Broccoli", "Carrots", "Zucchini", "Herbs"],
      instructions: "Steam vegetables, serve over cooked brown rice with herbs.",
    ),
  ];
}

/// --- Nutrition API Service with Enhanced Error Handling ---
class NutritionApiService {
  // FIXED: Use Environment base URL instead of hardcoded
  static String get baseUrl => AppConfig.openFoodFactsUrl;

  static Future<NutritionInfo?> fetchNutritionInfo(String barcode) async {
    if (barcode.isEmpty) return null;

    final url = "$baseUrl/$barcode.json";

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'FlutterApp/1.0'},
      ).timeout(Duration(seconds: AppConfig.apiTimeoutSeconds));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
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

/// --- Barcode Scanner Service with Enhanced Error Handling ---
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

/// --- FIXED: HomePage with proper architecture ---
class HomePage extends StatefulWidget {
  final bool isPremium;

  const HomePage({super.key, this.isPremium = false});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin {
  // Premium scanning state
  bool _isScanning = false;
  List<Map<String, String>> _scannedRecipes = [];
  
  // Nutrition scanner state
  File? _imageFile;
  String _nutritionText = '';
  int? _liverHealthScore;
  bool _showLiverBar = false;
  bool _isLoading = false;
  List<Recipe> _recipeSuggestions = [];
  List<FavoriteRecipe> _favoriteRecipes = [];
  bool _showInitialView = true;
  NutritionInfo? _currentNutrition;

  // FIXED: Premium state management without AnimatedBuilder performance issues
  late final PremiumGateController _premiumController;
  StreamSubscription? _premiumSubscription;
  bool _isPremium = false;
  int _remainingScans = 3;
  bool _hasUsedAllFreeScans = false;

  // FIXED: Proper ad management with disposal tracking
  InterstitialAd? _interstitialAd;
  bool _isAdReady = false;
  RewardedAd? _rewardedAd;
  bool _isRewardedAdReady = false;
  bool _isDisposed = false;

  // Image picker
  final ImagePicker _picker = ImagePicker();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializePremiumController();
    _initializeAsync();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _premiumSubscription?.cancel();
    _interstitialAd?.dispose();
    _rewardedAd?.dispose();
    super.dispose();
  }

  // FIXED: Proper premium controller management
  void _initializePremiumController() {
    _premiumController = PremiumGateController();
    
    // Listen to premium state changes efficiently
    _premiumSubscription = _premiumController.addListener(() {
      if (mounted && !_isDisposed) {
        setState(() {
          _isPremium = _premiumController.isPremium;
          _remainingScans = _premiumController.remainingScans;
          _hasUsedAllFreeScans = _premiumController.hasUsedAllFreeScans;
        });
      }
    }) as StreamSubscription?;

    // Initialize current state
    setState(() {
      _isPremium = _premiumController.isPremium;
      _remainingScans = _premiumController.remainingScans;
      _hasUsedAllFreeScans = _premiumController.hasUsedAllFreeScans;
    });
  }

  // FIXED: Async initialization with proper error handling
  Future<void> _initializeAsync() async {
    try {
      await _premiumController.refresh();
      await _loadFavoriteRecipes();
      _loadInterstitialAd();
      _loadRewardedAd();
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

  /// FIXED: Load interstitial ad with proper error handling
  void _loadInterstitialAd() {
  if (_isDisposed) return;

  // FIXED: Use Environment system instead of hardcoded IDs
  final adUnitId = AppConfig.interstitialAdId;
  InterstitialAd.load(
    adUnitId: adUnitId,
    request: AdRequest(),
    adLoadCallback: InterstitialAdLoadCallback(
      onAdLoaded: (ad) {
        if (!_isDisposed) {
          _interstitialAd = ad;
          _isAdReady = true;
          ad.setImmersiveMode(true);
        } else {
          ad.dispose();
        }
      },
      onAdFailedToLoad: (error) {
        if (AppConfig.enableDebugPrints) {
          print('InterstitialAd failed to load: $error');
        }
        _isAdReady = false;
      },
    ),
  );
}


  /// FIXED: Load rewarded ad with proper error handling
void _loadRewardedAd() {
  if (_isDisposed) return;

  // FIXED: Use Environment system instead of hardcoded IDs
  final adUnitId = AppConfig.rewardedAdId;

  RewardedAd.load(
    adUnitId: adUnitId,
    request: AdRequest(),
    rewardedAdLoadCallback: RewardedAdLoadCallback(
      onAdLoaded: (ad) {
        if (!_isDisposed) {
          _rewardedAd = ad;
          _isRewardedAdReady = true;
        } else {
          ad.dispose();
        }
      },
      onAdFailedToLoad: (error) {
        if (AppConfig.enableDebugPrints) {
          print('RewardedAd failed to load: $error');
        }
        _isRewardedAdReady = false;
      },
    ),
  );
}

  /// FIXED: Show interstitial ad with proper disposal checks
  void _showInterstitialAd(VoidCallback onAdClosed) {
    if (_isDisposed || !_isAdReady || _interstitialAd == null) {
      onAdClosed();
      return;
    }

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        print('Interstitial ad showed full screen content');
      },
      onAdDismissedFullScreenContent: (ad) {
        print('Interstitial ad dismissed');
        ad.dispose();
        if (!_isDisposed) {
          _loadInterstitialAd();
        }
        onAdClosed();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        print('Interstitial ad failed to show: $error');
        ad.dispose();
        if (!_isDisposed) {
          _loadInterstitialAd();
        }
        onAdClosed();
      },
    );
    
    _interstitialAd!.show();
    _isAdReady = false;
  }

  /// FIXED: Show rewarded ad with proper error handling
  void _showRewardedAd() {
    if (_isDisposed) return;

    if (_isRewardedAdReady && _rewardedAd != null) {
      _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdShowedFullScreenContent: (ad) {
          print('Rewarded ad showed full screen content');
        },
        onAdDismissedFullScreenContent: (ad) {
          print('Rewarded ad dismissed');
          ad.dispose();
          if (!_isDisposed) {
            _loadRewardedAd();
          }
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          print('Rewarded ad failed to show: $error');
          ad.dispose();
          if (!_isDisposed) {
            _loadRewardedAd();
          }
        },
      );
      
      _rewardedAd!.show(
        onUserEarnedReward: (ad, reward) {
          if (!_isDisposed) {
            print('User earned reward: ${reward.amount} ${reward.type}');
            _premiumController.addBonusScans(1);
            
            if (mounted) {
              ErrorHandlingService.showSuccess(
                context,
                'Bonus scan earned! You now have ${_premiumController.remainingScans} scans remaining.'
              );
            }
          }
        },
      );
      _isRewardedAdReady = false;
    } else {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'Ad not ready yet. Please try again in a moment.'
        );
      }
    }
  }

  /// FIXED: Load favorite recipes with proper error handling
  Future<void> _loadFavoriteRecipes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favoriteRecipesJson = prefs.getStringList('favorite_recipes_detailed') ?? [];
      
      if (mounted && !_isDisposed) {
        setState(() {
          _favoriteRecipes = favoriteRecipesJson
              .map((jsonString) {
                try {
                  return FavoriteRecipe.fromJson(json.decode(jsonString));
                } catch (e) {
                  print('Error parsing recipe: $e');
                  return null;
                }
              })
              .where((recipe) => recipe != null)
              .cast<FavoriteRecipe>()
              .toList();
        });
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

  /// FIXED: Toggle favorite recipe with enhanced error handling
  Future<void> _toggleFavoriteRecipe(Recipe recipe) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = AuthService.currentUserId;
      
      if (currentUserId == null) {
        if (mounted) {
          ErrorHandlingService.showSimpleError(context, 'Please log in to save recipes');
        }
        return;
      }

      final existingIndex = _favoriteRecipes.indexWhere((fav) => fav.recipeName == recipe.title);
      
      if (existingIndex >= 0) {
        // Remove from favorites
        if (mounted && !_isDisposed) {
          setState(() {
            _favoriteRecipes.removeAt(existingIndex);
          });
          
          ErrorHandlingService.showSuccess(
            context,
            'Removed "${recipe.title}" from favorites'
          );
        }
      } else {
        // Add to favorites
        final favoriteRecipe = FavoriteRecipe(
          userId: currentUserId,
          recipeName: recipe.title,
          ingredients: recipe.ingredients.join(', '),
          directions: recipe.instructions,
          createdAt: DateTime.now(),
        );
        
        if (mounted && !_isDisposed) {
          setState(() {
            _favoriteRecipes.add(favoriteRecipe);
          });
          
          ErrorHandlingService.showSuccess(
            context,
            'Added "${recipe.title}" to favorites!'
          );
        }
      }
      
      // Save to SharedPreferences
      final favoriteRecipesJson = _favoriteRecipes
          .map((recipe) => json.encode(recipe.toJson()))
          .toList();
      await prefs.setStringList('favorite_recipes_detailed', favoriteRecipesJson);
      
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
    if (mounted && !_isDisposed) {
      setState(() {
        _showInitialView = true;
        _nutritionText = '';
        _showLiverBar = false;
        _imageFile = null;
        _recipeSuggestions = [];
        _liverHealthScore = null;
        _isLoading = false;
        _scannedRecipes = [];
        _currentNutrition = null;
      });
    }
  }

  /// FIXED: Premium scan with proper error handling
  Future<void> _performScan() async {
    try {
      if (!_premiumController.canAccessFeature(PremiumFeature.scan)) {
        Navigator.pushNamed(context, '/purchase');
        return;
      }

      if (!_isPremium) {
        _showInterstitialAd(() => _executePerformScan());
      } else {
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
      setState(() {
        _isScanning = true;
      });

      final success = await _premiumController.useScan();
      
      if (!success) {
        Navigator.pushNamed(context, '/purchase');
        return;
      }

      // Simulate scanning delay
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
          'Scan successful! ${_premiumController.remainingScans} scans remaining today.'
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
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  /// FIXED: Take photo with proper error handling
  Future<void> _takePhoto() async {
    try {
      if (!_premiumController.canAccessFeature(PremiumFeature.scan)) {
        Navigator.pushNamed(context, '/purchase');
        return;
      }

      if (!_isPremium) {
        _showInterstitialAd(() => _executeTakePhoto());
      } else {
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

    try {
      if (mounted) {
        setState(() {
          _showInitialView = false;
          _nutritionText = '';
          _showLiverBar = false;
          _imageFile = null;
          _recipeSuggestions = [];
          _isLoading = false;
          _scannedRecipes = [];
        });
      }

      final pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (pickedFile != null && mounted && !_isDisposed) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.imageError,
          customMessage: 'Failed to take photo',
        );
      }
    }
  }

  /// FIXED: Submit photo with comprehensive error handling
  Future<void> _submitPhoto() async {
    if (_imageFile == null || _isDisposed) return;

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
          _showLiverBar = false;
          _recipeSuggestions = [];
        });
      }

      final nutrition = await BarcodeScannerService.scanAndLookup(_imageFile!.path);

      if (nutrition == null) {
        if (mounted && !_isDisposed) {
          setState(() {
            _nutritionText = "No barcode found or product not recognized. Please try again.";
            _showLiverBar = false;
            _isLoading = false;
          });
        }
        return;
      }

      final score = LiverHealthCalculator.calculate(
        fat: nutrition.fat,
        sodium: nutrition.sodium,
        sugar: nutrition.sugar,
        calories: nutrition.calories,
      );

      final suggestions = await RecipeGenerator.generateSuggestionsFromProduct(nutrition.productName);
      
      if (mounted && !_isDisposed) {
        setState(() {
          _nutritionText = _buildNutritionDisplay(nutrition);
          _liverHealthScore = score;
          _showLiverBar = true;
          _isLoading = false;
          _recipeSuggestions = suggestions;
          _currentNutrition = nutrition;
        });

        ErrorHandlingService.showSuccess(
          context,
          'Analysis successful! ${_premiumController.remainingScans} scans remaining today.'
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _nutritionText = "Error processing image: ${e.toString()}";
          _showLiverBar = false;
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

  /// FIXED: Search users with proper error handling
  /// UPDATED: Search users with proper error handling
Future<void> _searchUsers(String query) async {
  if (query.trim().isEmpty) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter a search term'),
          backgroundColor: const Color.fromARGB(255, 0, 221, 255),
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
Widget _buildSearchBar() {
  final TextEditingController searchController = TextEditingController();
  
  return Container(
    margin: EdgeInsets.only(bottom: 20),
    padding: EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withAlpha((0.95 * 255).toInt()),
      borderRadius: BorderRadius.circular(15),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      children: [
        Row(
          children: [
            Icon(
              Icons.people,
              color: Colors.blue.shade700,
              size: 24,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Find Friends & Share Recipes',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 4),
        Text(
          'Search by name, username, or email',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
            fontStyle: FontStyle.italic,
          ),
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  hintText: 'Try "John Smith" or "jsmith"...',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(Icons.person_search, color: Colors.grey.shade600),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide(color: Colors.blue, width: 2),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (value) => _searchUsers(value),
              ),
            ),
            SizedBox(width: 12),
            ElevatedButton(
              onPressed: () => _searchUsers(searchController.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: CircleBorder(),
                padding: EdgeInsets.all(14),
                elevation: 3,
              ),
              child: Icon(Icons.search, size: 24),
            ),
          ],
        ),
        SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 14, color: const Color.fromARGB(255, 1, 158, 255)),
            SizedBox(width: 4),
            Text(
              'Search by Name, Username or Email!',
              style: TextStyle(
                fontSize: 11,
                color: const Color.fromARGB(255, 67, 144, 160),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
  /// Build recipe suggestions for nutrition analysis
  Widget _buildNutritionRecipeSuggestions() {
    if (_recipeSuggestions.isEmpty) return const SizedBox.shrink();

    return PremiumGate(
      feature: PremiumFeature.viewRecipes,
      featureName: 'Recipe Details',
      featureDescription: 'View full recipe details with ingredients and directions.',
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue.shade800,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Health-Based Recipe Suggestions:',
              style: TextStyle(
                fontSize: 20,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ..._recipeSuggestions.map((recipe) => _buildNutritionRecipeCard(recipe)),
          ],
        ),
      ),
    );
  }

  /// Build collapsible recipe card for nutrition results
  Widget _buildNutritionRecipeCard(Recipe recipe) {
    final isFavorite = _isRecipeFavorited(recipe.title);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
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
            Icon(Icons.expand_more, color: Colors.white),
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
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ingredients: ${recipe.ingredients.join(', ')}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white60,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Instructions: ${recipe.instructions}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white60,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: PremiumGate(
                        feature: PremiumFeature.favoriteRecipes,
                        featureName: 'Favorite Recipes',
                        child: ElevatedButton.icon(
                          onPressed: () => _toggleFavoriteRecipe(recipe),
                          icon: Icon(Icons.favorite),
                          label: Text('Save Recipe'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color.fromARGB(255, 0, 174, 255),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: PremiumGate(
                        feature: PremiumFeature.groceryList,
                        featureName: 'Grocery List',
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (mounted) {
                              ErrorHandlingService.showSuccess(context, 'Added to grocery list!');
                            }
                          },
                          icon: Icon(Icons.add_shopping_cart),
                          label: Text('Add to List'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color.fromARGB(255, 0, 179, 255),
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

  /// Build initial welcome view - FIXED: No more AnimatedBuilder
  Widget _buildInitialView() {
    return Stack(
      children: [
        // Background
        Positioned.fill(
          child: Image.asset(
            'assets/bari.png',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: const Color.fromARGB(255, 116, 215, 251),
                child: Center(
                  child: Icon(
                    Icons.image_not_supported,
                    size: 50,
                    color: Colors.grey,
                  ),
                ),
              );
            },
          ),
        ),
        
        // Content
        SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              // Search Bar
              _buildSearchBar(),
              
              // Welcome Section
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha((0.9 * 255).toInt()),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.scanner,
                      size: 48,
                      color: const Color.fromARGB(255, 0, 255, 251),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Welcome to Liver Food Scanner',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Scan products to discover amazing recipes and get nutrition insights!',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 30),
              
              // FIXED: Scan Button Section with direct state management
              Center(
                child: Column(
                  children: [
                    // Main Scan Button
                    GestureDetector(
                      onTap: _isScanning ? null : _takePhoto,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          color: _isScanning 
                              ? Colors.grey 
                              : (_premiumController.canAccessFeature(PremiumFeature.scan) 
                                  ? Colors.blue 
                                  : Colors.red),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 10,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Center(
                          child: _isScanning
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(color: Colors.white),
                                    SizedBox(height: 16),
                                    Text(
                                      'Scanning...',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _premiumController.canAccessFeature(PremiumFeature.scan)
                                          ? Icons.camera_alt
                                          : Icons.lock,
                                      color: Colors.white,
                                      size: 60,
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      _premiumController.canAccessFeature(PremiumFeature.scan)
                                          ? 'Tap to Scan'
                                          : 'Upgrade to Scan',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    
                    SizedBox(height: 20),
                    
                    // Scan Status
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha((0.9 * 255).toInt()),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          if (!_isPremium) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _premiumController.canAccessFeature(PremiumFeature.scan)
                                      ? Icons.check_circle
                                      : Icons.warning,
                                  color: _premiumController.canAccessFeature(PremiumFeature.scan)
                                      ? const Color.fromARGB(255, 0, 234, 255)
                                      : Colors.red,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  _premiumController.canAccessFeature(PremiumFeature.scan)
                                      ? 'Free scans remaining: $_remainingScans/3'
                                      : 'Daily scan limit reached!',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: _premiumController.canAccessFeature(PremiumFeature.scan)
                                        ? const Color.fromARGB(255, 0, 208, 255)
                                        : Colors.red.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pushNamed(context, '/purchase');
                              },
                              icon: Icon(Icons.star),
                              label: Text('Upgrade for Unlimited Scans'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            
                            SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: _showRewardedAd,
                              icon: Icon(Icons.play_circle_fill),
                              label: Text('Watch Ad for Bonus Scan'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ] else ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.star, color: Colors.amber, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Premium: Unlimited Scans',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.amber.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    
                    SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _performScan,
                      icon: Icon(Icons.qr_code_scanner),
                      label: Text('Quick Scan Demo'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(255, 0, 234, 255),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 30),
              
              // Recipe Results from Demo Scan
              if (_scannedRecipes.isNotEmpty) ...[
                PremiumGate(
                  feature: PremiumFeature.viewRecipes,
                  featureName: 'Recipe Details',
                  featureDescription: 'View full recipe details with ingredients and directions.',
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha((0.9 * 255).toInt()),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.restaurant, color: const Color.fromARGB(255, 0, 208, 255), size: 24),
                            SizedBox(width: 12),
                            Text(
                              'Recipe Suggestions',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      SizedBox(height: 16),
                      
                      ..._scannedRecipes.map((recipe) => _buildScannedRecipeCard(recipe)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Build scanned recipe card
  Widget _buildScannedRecipeCard(Map<String, String> recipe) {
    final isFavorite = _isRecipeFavorited(recipe['name']!);
    
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha((0.9 * 255).toInt()),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ExpansionTile(
        title: Row(
          children: [
            Icon(Icons.restaurant, color: const Color.fromARGB(255, 0, 191, 255)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                recipe['name']!,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
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
            Icon(Icons.expand_more),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ingredients:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 8),
                Text(recipe['ingredients']!),
                
                SizedBox(height: 16),
                
                Text(
                  'Directions:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 8),
                Text(recipe['directions']!),
                
                SizedBox(height: 16),
                
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
                          icon: Icon(Icons.favorite),
                          label: Text('Save Recipe'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: PremiumGate(
                        feature: PremiumFeature.groceryList,
                        featureName: 'Grocery List',
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (mounted) {
                              ErrorHandlingService.showSuccess(context, 'Added to grocery list!');
                            }
                          },
                          icon: Icon(Icons.add_shopping_cart),
                          label: Text('Add to List'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color.fromARGB(255, 0, 165, 183),
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

  /// Build scanning view with results
  Widget _buildScanningView() {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/bari.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 20),

            // Image preview
            if (_imageFile != null)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    _imageFile!,
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.error,
                          size: 50,
                          color: Colors.red,
                        ),
                      );
                    },
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _takePhoto,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Retake'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
                if (_imageFile != null && !_isLoading)
                  ElevatedButton.icon(
                    onPressed: _submitPhoto,
                    icon: const Icon(Icons.send),
                    label: const Text('Analyze'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 76, 170, 175),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ElevatedButton.icon(
                  onPressed: _resetToHome,
                  icon: const Icon(Icons.home),
                  label: const Text('Home'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Loading indicator
            if (_isLoading)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha((0.9 * 255).toInt()),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Analyzing nutrition information...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

            // Nutrition information
            if (_nutritionText.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 0, 185, 252),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info, color: Colors.white, size: 24),
                        SizedBox(width: 12),
                        Text(
                          'Nutrition Information',
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Text(
                      _nutritionText,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.left,
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // Liver health bar
            if (_showLiverBar && _liverHealthScore != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: LiverHealthBar(healthScore: _liverHealthScore!),
              ),

            const SizedBox(height: 20),

            // Recipe suggestions from nutrition analysis
            _buildNutritionRecipeSuggestions(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: MenuIconWithBadge(),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text('Liver Food Scanner'),
        backgroundColor: const Color.fromARGB(255, 76, 152, 175),
        foregroundColor: Colors.white,
        actions: [
          // FIXED: Show purchase button for non-premium users without AnimatedBuilder
          if (!_isPremium)
            IconButton(
              icon: const Icon(Icons.shopping_cart),
              onPressed: () {
                Navigator.pushNamed(context, '/purchase');
              },
            ),
        ],
      ),
      drawer: AppDrawer(currentPage: 'home'),
      body: _showInitialView ? _buildInitialView() : _buildScanningView(),
    );
  }
}