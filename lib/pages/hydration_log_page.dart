// lib/pages/hydration_log_page.dart
// Log and view daily water intake — critical post-bariatric surgery hydration tracking.
// Bariatric patients must sip fluids constantly; this page enforces the 64oz/8-cup daily goal.
// Route: '/hydration-log'

import 'package:flutter/material.dart';
import '../models/bari_models.dart';
import '../services/bari_features_service.dart';
import '../services/recent_activity_tracker.dart';
import '../config/app_config.dart';

class HydrationLogPage extends StatefulWidget {
  const HydrationLogPage({super.key});

  @override
  State<HydrationLogPage> createState() => _HydrationLogPageState();
}

class _HydrationLogPageState extends State<HydrationLogPage> {
  double _cupsToAdd = 1.0;
  bool _saving = false;
  double _todayTotal = 0;
  List<HydrationEntry> _todayEntries = [];
  bool _loading = true;

  final String _today =
      DateTime.now().toIso8601String().split('T').first;

  // Post-bariatric daily hydration goal: 64oz = 8 cups
  final double _dailyGoal = 8.0;

  @override
  void initState() {
    super.initState();
    _loadToday();
    RecentActivityTracker.recordScreen(label: 'Hydration', route: '/hydration-log');
  }

  Future<void> _loadToday() async {
    try {
      final entries = await BariFeaturesService.getHydrationLog(
        from: DateTime.parse(_today),
        to: DateTime.parse(_today).add(const Duration(days: 1)),
      );

      final sum = entries.fold<double>(0, (s, e) => s + e.cups);

      if (mounted) {
        setState(() {
          _todayEntries = entries;
          _todayTotal = sum;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      AppConfig.debugPrint('Error loading hydration: $e');
    }
  }

  Future<void> _logCups() async {
    setState(() => _saving = true);
    try {
      await BariFeaturesService.logHydration(cups: _cupsToAdd);
      await _loadToday();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '💧 +${_cupsToAdd.toStringAsFixed(1)} cup${_cupsToAdd == 1 ? "" : "s"} logged!'),
            backgroundColor: Colors.blue.shade600,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteEntry(HydrationEntry entry) async {
    if (entry.id == null) return;
    try {
      await BariFeaturesService.deleteHydrationEntry(entry.id!);
      await _loadToday();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_todayTotal / _dailyGoal).clamp(0.0, 1.0);
    final remaining = (_dailyGoal - _todayTotal).clamp(0.0, _dailyGoal);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hydration Log'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- Progress card ----
                  Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_todayTotal.toStringAsFixed(1)} / $_dailyGoal cups',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade800,
                                    ),
                                  ),
                                  Text(
                                    remaining > 0
                                        ? '${remaining.toStringAsFixed(1)} cups to go'
                                        : '🎉 Goal reached!',
                                    style: TextStyle(
                                        color: Colors.blue.shade600),
                                  ),
                                ],
                              ),
                              _WaterBottleWidget(progress: progress),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 10,
                              backgroundColor: Colors.blue.shade100,
                              valueColor: AlwaysStoppedAnimation(
                                  Colors.blue.shade600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ---- Quick-log card ----
                  Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Log Water',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),

                          // Quick-add buttons
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceEvenly,
                            children: [0.5, 1.0, 1.5, 2.0].map((c) {
                              final selected = _cupsToAdd == c;
                              return GestureDetector(
                                onTap: () =>
                                    setState(() => _cupsToAdd = c),
                                child: AnimatedContainer(
                                  duration: const Duration(
                                      milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? Colors.blue.shade600
                                        : Colors.grey.shade100,
                                    borderRadius:
                                        BorderRadius.circular(12),
                                    border: Border.all(
                                      color: selected
                                          ? Colors.blue.shade600
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Text(
                                    '${c == c.roundToDouble() ? c.toInt() : c} cup${c == 1 ? "" : "s"}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),

                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              icon: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white))
                                  : const Icon(Icons.water_drop_rounded),
                              label: Text(_saving
                                  ? 'Saving…'
                                  : 'Log ${_cupsToAdd == _cupsToAdd.roundToDouble() ? _cupsToAdd.toInt() : _cupsToAdd} Cup${_cupsToAdd == 1 ? "" : "s"}'),
                              style: FilledButton.styleFrom(
                                  backgroundColor:
                                      Colors.blue.shade700),
                              onPressed: _saving ? null : _logCups,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ---- Today's entries ----
                  const Text("Today's Log",
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),

                  if (_todayEntries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                          child: Text('Nothing logged yet today.',
                              style:
                                  TextStyle(color: Colors.grey))),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _todayEntries.length,
                      itemBuilder: (ctx, i) {
                        final e = _todayEntries[i];
                        final time =
                            '${e.loggedAt.hour.toString().padLeft(2, "0")}:${e.loggedAt.minute.toString().padLeft(2, "0")}';
                        return ListTile(
                          leading: const Text('💧',
                              style: TextStyle(fontSize: 22)),
                          title: Text(
                              '${e.cups.toStringAsFixed(1)} cup${e.cups == 1 ? "" : "s"}'),
                          subtitle: Text(time,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            onPressed: () => _deleteEntry(e),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }
}

/// Simple animated water-bottle icon showing fill level
class _WaterBottleWidget extends StatelessWidget {
  final double progress;
  const _WaterBottleWidget({required this.progress});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 64,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: Colors.blue.shade300, width: 2),
            ),
          ),
          FractionallySizedBox(
            heightFactor: progress,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue.shade400.withOpacity(0.6),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(6),
                  bottomRight: Radius.circular(6),
                ),
              ),
            ),
          ),
          Center(
            child: Text(
              '${(progress * 100).round()}%',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}