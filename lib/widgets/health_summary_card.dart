// lib/widgets/health_summary_card.dart
// Compact at-a-glance card shown on HomeScreen between the friends bar
// and the nutrition snapshot. Shows today's bariatric score, water cups
// logged, and current weight streak — the three metrics users most want
// to see without navigating away.
//
// Data comes entirely from local storage (TrackerService + SharedPreferences)
// so this card never blocks on network. Falls back gracefully when no data.
//
// Usage in home_screen.dart _buildInitialView():
//   // After FriendsOnlineBar, before _buildNutritionSnapshot()
//   const HealthSummaryCard(),
//
// iOS 14 Compatible | Production Ready

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/tracker_service.dart';

class HealthSummaryCard extends StatefulWidget {
  const HealthSummaryCard({super.key});

  @override
  State<HealthSummaryCard> createState() => _HealthSummaryCardState();
}

class _HealthSummaryCardState extends State<HealthSummaryCard> {
  int? _todayScore;
  double? _waterCups;
  int? _streak;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = AuthService.currentUserId;
    if (userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final today = DateTime.now().toString().split(' ')[0];
      final entry = await TrackerService.getEntryForDate(userId, today);
      final streak = await TrackerService.getWeightStreak(userId);

      double? cups;
      if (entry?.waterIntake != null && entry!.waterIntake!.isNotEmpty) {
        cups = _parseCups(entry.waterIntake!);
      }

      if (mounted) {
        setState(() {
          _todayScore = entry?.dailyScore;
          _waterCups = cups;
          _streak = streak;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _parseCups(String water) {
    final lower = water.toLowerCase();
    if (lower.contains('oz')) {
      final m = RegExp(r'(\d+)').firstMatch(lower);
      if (m != null) return (int.tryParse(m.group(1)!) ?? 0) / 8.0;
    }
    final m = RegExp(r'(\d+\.?\d*)').firstMatch(lower);
    return double.tryParse(m?.group(1) ?? '') ?? 0;
  }

  /// Maps a 0–100 bariatric daily score to a display color.
  Color _scoreColor(int score) {
    if (score <= 25) return Colors.red.shade700;
    if (score <= 49) return Colors.orange.shade700;
    if (score <= 74) return Colors.yellow.shade800;
    return Colors.green.shade700;
  }

  @override
  Widget build(BuildContext context) {
    // Hide entirely when no data exists yet (first-time user)
    if (!_loading &&
        _todayScore == null &&
        _waterCups == null &&
        (_streak == null || _streak == 0)) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha((0.95 * 255).toInt()),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: _loading
          ? const Center(
              child: SizedBox(
                height: 32,
                width: 32,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Row(
              children: [
                // ── Today's score ────────────────────────────────────
                if (_todayScore != null)
                  _buildMetric(
                    icon: Icons.favorite_rounded,
                    iconColor: _scoreColor(_todayScore!),
                    label: 'Today\'s Score',
                    value: '$_todayScore',
                    unit: '/100',
                    valueColor: _scoreColor(_todayScore!),
                    onTap: () => Navigator.pushNamed(context, '/tracker'),
                  ),

                if (_todayScore != null &&
                    (_waterCups != null || _streak != null))
                  _divider(),

                // ── Water cups ───────────────────────────────────────
                if (_waterCups != null && _waterCups! > 0)
                  _buildMetric(
                    icon: Icons.water_drop_rounded,
                    iconColor: Colors.blue.shade600,
                    label: 'Water',
                    value: _waterCups! % 1 == 0
                        ? _waterCups!.toInt().toString()
                        : _waterCups!.toStringAsFixed(1),
                    unit: 'cups',
                    valueColor: _waterCups! >= 8
                        ? Colors.green.shade600
                        : Colors.blue.shade600,
                    onTap: () =>
                        Navigator.pushNamed(context, '/hydration-log'),
                  ),

                if (_waterCups != null &&
                    _waterCups! > 0 &&
                    _streak != null &&
                    _streak! > 0)
                  _divider(),

                // ── Weight streak ────────────────────────────────────
                if (_streak != null && _streak! > 0)
                  _buildMetric(
                    icon: Icons.local_fire_department_rounded,
                    iconColor: _streak! >= 7
                        ? Colors.orange.shade700
                        : Colors.grey.shade600,
                    label: 'Streak',
                    value: '$_streak',
                    unit: _streak == 1 ? 'day' : 'days',
                    valueColor: _streak! >= 7
                        ? Colors.orange.shade700
                        : Colors.grey.shade700,
                    onTap: () =>
                        Navigator.pushNamed(context, '/bari-dashboard'),
                  ),
              ],
            ),
    );
  }

  Widget _buildMetric({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String unit,
    required Color valueColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(height: 4),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: valueColor,
                    ),
                  ),
                  TextSpan(
                    text: unit,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(
      height: 40,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.grey.shade200,
    );
  }
}