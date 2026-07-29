// lib/pages/bari_dashboard_page.dart
// Weekly progress dashboard showing trends for all bariatric metrics.
// Route: '/bari-dashboard'
//
// ── Section 13 additions (this session) ──────────────────────────────────
// - Dashboard Overview: new first tab combining Tracker Summary Cards,
//   Meal Plan Summary, and Smart Insights.
// - Tracker Summary Cards: one card per major tracker (Weight, Meals,
//   Supplements, Hydration, Symptoms, Meal Plan) — each shows its own
//   system's numbers side-by-side rather than merging anything, per
//   explicit user direction this session ("connect, don't unify").
// - Meal Plan Summary: reads meal_planner_page.dart's PlannedMeal data
//   directly (public class, safe to import) for today's + this week's
//   planned meal counts.
// - Smart Insights: simple rule-based pattern checks across the data
//   already loaded (not AI/ML) — flagged as such, not oversold.
// - Dashboard Filters: 7 / 30 / 90 day range selector, applies to the
//   Nutrients tab chart and Overview computations.
// - Bug fix (found during verification, not introduced this session):
//   the local-fallback snapshot path (used when Supabase has under a
//   week of data) never set `waterCups`, so Water silently showed no
//   data on any locally-filled day even if the user logged water in
//   tracker_page.dart. Fixed by parsing TrackerEntry.waterIntake.

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bari_models.dart';
import '../services/bari_features_service.dart';
import '../services/tracker_service.dart';
import '../services/recent_activity_tracker.dart';
import '../config/app_config.dart';
import 'meal_planner_page.dart' show PlannedMeal;

const _kDNavy      = Color(0xFF0A1628);
const _kDNavyLight = Color(0xFF1A2E4A);
const _kDBg        = Color(0xFFEEF2F7);
const _kDGold      = Color(0xFFC9A84C);

// Mirrors the private `_prefKey` in meal_planner_page.dart's State class.
// Duplicated intentionally — that key is a private (`_`-prefixed) const
// and Dart library privacy prevents cross-file reuse without exporting
// it. Same additive-only approach used for tracker_landing_page.dart's
// reads of extended_tracker_page.dart's keys earlier this session.
const String _kMealPlannerData = 'meal_planner_data';

// Mirrors extended_tracker_page.dart's private `_kWeight` key, for the
// same reason as above.
const String _kExtWeight = 'ext_tracker_weight';

class BariDashboardPage extends StatefulWidget {
  const BariDashboardPage({super.key});

  @override
  State<BariDashboardPage> createState() => _BariDashboardPageState();
}

class _BariDashboardPageState extends State<BariDashboardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _loading = true;

  List<BariNutrientSnapshot> _snapshots = [];
  List<SymptomEntry> _symptoms = [];
  BariWeeklyGoal? _weekGoal;

  // ── Section 13 additions: filter + summary-card data ────────────────
  int _rangeDays = 30;

  double? _todayHydrationCups;
  List<SupplementSchedule> _supplementSchedules = [];
  List<SupplementTakenEntry> _supplementTakenToday = [];

  Map<String, List<PlannedMeal>> _mealPlan = {};

  double? _extWeightLatestKg;
  String? _extWeightLatestDate;

  final _proteinCtrl = TextEditingController();
  final _sodiumCtrl = TextEditingController();
  final _sugarCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();
  final _fiberCtrl = TextEditingController();
  final _waterCtrl = TextEditingController();
  bool _savingGoal = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _loadData();
    RecentActivityTracker.recordScreen(label: 'Dashboard', route: '/bari-dashboard');
  }

  @override
  void dispose() {
    _tabs.dispose();
    _proteinCtrl.dispose();
    _sodiumCtrl.dispose();
    _sugarCtrl.dispose();
    _fatCtrl.dispose();
    _fiberCtrl.dispose();
    _waterCtrl.dispose();
    super.dispose();
  }

  static double? _parseWaterCupsFromString(String water) {
    final match = RegExp(r'^(\d+\.?\d*)').firstMatch(water.trim());
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  String _todayDateKey() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _loading = true);
    try {
      final userId =
          Supabase.instance.client.auth.currentUser?.id ?? '';
      final [supaSnapshots, symptoms, goal] = await Future.wait([
        BariFeaturesService.getDailySnapshots(days: _rangeDays),
        BariFeaturesService.getSymptomLog(
            from: DateTime.now().subtract(Duration(days: _rangeDays))),
        BariFeaturesService.getCurrentWeekGoal(),
      ]);

      List<BariNutrientSnapshot> combined =
          supaSnapshots as List<BariNutrientSnapshot>;

      if (combined.length < 7) {
        // NOTE: TrackerService.getLastSevenDays is hardcoded to 7 days
        // regardless of the selected filter range — this local-fallback
        // path was not modified beyond the water-cups fix, so it still
        // only ever contributes up to 7 days even when a 30/90-day
        // range is selected. Flagging as a pre-existing limitation of
        // this fallback, not something introduced or silently widened.
        final localEntries =
            await TrackerService.getLastSevenDays(userId);
        for (final entry in localEntries) {
          final alreadyHas = combined.any((s) =>
              s.snapshotDate.toIso8601String().startsWith(entry.date));
          if (!alreadyHas) {
            final totals =
                TrackerService.calculateNutritionTotals(entry.meals);
            combined.add(BariNutrientSnapshot(
              userId: userId,
              snapshotDate: DateTime.parse(entry.date),
              calories: totals['calories'],
              proteinG: totals['protein'],
              fatG: totals['fat'],
              saturatedFatG: totals['saturatedFat'],
              sugarG: totals['sugar'],
              sodiumMg: totals['sodium'],
              fiberG: totals['fiber'],
              // ✅ Section 13 bug fix: previously omitted entirely, which
              // silently showed "no data" for Water on any locally-filled
              // day even when the user had logged water that day.
              waterCups: entry.waterIntake != null
                  ? _parseWaterCupsFromString(entry.waterIntake!)
                  : null,
              dailyScore: entry.dailyScore,
              weightKg: entry.weight,
              supplementCount: entry.supplements.length,
            ));
          }
        }
        combined.sort((a, b) => a.snapshotDate.compareTo(b.snapshotDate));
      }

      final weekGoal = goal as BariWeeklyGoal?;

      // ── Section 13: Tracker Summary Card data loads ──────────────────
      double? todayHydration;
      List<SupplementSchedule> schedules = [];
      List<SupplementTakenEntry> takenToday = [];
      try {
        final today = DateTime.now();
        final todayStart = DateTime(today.year, today.month, today.day);
        final todayEnd = todayStart.add(const Duration(days: 1));
        final results = await Future.wait([
          BariFeaturesService.getHydrationLog(from: todayStart, to: todayEnd),
          BariFeaturesService.getSupplementSchedules(),
          BariFeaturesService.getSupplementTakenLog(
              from: todayStart, to: todayEnd),
        ]);
        final hydrationEntries = results[0] as List;
        todayHydration =
            hydrationEntries.fold<double>(0, (s, e) => s + (e.cups as double));
        schedules = results[1] as List<SupplementSchedule>;
        takenToday = results[2] as List<SupplementTakenEntry>;
      } catch (e) {
        AppConfig.debugPrint('Dashboard summary-card load error: $e');
      }

      // ── Section 13: Meal Plan Summary data load ──────────────────────
      Map<String, List<PlannedMeal>> mealPlan = {};
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_kMealPlannerData);
        if (raw != null) {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          for (final entry in decoded.entries) {
            mealPlan[entry.key] = (entry.value as List)
                .map((m) => PlannedMeal.fromJson(m as Map<String, dynamic>))
                .toList();
          }
        }
      } catch (e) {
        AppConfig.debugPrint('Dashboard meal-plan load error: $e');
      }

      // ── Section 13: extended_tracker_page.dart Weight system read ────
      double? extWeightKg;
      String? extWeightDate;
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_kExtWeight);
        if (raw != null) {
          final list = jsonDecode(raw) as List;
          if (list.isNotEmpty) {
            // Entries are inserted most-recent-first in
            // extended_tracker_page.dart, but read defensively by date
            // rather than assuming order.
            final sorted = list
                .map((j) => j as Map<String, dynamic>)
                .toList()
              ..sort((a, b) =>
                  (b['date'] as String).compareTo(a['date'] as String));
            extWeightKg = (sorted.first['weightKg'] as num).toDouble();
            extWeightDate = sorted.first['date'] as String?;
          }
        }
      } catch (e) {
        AppConfig.debugPrint('Dashboard ext-weight load error: $e');
      }

      if (mounted) {
        setState(() {
          _snapshots = combined;
          _symptoms = symptoms as List<SymptomEntry>;
          _weekGoal = weekGoal;
          _todayHydrationCups = todayHydration;
          _supplementSchedules = schedules;
          _supplementTakenToday = takenToday;
          _mealPlan = mealPlan;
          _extWeightLatestKg = extWeightKg;
          _extWeightLatestDate = extWeightDate;
          _loading = false;
          _proteinCtrl.text =
              weekGoal?.goalProteinG?.toStringAsFixed(0) ?? '60';
          _sodiumCtrl.text =
              weekGoal?.goalSodiumMg?.toStringAsFixed(0) ?? '1500';
          _sugarCtrl.text =
              weekGoal?.goalSugarG?.toStringAsFixed(0) ?? '25';
          _fatCtrl.text =
              weekGoal?.goalFatG?.toStringAsFixed(0) ?? '45';
          _fiberCtrl.text =
              weekGoal?.goalFiberG?.toStringAsFixed(0) ?? '20';
          _waterCtrl.text =
              weekGoal?.goalWaterCups?.toStringAsFixed(1) ?? '8';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      AppConfig.debugPrint('Dashboard load error: $e');
    }
  }

  Future<void> _saveWeeklyGoal() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    setState(() => _savingGoal = true);
    try {
      final goal = BariWeeklyGoal(
        id: _weekGoal?.id,
        userId: uid,
        weekStartDate: _getMondayOfCurrentWeek(),
        goalProteinG: double.tryParse(_proteinCtrl.text),
        goalSodiumMg: double.tryParse(_sodiumCtrl.text),
        goalSugarG: double.tryParse(_sugarCtrl.text),
        goalFatG: double.tryParse(_fatCtrl.text),
        goalFiberG: double.tryParse(_fiberCtrl.text),
        goalWaterCups: double.tryParse(_waterCtrl.text),
      );
      final saved = await BariFeaturesService.saveWeeklyGoal(goal);
      if (mounted) {
        setState(() => _weekGoal = saved);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✅ Weekly goals saved!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error saving goals: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _savingGoal = false);
    }
  }

  void _onRangeChanged(int days) {
    if (days == _rangeDays) return;
    setState(() => _rangeDays = days);
    _loadData();
  }

  BariNutrientSnapshot? get _todaySnapshot {
    final todayKey = _todayDateKey();
    for (final s in _snapshots) {
      if (s.snapshotDate.toIso8601String().startsWith(todayKey)) return s;
    }
    return null;
  }

  int get _todayPlannedMealCount =>
      (_mealPlan[_todayDateKey()] ?? []).length;

  int get _weekPlannedMealCount {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    int count = 0;
    for (int i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i));
      final key =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      count += (_mealPlan[key] ?? []).length;
    }
    return count;
  }

  int get _todaySymptomCount {
    final now = DateTime.now();
    return _symptoms
        .where((s) =>
            s.loggedAt.year == now.year &&
            s.loggedAt.month == now.month &&
            s.loggedAt.day == now.day)
        .length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kDBg,
      appBar: AppBar(
        title: const Text('Bariatric Dashboard'),
        backgroundColor: _kDNavy,
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              // ── Section 13: Dashboard Filters ─────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [7, 30, 90].map((d) {
                    final sel = _rangeDays == d;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text('$d days',
                            style: const TextStyle(fontSize: 12)),
                        selected: sel,
                        selectedColor: _kDGold.withOpacity(0.25),
                        backgroundColor: Colors.white.withOpacity(0.08),
                        labelStyle: TextStyle(
                            color: sel ? _kDGold : Colors.white70),
                        side: BorderSide(
                            color: sel ? _kDGold : Colors.white24),
                        onSelected: (_) => _onRangeChanged(d),
                      ),
                    );
                  }).toList(),
                ),
              ),
              TabBar(
                controller: _tabs,
                indicatorColor: _kDGold,
                indicatorWeight: 3,
                labelColor: _kDGold,
                unselectedLabelColor: Colors.white54,
                isScrollable: true,
                tabs: const [
                  Tab(icon: Icon(Icons.dashboard_rounded), text: 'Overview'),
                  Tab(icon: Icon(Icons.bar_chart_rounded), text: 'Nutrients'),
                  Tab(icon: Icon(Icons.sick_rounded), text: 'Symptoms'),
                  Tab(icon: Icon(Icons.flag_rounded), text: 'Goals'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _OverviewTab(
                  rangeDays: _rangeDays,
                  todaySnapshot: _todaySnapshot,
                  todayHydrationCups: _todayHydrationCups,
                  supplementSchedules: _supplementSchedules,
                  supplementTakenToday: _supplementTakenToday,
                  extWeightLatestKg: _extWeightLatestKg,
                  extWeightLatestDate: _extWeightLatestDate,
                  todayPlannedMealCount: _todayPlannedMealCount,
                  weekPlannedMealCount: _weekPlannedMealCount,
                  todaySymptomCount: _todaySymptomCount,
                  snapshots: _snapshots,
                  symptoms: _symptoms,
                  onGoToNutrients: () => _tabs.animateTo(1),
                ),
                _NutrientTab(snapshots: _snapshots),
                _SymptomTab(symptoms: _symptoms),
                _GoalsTab(
                  proteinCtrl: _proteinCtrl,
                  sodiumCtrl: _sodiumCtrl,
                  sugarCtrl: _sugarCtrl,
                  fatCtrl: _fatCtrl,
                  fiberCtrl: _fiberCtrl,
                  waterCtrl: _waterCtrl,
                  saving: _savingGoal,
                  onSave: _saveWeeklyGoal,
                  snapshots: _snapshots,
                  weekGoal: _weekGoal,
                ),
              ],
            ),
    );
  }

  static DateTime _getMondayOfCurrentWeek() {
    final now = DateTime.now();
    return now.subtract(Duration(days: now.weekday - 1));
  }
}

// ============================================================
// TAB 0 — OVERVIEW (Section 13 addition)
// ============================================================

class _OverviewTab extends StatelessWidget {
  final int rangeDays;
  final BariNutrientSnapshot? todaySnapshot;
  final double? todayHydrationCups;
  final List<SupplementSchedule> supplementSchedules;
  final List<SupplementTakenEntry> supplementTakenToday;
  final double? extWeightLatestKg;
  final String? extWeightLatestDate;
  final int todayPlannedMealCount;
  final int weekPlannedMealCount;
  final int todaySymptomCount;
  final List<BariNutrientSnapshot> snapshots;
  final List<SymptomEntry> symptoms;
  final VoidCallback onGoToNutrients;

  const _OverviewTab({
    required this.rangeDays,
    required this.todaySnapshot,
    required this.todayHydrationCups,
    required this.supplementSchedules,
    required this.supplementTakenToday,
    required this.extWeightLatestKg,
    required this.extWeightLatestDate,
    required this.todayPlannedMealCount,
    required this.weekPlannedMealCount,
    required this.todaySymptomCount,
    required this.snapshots,
    required this.symptoms,
    required this.onGoToNutrients,
  });

  bool _isTakenToday(SupplementSchedule s) => supplementTakenToday
      .any((t) => t.scheduleId == s.id || t.name == s.name);

  /// Weight card: compares the local tracker_page.dart weight (folded
  /// into today's snapshot, if present) against the separate
  /// extended_tracker_page.dart weight system by date, and shows
  /// whichever is more recent. Flags with a warning icon if both exist
  /// and disagree — surfaces the duplication rather than resolving it.
  Widget _buildWeightCard() {
    final trackerPageKg = todaySnapshot?.weightKg;
    final trackerPageDate = todaySnapshot?.snapshotDate;

    double? displayKg;
    String? sourceLabel;
    bool conflict = false;

    if (trackerPageKg != null && extWeightLatestKg != null) {
      displayKg = trackerPageKg;
      sourceLabel = 'Tracker';
      if ((trackerPageKg - extWeightLatestKg!).abs() > 0.5) {
        conflict = true;
      }
    } else if (trackerPageKg != null) {
      displayKg = trackerPageKg;
      sourceLabel = 'Tracker';
    } else if (extWeightLatestKg != null) {
      displayKg = extWeightLatestKg;
      sourceLabel = 'Extended';
    }

    return _TrackerSummaryCard(
      icon: Icons.monitor_weight_rounded,
      color: Colors.blue.shade700,
      title: 'Weight',
      value: displayKg != null
          ? '${(displayKg * 2.20462).toStringAsFixed(1)} lbs'
          : '—',
      subtitle: displayKg == null
          ? 'Not logged'
          : conflict
              ? '⚠ $sourceLabel system · two systems differ'
              : '$sourceLabel system'
                  '${trackerPageDate != null ? ' · today' : extWeightLatestDate != null ? ' · $extWeightLatestDate' : ''}',
      subtitleColor: conflict ? Colors.orange.shade800 : null,
    );
  }

  Widget _buildMealsCard() {
    final score = todaySnapshot?.dailyScore;
    return _TrackerSummaryCard(
      icon: Icons.restaurant_rounded,
      color: Colors.orange.shade700,
      title: 'Nutrition',
      value: score != null ? '$score pts' : '—',
      subtitle: score != null ? "Today's score" : 'No meals logged today',
    );
  }

  Widget _buildSupplementsCard() {
    if (supplementSchedules.isEmpty) {
      return _TrackerSummaryCard(
        icon: Icons.medication_rounded,
        color: Colors.teal.shade700,
        title: 'Supplements',
        value: '—',
        subtitle: 'No schedule set up',
      );
    }
    final takenCount =
        supplementSchedules.where(_isTakenToday).length;
    return _TrackerSummaryCard(
      icon: Icons.medication_rounded,
      color: Colors.teal.shade700,
      title: 'Supplements',
      value: '$takenCount/${supplementSchedules.length}',
      subtitle: 'Taken today (scheduled)',
    );
  }

  Widget _buildHydrationCard() {
    return _TrackerSummaryCard(
      icon: Icons.water_drop_rounded,
      color: Colors.lightBlue.shade700,
      title: 'Hydration',
      value: todayHydrationCups != null
          ? '${todayHydrationCups!.toStringAsFixed(1)} cups'
          : '0 cups',
      subtitle: 'Logged today',
    );
  }

  Widget _buildSymptomsCard() {
    return _TrackerSummaryCard(
      icon: Icons.sick_rounded,
      color: todaySymptomCount > 0 ? Colors.red.shade600 : Colors.green.shade600,
      title: 'Symptoms',
      value: '$todaySymptomCount',
      subtitle: todaySymptomCount > 0 ? 'Logged today' : 'None today',
    );
  }

  Widget _buildMealPlanCard() {
    return _TrackerSummaryCard(
      icon: Icons.event_note_rounded,
      color: Colors.purple.shade700,
      title: 'Meal Plan',
      value: '$todayPlannedMealCount today',
      subtitle: '$weekPlannedMealCount planned this week',
    );
  }

  List<String> _buildInsights() {
    // Simple, rule-based pattern checks over data already loaded —
    // not AI/ML. Flagged as such rather than oversold as "smart" in
    // any predictive sense.
    final insights = <String>[];

    final recentWithProtein =
        snapshots.where((s) => s.proteinG != null).toList();
    if (recentWithProtein.isNotEmpty) {
      final avgProtein = recentWithProtein
              .map((s) => s.proteinG!)
              .reduce((a, b) => a + b) /
          recentWithProtein.length;
      if (avgProtein < 42) {
        insights.add(
            'Protein has averaged ${avgProtein.toStringAsFixed(0)}g/day over the last $rangeDays days — below the 60g target.');
      }
    }

    final recentWithSodium =
        snapshots.where((s) => s.sodiumMg != null).toList();
    if (recentWithSodium.isNotEmpty) {
      final avgSodium = recentWithSodium
              .map((s) => s.sodiumMg!)
              .reduce((a, b) => a + b) /
          recentWithSodium.length;
      if (avgSodium > 1800) {
        insights.add(
            'Sodium has averaged ${avgSodium.toStringAsFixed(0)}mg/day — above the 1500mg target.');
      }
    }

    final weighted = snapshots.where((s) => s.weightKg != null).toList();
    if (weighted.length >= 2) {
      final change = weighted.last.weightKg! - weighted.first.weightKg!;
      if (change.abs() >= 0.5) {
        final lbs = (change.abs() * 2.20462).toStringAsFixed(1);
        insights.add(change < 0
            ? 'Weight is down $lbs lbs over the last $rangeDays days (Tracker system).'
            : 'Weight is up $lbs lbs over the last $rangeDays days (Tracker system).');
      }
    }

    if ((todayHydrationCups ?? 0) < 4) {
      insights.add('Hydration is under 4 cups so far today.');
    }

    if (todayPlannedMealCount == 0) {
      insights.add('No meals planned for today yet — check the Meal Planner.');
    }

    final last7Symptoms = symptoms
        .where((s) =>
            s.loggedAt.isAfter(DateTime.now().subtract(const Duration(days: 7))))
        .length;
    if (last7Symptoms >= 3) {
      insights.add(
          '$last7Symptoms symptoms logged in the last 7 days — consider discussing patterns with your care team.');
    }

    if (insights.isEmpty) {
      insights.add('Everything looks on track — keep it up!');
    }
    return insights;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Last $rangeDays days',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          const Text('At a Glance',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildWeightCard(),
                _buildMealsCard(),
                _buildSupplementsCard(),
                _buildHydrationCard(),
                _buildSymptomsCard(),
                _buildMealPlanCard(),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _MealPlanSummaryCard(
            todayCount: todayPlannedMealCount,
            weekCount: weekPlannedMealCount,
          ),
          const SizedBox(height: 20),
          _InsightsCard(insights: _buildInsights()),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: onGoToNutrients,
            icon: const Icon(Icons.bar_chart_rounded),
            label: const Text('View Full Nutrient Trends'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kDNavy,
              side: const BorderSide(color: _kDNavy),
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackerSummaryCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String subtitle;
  final Color? subtitleColor;

  const _TrackerSummaryCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.subtitle,
    this.subtitleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE3EE)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          Text(subtitle,
              style: TextStyle(
                  fontSize: 10,
                  color: subtitleColor ?? Colors.grey.shade500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _MealPlanSummaryCard extends StatelessWidget {
  final int todayCount;
  final int weekCount;

  const _MealPlanSummaryCard({
    required this.todayCount,
    required this.weekCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE3EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_note_rounded, color: Colors.purple.shade700),
              const SizedBox(width: 8),
              const Text('Meal Plan Summary',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Text('$todayCount',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple.shade700)),
                    Text('Planned today',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Container(width: 1, height: 36, color: Colors.grey.shade200),
              Expanded(
                child: Column(
                  children: [
                    Text('$weekCount',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple.shade700)),
                    Text('Planned this week',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
          if (todayCount == 0) ...[
            const SizedBox(height: 10),
            Text(
              'Nothing planned for today yet — visit the Meal Planner to add meals.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }
}

class _InsightsCard extends StatelessWidget {
  final List<String> insights;

  const _InsightsCard({required this.insights});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE3EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, color: _kDGold),
              const SizedBox(width: 8),
              const Text('Insights',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Pattern-based observations from your logged data — not medical advice.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 12),
          ...insights.map((text) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(Icons.circle,
                          size: 6, color: Colors.grey.shade400),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(text,
                            style: const TextStyle(fontSize: 13, height: 1.4))),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ============================================================
// TAB 1 — NUTRIENT TRENDS
// ============================================================

class _NutrientTab extends StatefulWidget {
  final List<BariNutrientSnapshot> snapshots;
  const _NutrientTab({required this.snapshots});

  @override
  State<_NutrientTab> createState() => _NutrientTabState();
}

class _NutrientTabState extends State<_NutrientTab> {
  String _selected = 'protein_g';

  final Map<String, _MetricMeta> _metrics = {
    'protein_g': _MetricMeta('Protein', 'g', Colors.blue, 60),
    'sodium_mg': _MetricMeta('Sodium', 'mg', Colors.red, 1500),
    'sugar_g': _MetricMeta('Sugar', 'g', Colors.orange, 25),
    'fat_g': _MetricMeta('Fat', 'g', Colors.purple, 45),
    'fiber_g': _MetricMeta('Fiber', 'g', Colors.teal, 20),
    'water_cups': _MetricMeta('Water', 'cups', Colors.lightBlue, 8),
    'daily_score': _MetricMeta('Daily Score', 'pts', Colors.green, 80),
  };

  List<double?> _valuesFor(String key) {
    return widget.snapshots.map((s) {
      switch (key) {
        case 'protein_g': return s.proteinG;
        case 'sodium_mg': return s.sodiumMg;
        case 'sugar_g': return s.sugarG;
        case 'fat_g': return s.fatG;
        case 'fiber_g': return s.fiberG;
        case 'water_cups': return s.waterCups;
        case 'daily_score': return s.dailyScore?.toDouble();
        default: return null;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.snapshots.isEmpty) {
      return const Center(
          child: Text(
        'No data yet — keep logging meals in the Tracker!',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey),
      ));
    }

    final meta = _metrics[_selected]!;
    final values = _valuesFor(_selected);
    final nonNull = values.whereType<double>().toList();
    final avg = nonNull.isEmpty
        ? 0.0
        : nonNull.reduce((a, b) => a + b) / nonNull.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _metrics.entries.map((entry) {
                final sel = _selected == entry.key;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.value.label),
                    selected: sel,
                    selectedColor: entry.value.color.withOpacity(0.2),
                    side: BorderSide(
                        color: sel
                            ? entry.value.color
                            : Colors.grey.shade300),
                    onSelected: (_) =>
                        setState(() => _selected = entry.key),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _StatChip(
                label: '7-day avg',
                value: '${avg.toStringAsFixed(1)} ${meta.unit}',
                color: meta.color,
              ),
              const SizedBox(width: 12),
              _StatChip(
                label: 'Target',
                value: '${meta.target} ${meta.unit}',
                color: Colors.grey,
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Recent trend',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 10),
          _SimpleBarChart(
            values: values,
            labels: widget.snapshots
                .map((s) =>
                    '${s.snapshotDate.month}/${s.snapshotDate.day}')
                .toList(),
            color: meta.color,
            target: meta.target,
          ),
        ],
      ),
    );
  }
}

class _MetricMeta {
  final String label;
  final String unit;
  final Color color;
  final double target;
  _MetricMeta(this.label, this.unit, this.color, this.target);
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE3EE)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16, color: color)),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _SimpleBarChart extends StatelessWidget {
  final List<double?> values;
  final List<String> labels;
  final Color color;
  final double target;

  const _SimpleBarChart({
    required this.values,
    required this.labels,
    required this.color,
    required this.target,
  });

  @override
  Widget build(BuildContext context) {
    final nonNull = values.whereType<double>().toList();
    if (nonNull.isEmpty) {
      return const SizedBox(
          height: 120,
          child: Center(
              child: Text('Not enough data',
                  style: TextStyle(color: Colors.grey))));
    }

    final maxVal = nonNull.reduce((a, b) => a > b ? a : b);
    final chartMax =
        [maxVal, target].reduce((a, b) => a > b ? a : b) * 1.2;

    final displayValues =
        values.length > 10 ? values.sublist(values.length - 10) : values;
    final displayLabels =
        labels.length > 10 ? labels.sublist(labels.length - 10) : labels;

    return SizedBox(
      height: 180,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(displayValues.length, (i) {
          final val = displayValues[i];
          final barHeight = val != null
              ? (val / chartMax * 140).clamp(4.0, 140.0)
              : 4.0;
          final isOver = target > 60
              ? val != null && val > target
              : val != null && val < target * 0.5;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (val != null)
                    Text(
                      val >= 1000
                          ? '${(val / 1000).toStringAsFixed(1)}k'
                          : val.toStringAsFixed(0),
                      style: TextStyle(
                          fontSize: 9,
                          color: isOver ? Colors.red : Colors.grey),
                    ),
                  const SizedBox(height: 2),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: val == null
                          ? Colors.grey.shade200
                          : isOver
                              ? Colors.red.shade300
                              : color.withOpacity(0.8),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    displayLabels[i],
                    style: const TextStyle(fontSize: 9, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ============================================================
// TAB 2 — SYMPTOM TRENDS
// ============================================================

class _SymptomTab extends StatelessWidget {
  final List<SymptomEntry> symptoms;
  const _SymptomTab({required this.symptoms});

  @override
  Widget build(BuildContext context) {
    if (symptoms.isEmpty) {
      return const Center(
          child: Text(
        'No symptoms logged yet.\nUse the Symptom Log screen to track how you feel.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey),
      ));
    }

    final byType = <SymptomType, List<SymptomEntry>>{};
    for (final e in symptoms) {
      byType.putIfAbsent(e.symptomType, () => []).add(e);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${symptoms.length} entries in the selected range',
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 16),
          ...byType.entries.map((entry) {
            final type = entry.key;
            final entries = entry.value
              ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
            final avgSeverity =
                entries.map((e) => e.severity).reduce((a, b) => a + b) /
                    entries.length;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(type.emoji,
                            style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 8),
                        Text(type.displayName,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _severityColor(avgSeverity.round())
                                .withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Avg ${avgSeverity.toStringAsFixed(1)}/5',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _severityColor(avgSeverity.round()),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${entries.length} log${entries.length == 1 ? "" : "s"} in selected range',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Row(
                      children: entries.take(10).map((e) {
                        return Expanded(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 1),
                            child: Tooltip(
                              message:
                                  '${e.loggedAt.month}/${e.loggedAt.day}: ${e.severity}/5',
                              child: Container(
                                height: 8.0 + e.severity * 4,
                                decoration: BoxDecoration(
                                  color: _severityColor(e.severity),
                                  borderRadius: BorderRadius.circular(3),
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
            );
          }),
        ],
      ),
    );
  }

  Color _severityColor(int s) {
    if (s <= 2) return Colors.green;
    if (s == 3) return Colors.orange;
    return Colors.red;
  }
}

// ============================================================
// TAB 3 — WEEKLY GOALS
// ============================================================

class _GoalsTab extends StatelessWidget {
  final TextEditingController proteinCtrl;
  final TextEditingController sodiumCtrl;
  final TextEditingController sugarCtrl;
  final TextEditingController fatCtrl;
  final TextEditingController fiberCtrl;
  final TextEditingController waterCtrl;
  final bool saving;
  final VoidCallback onSave;
  final List<BariNutrientSnapshot> snapshots;
  final BariWeeklyGoal? weekGoal;

  const _GoalsTab({
    required this.proteinCtrl,
    required this.sodiumCtrl,
    required this.sugarCtrl,
    required this.fatCtrl,
    required this.fiberCtrl,
    required this.waterCtrl,
    required this.saving,
    required this.onSave,
    required this.snapshots,
    required this.weekGoal,
  });

  double _weekAvg(double? Function(BariNutrientSnapshot) getter) {
    final lastWeek = snapshots.where((s) => s.snapshotDate
        .isAfter(DateTime.now().subtract(const Duration(days: 7))));
    final vals = lastWeek.map(getter).whereType<double>().toList();
    if (vals.isEmpty) return 0;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  @override
  Widget build(BuildContext context) {
    final goalRows = [
      _GoalRow(
          label: 'Protein',
          unit: 'g/day',
          ctrl: proteinCtrl,
          weekAvg: _weekAvg((s) => s.proteinG),
          higherIsBetter: true),
      _GoalRow(
          label: 'Sodium',
          unit: 'mg/day',
          ctrl: sodiumCtrl,
          weekAvg: _weekAvg((s) => s.sodiumMg),
          higherIsBetter: false),
      _GoalRow(
          label: 'Sugar',
          unit: 'g/day',
          ctrl: sugarCtrl,
          weekAvg: _weekAvg((s) => s.sugarG),
          higherIsBetter: false),
      _GoalRow(
          label: 'Fat',
          unit: 'g/day',
          ctrl: fatCtrl,
          weekAvg: _weekAvg((s) => s.fatG),
          higherIsBetter: false),
      _GoalRow(
          label: 'Fiber',
          unit: 'g/day',
          ctrl: fiberCtrl,
          weekAvg: _weekAvg((s) => s.fiberG),
          higherIsBetter: true),
      _GoalRow(
          label: 'Water',
          unit: 'cups/day',
          ctrl: waterCtrl,
          weekAvg: _weekAvg((s) => s.waterCups),
          higherIsBetter: true),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_kDNavy, _kDNavyLight],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              border: Border.all(color: _kDGold.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.flag_rounded, color: _kDGold),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      weekGoal != null
                          ? 'Goals set for this week. Update anytime.'
                          : 'Set your bariatric nutrition goals for the week.',
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...goalRows.map((row) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: row,
              )),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded),
              label: Text(saving ? 'Saving…' : 'Save Weekly Goals'),
              style: FilledButton.styleFrom(
                  backgroundColor: _kDNavy,
                  side: BorderSide(color: _kDGold.withOpacity(0.4))),
              onPressed: saving ? null : onSave,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalRow extends StatelessWidget {
  final String label;
  final String unit;
  final TextEditingController ctrl;
  final double weekAvg;
  final bool higherIsBetter;

  const _GoalRow({
    required this.label,
    required this.unit,
    required this.ctrl,
    required this.weekAvg,
    required this.higherIsBetter,
  });

  @override
  Widget build(BuildContext context) {
    final goal = double.tryParse(ctrl.text) ?? 0;
    Color indicatorColor = Colors.grey;
    String status = '';

    if (goal > 0 && weekAvg > 0) {
      final ratio = weekAvg / goal;
      if (higherIsBetter) {
        if (ratio >= 0.9) {
          indicatorColor = Colors.green;
          status = '✓ On track';
        } else if (ratio >= 0.6) {
          indicatorColor = Colors.orange;
          status = '⚠ Close';
        } else {
          indicatorColor = Colors.red;
          status = '↑ Need more';
        }
      } else {
        if (ratio <= 1.0) {
          indicatorColor = Colors.green;
          status = '✓ On track';
        } else if (ratio <= 1.2) {
          indicatorColor = Colors.orange;
          status = '⚠ Slightly over';
        } else {
          indicatorColor = Colors.red;
          status = '↓ Over limit';
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('$label ($unit)',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (weekAvg > 0) ...[
              Text('7-day avg: ${weekAvg.toStringAsFixed(1)}',
                  style:
                      const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(width: 8),
              Text(status,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: indicatorColor)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            suffixText: unit,
            isDense: true,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }
}