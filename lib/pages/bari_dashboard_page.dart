// lib/pages/bari_dashboard_page.dart
// Weekly progress dashboard showing trends for all bariatric metrics.
// Route: '/bari-dashboard'

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bari_models.dart';
import '../services/bari_features_service.dart';
import '../services/tracker_service.dart';
import '../services/recent_activity_tracker.dart';
import '../config/app_config.dart';

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
    _tabs = TabController(length: 3, vsync: this);
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

  Future<void> _loadData() async {
    try {
      final userId =
          Supabase.instance.client.auth.currentUser?.id ?? '';
      final [supaSnapshots, symptoms, goal] = await Future.wait([
        BariFeaturesService.getDailySnapshots(days: 30),
        BariFeaturesService.getSymptomLog(
            from: DateTime.now().subtract(const Duration(days: 30))),
        BariFeaturesService.getCurrentWeekGoal(),
      ]);

      List<BariNutrientSnapshot> combined =
          supaSnapshots as List<BariNutrientSnapshot>;

      if (combined.length < 7) {
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
              dailyScore: entry.dailyScore,
              weightKg: entry.weight,
              supplementCount: entry.supplements.length,
            ));
          }
        }
        combined.sort((a, b) => a.snapshotDate.compareTo(b.snapshotDate));
      }

      final weekGoal = goal as BariWeeklyGoal?;

      if (mounted) {
        setState(() {
          _snapshots = combined;
          _symptoms = symptoms as List<SymptomEntry>;
          _weekGoal = weekGoal;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bariatric Dashboard'),
        backgroundColor: Colors.orange.shade800,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.bar_chart_rounded), text: 'Nutrients'),
            Tab(icon: Icon(Icons.sick_rounded), text: 'Symptoms'),
            Tab(icon: Icon(Icons.flag_rounded), text: 'Goals'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
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
          const Text('Last 30 days',
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
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
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
          Text('Last 30 days — ${symptoms.length} entries',
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
                      '${entries.length} log${entries.length == 1 ? "" : "s"} in last 30 days',
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
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.flag_rounded, color: Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      weekGoal != null
                          ? 'Goals set for this week. Update anytime.'
                          : 'Set your bariatric nutrition goals for the week.',
                      style: const TextStyle(fontSize: 13),
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
                  backgroundColor: Colors.orange.shade700),
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