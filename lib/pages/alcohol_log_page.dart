// lib/pages/alcohol_log_page.dart
// Alcohol tracking screen with:
//   • Quick-log presets
//   • Custom drink calculator (volume × ABV = pure alcohol oz)
//   • Today's log
//   • 7-day bar chart with standard-drink overlay
//   • Bariatric alcohol education panel
// Route: '/alcohol-log'

import 'package:flutter/material.dart';
import '../models/alcohol_entry.dart';
import '../services/alcohol_service.dart';
import '../services/recent_activity_tracker.dart';
import '../config/app_config.dart';

class AlcoholLogPage extends StatefulWidget {
  const AlcoholLogPage({super.key});

  @override
  State<AlcoholLogPage> createState() => _AlcoholLogPageState();
}

class _AlcoholLogPageState extends State<AlcoholLogPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  final _nameCtrl = TextEditingController();
  final _volCtrl = TextEditingController();
  final _abvCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _saving = false;
  List<AlcoholEntry> _todayEntries = [];
  bool _loadingToday = true;

  Map<String, double> _weeklyData = {};
  double _weeklyStdDrinks = 0;
  double _weeklyPureOz = 0;
  bool _loadingWeekly = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadToday();
    _loadWeekly();
    RecentActivityTracker.recordScreen(label: 'Alcohol Log', route: '/alcohol-log');
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose();
    _volCtrl.dispose();
    _abvCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadToday() async {
    try {
      final entries = await AlcoholService.getTodayLog();
      if (mounted) setState(() {
        _todayEntries = entries;
        _loadingToday = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingToday = false);
      AppConfig.debugPrint('Alcohol today load error: $e');
    }
  }

  Future<void> _loadWeekly() async {
    try {
      final [data, stdDrinks, pureOz] = await Future.wait([
        AlcoholService.getWeeklyPureAlcoholOz(),
        AlcoholService.getWeeklyStandardDrinks(),
        AlcoholService.getWeeklyTotalOz(),
      ]);
      if (mounted) setState(() {
        _weeklyData = data as Map<String, double>;
        _weeklyStdDrinks = stdDrinks as double;
        _weeklyPureOz = pureOz as double;
        _loadingWeekly = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingWeekly = false);
    }
  }

  Future<void> _logCustomDrink() async {
    final name = _nameCtrl.text.trim();
    final vol = double.tryParse(_volCtrl.text.trim());
    final abv = double.tryParse(_abvCtrl.text.trim());

    if (name.isEmpty || vol == null || vol <= 0 || abv == null || abv < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in drink name, volume, and ABV correctly.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await AlcoholService.logDrink(
        drinkName: name,
        totalVolumeOz: vol,
        abvPercent: abv,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      _nameCtrl.clear();
      _volCtrl.clear();
      _abvCtrl.clear();
      _notesCtrl.clear();
      await Future.wait([_loadToday(), _loadWeekly()]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🍺 Logged! Pure alcohol: '
              '${(vol * abv / 100).toStringAsFixed(2)} oz '
              '(${(vol * abv / 100 / 0.6).toStringAsFixed(1)} std drinks)',
            ),
            backgroundColor: Colors.brown.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logPreset(DrinkPreset preset) async {
    setState(() => _saving = true);
    try {
      await AlcoholService.logDrink(
        drinkName: preset.name,
        totalVolumeOz: preset.volumeOz,
        abvPercent: preset.abvPercent,
      );
      await Future.wait([_loadToday(), _loadWeekly()]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${preset.emoji} ${preset.name} logged — '
              '${preset.pureAlcoholOz.toStringAsFixed(2)} oz pure alcohol',
            ),
            backgroundColor: Colors.brown.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteEntry(AlcoholEntry e) async {
    if (e.id == null) return;
    try {
      await AlcoholService.deleteEntry(e.id!);
      await Future.wait([_loadToday(), _loadWeekly()]);
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $err')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alcohol Tracker'),
        backgroundColor: Colors.brown.shade700,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.add_rounded), text: 'Log'),
            Tab(icon: Icon(Icons.bar_chart_rounded), text: 'Weekly'),
            Tab(icon: Icon(Icons.info_outline_rounded), text: 'Learn'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _LogTab(
            todayEntries: _todayEntries,
            loading: _loadingToday,
            saving: _saving,
            nameCtrl: _nameCtrl,
            volCtrl: _volCtrl,
            abvCtrl: _abvCtrl,
            notesCtrl: _notesCtrl,
            onLogCustom: _logCustomDrink,
            onLogPreset: _logPreset,
            onDelete: _deleteEntry,
          ),
          _WeeklyTab(
            weeklyData: _weeklyData,
            weeklyStdDrinks: _weeklyStdDrinks,
            weeklyPureOz: _weeklyPureOz,
            loading: _loadingWeekly,
          ),
          const _LearnTab(),
        ],
      ),
    );
  }
}

// ============================================================
// TAB 1 — LOG
// ============================================================

class _LogTab extends StatefulWidget {
  final List<AlcoholEntry> todayEntries;
  final bool loading;
  final bool saving;
  final TextEditingController nameCtrl;
  final TextEditingController volCtrl;
  final TextEditingController abvCtrl;
  final TextEditingController notesCtrl;
  final VoidCallback onLogCustom;
  final Future<void> Function(DrinkPreset) onLogPreset;
  final Future<void> Function(AlcoholEntry) onDelete;

  const _LogTab({
    required this.todayEntries,
    required this.loading,
    required this.saving,
    required this.nameCtrl,
    required this.volCtrl,
    required this.abvCtrl,
    required this.notesCtrl,
    required this.onLogCustom,
    required this.onLogPreset,
    required this.onDelete,
  });

  @override
  State<_LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<_LogTab> {
  double get _previewPureOz {
    final vol = double.tryParse(widget.volCtrl.text) ?? 0;
    final abv = double.tryParse(widget.abvCtrl.text) ?? 0;
    return vol * abv / 100;
  }

  double get _previewStdDrinks => _previewPureOz / 0.6;

  double get _todayPureOz =>
      widget.todayEntries.fold(0.0, (s, e) => s + e.pureAlcoholOz);

  double get _todayStdDrinks => _todayPureOz / 0.6;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.loading) _TodaySummaryCard(
            pureOz: _todayPureOz,
            stdDrinks: _todayStdDrinks,
          ),

          const SizedBox(height: 16),

          const Text('Quick Log',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kDrinkPresets.map((preset) {
              return ActionChip(
                avatar: Text(preset.emoji,
                    style: const TextStyle(fontSize: 16)),
                label: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(preset.name,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    Text(
                      '${preset.volumeOz}oz · ${preset.abvPercent}% · '
                      '${preset.pureAlcoholOz.toStringAsFixed(2)}oz pure',
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                onPressed:
                    widget.saving ? null : () => widget.onLogPreset(preset),
                backgroundColor: Colors.brown.shade50,
                side: BorderSide(color: Colors.brown.shade200),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Custom Drink Calculator',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: widget.nameCtrl,
                    decoration: _inputDec('Drink name', 'e.g. Craft Stout'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: widget.volCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: _inputDec('Volume (oz)', 'e.g. 16'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: widget.abvCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: _inputDec('ABV %', 'e.g. 8.5'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),

                  if (_previewPureOz > 0) ...[
                    const SizedBox(height: 12),
                    _CalcPreviewCard(
                      volumeOz: double.tryParse(widget.volCtrl.text) ?? 0,
                      abvPercent: double.tryParse(widget.abvCtrl.text) ?? 0,
                      pureAlcoholOz: _previewPureOz,
                      standardDrinks: _previewStdDrinks,
                    ),
                  ],

                  const SizedBox(height: 10),
                  TextField(
                    controller: widget.notesCtrl,
                    decoration: _inputDec('Notes (optional)', ''),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: widget.saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_rounded),
                      label: Text(
                          widget.saving ? 'Saving…' : 'Log This Drink'),
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.brown.shade700),
                      onPressed: widget.saving ? null : widget.onLogCustom,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          const Text("Today's Log",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          if (widget.loading)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ))
          else if (widget.todayEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('Nothing logged today.',
                    style: TextStyle(color: Colors.grey.shade500)),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.todayEntries.length,
              itemBuilder: (ctx, i) {
                final e = widget.todayEntries[i];
                final time =
                    '${e.loggedAt.hour.toString().padLeft(2, '0')}:'
                    '${e.loggedAt.minute.toString().padLeft(2, '0')}';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                    leading: const Text('🍺',
                        style: TextStyle(fontSize: 22)),
                    title: Text(e.drinkName,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${e.totalVolumeOz}oz · ${e.abvPercent}% ABV · '
                      '${e.pureAlcoholOz.toStringAsFixed(2)}oz pure · '
                      '${e.standardDrinks.toStringAsFixed(1)} std · $time',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red, size: 20),
                      onPressed: () => widget.onDelete(e),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  InputDecoration _inputDec(String label, String hint) => InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );
}

class _TodaySummaryCard extends StatelessWidget {
  final double pureOz;
  final double stdDrinks;

  const _TodaySummaryCard({required this.pureOz, required this.stdDrinks});

  @override
  Widget build(BuildContext context) {
    final risk = AlcoholService.weeklyRiskLevel(stdDrinks * 7);
    final color = Color(risk.colorValue);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text(pureOz == 0 ? '💧' : '🍺',
              style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pureOz == 0
                      ? 'No alcohol today'
                      : '${pureOz.toStringAsFixed(2)} oz pure alcohol today',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15, color: color),
                ),
                if (pureOz > 0)
                  Text(
                    '${stdDrinks.toStringAsFixed(1)} standard drink${stdDrinks == 1 ? '' : 's'}',
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                if (pureOz > 0)
                  Text(
                    '⚠️ Post-op absorption is 2–3× faster than before surgery.',
                    style: TextStyle(
                        fontSize: 11, color: Colors.orange.shade800),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CalcPreviewCard extends StatelessWidget {
  final double volumeOz;
  final double abvPercent;
  final double pureAlcoholOz;
  final double standardDrinks;

  const _CalcPreviewCard({
    required this.volumeOz,
    required this.abvPercent,
    required this.pureAlcoholOz,
    required this.standardDrinks,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calculate_rounded,
                  color: Colors.amber.shade800, size: 18),
              const SizedBox(width: 6),
              Text('Calculation Preview',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
                      fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${volumeOz.toStringAsFixed(1)} oz  ×  '
            '(${abvPercent.toStringAsFixed(1)}% ÷ 100)  =  '
            '${pureAlcoholOz.toStringAsFixed(3)} oz pure alcohol',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            '${pureAlcoholOz.toStringAsFixed(3)} oz ÷ 0.6  =  '
            '${standardDrinks.toStringAsFixed(2)} standard drinks',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            '1 US standard drink = 0.6 oz (14g) pure alcohol',
            style: TextStyle(fontSize: 11, color: Colors.amber.shade800),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// TAB 2 — WEEKLY
// ============================================================

class _WeeklyTab extends StatelessWidget {
  final Map<String, double> weeklyData;
  final double weeklyStdDrinks;
  final double weeklyPureOz;
  final bool loading;

  const _WeeklyTab({
    required this.weeklyData,
    required this.weeklyStdDrinks,
    required this.weeklyPureOz,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());

    final risk = AlcoholService.weeklyRiskLevel(weeklyStdDrinks);
    final riskColor = Color(risk.colorValue);
    final maxVal = weeklyData.values.isEmpty
        ? 1.0
        : weeklyData.values.reduce((a, b) => a > b ? a : b);
    final chartMax = maxVal < 1 ? 1.0 : maxVal * 1.2;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _WeekStat(
                label: 'Pure Alcohol',
                value: '${weeklyPureOz.toStringAsFixed(1)} oz',
                color: riskColor,
              ),
              const SizedBox(width: 10),
              _WeekStat(
                label: 'Std Drinks',
                value: weeklyStdDrinks.toStringAsFixed(1),
                color: riskColor,
              ),
              const SizedBox(width: 10),
              _WeekStat(
                label: 'Risk Level',
                value: '${risk.emoji} ${risk.label.split(' ').first}',
                color: riskColor,
              ),
            ],
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: riskColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: riskColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Text(risk.emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(risk.label,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: riskColor,
                              fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(
                        _riskExplanation(risk),
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          const Text('Last 7 Days (oz pure alcohol)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: weeklyData.entries.map((entry) {
                final val = entry.value;
                final barH = val > 0
                    ? (val / chartMax * 140).clamp(4.0, 140.0)
                    : 4.0;
                final isToday = entry.key == _todayKey();
                final dayLabel = _shortDay(entry.key);

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (val > 0)
                          Text(
                            val.toStringAsFixed(1),
                            style: TextStyle(
                                fontSize: 9,
                                color: val > 0.6
                                    ? Colors.red.shade400
                                    : Colors.green.shade600),
                          ),
                        const SizedBox(height: 2),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          height: barH,
                          decoration: BoxDecoration(
                            color: val == 0
                                ? Colors.grey.shade200
                                : val > 1.2
                                    ? Colors.red.shade400
                                    : Colors.brown.shade400,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4)),
                            border: isToday
                                ? Border.all(
                                    color: Colors.brown.shade700, width: 2)
                                : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dayLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isToday
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color:
                                isToday ? Colors.brown.shade700 : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 20),
          const _GuidelineCard(),
        ],
      ),
    );
  }

  String _riskExplanation(AlcoholRiskLevel r) => switch (r) {
        AlcoholRiskLevel.none =>
          'No alcohol detected this week. Great for your weight loss progress.',
        AlcoholRiskLevel.low =>
          'Within low-risk guidelines. Remember: post-op absorption is significantly faster.',
        AlcoholRiskLevel.moderate =>
          'Above low-risk guidelines. Alcohol stalls weight loss and stresses your healing body.',
        AlcoholRiskLevel.high =>
          'High intake detected. Heavy drinking after bariatric surgery carries serious health risks.',
      };

  static String _todayKey() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String _shortDay(String dateKey) {
    try {
      final d = DateTime.parse(dateKey);
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[d.weekday - 1];
    } catch (_) {
      return '';
    }
  }
}

class _WeekStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _WeekStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14, color: color),
                textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _GuidelineCard extends StatelessWidget {
  const _GuidelineCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rule_rounded, color: Colors.blue.shade700, size: 18),
              const SizedBox(width: 6),
              Text('NIAAA Low-Risk Guidelines',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                      fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          _guidelineRow('Men', '≤4 drinks/day, ≤14 drinks/week'),
          _guidelineRow('Women', '≤3 drinks/day, ≤7 drinks/week'),
          _guidelineRow('1 std drink', '0.6 oz (14g) pure alcohol'),
          const SizedBox(height: 6),
          Text(
            'These guidelines apply to the general population. '
            'After bariatric surgery, your surgeon\'s advice takes priority — '
            'standard drink limits do not account for significantly altered '
            'alcohol absorption post-op.',
            style: TextStyle(fontSize: 11, color: Colors.blue.shade800),
          ),
        ],
      ),
    );
  }

  Widget _guidelineRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 12)),
          ),
          Text(value, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

// ============================================================
// TAB 3 — LEARN
// ============================================================

class _LearnTab extends StatelessWidget {
  const _LearnTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _InfoCard(
          emoji: '⚗️',
          title: 'Alcohol After Bariatric Surgery',
          body:
              'After gastric bypass or sleeve gastrectomy, alcohol no longer '
              'passes through a full stomach before entering your bloodstream. '
              'Without the buffering effect of stomach tissue, alcohol absorbs '
              'almost immediately into your system. Studies show peak blood '
              'alcohol concentration (BAC) can be 2–3× higher than before '
              'surgery — from the exact same amount of alcohol.',
        ),
        _InfoCard(
          emoji: '🔄',
          title: 'Transfer Addiction Risk',
          body:
              'Bariatric surgery removes food as a coping mechanism. Research '
              'shows a meaningful subset of post-op patients develop substance '
              'use disorders — including alcohol — as a form of transfer '
              'addiction. This is not a character flaw; it is a documented '
              'neurological pattern. If you notice alcohol use increasing after '
              'surgery, speak with your bariatric care team promptly.',
        ),
        _InfoCard(
          emoji: '💥',
          title: 'Dumping Syndrome & Alcohol',
          body:
              'Sugary mixers — cocktails, beer, cider, wine coolers — can '
              'trigger dumping syndrome in post-op patients. Rapid gastric '
              'emptying causes sweating, heart palpitations, nausea, and '
              'sudden weakness within 15–30 minutes of eating or drinking. '
              'Alcohol compounds this by accelerating gastric emptying further, '
              'making intoxication faster and more unpredictable.',
        ),
        _InfoCard(
          emoji: '⚖️',
          title: 'Empty Calories & Weight Loss',
          body:
              'Alcohol contains 7 calories per gram — nearly as calorie-dense '
              'as fat — with zero nutritional value. Even moderate drinking '
              'can stall weight loss progress by:\n\n'
              '• Displacing protein and nutrient intake\n'
              '• Lowering inhibition around food choices\n'
              '• Disrupting sleep quality and recovery\n'
              '• Increasing cortisol, which promotes fat storage\n\n'
              'Consistent tracking helps you see the real impact on your goals.',
        ),
        _InfoCard(
          emoji: '🛑',
          title: 'Warning Signs to Watch For',
          body:
              'Log your symptoms alongside alcohol intake. Contact your '
              'bariatric care team if you notice:\n\n'
              '• Getting intoxicated much faster than expected\n'
              '• Severe dumping symptoms after drinks\n'
              '• Hypoglycemia (shakiness, sweating, confusion) after drinking\n'
              '• Increasing cravings for alcohol post-op\n'
              '• Nausea, vomiting, or abdominal pain after drinking\n'
              '• Difficulty controlling how much you drink',
        ),
        _InfoCard(
          emoji: '✅',
          title: 'Practical Harm-Reduction Tips',
          body:
              '• Never drink on an empty pouch — always eat protein first.\n'
              '• Sip extremely slowly — your absorption rate is dramatically faster.\n'
              '• Avoid shots and high-ABV spirits entirely post-op.\n'
              '• Choose low-sugar options to reduce dumping syndrome risk.\n'
              '• Match every alcoholic drink with a full glass of water.\n'
              '• Never drink and drive — your BAC may be far higher than you feel.\n'
              '• Follow your surgeon\'s specific guidance above all else.',
        ),
        _InfoCard(
          emoji: '🧮',
          title: 'Understanding the Calculator',
          body:
              'Pure alcohol (oz) = Total Volume (oz) × ABV% ÷ 100\n\n'
              'Example: A 12 oz beer at 5% ABV contains:\n'
              '12 × 0.05 = 0.6 oz of pure alcohol = 1 standard drink\n\n'
              'Example: A 5 oz glass of 14% wine contains:\n'
              '5 × 0.14 = 0.70 oz pure alcohol = 1.17 standard drinks\n\n'
              'Post-op, even 1 standard drink may produce effects equivalent '
              'to 2–3 drinks in someone without bariatric surgery.',
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String body;

  const _InfoCard(
      {required this.emoji, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(body,
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade800,
                    height: 1.55)),
          ],
        ),
      ),
    );
  }
}