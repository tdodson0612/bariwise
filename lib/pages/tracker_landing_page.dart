// lib/pages/tracker_landing_page.dart
// Section 12 — Tracker Landing
// Route: '/tracker-landing'
//
// Navigation hub for all tracker surfaces in the app. Per explicit user
// direction (Option 2 — "connect, don't unify"), this page does NOT merge
// or replace any existing tracker system. It links out to:
//   - tracker_page.dart            (Weight / Meals / Nutrition / Supplements)
//   - extended_tracker_page.dart   (Weight / Tolerance / Allergy / GLP-1 / Wellness)
//   - hydration_log_page.dart      (Supabase-backed, pre-existing)
//   - supplement_schedule_page.dart(Supabase-backed, pre-existing)
//   - symptom_log_page.dart        (Supabase-backed, pre-existing)
//   - alcohol_log_page.dart        (Supabase-backed, pre-existing)
//
// Suggestion card scope (flagged assumption, see session log):
// Computed ONLY against the six checklist trackers (Weight, Meals,
// Tolerance, Allergy, GLP-1, Wellness). The four externally-connected
// pages are nav tiles only — no live "today" status is pulled for them.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/tracker_service.dart';
import '../services/auth_service.dart';
import '../services/recent_activity_tracker.dart';
import 'tracker_page.dart';
import 'extended_tracker_page.dart';
import 'hydration_log_page.dart';
import 'supplement_schedule_page.dart';
import 'symptom_log_page.dart';
import 'alcohol_log_page.dart';

// Mirrors the private SharedPreferences keys defined in
// extended_tracker_page.dart. Duplicated intentionally (Dart library
// privacy prevents cross-file reuse of `_`-prefixed consts) rather than
// modifying that file to export them — additive only, per Rule 1.5.
const String _kExtWeight = 'ext_tracker_weight';
const String _kExtTolerance = 'ext_tracker_tolerance';
const String _kExtAllergy = 'ext_tracker_allergy';
const String _kExtGlp1 = 'ext_tracker_glp1';
const String _kExtWellness = 'ext_tracker_wellness';

String _todayKey() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class TrackerLandingPage extends StatefulWidget {
  const TrackerLandingPage({super.key});

  @override
  State<TrackerLandingPage> createState() => _TrackerLandingPageState();
}

class _TrackerLandingPageState extends State<TrackerLandingPage> {
  bool _loading = true;

  // Today-logged status for the six checklist trackers.
  bool _weightLoggedToday = false;
  bool _mealsLoggedToday = false;
  bool _toleranceLoggedToday = false;
  bool _allergyLoggedToday = false;
  bool _glp1LoggedToday = false;
  bool _wellnessLoggedToday = false;

  @override
  void initState() {
    super.initState();
    _loadTodayStatus();
    RecentActivityTracker.recordScreen(
        label: 'Tracker Landing', route: '/tracker-landing');
  }

  Future<void> _loadTodayStatus() async {
    try {
      final today = _todayKey();
      final prefs = await SharedPreferences.getInstance();

      // Weight / Meals live in tracker_page.dart's TrackerEntry via
      // TrackerService (SharedPreferences, per-user key).
      final userId = AuthService.currentUserId;
      bool weightDone = false;
      bool mealsDone = false;
      if (userId != null) {
        final entry = await TrackerService.getEntryForDate(
            userId, DateTime.now().toString().split(' ')[0]);
        weightDone = entry?.weight != null;
        mealsDone = entry != null && entry.meals.isNotEmpty;
      }

      bool checkListHasToday(String? raw) {
        if (raw == null) return false;
        try {
          final list = jsonDecode(raw) as List;
          return list.any((e) => (e as Map)['date'] == today);
        } catch (_) {
          return false;
        }
      }

      final toleranceDone =
          checkListHasToday(prefs.getString(_kExtTolerance));
      final allergyDone = checkListHasToday(prefs.getString(_kExtAllergy));
      final glp1Done = checkListHasToday(prefs.getString(_kExtGlp1));
      final wellnessDone =
          checkListHasToday(prefs.getString(_kExtWellness));
      // Extended-tracker weight entries are keyed the same way as the
      // other ext_tracker_* lists (date field), independent of the
      // tracker_page.dart weight field above — intentionally checked
      // separately since they are two distinct, unreconciled systems.
      final extWeightDone = checkListHasToday(prefs.getString(_kExtWeight));

      if (mounted) {
        setState(() {
          _weightLoggedToday = weightDone || extWeightDone;
          _mealsLoggedToday = mealsDone;
          _toleranceLoggedToday = toleranceDone;
          _allergyLoggedToday = allergyDone;
          _glp1LoggedToday = glp1Done;
          _wellnessLoggedToday = wellnessDone;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_SuggestionItem> get _gaps {
    final items = <_SuggestionItem>[];
    if (!_weightLoggedToday) {
      items.add(_SuggestionItem('Log today\'s weight', Icons.monitor_weight_rounded,
          Colors.blue.shade700, () => _open(const TrackerPage())));
    }
    if (!_mealsLoggedToday) {
      items.add(_SuggestionItem('No meals logged yet today', Icons.restaurant_rounded,
          Colors.orange.shade700, () => _open(const TrackerPage())));
    }
    if (!_toleranceLoggedToday) {
      items.add(_SuggestionItem('Log a food tolerance entry', Icons.restaurant_menu_rounded,
          Colors.green.shade700, () => _open(const ExtendedTrackerPage())));
    }
    if (!_allergyLoggedToday) {
      // Absence of an allergy log is a good thing, not a gap — worded
      // accordingly rather than nagging.
    }
    if (!_glp1LoggedToday) {
      items.add(_SuggestionItem('No GLP-1 dose logged today', Icons.vaccines_rounded,
          Colors.teal.shade700, () => _open(const ExtendedTrackerPage())));
    }
    if (!_wellnessLoggedToday) {
      items.add(_SuggestionItem('30-second wellness check-in — none today',
          Icons.self_improvement_rounded, Colors.purple.shade700,
          () => _open(const ExtendedTrackerPage())));
    }
    return items;
  }

  void _open(Widget page) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => page))
        .then((_) => _loadTodayStatus());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Trackers'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadTodayStatus,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSuggestionCard(),
                  const SizedBox(height: 20),
                  const Text('Your Trackers',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  _TrackerTile(
                    title: 'Weight, Meals & Supplements',
                    subtitle: 'Daily nutrition score, weight, supplement log',
                    icon: Icons.restaurant_rounded,
                    color: Colors.orange.shade700,
                    done: _weightLoggedToday && _mealsLoggedToday,
                    onTap: () => _open(const TrackerPage()),
                  ),
                  _TrackerTile(
                    title: 'Tolerance, Allergy, GLP-1 & Wellness',
                    subtitle: 'Food tolerance, reactions, GLP-1 doses, check-ins',
                    icon: Icons.favorite_rounded,
                    color: Colors.purple.shade700,
                    done: _toleranceLoggedToday &&
                        _glp1LoggedToday &&
                        _wellnessLoggedToday,
                    onTap: () => _open(const ExtendedTrackerPage()),
                  ),
                  const SizedBox(height: 20),
                  const Text('Also Available',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    'Separate tracking systems — not yet unified with the trackers above.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 10),
                  _TrackerTile(
                    title: 'Hydration',
                    subtitle: 'Daily water intake goal',
                    icon: Icons.water_drop_rounded,
                    color: Colors.blue.shade700,
                    onTap: () => _open(const HydrationLogPage()),
                  ),
                  _TrackerTile(
                    title: 'Supplement Schedule',
                    subtitle: 'Scheduled supplements & reminders',
                    icon: Icons.medication_rounded,
                    color: Colors.orange.shade700,
                    onTap: () => _open(const SupplementSchedulePage()),
                  ),
                  _TrackerTile(
                    title: 'Symptom Log',
                    subtitle: 'Fatigue, nausea, dumping syndrome & more',
                    icon: Icons.sick_rounded,
                    color: Colors.green.shade700,
                    onTap: () => _open(const SymptomLogPage()),
                  ),
                  _TrackerTile(
                    title: 'Alcohol Tracker',
                    subtitle: 'Standard drinks, weekly risk, education',
                    icon: Icons.local_bar_rounded,
                    color: Colors.brown.shade700,
                    onTap: () => _open(const AlcoholLogPage()),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildSuggestionCard() {
    final gaps = _gaps;
    if (gaps.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green.shade700, size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('All caught up! Every tracker is logged for today.',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_rounded, color: Colors.orange.shade700, size: 22),
              const SizedBox(width: 8),
              const Text('Suggestions for Today',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          ...gaps.map((g) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: g.onTap,
                  borderRadius: BorderRadius.circular(10),
                  child: Row(
                    children: [
                      Icon(g.icon, size: 18, color: g.color),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(g.label, style: const TextStyle(fontSize: 13))),
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: Colors.grey.shade500),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

class _SuggestionItem {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  _SuggestionItem(this.label, this.icon, this.color, this.onTap);
}

class _TrackerTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool? done;
  final VoidCallback onTap;

  const _TrackerTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.done,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: done == null
            ? const Icon(Icons.chevron_right_rounded)
            : Icon(
                done! ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                color: done! ? Colors.green.shade600 : null,
              ),
      ),
    );
  }
}