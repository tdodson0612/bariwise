// lib/services/ingredient_database_service.dart
// Multi-database ingredient search with regional priority
// iOS 14 Compatible | Production Ready

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/nutrition_info.dart';
import '../models/ingredient_search_result.dart';
import '../config/app_config.dart';
import 'database_service_core.dart';
import 'profile_service.dart';

class IngredientDatabaseService {
  // Cache for database configuration
  static List<Map<String, dynamic>>? _cachedDatabases;
  static DateTime? _cacheTimestamp;
  static const Duration _cacheDuration = Duration(hours: 24);

  // ============================================================
  // PUBLIC API
  // ============================================================

  /// Search ingredient across all databases with regional priority
  /// Priority: User's region → USDA → Open Food Facts → Global
  static Future<List<IngredientSearchResult>> searchIngredient(
    String query, {
    String? userCountry,
    bool includeNutrition = true,
  }) async {
    try {
      if (query.trim().isEmpty) {
        throw Exception('Search query cannot be empty');
      }

      AppConfig.debugPrint('🔍 Searching for: "$query"');

      // Get user's country if not provided
      userCountry ??= await _getUserCountry();

      // Get regional databases
      final databases = await getRegionalDatabases(userCountry);

      if (databases.isEmpty) {
        throw Exception('No active ingredient databases configured');
      }

      // Search each database in priority order
      final List<IngredientSearchResult> allResults = [];

      for (final db in databases) {
        if (db['is_active'] != true) continue;

        try {
          AppConfig.debugPrint(
            '📚 Searching ${db['name']} (priority: ${db['priority']})',
          );

          final results = await _searchDatabase(
            db['name'],
            db['api_endpoint'],
            query,
            includeNutrition: includeNutrition,
          );

          allResults.addAll(results);

          // If we found good results from high-priority source, we can stop
          if (allResults.length >= 10 && db['priority'] == 1) {
            break;
          }
        } catch (dbError) {
          AppConfig.debugPrint(
            '⚠️ Error searching ${db['name']}: $dbError',
          );
          // Continue to next database
        }
      }

      // Remove duplicates and sort by relevance
      final uniqueResults = _removeDuplicates(allResults);
      uniqueResults.sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));

      AppConfig.debugPrint(
        '✅ Found ${uniqueResults.length} unique results',
      );

      return uniqueResults.take(20).toList();
    } catch (e) {
      AppConfig.debugPrint('❌ Search error: $e');
      throw Exception('Failed to search ingredients: $e');
    }
  }

  /// Get regional database priority list based on user location
  static Future<List<Map<String, dynamic>>> getRegionalDatabases(
    String country,
  ) async {
    try {
      // Check cache
      if (_cachedDatabases != null &&
          _cacheTimestamp != null &&
          DateTime.now().difference(_cacheTimestamp!) < _cacheDuration) {
        return _getFilteredByCountry(_cachedDatabases!, country);
      }

      // Fetch from database
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'ingredient_databases',
        columns: ['*'],
        orderBy: 'priority',
        ascending: true,
      );

      if (response == null || (response as List).isEmpty) {
        // Fallback to defaults
        return _getDefaultDatabases();
      }

      _cachedDatabases = List<Map<String, dynamic>>.from(response);
      _cacheTimestamp = DateTime.now();

      return _getFilteredByCountry(_cachedDatabases!, country);
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error loading databases: $e');
      return _getDefaultDatabases();
    }
  }

  /// Search specific database by name
  static Future<List<IngredientSearchResult>> searchDatabase(
    String databaseName,
    String query,
  ) async {
    try {
      final databases = await getRegionalDatabases('US');
      final db = databases.firstWhere(
        (d) => d['name'] == databaseName,
        orElse: () => throw Exception('Database not found: $databaseName'),
      );

      return await _searchDatabase(
        db['name'],
        db['api_endpoint'],
        query,
        includeNutrition: true,
      );
    } catch (e) {
      throw Exception('Failed to search $databaseName: $e');
    }
  }

  /// Fetch nutrition for specific ingredient by barcode
  static Future<NutritionInfo?> getNutritionData(
    String barcode, {
    String? databaseSource,
  }) async {
    try {
      AppConfig.debugPrint('🔎 Fetching nutrition for barcode: $barcode');

      // Try Open Food Facts first (has best barcode coverage)
      try {
        final nutrition = await _fetchFromOpenFoodFacts(barcode);
        if (nutrition != null && !nutrition.isEmpty) {
          return nutrition;
        }
      } catch (e) {
        AppConfig.debugPrint('⚠️ Open Food Facts lookup failed: $e');
      }

      // Try USDA if specified
      if (databaseSource == 'USDA') {
        try {
          final nutrition = await _fetchFromUSDA(barcode);
          if (nutrition != null && !nutrition.isEmpty) {
            return nutrition;
          }
        } catch (e) {
          AppConfig.debugPrint('⚠️ USDA lookup failed: $e');
        }
      }

      AppConfig.debugPrint('ℹ️ No nutrition data found for barcode');
      return null;
    } catch (e) {
      AppConfig.debugPrint('❌ Error fetching nutrition: $e');
      return null;
    }
  }

  /// Clear database cache (call when databases are updated)
  static void clearCache() {
    _cachedDatabases = null;
    _cacheTimestamp = null;
  }

  // ============================================================
  // PRIVATE HELPERS
  // ============================================================

  static Future<String> _getUserCountry() async {
    try {
      final userId = DatabaseServiceCore.currentUserId;
      if (userId == null) return 'US';

      final profile = await ProfileService.getUserProfile(userId);
      return profile?['location_country'] ?? 'US';
    } catch (e) {
      return 'US';
    }
  }

  static List<Map<String, dynamic>> _getFilteredByCountry(
    List<Map<String, dynamic>> databases,
    String country,
  ) {
    // Get databases for user's region + global databases
    final filtered = databases.where((db) {
      return db['region'] == country ||
          db['region'] == 'Global' ||
          db['is_active'] == true;
    }).toList();

    // Sort by priority (lower = higher priority)
    filtered.sort((a, b) {
      final aPriority = a['priority'] as int? ?? 999;
      final bPriority = b['priority'] as int? ?? 999;

      // Prioritize user's region
      if (a['region'] == country && b['region'] != country) return -1;
      if (b['region'] == country && a['region'] != country) return 1;

      return aPriority.compareTo(bPriority);
    });

    return filtered;
  }

  static List<Map<String, dynamic>> _getDefaultDatabases() {
    return [
      {
        'name': 'Open Food Facts',
        'region': 'Global',
        'api_endpoint': 'https://world.openfoodfacts.org/api/v2',
        'priority': 1,
        'is_active': true,
      },
      {
        'name': 'USDA FoodData Central',
        'region': 'US',
        'api_endpoint': 'https://api.nal.usda.gov/fdc/v1',
        'priority': 2,
        'is_active': true,
      },
    ];
  }

  static Future<List<IngredientSearchResult>> _searchDatabase(
    String databaseName,
    String apiEndpoint,
    String query, {
    required bool includeNutrition,
  }) async {
    switch (databaseName) {
      case 'Open Food Facts':
        return await _searchOpenFoodFacts(query, includeNutrition);

      case 'USDA FoodData Central':
        return await _searchUSDA(query, includeNutrition);

      default:
        throw Exception('Unsupported database: $databaseName');
    }
  }

  // ============================================================
  // OPEN FOOD FACTS API
  // ============================================================

  static Future<List<IngredientSearchResult>> _searchOpenFoodFacts(
    String query,
    bool includeNutrition,
  ) async {
    try {
      final url = Uri.parse(
        'https://world.openfoodfacts.org/cgi/search.pl'
        '?search_terms=$query'
        '&search_simple=1'
        '&action=process'
        '&json=1'
        '&page_size=20',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('Open Food Facts timeout'),
      );

      if (response.statusCode != 200) {
        throw Exception('Open Food Facts API error: ${response.statusCode}');
      }

      final data = json.decode(response.body);
      final products = data['products'] as List? ?? [];

      return products.map((product) {
        final name = product['product_name'] ?? 'Unknown';
        final brand = product['brands'] ?? '';
        final barcode = product['code']?.toString();

        NutritionInfo? nutrition;
        if (includeNutrition && product['nutriments'] != null) {
          try {
            nutrition = NutritionInfo.fromJson({'product': product});
          } catch (e) {
            AppConfig.debugPrint('⚠️ Error parsing nutrition: $e');
          }
        }

        return IngredientSearchResult(
          id: barcode ?? name,
          name: name,
          brand: brand.isNotEmpty ? brand : null,
          barcode: barcode,
          source: 'Open Food Facts',
          nutrition: nutrition,
          servingSize: product['serving_size']?.toString(),
          relevanceScore: _calculateRelevance(name, brand, query),
        );
      }).toList();
    } catch (e) {
      throw Exception('Open Food Facts search failed: $e');
    }
  }

  static Future<NutritionInfo?> _fetchFromOpenFoodFacts(String barcode) async {
    try {
      final url = Uri.parse(
        'https://world.openfoodfacts.org/api/v2/product/$barcode',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      if (data['status'] != 1) return null;

      return NutritionInfo.fromJson(data);
    } catch (e) {
      AppConfig.debugPrint('⚠️ Open Food Facts fetch error: $e');
      return null;
    }
  }

  // ============================================================
  // USDA FOODDATA CENTRAL API
  // ============================================================

  static Future<List<IngredientSearchResult>> _searchUSDA(
    String query,
    bool includeNutrition,
  ) async {
    try {
      // Note: USDA requires API key in production
      // For now, return empty results
      AppConfig.debugPrint('⚠️ USDA search not yet implemented');
      return [];
    } catch (e) {
      throw Exception('USDA search failed: $e');
    }
  }

  static Future<NutritionInfo?> _fetchFromUSDA(String fdcId) async {
    try {
      // Note: USDA requires API key in production
      AppConfig.debugPrint('⚠️ USDA fetch not yet implemented');
      return null;
    } catch (e) {
      AppConfig.debugPrint('⚠️ USDA fetch error: $e');
      return null;
    }
  }

  // ============================================================
  // UTILITIES
  // ============================================================

  static double _calculateRelevance(
    String name,
    String brand,
    String query,
  ) {
    final lowerName = name.toLowerCase();
    final lowerBrand = brand.toLowerCase();
    final lowerQuery = query.toLowerCase();

    double score = 0.0;

    // Exact match = highest score
    if (lowerName == lowerQuery) {
      score = 1.0;
    }
    // Starts with query = high score
    else if (lowerName.startsWith(lowerQuery)) {
      score = 0.9;
    }
    // Contains query = medium score
    else if (lowerName.contains(lowerQuery)) {
      score = 0.7;
    }
    // Brand match = bonus
    else if (lowerBrand.contains(lowerQuery)) {
      score = 0.5;
    }
    // Fuzzy match = low score
    else {
      score = _fuzzyMatch(lowerName, lowerQuery);
    }

    return score;
  }

  static double _fuzzyMatch(String str, String query) {
    int matches = 0;
    for (final char in query.split('')) {
      if (str.contains(char)) matches++;
    }
    return matches / query.length * 0.4;
  }

  static List<IngredientSearchResult> _removeDuplicates(
    List<IngredientSearchResult> results,
  ) {
    final seen = <String>{};
    final unique = <IngredientSearchResult>[];

    for (final result in results) {
      final key = '${result.name}_${result.brand ?? ''}'.toLowerCase();

      if (!seen.contains(key)) {
        seen.add(key);
        unique.add(result);
      }
    }

    return unique;
  }
}