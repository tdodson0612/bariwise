// lib/services/nutrition_api_service.dart
// ✅ IMPROVED: Better search relevance and filtering

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:bari_wise/config/app_config.dart';
import 'package:bari_wise/models/nutrition_info.dart';

class NutritionApiService {
  /// Base URL for product-by-barcode lookups.
  static String get _productBaseUrl => AppConfig.openFoodFactsUrl;

  /// Base URL for text search by product/food name.
  static const String _searchBaseUrl =
      'https://world.openfoodfacts.org/cgi/search.pl';

  /// Look up a single product by barcode.
  static Future<NutritionInfo?> fetchByBarcode(String barcode) async {
    if (barcode.trim().isEmpty) return null;

    final url = '$_productBaseUrl/$barcode.json';

    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {'User-Agent': 'bariWiseApp/1.0'},
          )
          .timeout(Duration(seconds: AppConfig.apiTimeoutSeconds));

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      if (data is! Map || data['status'] != 1) return null;

      return NutritionInfo.fromJson(data as Map<String, dynamic>);
    } catch (e) {
      if (AppConfig.enableDebugPrints) {
        print('❌ fetchByBarcode error: $e');
      }
      return null;
    }
  }

  /// Search for products / foods by name with improved relevance filtering.
  static Future<List<NutritionInfo>> searchByName(
    String query, {
    int pageSize = 100, // Fetch more to filter better
    String searchType = 'product', // 'product', 'brand', 'ingredient', 'substitute'
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    try {
      if (AppConfig.enableDebugPrints) {
        print('🔍 Searching for: "$trimmed" (type: $searchType)');
      }

      List<NutritionInfo> rawResults;

      // Handle different search types
      switch (searchType) {
        case 'brand':
          rawResults = await _searchByBrand(trimmed, pageSize: pageSize);
          break;
        case 'ingredient':
          rawResults = await _searchByIngredient(trimmed, pageSize: pageSize);
          break;
        case 'substitute':
          rawResults = await _searchSubstitutes(trimmed, pageSize: pageSize);
          break;
        default: // 'product'
          rawResults = await _performSearch(trimmed, pageSize: pageSize);
      }

      if (AppConfig.enableDebugPrints) {
        print('📦 Raw results: ${rawResults.length}');
      }

      // Filter and score results for relevance
      final scoredResults = _scoreAndFilterResults(rawResults, trimmed);

      if (AppConfig.enableDebugPrints) {
        print('✅ Filtered results: ${scoredResults.length}');
        if (scoredResults.isNotEmpty) {
          print('Top 5 results:');
          for (var i = 0; i < scoredResults.length && i < 5; i++) {
            print('  ${i + 1}. ${scoredResults[i].productName}');
          }
        }
      }

      // Return top 20 most relevant results
      return scoredResults.take(20).toList();
    } catch (e) {
      if (AppConfig.enableDebugPrints) {
        print('❌ searchByName error: $e');
      }
      return [];
    }
  }

  /// Score and filter results based on relevance to search query
  static List<NutritionInfo> _scoreAndFilterResults(
    List<NutritionInfo> results,
    String query,
  ) {
    final queryLower = query.toLowerCase();
    final queryWords = queryLower.split(RegExp(r'\s+'));

    // Score each result
    final scored = <Map<String, dynamic>>[];
    
    for (final item in results) {
      final nameLower = item.productName.toLowerCase();
      int score = 0;

      // Exact match gets highest score
      if (nameLower == queryLower) {
        score += 1000;
      }

      // Contains exact query gets high score
      if (nameLower.contains(queryLower)) {
        score += 500;
      }

      // Starts with query gets bonus
      if (nameLower.startsWith(queryLower)) {
        score += 300;
      }

      // Check if all query words are present
      int wordMatchCount = 0;
      for (final word in queryWords) {
        if (nameLower.contains(word)) {
          wordMatchCount++;
          score += 100;
        }
      }

      // Bonus if all words match
      if (wordMatchCount == queryWords.length) {
        score += 200;
      }

      // Penalize if name is too long (likely unrelated)
      final wordCount = nameLower.split(RegExp(r'\s+')).length;
      if (wordCount > queryWords.length * 3) {
        score -= 50;
      }

      // Bonus for shorter names (more likely to be generic items)
      if (wordCount <= queryWords.length + 2) {
        score += 50;
      }

      // Must have at least some relevance
      if (score >= 100) {
        scored.add({'item': item, 'score': score});
      }
    }

    // Sort by score descending
    scored.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

    return scored.map((x) => x['item'] as NutritionInfo).toList();
  }

  /// Internal helper to perform a single search query
  static Future<List<NutritionInfo>> _performSearch(
    String query, {
    required int pageSize,
  }) async {
    return await _fetchAndParseResults(
      Uri.parse(_searchBaseUrl).replace(
        queryParameters: <String, String>{
          'search_terms': query,
          'action': 'process',
          'json': '1',
          'page_size': pageSize.toString(),
          'fields': 'product_name,nutriments,brands,categories',
          'sort_by': 'unique_scans_n',
        },
      ),
    );
  }

  /// Search by brand name
  static Future<List<NutritionInfo>> _searchByBrand(
    String brand, {
    required int pageSize,
  }) async {
    try {
      final queryParams = <String, String>{
        'tagtype_0': 'brands',
        'tag_contains_0': 'contains',
        'tag_0': brand,
        'action': 'process',
        'json': '1',
        'page_size': pageSize.toString(),
        'fields': 'product_name,nutriments,brands,categories',
        'sort_by': 'unique_scans_n',
      };

      final uri = Uri.parse(_searchBaseUrl).replace(
        queryParameters: queryParams,
      );

      return await _fetchAndParseResults(uri);
    } catch (e) {
      if (AppConfig.enableDebugPrints) {
        print('❌ _searchByBrand error: $e');
      }
      return [];
    }
  }

  /// Search by ingredient
  static Future<List<NutritionInfo>> _searchByIngredient(
    String ingredient, {
    required int pageSize,
  }) async {
    try {
      final queryParams = <String, String>{
        'tagtype_0': 'ingredients',
        'tag_contains_0': 'contains',
        'tag_0': ingredient,
        'action': 'process',
        'json': '1',
        'page_size': pageSize.toString(),
        'fields': 'product_name,nutriments,brands,categories,ingredients_text',
        'sort_by': 'unique_scans_n',
      };

      final uri = Uri.parse(_searchBaseUrl).replace(
        queryParameters: queryParams,
      );

      return await _fetchAndParseResults(uri);
    } catch (e) {
      if (AppConfig.enableDebugPrints) {
        print('❌ _searchByIngredient error: $e');
      }
      return [];
    }
  }

  /// Search for healthy substitutes (healthier alternatives)
  static Future<List<NutritionInfo>> _searchSubstitutes(
    String product, {
    required int pageSize,
  }) async {
    try {
      // Extract category/type from product name (e.g., "beef" from "ground beef")
      final productLower = product.toLowerCase();
      
      // Define substitute mappings
      final substituteMap = {
        'beef': 'turkey OR chicken OR tofu',
        'pork': 'turkey OR chicken',
        'chicken': 'turkey',
        'butter': 'olive oil OR avocado oil',
        'milk': 'almond milk OR oat milk',
        'cream': 'greek yogurt OR coconut cream',
        'sugar': 'honey OR stevia OR monk fruit',
        'white rice': 'brown rice OR quinoa',
        'pasta': 'whole wheat pasta OR zucchini noodles',
        'bread': 'whole wheat bread OR whole grain bread',
        'cheese': 'reduced fat cheese OR nutritional yeast',
        'sour cream': 'greek yogurt',
        'mayonnaise': 'greek yogurt OR avocado',
        'soda': 'sparkling water OR herbal tea',
        'chips': 'veggie chips OR air-popped popcorn',
        'ice cream': 'frozen yogurt OR banana ice cream',
      };

      // Find substitute search term
      String? substituteQuery;
      for (final entry in substituteMap.entries) {
        if (productLower.contains(entry.key)) {
          substituteQuery = entry.value;
          break;
        }
      }

      // If no specific substitute, search for "low fat", "reduced sodium", or "organic" versions
      if (substituteQuery == null) {
        substituteQuery = 'organic $product OR low fat $product OR reduced sodium $product';
      }

      if (AppConfig.enableDebugPrints) {
        print('🔄 Substitute query: $substituteQuery');
      }

      // Search for multiple terms (split by OR)
      final terms = substituteQuery.split(' OR ').map((t) => t.trim()).toList();
      final allResults = <NutritionInfo>[];
      final seenProducts = <String>{};

      for (final term in terms) {
        final results = await _performSearch(term, pageSize: pageSize ~/ terms.length);
        
        for (final result in results) {
          final key = result.productName.toLowerCase();
          if (!seenProducts.contains(key)) {
            seenProducts.add(key);
            allResults.add(result);
          }
        }
      }

      return allResults;
    } catch (e) {
      if (AppConfig.enableDebugPrints) {
        print('❌ _searchSubstitutes error: $e');
      }
      return [];
    }
  }

  /// Fetch and parse results from API
  static Future<List<NutritionInfo>> _fetchAndParseResults(Uri uri) async {
    try {
      final response = await http
          .get(
            uri,
            headers: {'User-Agent': 'bariWiseApp/1.0'},
          )
          .timeout(Duration(seconds: AppConfig.apiTimeoutSeconds));

      if (response.statusCode != 200) return [];

      final data = json.decode(response.body);
      if (data is! Map) return [];

      final products = (data['products'] as List?) ?? [];
      final List<NutritionInfo> results = [];

      for (final item in products) {
        if (item is! Map<String, dynamic>) continue;

        final wrapped = <String, dynamic>{'product': item};

        try {
          final info = NutritionInfo.fromJson(wrapped);

          final hasValidName = info.productName.isNotEmpty &&
              info.productName.toLowerCase() != 'unknown product';

          if (hasValidName) {
            results.add(info);
          }
        } catch (e) {
          if (AppConfig.enableDebugPrints) {
            print('⚠️ Failed to parse product: $e');
          }
          continue;
        }
      }

      return results;
    } catch (e) {
      if (AppConfig.enableDebugPrints) {
        print('❌ _fetchAndParseResults error: $e');
      }
      return [];
    }
  }
}