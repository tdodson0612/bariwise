// lib/pages/grocery_list.dart - ENHANCED with multi-select, action buttons, and better error handling
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/auth_service.dart';
import '../services/grocery_service.dart';
import '../models/grocery_item.dart';
import '../services/error_handling_service.dart';

class GroceryListPage extends StatefulWidget {
  final String? initialItem;

  const GroceryListPage({super.key, this.initialItem});

  @override
  State<GroceryListPage> createState() => _GroceryListPageState();
}

class _GroceryListPageState extends State<GroceryListPage> {
  List<Map<String, TextEditingController>> itemControllers = [];
  bool isLoading = true;
  bool isSaving = false;
  String? _errorMessage;  // 🔥 NEW: Track error state

  // ✅ Multi-select mode
  bool isMultiSelectMode = false;
  Set<int> selectedIndices = {};

  // Cache configuration
  static const Duration _listCacheDuration = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _initializeUser();
  }

  // 🔥 IMPROVED: Better error handling in initialization
  Future<void> _initializeUser() async {
    if (!mounted) return;
    
    setState(() {
      isLoading = true;
      _errorMessage = null;
    });

    try {
      // 🔥 ADDED: Check authentication with better error handling
      try {
        AuthService.ensureUserAuthenticated();
      } catch (e) {
        print('❌ Authentication check failed: $e');
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
        return;
      }

      // 🔥 IMPROVED: Load grocery list with error handling
      await _loadGroceryList();

      // Add scanned item if provided
      if (widget.initialItem != null && widget.initialItem!.isNotEmpty && mounted) {
        _addScannedItem(widget.initialItem!);
      }
    } catch (e, stackTrace) {
      print('❌ Error initializing grocery list: $e');
      print('Stack trace: $stackTrace');
      
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to initialize grocery list';
          // Create empty list so user can still add items
          itemControllers = [
            {
              'quantity': TextEditingController(),
              'measurement': TextEditingController(),
              'name': TextEditingController(),
            }
          ];
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void _addScannedItem(String item) {
    if (!mounted) return;
    
    setState(() {
      // Remove last empty row if exists
      if (itemControllers.isNotEmpty && 
          itemControllers.last['name']!.text.isEmpty) {
        itemControllers.last['name']!.dispose();
        itemControllers.last['quantity']!.dispose();
        itemControllers.last['measurement']!.dispose();
        itemControllers.removeLast();
      }

      final parsed = _parseItemText(item);
      itemControllers.add({
        'quantity': TextEditingController(text: parsed['quantity']!.isEmpty ? '1' : parsed['quantity']),
        'measurement': TextEditingController(text: parsed['measurement']),
        'name': TextEditingController(text: parsed['name']),
      });

      // Add new empty row
      itemControllers.add({
        'quantity': TextEditingController(),
        'measurement': TextEditingController(),
        'name': TextEditingController(),
      });
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Added "$item" to grocery list'),
        backgroundColor: Colors.orange,
        action: SnackBarAction(
          label: 'Save',
          textColor: Colors.white,
          onPressed: _saveGroceryList,
        ),
      ),
    );
  }

  Future<List<GroceryItem>?> _getCachedGroceryList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('grocery_list');
      if (cached == null) return null;

      final data = json.decode(cached);
      final timestamp = data['_cached_at'] as int?;
      if (timestamp == null) return null;

      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > _listCacheDuration.inMilliseconds) return null;

      final items = (data['items'] as List)
          .map((e) => GroceryItem.fromJson(e))
          .toList();

      print('📦 Using cached grocery list (${items.length} items)');
      return items;
    } catch (e) {
      print('⚠️ Error loading cached grocery list: $e');
      return null;
    }
  }

  Future<void> _cacheGroceryList(List<GroceryItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'items': items.map((item) => item.toJson()).toList(),
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString('grocery_list', json.encode(cacheData));
      print('💾 Cached ${items.length} grocery items');
    } catch (e) {
      print('⚠️ Error caching grocery list: $e');
    }
  }

  Future<void> _invalidateGroceryListCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('grocery_list');
      print('🗑️ Invalidated grocery list cache');
    } catch (e) {
      print('⚠️ Error invalidating grocery list cache: $e');
    }
  }

  Map<String, String> _parseItemText(String itemText) {
    String quantity = '';
    String measurement = '';
    String name = itemText;

    final parts = itemText.trim().split(RegExp(r'\s+'));

    if (parts.length >= 3) {
      if (RegExp(r'^[\d.]+$').hasMatch(parts[0])) {
        quantity = parts[0];
        measurement = parts[1];
        name = parts.sublist(2).join(' ');
      }
    } else if (parts.length == 2) {
      if (parts[1].toLowerCase() == 'x' || RegExp(r'^[\d.]+$').hasMatch(parts[0])) {
        final quantityMatch = RegExp(r'^([\d.]+)\s*x?\s*(.+)$').firstMatch(itemText);
        if (quantityMatch != null) {
          quantity = quantityMatch.group(1) ?? '';
          name = quantityMatch.group(2) ?? itemText;
        }
      }
    }

    return {
      'quantity': quantity,
      'measurement': measurement,
      'name': name,
    };
  }

  // 🔥 COMPLETELY REWRITTEN: Much better error handling
  Future<void> _loadGroceryList({bool forceRefresh = false}) async {
    if (!mounted) return;
    
    print('🔄 Loading grocery list (forceRefresh: $forceRefresh)...');
    
    try {
      // Try cache first if not forcing refresh
      if (!forceRefresh) {
        final cachedItems = await _getCachedGroceryList();
        if (cachedItems != null && mounted) {
          print('✅ Loaded ${cachedItems.length} items from cache');
          _populateControllersFromItems(cachedItems);
          return;
        }
      }

      // 🔥 IMPROVED: Fetch from service with explicit error handling
      List<GroceryItem> groceryItems;
      try {
        print('🌐 Fetching grocery list from service...');
        groceryItems = await GroceryService.getGroceryList();
        print('✅ Fetched ${groceryItems.length} items from service');
      } catch (e, stackTrace) {
        print('❌ Error fetching from service: $e');
        print('Stack trace: $stackTrace');
        
        // 🔥 IMPROVED: Try stale cache as fallback
        final staleItems = await _getCachedGroceryList();
        if (staleItems != null && mounted) {
          print('⚠️ Using stale cache as fallback (${staleItems.length} items)');
          _populateControllersFromItems(staleItems);
          
          // Show warning banner
          setState(() {
            _errorMessage = 'Using offline data. Some items may be outdated.';
          });
          
          // Show snackbar with retry option
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Failed to load latest grocery list. Showing cached data.'),
              backgroundColor: Colors.orange,
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () => _loadGroceryList(forceRefresh: true),
              ),
            ),
          );
          return;
        }
        
        // 🔥 IMPROVED: No cache available - create empty list
        print('⚠️ No cache available, creating empty list');
        if (mounted) {
          setState(() {
            itemControllers = [
              {
                'quantity': TextEditingController(),
                'measurement': TextEditingController(),
                'name': TextEditingController(),
              }
            ];
            _errorMessage = 'Unable to load grocery list. Please check your connection.';
          });
          
          // Show error dialog with better message
          await ErrorHandlingService.handleError(
            context: context,
            error: e,
            category: ErrorHandlingService.databaseError,
            customMessage: 'Unable to load grocery list',
            onRetry: () => _loadGroceryList(forceRefresh: true),
          );
        }
        return;
      }

      // 🔥 SUCCESS: Cache the fresh data
      await _cacheGroceryList(groceryItems);

      if (mounted) {
        _populateControllersFromItems(groceryItems);
        setState(() {
          _errorMessage = null;  // Clear any previous errors
        });
      }
    } catch (e, stackTrace) {
      print('❌ Unexpected error in _loadGroceryList: $e');
      print('Stack trace: $stackTrace');
      
      if (mounted) {
        setState(() {
          _errorMessage = 'Unexpected error loading grocery list';
          // Ensure we have at least one empty row
          if (itemControllers.isEmpty) {
            itemControllers = [
              {
                'quantity': TextEditingController(),
                'measurement': TextEditingController(),
                'name': TextEditingController(),
              }
            ];
          }
        });
      }
    }
  }

  // 🔥 NEW: Helper method to populate controllers from items
  void _populateControllersFromItems(List<GroceryItem> items) {
    if (!mounted) return;
    
    setState(() {
      // Dispose existing controllers
      for (var controllers in itemControllers) {
        controllers['name']?.dispose();
        controllers['quantity']?.dispose();
        controllers['measurement']?.dispose();
      }
      
      // Create new controllers from items
      itemControllers = items.map((item) {
        final parsed = _parseItemText(item.item);
        return {
          'quantity': TextEditingController(text: parsed['quantity']),
          'measurement': TextEditingController(text: parsed['measurement']),
          'name': TextEditingController(text: parsed['name']),
        };
      }).toList();

      // Ensure at least one empty row exists
      if (itemControllers.isEmpty) {
        itemControllers.add({
          'quantity': TextEditingController(),
          'measurement': TextEditingController(),
          'name': TextEditingController(),
        });
      }

      // Add trailing empty row for new items
      itemControllers.add({
        'quantity': TextEditingController(),
        'measurement': TextEditingController(),
        'name': TextEditingController(),
      });
    });
  }

  @override
  void dispose() {
    for (var controllers in itemControllers) {
      controllers['name']?.dispose();
      controllers['quantity']?.dispose();
      controllers['measurement']?.dispose();
    }
    super.dispose();
  }

  void _addNewItem() {
    setState(() {
      itemControllers.add({
        'quantity': TextEditingController(),
        'measurement': TextEditingController(),
        'name': TextEditingController(),
      });
    });
  }

  void _removeItem(int index) {
    if (itemControllers.length > 1) {
      setState(() {
        itemControllers[index]['name']?.dispose();
        itemControllers[index]['quantity']?.dispose();
        itemControllers[index]['measurement']?.dispose();
        itemControllers.removeAt(index);
        selectedIndices.remove(index);
      });
    }
  }

  // ✅ Toggle multi-select mode
  void _toggleMultiSelectMode() {
    setState(() {
      isMultiSelectMode = !isMultiSelectMode;
      if (!isMultiSelectMode) {
        selectedIndices.clear();
      }
    });
  }

  // ✅ Toggle item selection
  void _toggleSelection(int index) {
    setState(() {
      if (selectedIndices.contains(index)) {
        selectedIndices.remove(index);
      } else {
        selectedIndices.add(index);
      }
    });
  }

  // ✅ Add selected items to draft recipe
  Future<void> _addToDraftRecipe() async {
    if (selectedIndices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please select items first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final selectedItems = selectedIndices
        .where((i) => i < itemControllers.length && itemControllers[i]['name']!.text.trim().isNotEmpty)
        .map((i) {
          final name = itemControllers[i]['name']!.text.trim();
          final quantity = itemControllers[i]['quantity']!.text.trim();
          final measurement = itemControllers[i]['measurement']!.text.trim();

          List<String> parts = [];
          if (quantity.isNotEmpty) parts.add(quantity);
          if (measurement.isNotEmpty) parts.add(measurement);
          parts.add(name);
          return parts.join(' ');
        })
        .toList();

    // Navigate to submit recipe with pre-filled ingredients
    Navigator.pushNamed(
      context,
      '/submit-recipe',
      arguments: {'prefilledIngredients': selectedItems},
    );
  }

  // ✅ Find recipes using selected ingredients
  Future<void> _findSuggestedRecipe() async {
    if (selectedIndices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please select ingredients first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final selectedIngredients = selectedIndices
        .where((i) => i < itemControllers.length && itemControllers[i]['name']!.text.trim().isNotEmpty)
        .map((i) => itemControllers[i]['name']!.text.trim())
        .toList();

    // Navigate to recipe search with these ingredients as keywords
    Navigator.pushNamed(
      context,
      '/home',
      arguments: {'searchIngredients': selectedIngredients},
    );
  }

  // ✅ Find ingredient substitutes
  Future<void> _findSubstitute() async {
    if (selectedIndices.length != 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please select exactly ONE ingredient to find substitutes'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final index = selectedIndices.first;
    final ingredientName = itemControllers[index]['name']!.text.trim();

    if (ingredientName.isEmpty) {
      return;
    }

    // Show substitution dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Substitutes for "$ingredientName"'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Common substitutes:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              ..._getCommonSubstitutes(ingredientName).map((sub) => 
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.swap_horiz, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          sub['name']!,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getHealthScoreColor(sub['healthScore']!),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${sub['healthScore']}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ✅ Get common substitutes with health scoring
  List<Map<String, String>> _getCommonSubstitutes(String ingredient) {
    final lower = ingredient.toLowerCase();

    // Simple substitution database (can be expanded or moved to a service)
    final substitutes = <String, List<Map<String, String>>>{
      'ground beef': [
        {'name': 'Ground turkey', 'healthScore': '85'},
        {'name': 'Ground chicken', 'healthScore': '80'},
        {'name': 'Lean ground beef', 'healthScore': '70'},
        {'name': 'Plant-based meat', 'healthScore': '75'},
      ],
      'butter': [
        {'name': 'Olive oil', 'healthScore': '90'},
        {'name': 'Coconut oil', 'healthScore': '75'},
        {'name': 'Avocado oil', 'healthScore': '85'},
        {'name': 'Greek yogurt', 'healthScore': '80'},
      ],
      'sugar': [
        {'name': 'Honey', 'healthScore': '70'},
        {'name': 'Maple syrup', 'healthScore': '75'},
        {'name': 'Stevia', 'healthScore': '90'},
        {'name': 'Monk fruit sweetener', 'healthScore': '95'},
      ],
      'white rice': [
        {'name': 'Brown rice', 'healthScore': '85'},
        {'name': 'Quinoa', 'healthScore': '90'},
        {'name': 'Cauliflower rice', 'healthScore': '95'},
        {'name': 'Wild rice', 'healthScore': '88'},
      ],
      'milk': [
        {'name': 'Almond milk', 'healthScore': '80'},
        {'name': 'Oat milk', 'healthScore': '75'},
        {'name': 'Soy milk', 'healthScore': '85'},
        {'name': 'Coconut milk', 'healthScore': '70'},
      ],
    };

    // Check for exact matches first
    if (substitutes.containsKey(lower)) {
      return substitutes[lower]!;
    }

    // Check for partial matches
    for (final key in substitutes.keys) {
      if (lower.contains(key) || key.contains(lower)) {
        return substitutes[key]!;
      }
    }

    // Default generic substitutes
    return [
      {'name': 'No specific substitutes found', 'healthScore': '50'},
      {'name': 'Try searching online for "$ingredient alternatives"', 'healthScore': '50'},
    ];
  }

  Color _getHealthScoreColor(String scoreStr) {
    final score = int.tryParse(scoreStr) ?? 50;
    if (score >= 85) return Colors.orange;
    if (score >= 70) return Colors.orange;
    return Colors.red;
  }

  // 🔥 IMPROVED: Better error handling in save
  Future<void> _saveGroceryList() async {
    if (!mounted) return;
    
    setState(() {
      isSaving = true;
    });

    try {
      List<String> items = itemControllers
          .where((controllers) => controllers['name']!.text.trim().isNotEmpty)
          .map((controllers) {
            final name = controllers['name']!.text.trim();
            final quantity = controllers['quantity']!.text.trim();
            final measurement = controllers['measurement']!.text.trim();

            List<String> parts = [];
            if (quantity.isNotEmpty) parts.add(quantity);
            if (measurement.isNotEmpty) parts.add(measurement);
            parts.add(name);
            return parts.join(' ');
          })
          .toList();

      if (items.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Add at least one item to save'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      print('💾 Saving ${items.length} items to grocery list...');
      
      // 🔥 ADDED: Try-catch around service call
      try {
        await GroceryService.saveGroceryList(items);
        print('✅ Grocery list saved successfully');
      } catch (e, stackTrace) {
        print('❌ Error saving to service: $e');
        print('Stack trace: $stackTrace');
        throw e;  // Re-throw to be caught by outer try-catch
      }

      // Invalidate and refresh cache
      await _invalidateGroceryListCache();
      
      // 🔥 ADDED: Try-catch around cache refresh
      try {
        final freshItems = await GroceryService.getGroceryList();
        await _cacheGroceryList(freshItems);
      } catch (e) {
        print('⚠️ Warning: Could not refresh cache after save: $e');
        // Don't throw - save was successful
      }

      if (mounted) {
        setState(() {
          _errorMessage = null;  // Clear any errors on successful save
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Saved ${items.length} item${items.length == 1 ? '' : 's'}!'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e, stackTrace) {
      print('❌ Error in _saveGroceryList: $e');
      print('Stack trace: $stackTrace');
      
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Error saving grocery list',
          onRetry: _saveGroceryList,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  // 🔥 IMPROVED: Better error handling in clear
  Future<void> _clearGroceryList() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear Grocery List'),
        content: const Text('Are you sure you want to clear your entire grocery list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      print('🗑️ Clearing grocery list...');
      
      // 🔥 ADDED: Try-catch around service call
      try {
        await GroceryService.clearGroceryList();
        print('✅ Grocery list cleared successfully');
      } catch (e, stackTrace) {
        print('❌ Error clearing grocery list: $e');
        print('Stack trace: $stackTrace');
        throw e;
      }

      await _invalidateGroceryListCache();

      if (mounted) {
        // Dispose existing controllers
        for (var controllers in itemControllers) {
          controllers['name']?.dispose();
          controllers['quantity']?.dispose();
          controllers['measurement']?.dispose();
        }

        setState(() {
          itemControllers = [
            {
              'quantity': TextEditingController(),
              'measurement': TextEditingController(),
              'name': TextEditingController(),
            }
          ];
          selectedIndices.clear();
          isMultiSelectMode = false;
          _errorMessage = null;  // Clear any errors
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑️ Grocery list cleared!'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e, stackTrace) {
      print('❌ Error in _clearGroceryList: $e');
      print('Stack trace: $stackTrace');
      
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Error clearing grocery list',
          onRetry: _clearGroceryList,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final nonEmptyCount = itemControllers.where((c) => c['name']!.text.trim().isNotEmpty).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(isMultiSelectMode ? '${selectedIndices.length} selected' : 'My Grocery List'),
        backgroundColor: isMultiSelectMode ? Colors.blue : Colors.orange,
        foregroundColor: Colors.white,
        leading: isMultiSelectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleMultiSelectMode,
              )
            : null,
        actions: [
          if (!isMultiSelectMode) ...[
            IconButton(
              icon: const Icon(Icons.checklist),
              onPressed: nonEmptyCount > 0 ? _toggleMultiSelectMode : null,
              tooltip: 'Select Items',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                await _loadGroceryList(forceRefresh: true);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('🔄 Grocery list refreshed'),
                      backgroundColor: Colors.blue,
                      duration: Duration(seconds: 1),
                    ),
                  );
                }
              },
              tooltip: 'Refresh',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearGroceryList,
              tooltip: 'Clear List',
            ),
          ],
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/background.jpeg',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(color: Colors.grey[100]);
                    },
                  ),
                ),
                RefreshIndicator(
                  onRefresh: () => _loadGroceryList(forceRefresh: true),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // 🔥 NEW: Error banner
                        if (_errorMessage != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade300),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber, color: Colors.orange.shade700),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(color: Colors.orange.shade900),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 20),
                                  onPressed: () {
                                    setState(() {
                                      _errorMessage = null;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        
                        // Header
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha((0.9 * 255).toInt()),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isMultiSelectMode ? Icons.checklist : Icons.shopping_cart,
                                size: 28,
                                color: isMultiSelectMode ? Colors.blue : Colors.orange,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  isMultiSelectMode ? 'Select Items' : 'My Grocery List',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isMultiSelectMode 
                                      ? Colors.blue.shade100 
                                      : Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isMultiSelectMode 
                                        ? Colors.blue.shade300 
                                        : Colors.orange.shade300,
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  '$nonEmptyCount items',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: isMultiSelectMode 
                                        ? Colors.blue.shade700 
                                        : Colors.orange.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ✅ Action buttons when items are selected
                        if (isMultiSelectMode && selectedIndices.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _addToDraftRecipe,
                                        icon: const Icon(Icons.receipt, size: 18),
                                        label: const Text('Add to Recipe'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _findSuggestedRecipe,
                                        icon: const Icon(Icons.search, size: 18),
                                        label: const Text('Find Recipe'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _findSubstitute,
                                    icon: const Icon(Icons.swap_horiz, size: 18),
                                    label: Text(
                                      selectedIndices.length == 1 
                                          ? 'Find Substitute' 
                                          : 'Find Substitute (select 1 item)',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: selectedIndices.length == 1 
                                          ? Colors.orange 
                                          : Colors.grey,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (isMultiSelectMode && selectedIndices.isNotEmpty)
                          const SizedBox(height: 16),

                        // List
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha((0.9 * 255).toInt()),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: itemControllers.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No items yet. Start adding groceries!',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: itemControllers.length,
                                    itemBuilder: (context, index) {
                                      final isSelected = selectedIndices.contains(index);
                                      final isEmpty = itemControllers[index]['name']!.text.trim().isEmpty;

                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 12),
                                        child: InkWell(
                                          onTap: isMultiSelectMode && !isEmpty
                                              ? () => _toggleSelection(index)
                                              : null,
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: isSelected 
                                                  ? Colors.blue.shade50 
                                                  : Colors.transparent,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: isSelected 
                                                    ? Colors.blue.shade300 
                                                    : Colors.transparent,
                                                width: 2,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                // ✅ Checkbox in multi-select mode
                                                if (isMultiSelectMode && !isEmpty)
                                                  Padding(
                                                    padding: const EdgeInsets.only(right: 8),
                                                    child: Checkbox(
                                                      value: isSelected,
                                                      onChanged: (val) => _toggleSelection(index),
                                                      activeColor: Colors.blue,
                                                    ),
                                                  )
                                                else
                                                  // Row number in normal mode
                                                  Container(
                                                    width: 35,
                                                    height: 35,
                                                    decoration: BoxDecoration(
                                                      color: Colors.blue.shade100,
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: Colors.blue.shade300,
                                                        width: 1,
                                                      ),
                                                    ),
                                                    child: Center(
                                                      child: Text(
                                                        '${index + 1}',
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.blue.shade700,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                const SizedBox(width: 12),

                                                // Quantity field
                                                SizedBox(
                                                  width: 50,
                                                  child: TextField(
                                                    controller: itemControllers[index]['quantity'],
                                                    decoration: InputDecoration(
                                                      hintText: 'Qty',
                                                      hintStyle: const TextStyle(fontSize: 11),
                                                      border: OutlineInputBorder(
                                                        borderRadius: BorderRadius.circular(8),
                                                        borderSide: BorderSide(color: Colors.grey.shade300),
                                                      ),
                                                      focusedBorder: OutlineInputBorder(
                                                        borderRadius: BorderRadius.circular(8),
                                                        borderSide: const BorderSide(color: Colors.blue, width: 2),
                                                      ),
                                                      contentPadding: const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 8,
                                                      ),
                                                      filled: true,
                                                      fillColor: Colors.grey.shade50,
                                                    ),
                                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                    inputFormatters: [
                                                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                                    ],
                                                    style: const TextStyle(fontSize: 13),
                                                    textAlign: TextAlign.center,
                                                    enabled: !isMultiSelectMode,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),

                                                // Measurement field
                                                SizedBox(
                                                  width: 55,
                                                  child: TextField(
                                                    controller: itemControllers[index]['measurement'],
                                                    decoration: InputDecoration(
                                                      hintText: 'Unit',
                                                      hintStyle: const TextStyle(fontSize: 11),
                                                      border: OutlineInputBorder(
                                                        borderRadius: BorderRadius.circular(8),
                                                        borderSide: BorderSide(color: Colors.grey.shade300),
                                                      ),
                                                      focusedBorder: OutlineInputBorder(
                                                        borderRadius: BorderRadius.circular(8),
                                                        borderSide: const BorderSide(color: Colors.blue, width: 2),
                                                      ),
                                                      contentPadding: const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 8,
                                                      ),
                                                      filled: true,
                                                      fillColor: Colors.grey.shade50,
                                                    ),
                                                    style: const TextStyle(fontSize: 13),
                                                    textAlign: TextAlign.center,
                                                    enabled: !isMultiSelectMode,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),

                                                // Item name field
                                                Expanded(
                                                  child: TextField(
                                                    controller: itemControllers[index]['name'],
                                                    decoration: InputDecoration(
                                                      hintText: 'Enter item name...',
                                                      border: OutlineInputBorder(
                                                        borderRadius: BorderRadius.circular(8),
                                                        borderSide: BorderSide(color: Colors.grey.shade300),
                                                      ),
                                                      focusedBorder: OutlineInputBorder(
                                                        borderRadius: BorderRadius.circular(8),
                                                        borderSide: const BorderSide(color: Colors.blue, width: 2),
                                                      ),
                                                      contentPadding: const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 8,
                                                      ),
                                                      filled: true,
                                                      fillColor: Colors.grey.shade50,
                                                    ),
                                                    onChanged: (text) {
                                                      if (index == itemControllers.length - 1 && text.isNotEmpty) {
                                                        _addNewItem();
                                                      }
                                                    },
                                                    enabled: !isMultiSelectMode,
                                                  ),
                                                ),

                                                // Remove button
                                                if (itemControllers.length > 1 && !isMultiSelectMode)
                                                  Padding(
                                                    padding: const EdgeInsets.only(left: 6),
                                                    child: IconButton(
                                                      icon: Icon(
                                                        Icons.remove_circle,
                                                        color: Colors.red.shade400,
                                                        size: 22,
                                                      ),
                                                      padding: EdgeInsets.zero,
                                                      constraints: const BoxConstraints(),
                                                      onPressed: () => _removeItem(index),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Buttons (hide in multi-select mode)
                        if (!isMultiSelectMode)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha((0.9 * 255).toInt()),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: ElevatedButton.icon(
                                    onPressed: isSaving ? null : _saveGroceryList,
                                    icon: isSaving
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                            ),
                                          )
                                        : const Icon(Icons.save),
                                    label: Text(isSaving ? 'Saving...' : 'Save Grocery List'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: ElevatedButton.icon(
                                    onPressed: _addNewItem,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add New Item'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
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
              ],
            ),
    );
  }
}