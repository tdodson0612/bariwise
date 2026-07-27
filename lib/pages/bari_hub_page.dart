// lib/pages/bari_hub_page.dart
// Central hub for all bariatric health features.
// Route: '/bari-hub'

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/tracker_service.dart';
import '../services/bari_features_service.dart';
import '../services/recent_activity_tracker.dart';
import '../config/app_config.dart';

// ─── BBRS Design Tokens ───────────────────────────────────────────────────────
const _kNavy      = Color(0xFF0A1628);
const _kNavyLight = Color(0xFF1A2E4A);
const _kBg        = Color(0xFFEEF2F7);
const _kGold      = Color(0xFFC9A84C);

class BariHubPage extends StatefulWidget {
  const BariHubPage({super.key});

  @override
  State<BariHubPage> createState() => _BariHubPageState();
}

class _BariHubPageState extends State<BariHubPage> {
  String? _userId;

  int? _weeklyScore;
  double _todayCups = 0;
  int _todaySupplements = 0;
  int _symptomCount7d = 0;
  bool _loading = true;

  static const double _dailyWaterGoal = 8.0;

  @override
  void initState() {
    super.initState();
    _userId = Supabase.instance.client.auth.currentUser?.id;
    _loadSummary();
    RecentActivityTracker.recordScreen(label: 'Bari Hub', route: '/bari-hub');
  }

  Future<void> _loadSummary() async {
    if (_userId == null) return;
    try {
      final today = DateTime.now().toIso8601String().split('T').first;
      final [weekScore, cups, schedules, takenToday, symptoms] =
          await Future.wait([
        TrackerService.getWeeklyScore(_userId!),
        BariFeaturesService.getTodayCups(today),
        BariFeaturesService.getSupplementSchedules(),
        BariFeaturesService.getSupplementTakenLog(
          from: DateTime.parse(today),
          to: DateTime.parse(today).add(const Duration(days: 1)),
        ),
        BariFeaturesService.getSymptomLog(
          from: DateTime.now().subtract(const Duration(days: 7)),
        ),
      ]);

      if (mounted) {
        setState(() {
          _weeklyScore = weekScore as int?;
          _todayCups = cups as double;
          _todaySupplements = (takenToday as List).length;
          _symptomCount7d = (symptoms as List).length;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      AppConfig.debugPrint('Bari hub load error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text('Bariatric Health'),
        backgroundColor: _kNavy,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              setState(() => _loading = true);
              _loadSummary();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadSummary,
        color: _kGold,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_loading)
                const SizedBox(
                    height: 100,
                    child: Center(child: CircularProgressIndicator()))
              else
                _SummaryRow(
                  weeklyScore: _weeklyScore,
                  todayCups: _todayCups,
                  dailyWaterGoal: _dailyWaterGoal,
                  todaySupplements: _todaySupplements,
                  symptomCount7d: _symptomCount7d,
                ),

              const SizedBox(height: 24),

              const Text('Track & Monitor',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              _FeatureGrid(
                features: [
                  _FeatureTile(
                    icon: Icons.water_drop_rounded,
                    color: Colors.blue.shade600,
                    title: 'Hydration Log',
                    subtitle: '${_todayCups.toStringAsFixed(1)} / 8 cups today',
                    route: '/hydration-log',
                  ),
                  _FeatureTile(
                    icon: Icons.medication_rounded,
                    color: Colors.green.shade700,
                    title: 'Supplements',
                    subtitle: '$_todaySupplements taken today',
                    route: '/supplement-schedule',
                  ),
                  _FeatureTile(
                    icon: Icons.sick_rounded,
                    color: Colors.orange.shade700,
                    title: 'Symptom Log',
                    subtitle: '$_symptomCount7d logs this week',
                    route: '/symptom-log',
                  ),
                  _FeatureTile(
                    icon: Icons.bar_chart_rounded,
                    color: Colors.purple.shade600,
                    title: 'Dashboard',
                    subtitle: 'Trends & weekly goals',
                    route: '/bari-dashboard',
                  ),
                ],
              ),

              const SizedBox(height: 24),

              _TipCard(),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------
// Summary row
// ----------------------------------------------------------------

class _SummaryRow extends StatelessWidget {
  final int? weeklyScore;
  final double todayCups;
  final double dailyWaterGoal;
  final int todaySupplements;
  final int symptomCount7d;

  const _SummaryRow({
    required this.weeklyScore,
    required this.todayCups,
    required this.dailyWaterGoal,
    required this.todaySupplements,
    required this.symptomCount7d,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SummaryCard(
          label: 'Weekly Score',
          value: weeklyScore != null ? '$weeklyScore' : '—',
          unit: weeklyScore != null ? '/100' : '',
          color: Colors.orange.shade700,
          icon: Icons.star_rounded,
        ),
        const SizedBox(width: 10),
        _SummaryCard(
          label: "Today's Water",
          value: todayCups.toStringAsFixed(1),
          unit: '/ 8 cups',
          color: Colors.blue.shade600,
          icon: Icons.water_drop_rounded,
        ),
        const SizedBox(width: 10),
        _SummaryCard(
          label: 'Symptoms (7d)',
          value: '$symptomCount7d',
          unit: 'logs',
          color: Colors.orange.shade700,
          icon: Icons.sick_rounded,
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFDDE3EE)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                value,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color),
              ),
            ),
            if (unit.isNotEmpty)
              Text(unit,
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------
// Feature grid
// ----------------------------------------------------------------

class _FeatureTile {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String route;

  _FeatureTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.route,
  });
}

class _FeatureGrid extends StatelessWidget {
  final List<_FeatureTile> features;
  const _FeatureGrid({required this.features});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.4,
      children: features.map((f) {
        return InkWell(
          onTap: () => Navigator.pushNamed(context, f.route),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDDE3EE)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(f.icon, color: f.color, size: 28),
                const SizedBox(height: 8),
                Text(f.title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: f.color)),
                const SizedBox(height: 2),
                Text(f.subtitle,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ----------------------------------------------------------------
// Rotating bariatric health tip
// ----------------------------------------------------------------

class _TipCard extends StatelessWidget {
  static const List<String> _tips = [
    '🥩 High protein intake (60–80g/day) is essential after bariatric surgery.',
    '💧 Sip fluids constantly — dehydration is the #1 post-op complication.',
    '🚫 Avoid drinking liquids 30 minutes before and after meals.',
    '💊 Never skip your supplements — deficiencies develop silently.',
    '🍽️ Eat protein first at every meal before vegetables or carbs.',
    '⚠️ Watch for dumping syndrome — avoid high-sugar foods and drinks.',
    '🏃 Regular exercise accelerates weight loss and preserves muscle.',
    '📊 Track every meal — consistent logging predicts long-term success.',
  ];

  @override
  Widget build(BuildContext context) {
    final idx = DateTime.now().weekday % _tips.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kNavy, _kNavyLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kGold.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: _kNavy.withValues(alpha: 0.3),
              blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          const Text('💡', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bariatric Health Tip',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(_tips[idx],
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}