// lib/pages/meal_planner_page.dart
// Section 9 — Meal Planner Workspace (COMPLETE)
// Route: '/meal-planner'
//
// Three tabs:
//   1. Weekly Grid    — plan meals for each day of the week
//   2. Daily Schedule — plan meals for any selected day (Active Day Selector)
//   3. Recipe Planner — grid of favorite recipes, stage several, assign to a day
//
// Additions in this version (Section 9 gap closure):
//   • Active Day Selector      — Daily tab can view/edit any day, not just today
//   • Day Totals Panel         — per-day meal-type breakdown badges
//   • Planner Totals Panel     — week-level summary stats
//   • Recipe Suggestion Grid   — Recipe Planner favorites shown as a grid
//   • Staged Recipes Area      — queue recipes, assign the batch to one day
//   • Plan Overview Mode       — compact read-only week view toggle
//   • Unsaved Changes Protection — Add Meal sheet confirms before discarding
//
// Storage: SharedPreferences (UI/UX-only phase — no Supabase)
// Grocery: planned meals auto-populate /grocery-list via GroceryService

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/grocery_service.dart';
import '../services/favorite_recipes_service.dart';
import '../services/recent_activity_tracker.dart';
import '../services/error_handling_service.dart';
import '../models/favorite_recipe.dart';
import '../config/app_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────────────────────────

class PlannedMeal {
  final String id;
  final String name;
  final String mealType; // breakfast, lunch, dinner, snack
  final String? recipeIngredients; // comma-separated, for grocery list
  final DateTime date;

  PlannedMeal({
    required this.id,
    required this.name,
    required this.mealType,
    this.recipeIngredients,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mealType': mealType,
        'recipeIngredients': recipeIngredients,
        'date': date.toIso8601String(),
      };

  factory PlannedMeal.fromJson(Map<String, dynamic> json) => PlannedMeal(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        mealType: json['mealType'] ?? 'meal',
        recipeIngredients: json['recipeIngredients'],
        date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE
// ─────────────────────────────────────────────────────────────────────────────

class MealPlannerPage extends StatefulWidget {
  const MealPlannerPage({super.key});

  @override
  State<MealPlannerPage> createState() => _MealPlannerPageState();
}

class _MealPlannerPageState extends State<MealPlannerPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  // Shared plan data — keyed by date string 'yyyy-MM-dd'
  Map<String, List<PlannedMeal>> _plan = {};
  bool _loading = true;

  // Favorites for recipe planner tab
  List<FavoriteRecipe> _favorites = [];
  bool _loadingFavorites = true;

  // Week navigation
  DateTime _weekStart = _getMondayOf(DateTime.now());

  // Active Day Selector (Daily tab) — which day is currently being edited
  DateTime _selectedDailyDay = DateTime.now();

  // Plan Overview Mode — compact read-only view toggle for Weekly tab
  bool _overviewMode = false;

  static const String _prefKey = 'meal_planner_data';

  static const List<String> _mealTypes = [
    'Breakfast',
    'Lunch',
    'Dinner',
    'Snack',
  ];

  static const Map<String, IconData> _mealTypeIcons = {
    'Breakfast': Icons.wb_sunny_rounded,
    'Lunch':     Icons.lunch_dining_rounded,
    'Dinner':    Icons.dinner_dining_rounded,
    'Snack':     Icons.apple_rounded,
  };

  static const Map<String, Color> _mealTypeColors = {
    'Breakfast': Color(0xFFF57C00),
    'Lunch':     Color(0xFF388E3C),
    'Dinner':    Color(0xFF1565C0),
    'Snack':     Color(0xFF6A1B9A),
  };

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadPlan();
    _loadFavorites();
    RecentActivityTracker.recordScreen(
        label: 'Meal Planner', route: '/meal-planner');
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> _loadPlan() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw != null) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final plan = <String, List<PlannedMeal>>{};
        for (final entry in decoded.entries) {
          final meals = (entry.value as List)
              .map((m) => PlannedMeal.fromJson(m as Map<String, dynamic>))
              .toList();
          plan[entry.key] = meals;
        }
        if (mounted) setState(() => _plan = plan);
      }
    } catch (e) {
      AppConfig.debugPrint('⚠️ Meal planner load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePlan() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_plan.map(
        (key, meals) => MapEntry(key, meals.map((m) => m.toJson()).toList()),
      ));
      await prefs.setString(_prefKey, encoded);
    } catch (e) {
      AppConfig.debugPrint('⚠️ Meal planner save error: $e');
    }
  }

  Future<void> _loadFavorites() async {
    try {
      final favs = await FavoriteRecipesService.getFavoriteRecipes();
      if (mounted) {
        setState(() {
        _favorites = favs;
        _loadingFavorites = false;
      });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingFavorites = false);
    }
  }

  // ── Plan helpers ───────────────────────────────────────────────────────────

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  List<PlannedMeal> _mealsForDate(DateTime date) =>
      _plan[_dateKey(date)] ?? [];

  void _addMeal(PlannedMeal meal) {
    final key = _dateKey(meal.date);
    setState(() {
      _plan.putIfAbsent(key, () => []);
      _plan[key]!.add(meal);
    });
    _savePlan();
  }

  void _removeMeal(PlannedMeal meal) {
    final key = _dateKey(meal.date);
    setState(() {
      _plan[key]?.removeWhere((m) => m.id == meal.id);
    });
    _savePlan();
  }

  static DateTime _getMondayOf(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  List<DateTime> get _weekDays =>
      List.generate(7, (i) => _weekStart.add(Duration(days: i)));

  void _goToPrevWeek() {
    setState(() {
      _weekStart = _weekStart.subtract(const Duration(days: 7));
      _selectedDailyDay = _weekStart;
    });
  }

  void _goToNextWeek() {
    setState(() {
      _weekStart = _weekStart.add(const Duration(days: 7));
      _selectedDailyDay = _weekStart;
    });
  }

  // ── Day / Planner totals (Section 9) ────────────────────────────────────

  Map<String, int> _countsForDay(DateTime day) {
    final meals = _mealsForDate(day);
    final counts = <String, int>{};
    for (final t in _mealTypes) {
      counts[t] = meals.where((m) => m.mealType == t).length;
    }
    return counts;
  }

  bool _dayIsFullyCovered(DateTime day) {
    final counts = _countsForDay(day);
    return counts.values.every((c) => c > 0);
  }

  // ── Grocery export ─────────────────────────────────────────────────────────

  Future<void> _exportWeekToGrocery() async {
    final weekMeals = _weekDays
        .expand((day) => _mealsForDate(day))
        .where((m) =>
            m.recipeIngredients != null &&
            m.recipeIngredients!.isNotEmpty)
        .toList();

    if (weekMeals.isEmpty) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'No planned meals with ingredients this week. '
          'Add meals from recipes to export ingredients.',
        );
      }
      return;
    }

    try {
      int count = 0;
      for (final meal in weekMeals) {
        final ingredients = meal.recipeIngredients!
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty);
        for (final ing in ingredients) {
          await GroceryService.addToGroceryList(ing);
          count++;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '$count ingredient${count == 1 ? '' : 's'} added to grocery list!'),
          backgroundColor: Colors.orange,
          action: SnackBarAction(
            label: 'VIEW',
            textColor: Colors.white,
            onPressed: () => Navigator.pushNamed(context, '/grocery-list'),
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          customMessage: 'Failed to export to grocery list',
        );
      }
    }
  }

  Future<void> _exportDayToGrocery(DateTime date) async {
    final meals = _mealsForDate(date)
        .where((m) =>
            m.recipeIngredients != null && m.recipeIngredients!.isNotEmpty)
        .toList();

    if (meals.isEmpty) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
            context, 'No meals with ingredients planned for this day.');
      }
      return;
    }

    try {
      int count = 0;
      for (final meal in meals) {
        final ingredients = meal.recipeIngredients!
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty);
        for (final ing in ingredients) {
          await GroceryService.addToGroceryList(ing);
          count++;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$count ingredient${count == 1 ? '' : 's'} added!'),
          backgroundColor: Colors.orange,
          action: SnackBarAction(
            label: 'VIEW',
            textColor: Colors.white,
            onPressed: () => Navigator.pushNamed(context, '/grocery-list'),
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          customMessage: 'Failed to export to grocery list',
        );
      }
    }
  }

  // ── Add meal dialog (Unsaved Changes Protection — Section 9) ───────────────

  Future<void> _showAddMealDialog(DateTime date,
      {String? preSelectedType}) async {
    final nameCtrl = TextEditingController();
    String mealType = preSelectedType ?? 'Breakfast';
    FavoriteRecipe? selectedRecipe;

    Future<bool> confirmDiscardIfNeeded(BuildContext dialogCtx) async {
      if (nameCtrl.text.trim().isEmpty) return true;
      final discard = await showDialog<bool>(
        context: dialogCtx,
        builder: (dctx) => AlertDialog(
          title: const Text('Discard Meal?'),
          content: const Text(
              'You have an unsaved meal name. Discard it without saving?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Keep Editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      return discard == true;
    }

    final result = await showModalBottomSheet<PlannedMeal>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final ok = await confirmDiscardIfNeeded(ctx);
            if (ok && ctx.mounted) Navigator.pop(ctx);
          },
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle + close button
                Row(
                  children: [
                    const Expanded(child: SizedBox()),
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () async {
                            final ok = await confirmDiscardIfNeeded(ctx);
                            if (ok && ctx.mounted) Navigator.pop(ctx);
                          },
                          child: Icon(Icons.close_rounded,
                              size: 20, color: Colors.grey.shade500),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Text(
                  'Add to ${_shortDate(date)}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Meal type selector
                const Text('Meal Type',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  children: _mealTypes.map((type) {
                    final sel = mealType == type;
                    final color =
                        _mealTypeColors[type] ?? Colors.orange;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () => setLocal(() => mealType = type),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                vertical: 8),
                            decoration: BoxDecoration(
                              color: sel
                                  ? color.withValues(alpha: 0.15)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: sel
                                    ? color
                                    : Colors.grey.shade300,
                                width: sel ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  _mealTypeIcons[type] ?? Icons.restaurant,
                                  size: 18,
                                  color: sel ? color : Colors.grey,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  type,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: sel
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: sel ? color : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 16),

                // From favorites
                if (_favorites.isNotEmpty) ...[
                  const Text('From Your Favorites (optional)',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _favorites.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final fav = _favorites[i];
                        final sel = selectedRecipe?.id == fav.id;
                        return GestureDetector(
                          onTap: () {
                            setLocal(() {
                              if (sel) {
                                selectedRecipe = null;
                                nameCtrl.clear();
                              } else {
                                selectedRecipe = fav;
                                nameCtrl.text = fav.recipeName;
                              }
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: sel
                                  ? Colors.orange.shade100
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: sel
                                    ? Colors.orange.shade600
                                    : Colors.grey.shade300,
                                width: sel ? 2 : 1,
                              ),
                            ),
                            child: Text(
                              fav.recipeName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: sel
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: sel
                                    ? Colors.orange.shade900
                                    : Colors.black87,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Meal name
                const Text('Meal Name *',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setLocal(() {}),
                  decoration: InputDecoration(
                    hintText: 'e.g. Greek yogurt with berries',
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: Colors.orange.shade700, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                              content: Text('Please enter a meal name')),
                        );
                        return;
                      }
                      Navigator.pop(
                        ctx,
                        PlannedMeal(
                          id: DateTime.now()
                              .millisecondsSinceEpoch
                              .toString(),
                          name: name,
                          mealType: mealType,
                          recipeIngredients:
                              selectedRecipe?.ingredients,
                          date: date,
                        ),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Add Meal',
                        style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result != null) {
      _addMeal(result);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meal Planner'),
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
        actions: [
          // Plan Overview Mode toggle (Section 9) — only meaningful on Weekly tab
          IconButton(
            icon: Icon(_overviewMode
                ? Icons.edit_rounded
                : Icons.visibility_rounded),
            tooltip: _overviewMode
                ? 'Switch to Edit Mode'
                : 'Switch to Overview Mode',
            onPressed: () => setState(() => _overviewMode = !_overviewMode),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.grid_view_rounded), text: 'Weekly'),
            Tab(icon: Icon(Icons.today_rounded), text: 'Daily'),
            Tab(icon: Icon(Icons.restaurant_menu_rounded),
                text: 'Recipes'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _WeeklyTab(
                  weekDays: _weekDays,
                  weekStart: _weekStart,
                  mealTypes: _mealTypes,
                  mealsForDate: _mealsForDate,
                  countsForDay: _countsForDay,
                  dayIsFullyCovered: _dayIsFullyCovered,
                  onAddMeal: _showAddMealDialog,
                  onRemoveMeal: _removeMeal,
                  onExportToGrocery: _exportWeekToGrocery,
                  onPrevWeek: _goToPrevWeek,
                  onNextWeek: _goToNextWeek,
                  mealTypeColors: _mealTypeColors,
                  mealTypeIcons: _mealTypeIcons,
                  overviewMode: _overviewMode,
                ),
                _DailyTab(
                  selectedDay: _selectedDailyDay,
                  weekDays: _weekDays,
                  onSelectDay: (d) =>
                      setState(() => _selectedDailyDay = d),
                  mealsForDate: _mealsForDate,
                  countsForDay: _countsForDay,
                  onAddMeal: _showAddMealDialog,
                  onRemoveMeal: _removeMeal,
                  onExportToGrocery: _exportDayToGrocery,
                  mealTypes: _mealTypes,
                  mealTypeColors: _mealTypeColors,
                  mealTypeIcons: _mealTypeIcons,
                ),
                _RecipePlannerTab(
                  favorites: _favorites,
                  loading: _loadingFavorites,
                  weekDays: _weekDays,
                  weekStart: _weekStart,
                  mealsForDate: _mealsForDate,
                  onAddMealDirect: _addMeal,
                  onExportToGrocery: _exportWeekToGrocery,
                  onPrevWeek: _goToPrevWeek,
                  onNextWeek: _goToNextWeek,
                ),
              ],
            ),
    );
  }

  String _shortDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED: DAY TOTALS PANEL (Section 9)
// ─────────────────────────────────────────────────────────────────────────────
// Compact badge row showing meal-type counts for a single day.

class _DayTotalsBadges extends StatelessWidget {
  final Map<String, int> counts;
  final Map<String, Color> mealTypeColors;
  final Map<String, IconData> mealTypeIcons;

  const _DayTotalsBadges({
    required this.counts,
    required this.mealTypeColors,
    required this.mealTypeIcons,
  });

  @override
  Widget build(BuildContext context) {
    final nonZero =
        counts.entries.where((e) => e.value > 0).toList();
    if (nonZero.isEmpty) {
      return Text('Nothing planned',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade400));
    }
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: nonZero.map((e) {
        final color = mealTypeColors[e.key] ?? Colors.orange;
        final icon = mealTypeIcons[e.key] ?? Icons.restaurant;
        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 10, color: color),
              const SizedBox(width: 3),
              Text('${e.value}',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: color)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1 — WEEKLY GRID
// ─────────────────────────────────────────────────────────────────────────────

class _WeeklyTab extends StatelessWidget {
  final List<DateTime> weekDays;
  final DateTime weekStart;
  final List<String> mealTypes;
  final List<PlannedMeal> Function(DateTime) mealsForDate;
  final Map<String, int> Function(DateTime) countsForDay;
  final bool Function(DateTime) dayIsFullyCovered;
  final Future<void> Function(DateTime, {String? preSelectedType})
      onAddMeal;
  final void Function(PlannedMeal) onRemoveMeal;
  final VoidCallback onExportToGrocery;
  final VoidCallback onPrevWeek;
  final VoidCallback onNextWeek;
  final Map<String, Color> mealTypeColors;
  final Map<String, IconData> mealTypeIcons;
  final bool overviewMode;

  const _WeeklyTab({
    required this.weekDays,
    required this.weekStart,
    required this.mealTypes,
    required this.mealsForDate,
    required this.countsForDay,
    required this.dayIsFullyCovered,
    required this.onAddMeal,
    required this.onRemoveMeal,
    required this.onExportToGrocery,
    required this.onPrevWeek,
    required this.onNextWeek,
    required this.mealTypeColors,
    required this.mealTypeIcons,
    required this.overviewMode,
  });

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _weekLabel() {
    final end = weekStart.add(const Duration(days: 6));
    if (weekStart.month == end.month) {
      return '${_months[weekStart.month - 1]} ${weekStart.day}–${end.day}';
    }
    return '${_months[weekStart.month - 1]} ${weekStart.day} – '
        '${_months[end.month - 1]} ${end.day}';
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final totalPlanned =
        weekDays.fold<int>(0, (s, d) => s + mealsForDate(d).length);
    final daysWithMeals =
        weekDays.where((d) => mealsForDate(d).isNotEmpty).length;
    final daysFullyCovered =
        weekDays.where((d) => dayIsFullyCovered(d)).length;

    return Column(
      children: [
        // Week header
        Container(
          color: Colors.white,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: onPrevWeek,
                color: Colors.orange.shade700,
              ),
              Expanded(
                child: Center(
                  child: Column(
                    children: [
                      Text(
                        _weekLabel(),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      if (overviewMode)
                        Text('Overview Mode',
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: onNextWeek,
                color: Colors.orange.shade700,
              ),
            ],
          ),
        ),

        // ── Planner Totals Panel (Section 9) ────────────────────────────
        Container(
          color: Colors.white,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _PlannerStat(
                  label: 'Meals Planned',
                  value: '$totalPlanned',
                  color: Colors.orange.shade700),
              _PlannerStat(
                  label: 'Days Started',
                  value: '$daysWithMeals/7',
                  color: Colors.blue.shade700),
              _PlannerStat(
                  label: 'Fully Covered',
                  value: '$daysFullyCovered/7',
                  color: Colors.green.shade700),
            ],
          ),
        ),

        // Export banner
        if (totalPlanned > 0)
          InkWell(
            onTap: onExportToGrocery,
            child: Container(
              color: Colors.orange.shade50,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.shopping_cart_rounded,
                      color: Colors.orange.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$totalPlanned meal${totalPlanned == 1 ? '' : 's'} planned this week — tap to add ingredients to grocery list',
                      style: TextStyle(
                          fontSize: 12, color: Colors.orange.shade900),
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 12, color: Colors.orange.shade700),
                ],
              ),
            ),
          ),

        const Divider(height: 1),

        // Scrollable day list
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: weekDays.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final day = weekDays[i];
              final meals = mealsForDate(day);
              final counts = countsForDay(day);
              final isToday = day.year == today.year &&
                  day.month == today.month &&
                  day.day == today.day;

              return Card(
                elevation: isToday ? 3 : 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: isToday
                      ? BorderSide(
                          color: Colors.orange.shade400, width: 2)
                      : BorderSide.none,
                ),
                child: Column(
                  children: [
                    // Day header
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isToday
                            ? Colors.orange.shade50
                            : Colors.grey.shade50,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isToday
                                  ? Colors.orange.shade700
                                  : Colors.grey.shade300,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _dayLabels[day.weekday - 1],
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isToday
                                          ? Colors.white
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                  Text(
                                    '${day.day}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isToday
                                          ? Colors.white
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            isToday ? 'Today' : _dayLabels[day.weekday - 1] == 'S'
                                ? day.weekday == 6 ? 'Saturday' : 'Sunday'
                                : ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'][day.weekday - 1],
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isToday
                                  ? Colors.orange.shade800
                                  : Colors.black87,
                            ),
                          ),
                          const Spacer(),
                          if (!overviewMode)
                            IconButton(
                              icon: Icon(Icons.add_circle_rounded,
                                  color: Colors.orange.shade700,
                                  size: 22),
                              onPressed: () => onAddMeal(day),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                        ],
                      ),
                    ),

                    // ── Day Totals Panel (Section 9) ────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _DayTotalsBadges(
                          counts: counts,
                          mealTypeColors: mealTypeColors,
                          mealTypeIcons: mealTypeIcons,
                        ),
                      ),
                    ),

                    // Meals — full list in Edit mode, compact icons in Overview mode
                    if (overviewMode) ...[
                      if (meals.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              14, 4, 14, 10),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: meals
                                .map((m) => Tooltip(
                                      message: m.name,
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: (mealTypeColors[
                                                      m.mealType] ??
                                                  Colors.orange)
                                              .withValues(alpha: 0.12),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          mealTypeIcons[m.mealType] ??
                                              Icons.restaurant,
                                          size: 14,
                                          color: mealTypeColors[
                                                  m.mealType] ??
                                              Colors.orange,
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                        )
                      else
                        const SizedBox(height: 4),
                    ] else ...[
                      if (meals.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          child: Text(
                            'No meals planned',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade400),
                          ),
                        )
                      else
                        ...meals.map((meal) => _MealChip(
                              meal: meal,
                              onRemove: () => onRemoveMeal(meal),
                              color: mealTypeColors[meal.mealType] ??
                                  Colors.orange,
                              icon: mealTypeIcons[meal.mealType] ??
                                  Icons.restaurant,
                            )),
                    ],

                    const SizedBox(height: 4),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PlannerStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _PlannerStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          Text(label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 2 — DAILY SCHEDULE (with Active Day Selector — Section 9)
// ─────────────────────────────────────────────────────────────────────────────

class _DailyTab extends StatelessWidget {
  final DateTime selectedDay;
  final List<DateTime> weekDays;
  final void Function(DateTime) onSelectDay;
  final List<PlannedMeal> Function(DateTime) mealsForDate;
  final Map<String, int> Function(DateTime) countsForDay;
  final Future<void> Function(DateTime, {String? preSelectedType})
      onAddMeal;
  final void Function(PlannedMeal) onRemoveMeal;
  final Future<void> Function(DateTime) onExportToGrocery;
  final List<String> mealTypes;
  final Map<String, Color> mealTypeColors;
  final Map<String, IconData> mealTypeIcons;

  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  const _DailyTab({
    required this.selectedDay,
    required this.weekDays,
    required this.onSelectDay,
    required this.mealsForDate,
    required this.countsForDay,
    required this.onAddMeal,
    required this.onRemoveMeal,
    required this.onExportToGrocery,
    required this.mealTypes,
    required this.mealTypeColors,
    required this.mealTypeIcons,
  });

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dayTitle() {
    final today = DateTime.now();
    if (_isSameDay(selectedDay, today)) return "Today's Plan";
    const names = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
      'Saturday', 'Sunday'
    ];
    return "${names[selectedDay.weekday - 1]}'s Plan";
  }

  @override
  Widget build(BuildContext context) {
    final meals = mealsForDate(selectedDay);
    final counts = countsForDay(selectedDay);
    final byType = <String, List<PlannedMeal>>{};
    for (final type in mealTypes) {
      byType[type] =
          meals.where((m) => m.mealType == type).toList();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Active Day Selector (Section 9) ─────────────────────────
          Row(
            children: weekDays.map((day) {
              final sel = _isSameDay(day, selectedDay);
              final today = _isSameDay(day, DateTime.now());
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: GestureDetector(
                    onTap: () => onSelectDay(day),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: sel
                            ? Colors.orange.shade700
                            : today
                                ? Colors.orange.shade50
                                : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: sel
                              ? Colors.orange.shade700
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _dayLabels[day.weekday - 1],
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: sel ? Colors.white : Colors.grey.shade700,
                            ),
                          ),
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: sel ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          // Date header
          Row(
            children: [
              const Icon(Icons.today_rounded, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _dayTitle(),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              if (meals.isNotEmpty)
                TextButton.icon(
                  onPressed: () => onExportToGrocery(selectedDay),
                  icon: const Icon(Icons.shopping_cart_rounded,
                      size: 16),
                  label: const Text('Grocery',
                      style: TextStyle(fontSize: 13)),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.orange.shade700),
                ),
            ],
          ),

          const SizedBox(height: 8),

          // ── Day Totals Panel (Section 9) ─────────────────────────────
          _DayTotalsBadges(
            counts: counts,
            mealTypeColors: mealTypeColors,
            mealTypeIcons: mealTypeIcons,
          ),

          const SizedBox(height: 16),

          // Meal type sections
          ...mealTypes.map((type) {
            final typeMeals = byType[type] ?? [];
            final color = mealTypeColors[type] ?? Colors.orange;
            final icon = mealTypeIcons[type] ?? Icons.restaurant;

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  // Section header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, size: 18, color: color),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          type,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => onAddMeal(selectedDay,
                              preSelectedType: type),
                          icon: Icon(Icons.add_rounded,
                              size: 16, color: color),
                          label: Text('Add',
                              style: TextStyle(
                                  color: color, fontSize: 12)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Meals
                  if (typeMeals.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      child: Text(
                        'Nothing planned for $type yet',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400),
                      ),
                    )
                  else
                    ...typeMeals.map((meal) => _MealChip(
                          meal: meal,
                          onRemove: () => onRemoveMeal(meal),
                          color: color,
                          icon: icon,
                        )),

                  const SizedBox(height: 4),
                ],
              ),
            );
          }),

          // Bariatric tips
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.orange.shade800,
                  Colors.orange.shade600
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text('💡', style: TextStyle(fontSize: 18)),
                    SizedBox(width: 8),
                    Text(
                      'Bariatric Meal Tips',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...const [
                  '• Protein first at every meal',
                  '• Wait 30 min before/after meals to drink',
                  '• Aim for 5–6 small meals per day',
                  '• Stop eating when comfortably full',
                ].map(
                  (tip) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      tip,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                          height: 1.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 3 — RECIPE PLANNER (Recipe Suggestion Grid + Staged Recipes — Section 9)
// ─────────────────────────────────────────────────────────────────────────────

class _RecipePlannerTab extends StatefulWidget {
  final List<FavoriteRecipe> favorites;
  final bool loading;
  final List<DateTime> weekDays;
  final DateTime weekStart;
  final List<PlannedMeal> Function(DateTime) mealsForDate;
  final void Function(PlannedMeal) onAddMealDirect;
  final VoidCallback onExportToGrocery;
  final VoidCallback onPrevWeek;
  final VoidCallback onNextWeek;

  const _RecipePlannerTab({
    required this.favorites,
    required this.loading,
    required this.weekDays,
    required this.weekStart,
    required this.mealsForDate,
    required this.onAddMealDirect,
    required this.onExportToGrocery,
    required this.onPrevWeek,
    required this.onNextWeek,
  });

  @override
  State<_RecipePlannerTab> createState() => _RecipePlannerTabState();
}

class _RecipePlannerTabState extends State<_RecipePlannerTab> {
  // ── Staged Recipes Area (Section 9) ─────────────────────────────────────
  final List<FavoriteRecipe> _staged = [];

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  static const _dayNames = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
  ];

  String _weekLabel() {
    final end = widget.weekStart.add(const Duration(days: 6));
    if (widget.weekStart.month == end.month) {
      return '${_months[widget.weekStart.month - 1]} ${widget.weekStart.day}–${end.day}';
    }
    return '${_months[widget.weekStart.month - 1]} ${widget.weekStart.day} – '
        '${_months[end.month - 1]} ${end.day}';
  }

  bool _isStaged(FavoriteRecipe recipe) =>
      _staged.any((r) => r.id == recipe.id);

  void _toggleStage(FavoriteRecipe recipe) {
    setState(() {
      if (_isStaged(recipe)) {
        _staged.removeWhere((r) => r.id == recipe.id);
      } else {
        _staged.add(recipe);
      }
    });
  }

  void _assignStagedToDay(DateTime day) {
    if (_staged.isEmpty) return;
    final count = _staged.length;
    for (final recipe in _staged) {
      widget.onAddMealDirect(PlannedMeal(
        id: '${DateTime.now().microsecondsSinceEpoch}_${recipe.id}',
        name: recipe.recipeName,
        mealType: 'Lunch',
        recipeIngredients: recipe.ingredients,
        date: day,
      ));
    }
    setState(() => _staged.clear());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Added $count recipe${count == 1 ? '' : 's'} to ${_shortDay(day)} (as Lunch — edit type in Weekly/Daily tab if needed)'),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _shortDay(DateTime day) =>
      '${_dayNames[day.weekday - 1]} ${day.day}';

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.favorites.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bookmark_border_rounded,
                  size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'No Favorite Recipes',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Save recipes to your favorites first, then come back here to plan them into your week.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.pushNamed(context, '/favorite-recipes'),
                icon: const Icon(Icons.favorite_rounded),
                label: const Text('Go to Favorites'),
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.shade700),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Week navigation
        Container(
          color: Colors.white,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: widget.onPrevWeek,
                color: Colors.orange.shade700,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    _weekLabel(),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: widget.onNextWeek,
                color: Colors.orange.shade700,
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // ── Staged Recipes Area (Section 9) ─────────────────────────────
        if (_staged.isNotEmpty)
          Container(
            width: double.infinity,
            color: Colors.orange.shade50,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.playlist_add_check_rounded,
                        size: 16, color: Colors.orange.shade800),
                    const SizedBox(width: 6),
                    Text(
                      'Staged (${_staged.length}) — tap a day to assign',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() => _staged.clear()),
                      child: Text('Clear',
                          style: TextStyle(
                              fontSize: 12, color: Colors.red.shade700)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _staged
                      .map((r) => Chip(
                            label: Text(r.recipeName,
                                style: const TextStyle(fontSize: 12)),
                            backgroundColor: Colors.white,
                            side: BorderSide(
                                color: Colors.orange.shade300),
                            deleteIcon: const Icon(Icons.close, size: 14),
                            onDeleted: () => _toggleStage(r),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 10),
                Row(
                  children: widget.weekDays.map((day) {
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 2),
                        child: GestureDetector(
                          onTap: () => _assignStagedToDay(day),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade700,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  _dayNames[day.weekday - 1],
                                  style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                                Text(
                                  '${day.day}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Export to grocery
                FilledButton.icon(
                  onPressed: widget.onExportToGrocery,
                  icon: const Icon(Icons.shopping_cart_rounded),
                  label: const Text('Export This Week to Grocery List'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    minimumSize:
                        const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Recipe Suggestion Grid (Section 9) ──────────────────
                const Text(
                  'Your Recipe Library',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap recipes to stage them, then assign the batch to a day above.',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),

                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.3,
                  ),
                  itemCount: widget.favorites.length,
                  itemBuilder: (context, i) {
                    final recipe = widget.favorites[i];
                    final staged = _isStaged(recipe);
                    return GestureDetector(
                      onTap: () => _toggleStage(recipe),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: staged
                              ? Colors.orange.shade100
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: staged
                                ? Colors.orange.shade600
                                : Colors.grey.shade300,
                            width: staged ? 2 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius:
                                        BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.restaurant_rounded,
                                    color: Colors.orange.shade700,
                                    size: 16,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  staged
                                      ? Icons.check_circle_rounded
                                      : Icons.add_circle_outline_rounded,
                                  size: 18,
                                  color: staged
                                      ? Colors.orange.shade700
                                      : Colors.grey.shade400,
                                ),
                              ],
                            ),
                            const Spacer(),
                            Text(
                              recipe.recipeName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED: MEAL CHIP
// ─────────────────────────────────────────────────────────────────────────────

class _MealChip extends StatelessWidget {
  final PlannedMeal meal;
  final VoidCallback onRemove;
  final Color color;
  final IconData icon;

  const _MealChip({
    required this.meal,
    required this.onRemove,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              meal.name,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (meal.recipeIngredients != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.shopping_cart_outlined,
                  size: 14, color: Colors.grey.shade400),
            ),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded,
                size: 16, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}