// lib/pages/grocery_list.dart - Adds Item Detail Sheet + Print/Share Flow
// (also includes: category grouping + checked/purchased behavior from prior delivery)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import '../services/auth_service.dart';
import '../services/grocery_service.dart';
import '../models/grocery_item.dart';
import '../services/error_handling_service.dart';
import '../services/recent_activity_tracker.dart';

class GroceryListPage extends StatefulWidget {
  final String? initialItem;

  const GroceryListPage({super.key, this.initialItem});

  @override
  State<GroceryListPage> createState() => _GroceryListPageState();
}

/// Internal row model: three text controllers plus category/checked state.
class _GroceryRow {
  final TextEditingController quantityController;
  final TextEditingController measurementController;
  final TextEditingController nameController;
  String category;
  bool checked;
  bool categoryManuallySet;

  _GroceryRow({
    TextEditingController? quantityController,
    TextEditingController? measurementController,
    TextEditingController? nameController,
    this.category = 'Other',
    this.checked = false,
    this.categoryManuallySet = false,
  })  : quantityController = quantityController ?? TextEditingController(),
        measurementController = measurementController ?? TextEditingController(),
        nameController = nameController ?? TextEditingController();

  void dispose() {
    quantityController.dispose();
    measurementController.dispose();
    nameController.dispose();
  }
}

class _GroceryListPageState extends State<GroceryListPage> {
  List<_GroceryRow> _rows = [];
  bool isLoading = true;
  bool isSaving = false;
  String? _errorMessage;

  bool isMultiSelectMode = false;
  Set<int> selectedIndices = {};

  final ScrollController _scrollController = ScrollController();

  static const Duration _listCacheDuration = Duration(minutes: 5);

  final List<String> _measurementUnits = [
    'oz', 'lb', 'g', 'kg', 'cup', 'tbsp', 'tsp', 'ml', 'L',
    'piece', 'can', 'bag', 'box', 'bunch', 'pkg',
  ];

  @override
  void initState() {
    super.initState();
    _initializeUser();
    RecentActivityTracker.recordScreen(label: 'Grocery List', route: '/grocery-list');
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (var row in _rows) {
      row.dispose();
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

        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
        return;
      }

      await _loadGroceryList();

      if (widget.initialItem != null && widget.initialItem!.isNotEmpty && mounted) {
        _addScannedItem(widget.initialItem!);
      }
    } catch (e) {

      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to initialize grocery list';
          _rows = [_GroceryRow()];
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
      if (_rows.isNotEmpty && _rows.last.nameController.text.isEmpty) {
        _rows.last.dispose();
        _rows.removeLast();
      }

      final parsed = _parseItemText(item);
      final name = parsed['name'] ?? '';
      _rows.add(_GroceryRow(
        quantityController: TextEditingController(
            text: parsed['quantity']!.isEmpty ? '1' : parsed['quantity']),
        measurementController: TextEditingController(text: parsed['measurement']),
        nameController: TextEditingController(text: name),
        category: GroceryService.autoAssignCategory(name),
        checked: false,
        categoryManuallySet: false,
      ));

      _rows.add(_GroceryRow());
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

debugPrint('📦 Using cached grocery list (${items.length} items)');
      return items;
    } catch (e) {

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

    // ignore: empty_catches
    } catch (e) {

    }
  }

  Future<void> _invalidateGroceryListCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('grocery_list');

    // ignore: empty_catches
    } catch (e) {

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

debugPrint('🔄 Loading grocery list (forceRefresh: $forceRefresh)...');

    try {
      if (!forceRefresh) {
        final cachedItems = await _getCachedGroceryList();
        if (cachedItems != null && mounted) {

          _populateRowsFromItems(cachedItems);
          return;
        }
      }

      List<GroceryItem> groceryItems;
      try {

        groceryItems = await GroceryService.getGroceryList();

      } catch (e) {

        final staleItems = await _getCachedGroceryList();
        if (staleItems != null && mounted) {
debugPrint('⚠️ Using stale cache as fallback (${staleItems.length} items)');
          _populateRowsFromItems(staleItems);

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

        if (mounted) {
          setState(() {
            _rows = [_GroceryRow()];
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
        _populateRowsFromItems(groceryItems);
        setState(() {
          _errorMessage = null;
        });
      }
    } catch (e) {

      if (mounted) {
        setState(() {
          _errorMessage = 'Unexpected error loading grocery list';
          if (_rows.isEmpty) {
            _rows = [_GroceryRow()];
          }
        });
      }
    }
  }

  void _populateRowsFromItems(List<GroceryItem> items) {
    if (!mounted) return;

    setState(() {
      for (var row in _rows) {
        row.dispose();
      }

      _rows = items.map((item) {
        final parsed = _parseItemText(item.item);
        return _GroceryRow(
          quantityController: TextEditingController(text: parsed['quantity']),
          measurementController: TextEditingController(text: parsed['measurement']),
          nameController: TextEditingController(text: parsed['name']),
          category: item.category,
          checked: item.checked,
          categoryManuallySet: true,
        );
      }).toList();

      if (_rows.isEmpty) {
        _rows.add(_GroceryRow());
      }

      _rows.add(_GroceryRow());
    });
  }

  void _onNameChanged(int index, String text) {
    final row = _rows[index];
    final isLast = index == _rows.length - 1;

    if (!row.categoryManuallySet) {
      row.category = text.trim().isEmpty ? 'Other' : GroceryService.autoAssignCategory(text);
    }

    if (isLast && text.isNotEmpty) {
      _addNewItem();
    } else {
      setState(() {});
    }
  }

  void _addNewItem() {
    setState(() {
      _rows.add(_GroceryRow());
    });

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
    if (_rows.length > 1) {
      setState(() {
        _rows[index].dispose();
        _rows.removeAt(index);
        selectedIndices.remove(index);
      });
    }
  }

  void _toggleChecked(int index) {
    setState(() {
      _rows[index].checked = !_rows[index].checked;
    });
  }

  Future<void> _showCategoryPicker(int index) async {
    final row = _rows[index];

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Choose Category',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              ...GroceryService.categories.map((cat) => ListTile(
                    leading: Icon(_categoryIcon(cat), color: Colors.orange),
                    title: Text(cat),
                    trailing: row.category == cat
                        ? const Icon(Icons.check, color: Colors.orange)
                        : null,
                    onTap: () => Navigator.pop(ctx, cat),
                  )),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.orange),
                title: const Text('Custom category...'),
                onTap: () => Navigator.pop(ctx, '__custom__'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (selected == null || !mounted) return;

    if (selected == '__custom__') {
      final controller = TextEditingController(text: row.category == 'Other' ? '' : row.category);
      final custom = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Custom Category'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'e.g. Baby Items'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (custom != null && custom.isNotEmpty && mounted) {
        setState(() {
          row.category = custom;
          row.categoryManuallySet = true;
        });
      }
    } else {
      setState(() {
        row.category = selected;
        row.categoryManuallySet = true;
      });
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Produce':
        return Icons.eco;
      case 'Dairy & Eggs':
        return Icons.egg;
      case 'Meat & Seafood':
        return Icons.set_meal;
      case 'Bakery':
        return Icons.bakery_dining;
      case 'Pantry':
        return Icons.kitchen;
      case 'Frozen':
        return Icons.ac_unit;
      case 'Beverages':
        return Icons.local_drink;
      case 'Snacks':
        return Icons.cookie;
      case 'Household':
        return Icons.cleaning_services;
      default:
        return Icons.label_outline;
    }
  }

  List<MapEntry<String, List<int>>> _groupedRowIndices() {
    if (_rows.isEmpty) return [];
    final lastIndex = _rows.length - 1;
    final Map<String, List<int>> groups = {};

    for (int i = 0; i < _rows.length; i++) {
      if (i == lastIndex) continue;
      if (_rows[i].nameController.text.trim().isEmpty) continue;
      final cat = _rows[i].category.trim().isEmpty ? 'Other' : _rows[i].category;
      groups.putIfAbsent(cat, () => []).add(i);
    }

    for (final indices in groups.values) {
      indices.sort((a, b) {
        final checkedA = _rows[a].checked;
        final checkedB = _rows[b].checked;
        if (checkedA == checkedB) return a.compareTo(b);
        return checkedA ? 1 : -1;
      });
    }

    final result = <MapEntry<String, List<int>>>[];

    for (final cat in GroceryService.categories) {
      if (cat == 'Other') continue;
      if (groups.containsKey(cat)) {
        result.add(MapEntry(cat, groups.remove(cat)!));
      }
    }

    final customCats = groups.keys.where((c) => c != 'Other').toList()..sort();
    for (final cat in customCats) {
      result.add(MapEntry(cat, groups.remove(cat)!));
    }

    if (groups.containsKey('Other')) {
      result.add(MapEntry('Other', groups.remove('Other')!));
    }

    return result;
  }

  // ==================================================
  // ITEM DETAIL SHEET
  // Reuses the row's existing controllers/state directly —
  // no duplicate fields, no separate save step needed here;
  // edits are live and picked up by the normal Save button.
  // ==================================================
  void _showItemDetailSheet(int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final row = _rows[index];
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.shopping_basket, color: Colors.orange),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Item Details',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: row.nameController,
                      decoration: const InputDecoration(
                        labelText: 'Item Name',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (text) {
                        if (!row.categoryManuallySet) {
                          setSheetState(() {
                            row.category =
                                text.trim().isEmpty ? 'Other' : GroceryService.autoAssignCategory(text);
                          });
                        }
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: row.quantityController,
                            decoration: const InputDecoration(
                              labelText: 'Quantity',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: row.measurementController.text.isEmpty
                                ? null
                                : (_measurementUnits.contains(row.measurementController.text)
                                    ? row.measurementController.text
                                    : null),
                            decoration: const InputDecoration(
                              labelText: 'Unit',
                              border: OutlineInputBorder(),
                            ),
                            items: _measurementUnits
                                .map((unit) => DropdownMenuItem<String>(value: unit, child: Text(unit)))
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setSheetState(() => row.measurementController.text = value);
                                setState(() {});
                              }
                            },
                            hint: const Text('Select'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () async {
                        await _showCategoryPicker(index);
                        setSheetState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(_categoryIcon(row.category), color: Colors.orange.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('Category: ${row.category}', style: const TextStyle(fontSize: 15)),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Purchased'),
                      value: row.checked,
                      activeThumbColor: Colors.green,
                      onChanged: (val) {
                        setSheetState(() => row.checked = val);
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _rows.length > 1
                            ? () {
                                Navigator.pop(ctx);
                                _removeItem(index);
                              }
                            : null,
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        label: const Text('Delete Item', style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==================================================
  // PRINT / SHARE FLOW
  // ==================================================
  Future<void> _shareGroceryList() async {
    final groups = _groupedRowIndices();

    if (groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Add items before sharing'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('🛒 My Grocery List');
    buffer.writeln('');

    for (final group in groups) {
      buffer.writeln('${group.key}:');
      for (final idx in group.value) {
        final row = _rows[idx];
        final name = row.nameController.text.trim();
        final quantity = row.quantityController.text.trim();
        final measurement = row.measurementController.text.trim();

        final parts = <String>[];
        if (quantity.isNotEmpty) parts.add(quantity);
        if (measurement.isNotEmpty) parts.add(measurement);
        parts.add(name);

        final mark = row.checked ? '[x]' : '[ ]';
        buffer.writeln('  $mark ${parts.join(' ')}');
      }
      buffer.writeln('');
    }

    await Share.share(buffer.toString().trim(), subject: 'My Grocery List');
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
        .where((i) => i < _rows.length && _rows[i].nameController.text.trim().isNotEmpty)
        .map((i) {
          final name = _rows[i].nameController.text.trim();
          final quantity = _rows[i].quantityController.text.trim();
          final measurement = _rows[i].measurementController.text.trim();

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
        .where((i) => i < _rows.length && _rows[i].nameController.text.trim().isNotEmpty)
        .map((i) => _rows[i].nameController.text.trim())
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
    final ingredientName = _rows[index].nameController.text.trim();

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
              ..._getCommonSubstitutes(ingredientName).map((sub) => Padding(
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
                  )),
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
      final userId = AuthService.currentUserId ?? '';

      final nonEmptyRows =
          _rows.where((row) => row.nameController.text.trim().isNotEmpty).toList();

      final items = <GroceryItem>[];
      for (var i = 0; i < nonEmptyRows.length; i++) {
        final row = nonEmptyRows[i];
        final name = row.nameController.text.trim();
        final quantity = row.quantityController.text.trim();
        final measurement = row.measurementController.text.trim();

        List<String> parts = [];
        if (quantity.isNotEmpty) parts.add(quantity);
        if (measurement.isNotEmpty) parts.add(measurement);
        parts.add(name);

        items.add(GroceryItem(
          userId: userId,
          item: parts.join(' '),
          orderIndex: i,
          createdAt: DateTime.now(),
          category: row.category.trim().isEmpty ? 'Other' : row.category,
          checked: row.checked,
        ));
      }

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

      try {
        await GroceryService.saveGroceryList(items);

      } catch (e) {

        rethrow;
      }

      await _invalidateGroceryListCache();

      try {
        final freshItems = await GroceryService.getGroceryList();
        await _cacheGroceryList(freshItems);
      // ignore: empty_catches
      } catch (e) {

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
    } catch (e) {

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

      try {
        await GroceryService.clearGroceryList();

      } catch (e) {

        rethrow;
      }

      await _invalidateGroceryListCache();

      if (mounted) {
        for (var row in _rows) {
          row.dispose();
        }

        setState(() {
          _rows = [_GroceryRow()];
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
    } catch (e) {

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

  Widget _buildGroupHeader(String category, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 4),
      child: Row(
        children: [
          Icon(_categoryIcon(category), size: 18, color: Colors.orange.shade700),
          const SizedBox(width: 6),
          Text(
            category,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
          ),
          const SizedBox(width: 6),
          Text('($count)', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildRowCard(int index) {
    final row = _rows[index];
    final isSelected = selectedIndices.contains(index);
    final isEmpty = row.nameController.text.trim().isEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: isMultiSelectMode && !isEmpty ? () => _toggleSelection(index) : null,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.shade50 : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.blue.shade300 : Colors.grey.shade300,
              width: 2,
            ),
          ),
          child: Opacity(
            opacity: row.checked && !isEmpty ? 0.55 : 1.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isMultiSelectMode && !isEmpty)
                      Checkbox(
                        value: isSelected,
                        onChanged: (val) => _toggleSelection(index),
                        activeColor: Colors.blue,
                      )
                    else if (!isEmpty)
                      Checkbox(
                        value: row.checked,
                        onChanged: (val) => _toggleChecked(index),
                        activeColor: Colors.green,
                      )
                    else
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.blue.shade300, width: 2),
                        ),
                        child: Center(
                          child: Icon(Icons.add, color: Colors.blue.shade700, size: 20),
                        ),
                      ),
                    const SizedBox(width: 12),

                    SizedBox(
                      width: 70,
                      child: TextField(
                        controller: row.quantityController,
                        decoration: InputDecoration(
                          labelText: 'Qty',
                          labelStyle: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade400),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.blue, width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                        style: const TextStyle(fontSize: 15),
                        textAlign: TextAlign.center,
                        enabled: !isMultiSelectMode,
                      ),
                    ),
                    const SizedBox(width: 12),

                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: row.measurementController.text.isEmpty
                            ? null
                            : (_measurementUnits.contains(row.measurementController.text)
                                ? row.measurementController.text
                                : null),
                        decoration: InputDecoration(
                          labelText: 'Unit',
                          labelStyle: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade400),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.blue, width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: _measurementUnits
                            .map((unit) => DropdownMenuItem<String>(
                                  value: unit,
                                  child: Text(unit, style: const TextStyle(fontSize: 15)),
                                ))
                            .toList(),
                        onChanged: isMultiSelectMode
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => row.measurementController.text = value);
                                }
                              },
                        hint: const Text('Select', style: TextStyle(fontSize: 14)),
                      ),
                    ),

                    if (!isMultiSelectMode && !isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: IconButton(
                          icon: Icon(Icons.open_in_full, color: Colors.blue.shade400, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'View Details',
                          onPressed: () => _showItemDetailSheet(index),
                        ),
                      ),

                    if (_rows.length > 1 && !isMultiSelectMode)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: IconButton(
                          icon: Icon(Icons.remove_circle, color: Colors.red.shade400, size: 28),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _removeItem(index),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                TextField(
                  controller: row.nameController,
                  decoration: InputDecoration(
                    labelText: 'Item Name',
                    labelStyle: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    hintText: 'Enter item name...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade400),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.blue, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  style: TextStyle(
                    fontSize: 16,
                    decoration: row.checked && !isEmpty ? TextDecoration.lineThrough : TextDecoration.none,
                    color: row.checked && !isEmpty ? Colors.grey.shade600 : Colors.black87,
                  ),
                  onChanged: (text) => _onNameChanged(index, text),
                  enabled: !isMultiSelectMode,
                  onTap: () {
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (_scrollController.hasClients) {
                        final double offset =
                            (index * 150.0).clamp(0.0, _scrollController.position.maxScrollExtent);
                        _scrollController.animateTo(
                          offset,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                    });
                  },
                ),

                if (!isEmpty && !isMultiSelectMode) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _showCategoryPicker(index),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_categoryIcon(row.category), size: 14, color: Colors.orange.shade700),
                          const SizedBox(width: 4),
                          Text(
                            row.category,
                            style: TextStyle(fontSize: 12, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.edit, size: 12, color: Colors.orange.shade400),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nonEmptyCount = _rows.where((r) => r.nameController.text.trim().isNotEmpty).length;
    final groups = _groupedRowIndices();

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
              icon: const Icon(Icons.share),
              onPressed: nonEmptyCount > 0 ? _shareGroceryList : null,
              tooltip: 'Share / Print List',
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
                RefreshIndicator(
                  onRefresh: () => _loadGroceryList(forceRefresh: true),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: MediaQuery.of(context).viewInsets.bottom + 100,
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
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isMultiSelectMode ? Colors.blue.shade100 : Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isMultiSelectMode ? Colors.blue.shade300 : Colors.orange.shade300,
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  '$nonEmptyCount items',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: isMultiSelectMode ? Colors.blue.shade700 : Colors.orange.shade700,
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
                                      backgroundColor:
                                          selectedIndices.length == 1 ? Colors.orange : Colors.grey,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (isMultiSelectMode && selectedIndices.isNotEmpty) const SizedBox(height: 16),

                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha((0.9 * 255).toInt()),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: (groups.isEmpty && nonEmptyCount == 0)
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(32),
                                    child: Text(
                                      'No items yet. Start adding groceries!',
                                      style: TextStyle(fontSize: 16, color: Colors.grey),
                                    ),
                                  ),
                                )
                              : Column(
                                  children: [
                                    for (final group in groups) ...[
                                      _buildGroupHeader(group.key, group.value.length),
                                      const SizedBox(height: 8),
                                      for (final idx in group.value) _buildRowCard(idx),
                                      const SizedBox(height: 8),
                                    ],
                                    _buildRowCard(_rows.length - 1),
                                  ],
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