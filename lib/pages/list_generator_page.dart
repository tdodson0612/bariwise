// lib/pages/list_generator_page.dart
// Section 11 — List Generator Workspace
// Route: '/list-generator'
//
// Multi-list manager with three built-in list types:
//   1. Grocery List      — food items to buy
//   2. Supplement Shop   — supplements to restock
//   3. Meal Prep         — prep tasks for the week
//
// Storage: SharedPreferences (UI/UX-only phase)
// The existing /grocery-list screen (GroceryService + Supabase) is untouched.
// This is a separate, richer list management surface.
// NOTE: this duplicate-surface situation is logged in Section 21 Technical Debt
//       ("Duplicate Grocery List Surfaces").
//
// ✅ Adds: List Detail Screen (edit name/category/note), List Archive Screen,
//    Archive Recovery Flow (restore individual / restore all / delete forever).
//    "Clear All" / "Clear Done" now archive instead of permanently deleting.

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/recent_activity_tracker.dart';
import '../config/app_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────────────────────────

enum ListType { grocery, supplement, mealPrep }

class ListItem {
  final String id;
  String name;
  bool checked;
  String? category;
  String? note;

  ListItem({
    required this.id,
    required this.name,
    this.checked = false,
    this.category,
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'checked': checked,
        'category': category,
        'note': note,
      };

  factory ListItem.fromJson(Map<String, dynamic> json) => ListItem(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        checked: json['checked'] ?? false,
        category: json['category'],
        note: json['note'],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// LIST METADATA
// ─────────────────────────────────────────────────────────────────────────────

class _ListMeta {
  final ListType type;
  final String title;
  final IconData icon;
  final Color color;
  final String prefKey;
  final List<String> categories;
  final List<String> suggestions;
  final String addHint;

  const _ListMeta({
    required this.type,
    required this.title,
    required this.icon,
    required this.color,
    required this.prefKey,
    required this.categories,
    required this.suggestions,
    required this.addHint,
  });

  /// Storage key for this list's archived items — kept alongside the
  /// active-list key, same SharedPreferences pattern already in use.
  String get archiveKey => '${prefKey}_archive';
}

const List<_ListMeta> _listMetas = [
  _ListMeta(
    type: ListType.grocery,
    title: 'Grocery List',
    icon: Icons.shopping_cart_rounded,
    color: Color(0xFF2E7D32),
    prefKey: 'list_gen_grocery',
    categories: ['Protein', 'Dairy', 'Produce', 'Grains', 'Beverages', 'Other'],
    suggestions: [
      'Chicken breast', 'Greek yogurt', 'Cottage cheese', 'Eggs',
      'Salmon', 'Turkey', 'Tuna (canned)', 'Protein powder',
      'Spinach', 'Broccoli', 'Zucchini', 'Avocado',
      'String cheese', 'Ricotta', 'Skyr yogurt',
      'Protein bars', 'Sugar-free jello', 'Bone broth',
    ],
    addHint: 'Add grocery item…',
  ),
  _ListMeta(
    type: ListType.supplement,
    title: 'Supplement Shop',
    icon: Icons.medication_rounded,
    color: Color(0xFF1565C0),
    prefKey: 'list_gen_supplement',
    categories: ['Vitamins', 'Minerals', 'Protein', 'Digestive', 'Other'],
    suggestions: [
      'Multivitamin', 'Calcium Citrate', 'Vitamin D3', 'Vitamin B12',
      'Iron', 'Folate', 'Zinc', 'Magnesium',
      'Vitamin B1 (Thiamine)', 'Omega-3 Fish Oil', 'Biotin',
      'Probiotics', 'CoQ10', 'Vitamin C', 'Vitamin K',
    ],
    addHint: 'Add supplement…',
  ),
  _ListMeta(
    type: ListType.mealPrep,
    title: 'Meal Prep',
    icon: Icons.kitchen_rounded,
    color: Color(0xFF6A1B9A),
    prefKey: 'list_gen_meal_prep',
    categories: ['Cook', 'Portion', 'Store', 'Thaw', 'Other'],
    suggestions: [
      'Cook chicken breast (batch)', 'Hard boil eggs', 'Portion Greek yogurt',
      'Prep protein shakes', 'Cook ground turkey',
      'Slice vegetables for snacks', 'Make bone broth',
      'Cook quinoa', 'Prepare cottage cheese bowls',
      'Freeze individual portions', 'Label and date containers',
      'Thaw salmon for tomorrow',
    ],
    addHint: 'Add prep task…',
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// PAGE
// ─────────────────────────────────────────────────────────────────────────────

class ListGeneratorPage extends StatefulWidget {
  const ListGeneratorPage({super.key});

  @override
  State<ListGeneratorPage> createState() => _ListGeneratorPageState();
}

class _ListGeneratorPageState extends State<ListGeneratorPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  // One active list per type
  final Map<ListType, List<ListItem>> _lists = {
    ListType.grocery: [],
    ListType.supplement: [],
    ListType.mealPrep: [],
  };

  // One archive per type
  final Map<ListType, List<ListItem>> _archives = {
    ListType.grocery: [],
    ListType.supplement: [],
    ListType.mealPrep: [],
  };

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadAll();
    RecentActivityTracker.recordScreen(
        label: 'List Generator', route: '/list-generator');
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final meta in _listMetas) {
        final raw = prefs.getString(meta.prefKey);
        if (raw != null) {
          final decoded = jsonDecode(raw) as List;
          _lists[meta.type] =
              decoded.map((j) => ListItem.fromJson(j)).toList();
        }

        final archivedRaw = prefs.getString(meta.archiveKey);
        if (archivedRaw != null) {
          final decodedArchive = jsonDecode(archivedRaw) as List;
          _archives[meta.type] =
              decodedArchive.map((j) => ListItem.fromJson(j)).toList();
        }
      }
    } catch (e) {
      AppConfig.debugPrint('⚠️ List generator load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveList(ListType type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final meta = _listMetas.firstWhere((m) => m.type == type);
      final encoded =
          jsonEncode(_lists[type]!.map((i) => i.toJson()).toList());
      await prefs.setString(meta.prefKey, encoded);
    } catch (e) {
      AppConfig.debugPrint('⚠️ List generator save error: $e');
    }
  }

  Future<void> _saveArchive(ListType type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final meta = _listMetas.firstWhere((m) => m.type == type);
      final encoded =
          jsonEncode(_archives[type]!.map((i) => i.toJson()).toList());
      await prefs.setString(meta.archiveKey, encoded);
    } catch (e) {
      AppConfig.debugPrint('⚠️ List generator archive save error: $e');
    }
  }

  // ── Item management (active list) ──────────────────────────────────────────

  void _addItem(ListType type, String name,
      {String? category, String? note}) {
    if (name.trim().isEmpty) return;
    setState(() {
      _lists[type]!.add(ListItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name.trim(),
        category: category,
        note: note,
      ));
    });
    _saveList(type);
  }

  void _toggleItem(ListType type, String id) {
    setState(() {
      final item = _lists[type]!.firstWhere((i) => i.id == id);
      item.checked = !item.checked;
    });
    _saveList(type);
  }

  void _deleteItem(ListType type, String id) {
    setState(() {
      _lists[type]!.removeWhere((i) => i.id == id);
    });
    _saveList(type);
  }

  /// Edits name/category/note on an existing active-list item in place.
  /// Used by the List Detail Screen bottom sheet.
  void _editItem(ListType type, String id,
      {String? name, String? category, String? note, bool clearNote = false}) {
    setState(() {
      final item = _lists[type]!.firstWhere((i) => i.id == id);
      if (name != null && name.trim().isNotEmpty) item.name = name.trim();
      item.category = category;
      item.note = clearNote ? null : (note?.trim().isEmpty ?? true ? null : note!.trim());
    });
    _saveList(type);
  }

  /// "Clear Done" now archives checked items instead of deleting them forever.
  void _clearChecked(ListType type) {
    setState(() {
      final toArchive = _lists[type]!.where((i) => i.checked).toList();
      _archives[type]!.insertAll(0, toArchive);
      _lists[type]!.removeWhere((i) => i.checked);
    });
    _saveList(type);
    _saveArchive(type);
  }

  /// "Clear All" now archives every item instead of deleting them forever.
  void _clearAll(ListType type) {
    setState(() {
      _archives[type]!.insertAll(0, _lists[type]!);
      _lists[type]!.clear();
    });
    _saveList(type);
    _saveArchive(type);
  }

  // ── Archive Recovery Flow ───────────────────────────────────────────────────

  /// Restores a single archived item back onto the active list.
  /// Checked state resets to false — restoring implies "need this again."
  void _restoreItem(ListType type, String id) {
    setState(() {
      final item = _archives[type]!.firstWhere((i) => i.id == id);
      item.checked = false;
      _lists[type]!.add(item);
      _archives[type]!.removeWhere((i) => i.id == id);
    });
    _saveList(type);
    _saveArchive(type);
  }

  /// Restores every archived item back onto the active list at once.
  void _restoreAll(ListType type) {
    setState(() {
      for (final item in _archives[type]!) {
        item.checked = false;
      }
      _lists[type]!.addAll(_archives[type]!);
      _archives[type]!.clear();
    });
    _saveList(type);
    _saveArchive(type);
  }

  /// Permanently deletes a single archived item — the only truly
  /// destructive action left in this flow, requires its own confirmation
  /// in the Archive screen itself.
  void _deleteArchivedItemForever(ListType type, String id) {
    setState(() {
      _archives[type]!.removeWhere((i) => i.id == id);
    });
    _saveArchive(type);
  }

  // ── Quick-add from suggestions ─────────────────────────────────────────────

  void _addSuggestion(ListType type, String suggestion) {
    final exists =
        _lists[type]!.any((i) => i.name.toLowerCase() == suggestion.toLowerCase());
    if (exists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('"$suggestion" is already on your list.'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ));
      }
      return;
    }
    _addItem(type, suggestion);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Added "$suggestion"'),
        backgroundColor:
            _listMetas.firstWhere((m) => m.type == type).color,
        duration: const Duration(seconds: 1),
      ));
    }
  }

  void _openArchive(_ListMeta meta) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => _ArchiveScreen(
          meta: meta,
          archivedItems: _archives[meta.type]!,
          onRestore: (id) => _restoreItem(meta.type, id),
          onRestoreAll: () => _restoreAll(meta.type),
          onDeleteForever: (id) => _deleteArchivedItemForever(meta.type, id),
        ),
      ),
    ).then((_) {
      // Refresh this screen's state in case items were restored/deleted
      // while the archive screen was open.
      if (mounted) setState(() {});
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('List Generator'),
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: _listMetas
              .map((m) => Tab(icon: Icon(m.icon, size: 20), text: m.title.split(' ').first))
              .toList(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: _listMetas
                  .map((meta) => _ListTab(
                        meta: meta,
                        items: _lists[meta.type]!,
                        archivedCount: _archives[meta.type]!.length,
                        onAdd: (name, {category, note}) =>
                            _addItem(meta.type, name,
                                category: category, note: note),
                        onToggle: (id) => _toggleItem(meta.type, id),
                        onDelete: (id) => _deleteItem(meta.type, id),
                        onEdit: (id, {name, category, note, clearNote = false}) =>
                            _editItem(meta.type, id,
                                name: name,
                                category: category,
                                note: note,
                                clearNote: clearNote),
                        onClearChecked: () => _clearChecked(meta.type),
                        onClearAll: () => _clearAll(meta.type),
                        onAddSuggestion: (s) =>
                            _addSuggestion(meta.type, s),
                        onOpenArchive: () => _openArchive(meta),
                      ))
                  .toList(),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LIST TAB (shared across all three list types)
// ─────────────────────────────────────────────────────────────────────────────

class _ListTab extends StatefulWidget {
  final _ListMeta meta;
  final List<ListItem> items;
  final int archivedCount;
  final void Function(String name, {String? category, String? note}) onAdd;
  final void Function(String id) onToggle;
  final void Function(String id) onDelete;
  final void Function(String id,
      {String? name, String? category, String? note, bool clearNote}) onEdit;
  final VoidCallback onClearChecked;
  final VoidCallback onClearAll;
  final void Function(String suggestion) onAddSuggestion;
  final VoidCallback onOpenArchive;

  const _ListTab({
    required this.meta,
    required this.items,
    required this.archivedCount,
    required this.onAdd,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
    required this.onClearChecked,
    required this.onClearAll,
    required this.onAddSuggestion,
    required this.onOpenArchive,
  });

  @override
  State<_ListTab> createState() => _ListTabState();
}

class _ListTabState extends State<_ListTab> {
  final TextEditingController _addCtrl = TextEditingController();
  String? _selectedCategory;
  bool _showSuggestions = false;

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  List<ListItem> get _unchecked =>
      widget.items.where((i) => !i.checked).toList();

  List<ListItem> get _checked =>
      widget.items.where((i) => i.checked).toList();

  // Group unchecked items by category
  Map<String, List<ListItem>> get _grouped {
    final map = <String, List<ListItem>>{};
    for (final item in _unchecked) {
      final cat = item.category ?? 'Other';
      map.putIfAbsent(cat, () => []).add(item);
    }
    return map;
  }

  void _submit() {
    final name = _addCtrl.text.trim();
    if (name.isEmpty) return;
    widget.onAdd(name, category: _selectedCategory);
    _addCtrl.clear();
    setState(() => _selectedCategory = null);
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive All Items?'),
        content: Text(
            'Move all ${widget.items.length} items from ${widget.meta.title} to the archive? '
            'You can restore them later from the archive screen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                FilledButton.styleFrom(backgroundColor: widget.meta.color),
            child: const Text('Archive All'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onClearAll();
  }

  void _showItemDetailSheet(ListItem item) {
    final nameCtrl = TextEditingController(text: item.name);
    final noteCtrl = TextEditingController(text: item.note ?? '');
    String? selectedCategory = item.category;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
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
                        Icon(widget.meta.icon, color: widget.meta.color),
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
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    const Text('Category', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ChoiceChip(
                          label: const Text('None'),
                          selected: selectedCategory == null,
                          onSelected: (_) => setSheetState(() => selectedCategory = null),
                          selectedColor: widget.meta.color,
                          labelStyle: TextStyle(
                            color: selectedCategory == null ? Colors.white : Colors.black87,
                          ),
                        ),
                        ...widget.meta.categories.map((c) => ChoiceChip(
                              label: Text(c),
                              selected: selectedCategory == c,
                              onSelected: (_) => setSheetState(() => selectedCategory = c),
                              selectedColor: widget.meta.color,
                              labelStyle: TextStyle(
                                color: selectedCategory == c ? Colors.white : Colors.black87,
                              ),
                            )),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          widget.onEdit(
                            item.id,
                            name: nameCtrl.text,
                            category: selectedCategory,
                            note: noteCtrl.text,
                            clearNote: noteCtrl.text.trim().isEmpty,
                          );
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.save),
                        label: const Text('Save Changes'),
                        style: FilledButton.styleFrom(backgroundColor: widget.meta.color),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          widget.onDelete(item.id);
                        },
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        label: const Text('Delete Item', style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
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

  @override
  Widget build(BuildContext context) {
    final color = widget.meta.color;
    final checkedCount = _checked.length;
    final totalCount = widget.items.length;

    return Column(
      children: [
        // ── Add item bar ───────────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _addCtrl,
                      decoration: InputDecoration(
                        hintText: widget.meta.addHint,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 11),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: color, width: 2),
                        ),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Icon(Icons.add_rounded, size: 22),
                  ),
                ],
              ),

              // Category selector
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _categoryChip('None', null, color),
                    ...widget.meta.categories
                        .map((c) => _categoryChip(c, c, color)),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Progress + actions bar ────────────────────────────────────
        if (totalCount > 0 || widget.archivedCount > 0)
          Container(
            color: color.withValues(alpha: 0.05),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: totalCount > 0
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$checkedCount / $totalCount done',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: color),
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: totalCount == 0
                                    ? 0
                                    : checkedCount / totalCount,
                                backgroundColor: color.withValues(alpha: 0.15),
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(color),
                                minHeight: 5,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          'No active items',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                ),
                const SizedBox(width: 12),
                if (checkedCount > 0)
                  TextButton.icon(
                    onPressed: widget.onClearChecked,
                    icon: const Icon(Icons.remove_done_rounded,
                        size: 16),
                    label: const Text('Clear done',
                        style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: color,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                if (totalCount > 0)
                  IconButton(
                    icon: Icon(Icons.archive_outlined,
                        color: Colors.red.shade400, size: 20),
                    onPressed: _confirmClearAll,
                    tooltip: 'Archive all',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      icon: Icon(Icons.inventory_2_outlined,
                          color: color, size: 20),
                      onPressed: widget.onOpenArchive,
                      tooltip: 'View archive',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    if (widget.archivedCount > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints:
                              const BoxConstraints(minWidth: 14, minHeight: 14),
                          child: Text(
                            '${widget.archivedCount}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

        const Divider(height: 1),

        // ── Suggestions toggle ────────────────────────────────────────
        InkWell(
          onTap: () =>
              setState(() => _showSuggestions = !_showSuggestions),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline_rounded,
                    size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  'Quick-add bariatric staples',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color),
                ),
                const Spacer(),
                Icon(
                  _showSuggestions
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                  color: color,
                ),
              ],
            ),
          ),
        ),

        if (_showSuggestions)
          Container(
            color: color.withValues(alpha: 0.03),
            padding:
                const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.meta.suggestions.map((s) {
                final alreadyAdded = widget.items
                    .any((i) => i.name.toLowerCase() == s.toLowerCase());
                return ActionChip(
                  label: Text(s,
                      style: const TextStyle(fontSize: 12)),
                  avatar: Icon(
                    alreadyAdded
                        ? Icons.check_rounded
                        : Icons.add_rounded,
                    size: 14,
                    color: alreadyAdded ? color : Colors.grey.shade600,
                  ),
                  onPressed: alreadyAdded
                      ? null
                      : () => widget.onAddSuggestion(s),
                  backgroundColor: alreadyAdded
                      ? color.withValues(alpha: 0.08)
                      : Colors.grey.shade100,
                  side: BorderSide(
                    color: alreadyAdded
                        ? color.withValues(alpha: 0.3)
                        : Colors.grey.shade300,
                  ),
                );
              }).toList(),
            ),
          ),

        const Divider(height: 1),

        // ── Items list ────────────────────────────────────────────────
        Expanded(
          child: widget.items.isEmpty
              ? _buildEmptyState(color)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                  children: [
                    // Unchecked items, grouped by category
                    ..._grouped.entries.expand((entry) => [
                          if (entry.key != 'Other' ||
                              _grouped.length > 1)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  4, 8, 4, 4),
                              child: Text(
                                entry.key,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ...entry.value.map((item) => _ItemTile(
                                item: item,
                                color: color,
                                onToggle: () =>
                                    widget.onToggle(item.id),
                                onDelete: () =>
                                    widget.onDelete(item.id),
                                onOpenDetail: () =>
                                    _showItemDetailSheet(item),
                              )),
                        ]),

                    // Checked items section
                    if (_checked.isNotEmpty) ...[
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(4, 16, 4, 4),
                        child: Row(
                          children: [
                            Expanded(
                                child: Divider(
                                    color: Colors.grey.shade300)),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
                              child: Text(
                                'Done (${_checked.length})',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500),
                              ),
                            ),
                            Expanded(
                                child: Divider(
                                    color: Colors.grey.shade300)),
                          ],
                        ),
                      ),
                      ..._checked.map((item) => _ItemTile(
                            item: item,
                            color: color,
                            onToggle: () => widget.onToggle(item.id),
                            onDelete: () => widget.onDelete(item.id),
                            onOpenDetail: () => _showItemDetailSheet(item),
                          )),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _categoryChip(String label, String? value, Color color) {
    final selected = _selectedCategory == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => setState(() => _selectedCategory = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? color : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? color : Colors.grey.shade300,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight:
                  selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? Colors.white : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(Color color) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(widget.meta.icon, size: 48, color: color),
            ),
            const SizedBox(height: 16),
            Text(
              '${widget.meta.title} is empty',
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              widget.archivedCount > 0
                  ? 'Type an item above, tap "Quick-add bariatric staples," or restore items from your archive (${widget.archivedCount}).'
                  : 'Type an item above or tap "Quick-add bariatric staples" to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  height: 1.5),
            ),
            if (widget.archivedCount > 0) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: widget.onOpenArchive,
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                label: Text('View Archive (${widget.archivedCount})'),
                style: OutlinedButton.styleFrom(foregroundColor: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ITEM TILE
// ─────────────────────────────────────────────────────────────────────────────

class _ItemTile extends StatelessWidget {
  final ListItem item;
  final Color color;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onOpenDetail;

  const _ItemTile({
    required this.item,
    required this.color,
    required this.onToggle,
    required this.onDelete,
    required this.onOpenDetail,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: item.checked ? 0 : 1,
      color: item.checked ? Colors.grey.shade100 : Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        dense: true,
        onTap: onOpenDetail,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: GestureDetector(
          onTap: onToggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: item.checked ? color : Colors.transparent,
              border: Border.all(
                color: item.checked ? color : Colors.grey.shade400,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: item.checked
                ? const Icon(Icons.check_rounded,
                    color: Colors.white, size: 16)
                : null,
          ),
        ),
        title: Text(
          item.name,
          style: TextStyle(
            fontSize: 14,
            decoration:
                item.checked ? TextDecoration.lineThrough : null,
            color: item.checked
                ? Colors.grey.shade500
                : Colors.black87,
          ),
        ),
        subtitle: item.note != null && item.note!.isNotEmpty
            ? Text(item.note!,
                style: const TextStyle(fontSize: 11))
            : null,
        trailing: IconButton(
          icon: Icon(Icons.delete_outline_rounded,
              size: 18, color: Colors.grey.shade400),
          onPressed: onDelete,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ARCHIVE SCREEN
// Shows archived items for one list type, with per-item Restore /
// Delete Forever, and a bulk Restore All action.
// ─────────────────────────────────────────────────────────────────────────────

class _ArchiveScreen extends StatefulWidget {
  final _ListMeta meta;
  final List<ListItem> archivedItems;
  final void Function(String id) onRestore;
  final VoidCallback onRestoreAll;
  final void Function(String id) onDeleteForever;

  const _ArchiveScreen({
    required this.meta,
    required this.archivedItems,
    required this.onRestore,
    required this.onRestoreAll,
    required this.onDeleteForever,
  });

  @override
  State<_ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<_ArchiveScreen> {
  Future<void> _confirmDeleteForever(ListItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Forever?'),
        content: Text(
            '"${item.name}" will be permanently deleted and cannot be restored.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() {
        widget.onDeleteForever(item.id);
        widget.archivedItems.removeWhere((i) => i.id == item.id);
      });
    }
  }

  Future<void> _confirmRestoreAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore All?'),
        content: Text(
            'Move all ${widget.archivedItems.length} archived items back to your active ${widget.meta.title}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: widget.meta.color),
            child: const Text('Restore All'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() {
        widget.onRestoreAll();
        widget.archivedItems.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.meta.color;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.meta.title} Archive'),
        backgroundColor: color,
        foregroundColor: Colors.white,
        actions: [
          if (widget.archivedItems.isNotEmpty)
            TextButton(
              onPressed: _confirmRestoreAll,
              child: const Text('Restore All',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: widget.archivedItems.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      'Nothing archived yet',
                      style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Items you archive from ${widget.meta.title} will show up here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              itemCount: widget.archivedItems.length,
              itemBuilder: (ctx, index) {
                final item = widget.archivedItems[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                    title: Text(item.name),
                    subtitle: item.note != null && item.note!.isNotEmpty
                        ? Text(item.note!, style: const TextStyle(fontSize: 12))
                        : (item.category != null
                            ? Text(item.category!, style: const TextStyle(fontSize: 12))
                            : null),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.restore, color: color),
                          tooltip: 'Restore',
                          onPressed: () {
                            setState(() {
                              widget.onRestore(item.id);
                              widget.archivedItems.removeWhere((i) => i.id == item.id);
                            });
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_forever_outlined, color: Colors.red.shade400),
                          tooltip: 'Delete Forever',
                          onPressed: () => _confirmDeleteForever(item),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}