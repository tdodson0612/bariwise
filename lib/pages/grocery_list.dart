// lib/pages/grocery_list.dart - FIXED: Keyboard doesn't cover input fields
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
  String? _errorMessage;

  // ✅ Multi-select mode
  bool isMultiSelectMode = false;
  Set<int> selectedIndices = {};

  // ✅ Scroll controller to auto-scroll when keyboard appears
  final ScrollController _scrollController = ScrollController();

  // Cache configuration
  static const Duration _listCacheDuration = Duration(minutes: 5);

  // 🔥 MEASUREMENT UNITS DROPDOWN
  final List<String> _measurementUnits = [
    'oz',
    'lb',
    'g',
    'kg',
    'cup',
    'tbsp',
    'tsp',
    'ml',
    'L',
    'piece',
    'can',
    'bag',
    'box',
    'bunch',
    'pkg',
  ];

  @override
  void initState() {
    super.initState();
    _initializeUser();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (var controllers in itemControllers) {
      controllers['name']?.dispose();
      controllers['quantity']?.dispose();
      controllers['measurement']?.dispose();
    }
    super.dispose();
  }

  Future<void> _initializeUser() async {
    if (!mounted) return;
    
    setState(() {
      isLoading = true;
      _errorMessage = null;
    });

    try {
      try {
        AuthService.ensureUserAuthenticated();
      } catch (e) {
        print('❌ Authentication check failed: $e');
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
        return;
      }

      await _loadGroceryList();

      if (widget.initialItem != null && widget.initialItem!.isNotEmpty && mounted) {
        _addScannedItem(widget.initialItem!);
      }
    } catch (e, stackTrace) {
      print('❌ Error initializing grocery list: $e');
      print('Stack trace: $stackTrace');
      
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to initialize grocery list';
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

  Future<void> _loadGroceryList({bool forceRefresh = false}) async {
    if (!mounted) return;
    
    print('🔄 Loading grocery list (forceRefresh: $forceRefresh)...');
    
    try {
      if (!forceRefresh) {
        final cachedItems = await _getCachedGroceryList();
        if (cachedItems != null && mounted) {
          print('✅ Loaded ${cachedItems.length} items from cache');
          _populateControllersFromItems(cachedItems);
          return;
        }
      }

      List<GroceryItem> groceryItems;
      try {
        print('🌐 Fetching grocery list from service...');
        groceryItems = await GroceryService.getGroceryList();
        print('✅ Fetched ${groceryItems.length} items from service');
      } catch (e, stackTrace) {
        print('❌ Error fetching from service: $e');
        print('Stack trace: $stackTrace');
        
        final staleItems = await _getCachedGroceryList();
        if (staleItems != null && mounted) {
          print('⚠️ Using stale cache as fallback (${staleItems.length} items)');
          _populateControllersFromItems(staleItems);
          
          setState(() {
            _errorMessage = 'Using offline data. Some items may be outdated.';
          });
          
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

      await _cacheGroceryList(groceryItems);

      if (mounted) {
        _populateControllersFromItems(groceryItems);
        setState(() {
          _errorMessage = null;
        });
      }
    } catch (e, stackTrace) {
      print('❌ Unexpected error in _loadGroceryList: $e');
      print('Stack trace: $stackTrace');
      
      if (mounted) {
        setState(() {
          _errorMessage = 'Unexpected error loading grocery list';
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

  void _populateControllersFromItems(List<GroceryItem> items) {
    if (!mounted) return;
    
    setState(() {
      for (var controllers in itemControllers) {
        controllers['name']?.dispose();
        controllers['quantity']?.dispose();
        controllers['measurement']?.dispose();
      }
      
      itemControllers = items.map((item) {
        final parsed = _parseItemText(item.item);
        return {
          'quantity': TextEditingController(text: parsed['quantity']),
          'measurement': TextEditingController(text: parsed['measurement']),
          'name': TextEditingController(text: parsed['name']),
        };
      }).toList();

      if (itemControllers.isEmpty) {
        itemControllers.add({
          'quantity': TextEditingController(),
          'measurement': TextEditingController(),
          'name': TextEditingController(),
        });
      }

      itemControllers.add({
        'quantity': TextEditingController(),
        'measurement': TextEditingController(),
        'name': TextEditingController(),
      });
    });
  }

  void _addNewItem() {
    setState(() {
      itemControllers.add({
        'quantity': TextEditingController(),
        'measurement': TextEditingController(),
        'name': TextEditingController(),
      });
    });
    
    // ✅ Scroll to bottom after adding new item
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
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

  void _toggleMultiSelectMode() {
    setState(() {
      isMultiSelectMode = !isMultiSelectMode;
      if (!isMultiSelectMode) {
        selectedIndices.clear();
      }
    });
  }

  void _toggleSelection(int index) {
    setState(() {
      if (selectedIndices.contains(index)) {
        selectedIndices.remove(index);
      } else {
        selectedIndices.add(index);
      }
    });
  }

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

    Navigator.pushNamed(
      context,
      '/submit-recipe',
      arguments: {'prefilledIngredients': selectedItems},
    );
  }

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

    Navigator.pushNamed(
      context,
      '/home',
      arguments: {'searchIngredients': selectedIngredients},
    );
  }

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

  List<Map<String, String>> _getCommonSubstitutes(String ingredient) {
    final lower = ingredient.toLowerCase();

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

    if (substitutes.containsKey(lower)) {
      return substitutes[lower]!;
    }

    for (final key in substitutes.keys) {
      if (lower.contains(key) || key.contains(lower)) {
        return substitutes[key]!;
      }
    }

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
      
      try {
        await GroceryService.saveGroceryList(items);
        print('✅ Grocery list saved successfully');
      } catch (e, stackTrace) {
        print('❌ Error saving to service: $e');
        print('Stack trace: $stackTrace');
        throw e;
      }

      await _invalidateGroceryListCache();
      
      try {
        final freshItems = await GroceryService.getGroceryList();
        await _cacheGroceryList(freshItems);
      } catch (e) {
        print('⚠️ Warning: Could not refresh cache after save: $e');
      }

      if (mounted) {
        setState(() {
          _errorMessage = null;
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
          _errorMessage = null;
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
      // ✅ FIX: Prevent keyboard from covering input
      resizeToAvoidBottomInset: true,
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
                // ✅ FIX: Use SingleChildScrollView for entire content
                RefreshIndicator(
                  onRefresh: () => _loadGroceryList(forceRefresh: true),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: MediaQuery.of(context).viewInsets.bottom + 100, // ✅ Extra padding for keyboard
                    ),
                    child: Column(
                      children: [
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

                        // 🔥 ITEMS LIST
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha((0.9 * 255).toInt()),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: itemControllers.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(32),
                                    child: Text(
                                      'No items yet. Start adding groceries!',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                )
                              : Column(
                                  children: List.generate(
                                    itemControllers.length,
                                    (index) {
                                      final isSelected = selectedIndices.contains(index);
                                      final isEmpty = itemControllers[index]['name']!.text.trim().isEmpty;

                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 16),
                                        child: InkWell(
                                          onTap: isMultiSelectMode && !isEmpty
                                              ? () => _toggleSelection(index)
                                              : null,
                                          child: Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: isSelected 
                                                  ? Colors.blue.shade50 
                                                  : Colors.grey.shade50,
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: isSelected 
                                                    ? Colors.blue.shade300 
                                                    : Colors.grey.shade300,
                                                width: 2,
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                // ROW 1: Number/Checkbox + Quantity + Measurement + Delete
                                                Row(
                                                  children: [
                                                    // Number or Checkbox
                                                    if (isMultiSelectMode && !isEmpty)
                                                      Checkbox(
                                                        value: isSelected,
                                                        onChanged: (val) => _toggleSelection(index),
                                                        activeColor: Colors.blue,
                                                      )
                                                    else
                                                      Container(
                                                        width: 40,
                                                        height: 40,
                                                        decoration: BoxDecoration(
                                                          color: Colors.blue.shade100,
                                                          shape: BoxShape.circle,
                                                          border: Border.all(
                                                            color: Colors.blue.shade300,
                                                            width: 2,
                                                          ),
                                                        ),
                                                        child: Center(
                                                          child: Text(
                                                            '${index + 1}',
                                                            style: TextStyle(
                                                              fontSize: 16,
                                                              fontWeight: FontWeight.bold,
                                                              color: Colors.blue.shade700,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    const SizedBox(width: 12),

                                                    // QUANTITY
                                                    SizedBox(
                                                      width: 70,
                                                      child: TextField(
                                                        controller: itemControllers[index]['quantity'],
                                                        decoration: InputDecoration(
                                                          labelText: 'Qty',
                                                          labelStyle: TextStyle(
                                                            fontSize: 12,
                                                            color: Colors.grey.shade700,
                                                          ),
                                                          border: OutlineInputBorder(
                                                            borderRadius: BorderRadius.circular(8),
                                                            borderSide: BorderSide(color: Colors.grey.shade400),
                                                          ),
                                                          focusedBorder: OutlineInputBorder(
                                                            borderRadius: BorderRadius.circular(8),
                                                            borderSide: const BorderSide(color: Colors.blue, width: 2),
                                                          ),
                                                          contentPadding: const EdgeInsets.symmetric(
                                                            horizontal: 12,
                                                            vertical: 14,
                                                          ),
                                                          filled: true,
                                                          fillColor: Colors.white,
                                                        ),
                                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                        inputFormatters: [
                                                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                                        ],
                                                        style: const TextStyle(fontSize: 15),
                                                        textAlign: TextAlign.center,
                                                        enabled: !isMultiSelectMode,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),

                                                    // MEASUREMENT DROPDOWN
                                                    Expanded(
                                                      child: DropdownButtonFormField<String>(
                                                        value: itemControllers[index]['measurement']!.text.isEmpty 
                                                            ? null 
                                                            : (_measurementUnits.contains(itemControllers[index]['measurement']!.text)
                                                                ? itemControllers[index]['measurement']!.text
                                                                : null),
                                                        decoration: InputDecoration(
                                                          labelText: 'Unit',
                                                          labelStyle: TextStyle(
                                                            fontSize: 12,
                                                            color: Colors.grey.shade700,
                                                          ),
                                                          border: OutlineInputBorder(
                                                            borderRadius: BorderRadius.circular(8),
                                                            borderSide: BorderSide(color: Colors.grey.shade400),
                                                          ),
                                                          focusedBorder: OutlineInputBorder(
                                                            borderRadius: BorderRadius.circular(8),
                                                            borderSide: const BorderSide(color: Colors.blue, width: 2),
                                                          ),
                                                          contentPadding: const EdgeInsets.symmetric(
                                                            horizontal: 12,
                                                            vertical: 14,
                                                          ),
                                                          filled: true,
                                                          fillColor: Colors.white,
                                                        ),
                                                        items: _measurementUnits.map((unit) {
                                                          return DropdownMenuItem<String>(
                                                            value: unit,
                                                            child: Text(
                                                              unit,
                                                              style: const TextStyle(fontSize: 15),
                                                            ),
                                                          );
                                                        }).toList(),
                                                        onChanged: isMultiSelectMode 
                                                            ? null 
                                                            : (value) {
                                                                if (value != null) {
                                                                  itemControllers[index]['measurement']!.text = value;
                                                                }
                                                              },
                                                        hint: const Text('Select', style: TextStyle(fontSize: 14)),
                                                      ),
                                                    ),

                                                    // Delete button
                                                    if (itemControllers.length > 1 && !isMultiSelectMode)
                                                      Padding(
                                                        padding: const EdgeInsets.only(left: 8),
                                                        child: IconButton(
                                                          icon: Icon(
                                                            Icons.remove_circle,
                                                            color: Colors.red.shade400,
                                                            size: 28,
                                                          ),
                                                          padding: EdgeInsets.zero,
                                                          constraints: const BoxConstraints(),
                                                          onPressed: () => _removeItem(index),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                                
                                                const SizedBox(height: 12),
                                                
                                                // ROW 2: ITEM NAME (full width)
                                                TextField(
                                                  controller: itemControllers[index]['name'],
                                                  decoration: InputDecoration(
                                                    labelText: 'Item Name',
                                                    labelStyle: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey.shade700,
                                                    ),
                                                    hintText: 'Enter item name...',
                                                    border: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(8),
                                                      borderSide: BorderSide(color: Colors.grey.shade400),
                                                    ),
                                                    focusedBorder: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(8),
                                                      borderSide: const BorderSide(color: Colors.blue, width: 2),
                                                    ),
                                                    contentPadding: const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 16,
                                                    ),
                                                    filled: true,
                                                    fillColor: Colors.white,
                                                  ),
                                                  style: const TextStyle(fontSize: 16),
                                                  onChanged: (text) {
                                                    if (index == itemControllers.length - 1 && text.isNotEmpty) {
                                                      _addNewItem();
                                                    }
                                                  },
                                                  enabled: !isMultiSelectMode,
                                                  // ✅ Auto-scroll when field is focused
                                                  onTap: () {
                                                    Future.delayed(const Duration(milliseconds: 500), () {
                                                      if (_scrollController.hasClients) {
                                                        final double offset = (index * 150.0).clamp(
                                                          0.0, 
                                                          _scrollController.position.maxScrollExtent,
                                                        );
                                                        _scrollController.animateTo(
                                                          offset,
                                                          duration: const Duration(milliseconds: 300),
                                                          curve: Curves.easeOut,
                                                        );
                                                      }
                                                    });
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
                        ),
                        const SizedBox(height: 16),

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
                        // ✅ Extra spacing at bottom for keyboard
                        const SizedBox(height: 200),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}