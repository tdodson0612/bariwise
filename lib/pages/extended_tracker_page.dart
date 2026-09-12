// lib/pages/extended_tracker_page.dart
// Section 12 — Tracker Workspace
// Route: '/extended-tracker'
//
// Five tabs:
//   1. Weight        — log daily weight, view trend chart
//   2. Food Tolerance — log how well specific foods are tolerated post-op
//   3. Allergy       — track allergic reactions and trigger foods
//   4. GLP-1         — track GLP-1 medication doses and side effects
//   5. Wellness      — daily mood, energy, sleep, and pain check-in
//
// ── Section 12 addition (prior pass this session) ─────────────────────────
// Tracker Detail Screen: tap any history row in any tab to open a modal
// bottom sheet to edit or delete that entry.
//
// ── Section 12 addition (prior pass this session — Weight unification) ────
// Per explicit user decision ("Unify into one system now"), the Weight tab
// no longer keeps its own parallel SharedPreferences list (ext_tracker_weight).
// It is now a view onto TrackerService/TrackerEntry — the same store
// tracker_page.dart's Weight field already used, making it the single
// source of truth rather than building a third system. On first load,
// any existing ext_tracker_weight data is migrated into TrackerService
// entries (without overwriting a day that already has a tracker_page.dart
// weight) and then the old key is cleared, so no user's history is lost.
// TrackerEntry gained an optional `weightNote` field (additive) to
// preserve the note feature this tab already had.
// ⚠️ WEIGHT TAB IS INTENTIONALLY UNTOUCHED IN THIS PASS — do not edit it.
//
// ── Section 12 addition (this session — Tolerance/Allergy/GLP-1/Wellness
//    unification onto Supabase) ─────────────────────────────────────────
// Per explicit user decision ("yes, build it now"), the remaining four
// local-only tabs now read/write through BariFeaturesService against the
// live bari_tolerance_log / bari_allergy_log / bari_glp1_log /
// bari_wellness_log Supabase tables, using the ToleranceEntry / AllergyEntry
// / Glp1Entry / WellnessEntry models from bari_models.dart — matching the
// pattern already used for Weight (TrackerService) and Supplements
// (BariFeaturesService). The private local entry classes (_ToleranceEntry,
// _AllergyEntry, _Glp1Entry, _WellnessEntry) have been removed.
//
// On first load, each tab migrates any existing legacy SharedPreferences
// data (ext_tracker_tolerance / ext_tracker_allergy / ext_tracker_glp1 /
// ext_tracker_wellness) into Supabase — preserving each entry's original
// date via the `loggedAt` (or `checkinDate`) parameter rather than re-dating
// history to "today" — then clears the old key so migration doesn't repeat.
//
// Wellness remains one-check-in-per-day: both the daily check-in form and
// the detail-sheet edit flow call `upsertWellnessCheckin`, which overwrites
// in place for that date (no separate insert-vs-update branching needed).
//
// Entries fetched from Supabase always have a non-null `id`, so `entry.id!`
// is used when calling update/delete from the Tracker Detail Screen.
//
// Known assumption (flagged, not silently smoothed over): since these four
// tabs now require an authenticated Supabase user (BariFeaturesService
// throws/returns empty without one), each tab now shows a "please sign in"
// state if there's no current user — mirroring the Weight tab's existing
// _noUser handling. The pre-Supabase local-storage version had no such
// state because SharedPreferences needs no auth; this is a necessary,
// additive consequence of moving to a per-user backend, not a UI redesign.
//
// All UI elements, color schemes, and interaction patterns are otherwise
// preserved exactly — this is a data-layer swap only.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/recent_activity_tracker.dart';
import '../services/auth_service.dart';
import '../services/tracker_service.dart';
import '../services/bari_features_service.dart';
import '../models/tracker_entry.dart';
import '../models/bari_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SHARED PREF KEYS
// ─────────────────────────────────────────────────────────────────────────────

// ✅ Removed prior session: _kWeight ('ext_tracker_weight') is no longer the
// live store — see file header. The literal key string is still referenced
// once, in _migrateOldWeightData(), purely to read and then clear legacy
// data during the one-time migration.
//
// The four keys below are ALSO no longer the live store as of this session
// (see file header) — they are now referenced only inside each tab's
// one-time migration routine, to read old data and then clear it.
const _kTolerance    = 'ext_tracker_tolerance';
const _kAllergy      = 'ext_tracker_allergy';
const _kGlp1         = 'ext_tracker_glp1';
const _kWellness     = 'ext_tracker_wellness';

String _todayKey() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Formats a DateTime as a 'YYYY-MM-DD' label, matching the display format
/// the old SharedPreferences-backed tabs used for their `date` string field.
String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Wide lower bound used when fetching Supabase log history for these tabs,
/// since BariFeaturesService's get*Log methods require a `from` date and
/// these tabs (unlike Hydration) want full history, not a rolling window.
DateTime _fullHistoryFrom() =>
    DateTime.now().subtract(const Duration(days: 3650));

Future<bool> _confirmDelete(BuildContext context, String label) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete Entry'),
      content: Text('Delete this $label entry? This cannot be undone.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE
// ─────────────────────────────────────────────────────────────────────────────

class ExtendedTrackerPage extends StatefulWidget {
  const ExtendedTrackerPage({super.key});

  @override
  State<ExtendedTrackerPage> createState() => _ExtendedTrackerPageState();
}

class _ExtendedTrackerPageState extends State<ExtendedTrackerPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    RecentActivityTracker.recordScreen(
        label: 'Extended Tracker', route: '/extended-tracker');
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Trackers'),
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.monitor_weight_rounded, size: 18), text: 'Weight'),
            Tab(icon: Icon(Icons.restaurant_rounded, size: 18), text: 'Tolerance'),
            Tab(icon: Icon(Icons.warning_rounded, size: 18), text: 'Allergy'),
            Tab(icon: Icon(Icons.vaccines_rounded, size: 18), text: 'GLP-1'),
            Tab(icon: Icon(Icons.self_improvement_rounded, size: 18), text: 'Wellness'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _WeightTab(),
          _ToleranceTab(),
          _AllergyTab(),
          _Glp1Tab(),
          _WellnessTab(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1 — WEIGHT TRACKER (unified onto TrackerService in a prior pass)
// ⚠️ UNTOUCHED THIS SESSION — do not edit as part of the Tolerance/Allergy/
// GLP-1/Wellness Supabase unification work.
// ─────────────────────────────────────────────────────────────────────────────

class _WeightTab extends StatefulWidget {
  const _WeightTab();

  @override
  State<_WeightTab> createState() => _WeightTabState();
}

class _WeightTabState extends State<_WeightTab> {
  List<TrackerEntry> _entries = []; // only entries where weight != null
  bool _loading = true;
  bool _noUser = false;
  String _unit = 'lbs';
  final _weightCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _saving = false;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  /// One-time migration of legacy ext_tracker_weight local data into the
  /// unified TrackerService store. Skips any date that already has a
  /// tracker_page.dart-originated weight (never overwrites). Clears the
  /// old key once done so this doesn't re-run.
  Future<void> _migrateOldWeightData(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    const legacyKey = 'ext_tracker_weight';
    final raw = prefs.getString(legacyKey);
    if (raw == null) return;

    try {
      final list = jsonDecode(raw) as List;
      for (final j in list) {
        final map = j as Map<String, dynamic>;
        final date = map['date'] as String? ?? '';
        if (date.isEmpty) continue;
        final legacyKg = (map['weightKg'] as num?)?.toDouble();
        if (legacyKg == null) continue;
        final legacyNote = map['note'] as String?;

        final existing = await TrackerService.getEntryForDate(userId, date);
        if (existing != null && existing.weight != null) {
          // Already has a real weight for this day — don't overwrite.
          continue;
        }

        final merged = TrackerEntry(
          date: date,
          meals: existing?.meals ?? [],
          supplements: existing?.supplements ?? [],
          exercise: existing?.exercise,
          waterIntake: existing?.waterIntake,
          weight: legacyKg,
          weightNote: legacyNote,
          dailyScore: existing?.dailyScore ?? 0,
        );
        await TrackerService.saveEntry(userId, merged);
      }
    } catch (_) {
      // Malformed legacy data — nothing safe to migrate, fall through to
      // clearing the key below so it doesn't keep failing on every load.
    }

    await prefs.remove(legacyKey);
  }

  Future<void> _load() async {
    final userId = AuthService.currentUserId;
    _userId = userId;
    if (userId == null) {
      if (mounted) setState(() { _loading = false; _noUser = true; });
      return;
    }

    await _migrateOldWeightData(userId);
    await TrackerService.autoFillMissingWeights(userId);
    final all = await TrackerService.getEntries(userId);
    final withWeight = all.where((e) => e.weight != null).toList();
    // getEntries already sorts descending by date (newest first).

    if (mounted) {
      setState(() {
        _entries = withWeight;
        _loading = false;
      });
    }
  }

  double _displayWeight(TrackerEntry e) =>
      _unit == 'lbs' ? e.weight! / 0.453592 : e.weight!;

  Future<void> _logWeight() async {
    final val = double.tryParse(_weightCtrl.text.trim());
    if (val == null || val <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid weight')),
      );
      return;
    }
    final userId = _userId;
    if (userId == null) return;

    setState(() => _saving = true);
    final kg = _unit == 'lbs' ? val * 0.453592 : val;
    final today = _todayKey();
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();

    final existing = await TrackerService.getEntryForDate(userId, today);
    final entry = TrackerEntry(
      date: today,
      meals: existing?.meals ?? [],
      supplements: existing?.supplements ?? [],
      exercise: existing?.exercise,
      waterIntake: existing?.waterIntake,
      weight: kg,
      weightNote: note,
      dailyScore: existing?.dailyScore ?? 0,
    );
    await TrackerService.saveEntry(userId, entry);
    await _load();

    _weightCtrl.clear();
    _noteCtrl.clear();
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Weight logged: ${val.toStringAsFixed(1)} $_unit'),
        backgroundColor: Colors.blue.shade700,
      ));
    }
  }

  // ── Section 12: Tracker Detail Screen ──────────────────────────────
  Future<void> _showDetail(TrackerEntry entry) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _WeightDetailSheet(
        entry: entry,
        displayWeight: _displayWeight(entry),
        unit: _unit,
      ),
    );
    if (result == null || !mounted) return;
    final userId = _userId;
    if (userId == null) return;

    if (result['delete'] == true) {
      final confirmed = await _confirmDelete(context, 'weight');
      if (!confirmed) return;
      // Explicitly null out weight/weightNote rather than using copyWith
      // (copyWith's `?? this.weight` pattern can't clear a value to null —
      // see the note in tracker_entry.dart). Preserves the rest of that
      // day's data (meals/supplements/exercise/water) intact.
      final existing = await TrackerService.getEntryForDate(userId, entry.date);
      final cleared = TrackerEntry(
        date: entry.date,
        meals: existing?.meals ?? entry.meals,
        supplements: existing?.supplements ?? entry.supplements,
        exercise: existing?.exercise ?? entry.exercise,
        waterIntake: existing?.waterIntake ?? entry.waterIntake,
        weight: null,
        weightNote: null,
        dailyScore: existing?.dailyScore ?? entry.dailyScore,
      );
      await TrackerService.saveEntry(userId, cleared);
    } else {
      final newVal = result['weight'] as double;
      final newUnit = result['unit'] as String;
      final newNote = result['note'] as String?;
      final kg = newUnit == 'lbs' ? newVal * 0.453592 : newVal;
      final existing = await TrackerService.getEntryForDate(userId, entry.date);
      final updated = TrackerEntry(
        date: entry.date,
        meals: existing?.meals ?? entry.meals,
        supplements: existing?.supplements ?? entry.supplements,
        exercise: existing?.exercise ?? entry.exercise,
        waterIntake: existing?.waterIntake ?? entry.waterIntake,
        weight: kg,
        weightNote: newNote,
        dailyScore: existing?.dailyScore ?? entry.dailyScore,
      );
      await TrackerService.saveEntry(userId, updated);
    }
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['delete'] == true ? 'Entry deleted' : 'Entry updated'),
        backgroundColor: Colors.blue.shade700,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_noUser) {
      return Center(
        child: Text('Please sign in to track weight.',
            style: TextStyle(color: Colors.grey.shade600)),
      );
    }

    final last30 = _entries.take(30).toList().reversed.toList();
    double? change;
    if (_entries.length >= 2) {
      change = _displayWeight(_entries[0]) - _displayWeight(_entries[1]);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Log card
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Log Today\'s Weight',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _weightCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}'))],
                          decoration: InputDecoration(
                            hintText: _unit == 'lbs' ? 'e.g. 185.5' : 'e.g. 84.0',
                            suffixText: _unit,
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _UnitToggle(
                        options: const ['lbs', 'kg'],
                        selected: _unit,
                        color: Colors.blue.shade700,
                        onChanged: (v) => setState(() => _unit = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _noteCtrl,
                    decoration: InputDecoration(
                      hintText: 'Note (optional)',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _logWeight,
                      icon: _saving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_rounded),
                      label: Text(_saving ? 'Saving…' : 'Log Weight'),
                      style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Latest + change
          if (_entries.isNotEmpty) ...[
            Row(
              children: [
                _StatCard(
                  label: 'Latest',
                  value: '${_displayWeight(_entries[0]).toStringAsFixed(1)} $_unit',
                  color: Colors.blue.shade700,
                  icon: Icons.monitor_weight_rounded,
                ),
                const SizedBox(width: 10),
                if (change != null)
                  _StatCard(
                    label: 'vs Yesterday',
                    value: '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)} $_unit',
                    color: change <= 0 ? Colors.green.shade700 : Colors.red.shade600,
                    icon: change <= 0 ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Mini chart
          if (last30.length >= 2) ...[
            const Text('Recent Trend',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _MiniLineChart(
              values: last30.map(_displayWeight).toList(),
              color: Colors.blue.shade700,
              unit: _unit,
            ),
            const SizedBox(height: 16),
          ],

          // History
          Row(
            children: [
              const Text('History',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_entries.isNotEmpty)
                Text('Tap to edit', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 8),
          if (_entries.isEmpty)
            Text('No weight logged yet.', style: TextStyle(color: Colors.grey.shade500))
          else
            ..._entries.take(14).map((e) => ListTile(
                  dense: true,
                  onTap: () => _showDetail(e),
                  leading: Icon(Icons.monitor_weight_outlined, color: Colors.blue.shade700, size: 20),
                  title: Text('${_displayWeight(e).toStringAsFixed(1)} $_unit'),
                  subtitle: e.weightNote != null ? Text(e.weightNote!) : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(e.date, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey.shade400),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

class _WeightDetailSheet extends StatefulWidget {
  final TrackerEntry entry;
  final double displayWeight;
  final String unit;

  const _WeightDetailSheet({
    required this.entry,
    required this.displayWeight,
    required this.unit,
  });

  @override
  State<_WeightDetailSheet> createState() => _WeightDetailSheetState();
}

class _WeightDetailSheetState extends State<_WeightDetailSheet> {
  late final TextEditingController _weightCtrl;
  late final TextEditingController _noteCtrl;
  late String _unit;

  @override
  void initState() {
    super.initState();
    _weightCtrl = TextEditingController(text: widget.displayWeight.toStringAsFixed(1));
    _noteCtrl = TextEditingController(text: widget.entry.weightNote ?? '');
    _unit = widget.unit;
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Edit Weight Entry',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(widget.entry.date,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _weightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}'))],
                  decoration: InputDecoration(
                    labelText: 'Weight',
                    suffixText: _unit,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _UnitToggle(
                options: const ['lbs', 'kg'],
                selected: _unit,
                color: Colors.blue.shade700,
                onChanged: (v) => setState(() => _unit = v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            decoration: InputDecoration(
              labelText: 'Note (optional)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text('Delete', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                  onPressed: () => Navigator.pop(context, {'delete': true}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade700),
                  onPressed: () {
                    final val = double.tryParse(_weightCtrl.text.trim());
                    if (val == null || val <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a valid weight')),
                      );
                      return;
                    }
                    Navigator.pop(context, {
                      'delete': false,
                      'weight': val,
                      'unit': _unit,
                      'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 2 — FOOD TOLERANCE TRACKER (unified onto Supabase this session)
// ─────────────────────────────────────────────────────────────────────────────

class _ToleranceTab extends StatefulWidget {
  const _ToleranceTab();

  @override
  State<_ToleranceTab> createState() => _ToleranceTabState();
}

class _ToleranceTabState extends State<_ToleranceTab> {
  List<ToleranceEntry> _entries = [];
  bool _loading = true;
  bool _noUser = false;
  final _foodCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  int _score = 3;
  String? _symptoms;
  bool _saving = false;

  static const List<String> _symptomOptions = [
    'Nausea', 'Dumping syndrome', 'Vomiting', 'Pain', 'Bloating', 'Reflux', 'None'
  ];

  static const _scoreLabels = {1: 'Very Bad', 2: 'Poor', 3: 'Okay', 4: 'Good', 5: 'Excellent'};
  static const _scoreColors = {
    1: Color(0xFFD32F2F), 2: Color(0xFFEF6C00), 3: Color(0xFFF9A825),
    4: Color(0xFF558B2F), 5: Color(0xFF1B5E20)
  };

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _foodCtrl.dispose(); _noteCtrl.dispose(); super.dispose(); }

  /// One-time migration of legacy ext_tracker_tolerance local data into
  /// bari_tolerance_log via BariFeaturesService, preserving each entry's
  /// original date. Clears the old key once done so this doesn't re-run.
  Future<void> _migrateOldToleranceData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kTolerance);
    if (raw == null) return;

    try {
      final list = jsonDecode(raw) as List;
      for (final j in list) {
        final map = j as Map<String, dynamic>;
        final foodName = map['foodName'] as String? ?? '';
        if (foodName.isEmpty) continue;
        final date = map['date'] as String? ?? '';
        final loggedAt = DateTime.tryParse(date) ?? DateTime.now();
        await BariFeaturesService.logTolerance(
          foodName: foodName,
          toleranceScore: map['toleranceScore'] as int? ?? 3,
          symptoms: map['symptoms'] as String?,
          notes: map['note'] as String?,
          loggedAt: loggedAt,
        );
      }
    } catch (_) {
      // Malformed legacy data — nothing safe to migrate, fall through to
      // clearing the key below so it doesn't keep failing on every load.
    }

    await prefs.remove(_kTolerance);
  }

  Future<void> _load() async {
    final userId = AuthService.currentUserId;
    if (userId == null) {
      if (mounted) setState(() { _loading = false; _noUser = true; });
      return;
    }

    await _migrateOldToleranceData();
    final entries = await BariFeaturesService.getToleranceLog(from: _fullHistoryFrom());
    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
  }

  Future<void> _log() async {
    if (_foodCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a food name')));
      return;
    }
    setState(() => _saving = true);
    final foodName = _foodCtrl.text.trim();
    final scoreLabel = _scoreLabels[_score];
    await BariFeaturesService.logTolerance(
      foodName: foodName,
      toleranceScore: _score,
      symptoms: _symptoms,
      notes: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    );
    await _load();

    _foodCtrl.clear(); _noteCtrl.clear();
    if (mounted) {
      setState(() { _score = 3; _symptoms = null; _saving = false; });
      ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Logged: $foodName ($scoreLabel)'), backgroundColor: Colors.green.shade700));
    }
  }

  // ── Section 12: Tracker Detail Screen ──────────────────────────────
  Future<void> _showDetail(ToleranceEntry entry) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ToleranceDetailSheet(entry: entry, symptomOptions: _symptomOptions),
    );
    if (result == null || !mounted) return;

    if (result['delete'] == true) {
      final confirmed = await _confirmDelete(context, 'tolerance');
      if (!confirmed) return;
      await BariFeaturesService.deleteToleranceEntry(entry.id!);
    } else {
      await BariFeaturesService.updateToleranceEntry(
        entry.id!,
        foodName: result['foodName'] as String,
        toleranceScore: result['score'] as int,
        symptoms: result['symptoms'] as String?,
        notes: result['note'] as String?,
      );
    }
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['delete'] == true ? 'Entry deleted' : 'Entry updated'),
        backgroundColor: Colors.green.shade700,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_noUser) {
      return Center(
        child: Text('Please sign in to track food tolerance.',
            style: TextStyle(color: Colors.grey.shade600)),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Log Food Tolerance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(controller: _foodCtrl, textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(hintText: 'Food name (e.g. Scrambled eggs)',
                  isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 12),
              Text('Tolerance: ${_scoreLabels[_score]}',
                style: TextStyle(fontWeight: FontWeight.w600, color: _scoreColors[_score])),
              Slider(value: _score.toDouble(), min: 1, max: 5, divisions: 4,
                activeColor: _scoreColors[_score],
                onChanged: (v) => setState(() => _score = v.round())),
              const SizedBox(height: 8),
              const Text('Symptoms (if any)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: _symptomOptions.map((s) {
                final sel = _symptoms == s;
                return FilterChip(label: Text(s, style: const TextStyle(fontSize: 12)),
                  selected: sel, selectedColor: Colors.orange.shade100,
                  onSelected: (_) => setState(() => _symptoms = sel ? null : s));
              }).toList()),
              const SizedBox(height: 10),
              TextField(controller: _noteCtrl, decoration: InputDecoration(
                hintText: 'Note (optional)', isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: _saving ? null : _log,
                icon: const Icon(Icons.save_rounded), label: const Text('Log Tolerance'),
                style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700))),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          const Text('Recent Logs', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const Spacer(),
          if (_entries.isNotEmpty)
            Text('Tap to edit', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ]),
        const SizedBox(height: 8),
        if (_entries.isEmpty)
          Text('No tolerance logs yet.', style: TextStyle(color: Colors.grey.shade500))
        else
          ..._entries.take(20).map((e) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: ListTile(dense: true,
              onTap: () => _showDetail(e),
              leading: CircleAvatar(radius: 14, backgroundColor: Color(_scoreColors[e.toleranceScore]!.value).withOpacity(0.15),
                child: Text('${e.toleranceScore}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _scoreColors[e.toleranceScore]))),
              title: Text(e.foodName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text([if (e.symptoms != null) e.symptoms!, if (e.notes != null) e.notes!].join(' · '),
                style: const TextStyle(fontSize: 11)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_fmtDate(e.loggedAt), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey.shade400),
              ])),
          )),
      ]),
    );
  }
}

class _ToleranceDetailSheet extends StatefulWidget {
  final ToleranceEntry entry;
  final List<String> symptomOptions;

  const _ToleranceDetailSheet({required this.entry, required this.symptomOptions});

  @override
  State<_ToleranceDetailSheet> createState() => _ToleranceDetailSheetState();
}

class _ToleranceDetailSheetState extends State<_ToleranceDetailSheet> {
  late final TextEditingController _foodCtrl;
  late final TextEditingController _noteCtrl;
  late int _score;
  String? _symptoms;

  static const _scoreLabels = {1: 'Very Bad', 2: 'Poor', 3: 'Okay', 4: 'Good', 5: 'Excellent'};
  static const _scoreColors = {
    1: Color(0xFFD32F2F), 2: Color(0xFFEF6C00), 3: Color(0xFFF9A825),
    4: Color(0xFF558B2F), 5: Color(0xFF1B5E20)
  };

  @override
  void initState() {
    super.initState();
    _foodCtrl = TextEditingController(text: widget.entry.foodName);
    _noteCtrl = TextEditingController(text: widget.entry.notes ?? '');
    _score = widget.entry.toleranceScore;
    _symptoms = widget.entry.symptoms;
  }

  @override
  void dispose() {
    _foodCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Edit Tolerance Entry',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(_fmtDate(widget.entry.loggedAt), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(controller: _foodCtrl, textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: 'Food name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 12),
            Text('Tolerance: ${_scoreLabels[_score]}',
              style: TextStyle(fontWeight: FontWeight.w600, color: _scoreColors[_score])),
            Slider(value: _score.toDouble(), min: 1, max: 5, divisions: 4,
              activeColor: _scoreColors[_score],
              onChanged: (v) => setState(() => _score = v.round())),
            const SizedBox(height: 8),
            const Text('Symptoms (if any)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: widget.symptomOptions.map((s) {
              final sel = _symptoms == s;
              return FilterChip(label: Text(s, style: const TextStyle(fontSize: 12)),
                selected: sel, selectedColor: Colors.orange.shade100,
                onSelected: (_) => setState(() => _symptoms = sel ? null : s));
            }).toList()),
            const SizedBox(height: 10),
            TextField(controller: _noteCtrl, decoration: InputDecoration(
              labelText: 'Note (optional)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('Delete', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                    onPressed: () => Navigator.pop(context, {'delete': true}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Save'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                    onPressed: () {
                      if (_foodCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a food name')),
                        );
                        return;
                      }
                      Navigator.pop(context, {
                        'delete': false,
                        'foodName': _foodCtrl.text.trim(),
                        'score': _score,
                        'symptoms': _symptoms,
                        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 3 — ALLERGY TRACKER (unified onto Supabase this session)
// ─────────────────────────────────────────────────────────────────────────────

class _AllergyTab extends StatefulWidget {
  const _AllergyTab();

  @override
  State<_AllergyTab> createState() => _AllergyTabState();
}

class _AllergyTabState extends State<_AllergyTab> {
  List<AllergyEntry> _entries = [];
  bool _loading = true;
  bool _noUser = false;
  final _foodCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _severity = 'mild';
  final Set<String> _symptoms = {};

  static const _severityColors = {'mild': Color(0xFFF9A825), 'moderate': Color(0xFFEF6C00), 'severe': Color(0xFFD32F2F)};
  static const _symptomOptions = ['Hives', 'Swelling', 'Itching', 'Stomach pain', 'Nausea', 'Vomiting', 'Difficulty breathing', 'Rash'];

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _foodCtrl.dispose(); _noteCtrl.dispose(); super.dispose(); }

  /// One-time migration of legacy ext_tracker_allergy local data into
  /// bari_allergy_log via BariFeaturesService, preserving each entry's
  /// original date. Clears the old key once done so this doesn't re-run.
  Future<void> _migrateOldAllergyData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAllergy);
    if (raw == null) return;

    try {
      final list = jsonDecode(raw) as List;
      for (final j in list) {
        final map = j as Map<String, dynamic>;
        final triggerFood = map['triggerFood'] as String? ?? '';
        if (triggerFood.isEmpty) continue;
        final date = map['date'] as String? ?? '';
        final loggedAt = DateTime.tryParse(date) ?? DateTime.now();
        await BariFeaturesService.logAllergy(
          triggerFood: triggerFood,
          severity: map['severity'] as String? ?? 'mild',
          symptoms: List<String>.from(map['symptoms'] ?? []),
          notes: map['note'] as String?,
          loggedAt: loggedAt,
        );
      }
    } catch (_) {
      // Malformed legacy data — nothing safe to migrate, fall through to
      // clearing the key below so it doesn't keep failing on every load.
    }

    await prefs.remove(_kAllergy);
  }

  Future<void> _load() async {
    final userId = AuthService.currentUserId;
    if (userId == null) {
      if (mounted) setState(() { _loading = false; _noUser = true; });
      return;
    }

    await _migrateOldAllergyData();
    final entries = await BariFeaturesService.getAllergyLog(from: _fullHistoryFrom());
    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
  }

  Future<void> _log() async {
    if (_foodCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter the trigger food')));
      return;
    }
    final triggerFood = _foodCtrl.text.trim();
    await BariFeaturesService.logAllergy(
      triggerFood: triggerFood,
      severity: _severity,
      symptoms: _symptoms.toList(),
      notes: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    );
    await _load();

    _foodCtrl.clear(); _noteCtrl.clear();
    if (mounted) {
      setState(() { _severity = 'mild'; _symptoms.clear(); });
      ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Reaction logged: $triggerFood'), backgroundColor: Colors.orange.shade700));
    }
  }

  // ── Section 12: Tracker Detail Screen ──────────────────────────────
  Future<void> _showDetail(AllergyEntry entry) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AllergyDetailSheet(entry: entry, symptomOptions: _symptomOptions),
    );
    if (result == null || !mounted) return;

    if (result['delete'] == true) {
      final confirmed = await _confirmDelete(context, 'allergy');
      if (!confirmed) return;
      await BariFeaturesService.deleteAllergyEntry(entry.id!);
    } else {
      await BariFeaturesService.updateAllergyEntry(
        entry.id!,
        triggerFood: result['triggerFood'] as String,
        severity: result['severity'] as String,
        symptoms: List<String>.from(result['symptoms'] as List),
        notes: result['note'] as String?,
      );
    }
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['delete'] == true ? 'Entry deleted' : 'Entry updated'),
        backgroundColor: Colors.orange.shade700,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_noUser) {
      return Center(
        child: Text('Please sign in to track allergies.',
            style: TextStyle(color: Colors.grey.shade600)),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 2,
          child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Log Allergic Reaction', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(controller: _foodCtrl, textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(hintText: 'Trigger food or ingredient',
                isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 12),
            const Text('Severity', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            Row(children: ['mild', 'moderate', 'severe'].map((s) {
              final sel = _severity == s;
              final color = _severityColors[s]!;
              return Expanded(child: Padding(padding: const EdgeInsets.only(right: 6), child: GestureDetector(
                onTap: () => setState(() => _severity = s),
                child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(color: sel ? color.withOpacity(0.15) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: sel ? color : Colors.grey.shade300, width: sel ? 2 : 1)),
                  child: Center(child: Text(s[0].toUpperCase() + s.substring(1),
                    style: TextStyle(fontSize: 12, fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                      color: sel ? color : Colors.grey.shade700)))),
              )));
            }).toList()),
            const SizedBox(height: 12),
            const Text('Symptoms', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: _symptomOptions.map((s) {
              final sel = _symptoms.contains(s);
              return FilterChip(label: Text(s, style: const TextStyle(fontSize: 12)),
                selected: sel, selectedColor: Colors.red.shade100,
                onSelected: (_) => setState(() => sel ? _symptoms.remove(s) : _symptoms.add(s)));
            }).toList()),
            const SizedBox(height: 10),
            TextField(controller: _noteCtrl, decoration: InputDecoration(
              hintText: 'Additional notes (optional)', isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200)),
              child: Row(children: [
                Icon(Icons.emergency_rounded, color: Colors.red.shade700, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text('If experiencing severe symptoms, seek immediate medical attention.',
                  style: TextStyle(fontSize: 11, color: Colors.red.shade900)))
              ])),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: _log, icon: const Icon(Icons.save_rounded), label: const Text('Log Reaction'),
              style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700))),
          ])),
        ),
        const SizedBox(height: 16),
        Row(children: [
          const Text('Reaction History', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const Spacer(),
          if (_entries.isNotEmpty)
            Text('Tap to edit', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ]),
        const SizedBox(height: 8),
        if (_entries.isEmpty)
          Text('No reactions logged. Great!', style: TextStyle(color: Colors.grey.shade500))
        else
          ..._entries.take(20).map((e) {
            final color = _severityColors[e.severity] ?? Colors.orange;
            return Card(margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: ListTile(dense: true,
                onTap: () => _showDetail(e),
                leading: Container(width: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
                title: Text(e.triggerFood, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([e.severity.toUpperCase(), ...e.symptoms].join(' · '),
                  style: const TextStyle(fontSize: 11)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_fmtDate(e.loggedAt), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                  Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey.shade400),
                ])));
          }),
      ]),
    );
  }
}

class _AllergyDetailSheet extends StatefulWidget {
  final AllergyEntry entry;
  final List<String> symptomOptions;

  const _AllergyDetailSheet({required this.entry, required this.symptomOptions});

  @override
  State<_AllergyDetailSheet> createState() => _AllergyDetailSheetState();
}

class _AllergyDetailSheetState extends State<_AllergyDetailSheet> {
  late final TextEditingController _foodCtrl;
  late final TextEditingController _noteCtrl;
  late String _severity;
  late final Set<String> _symptoms;

  static const _severityColors = {'mild': Color(0xFFF9A825), 'moderate': Color(0xFFEF6C00), 'severe': Color(0xFFD32F2F)};

  @override
  void initState() {
    super.initState();
    _foodCtrl = TextEditingController(text: widget.entry.triggerFood);
    _noteCtrl = TextEditingController(text: widget.entry.notes ?? '');
    _severity = widget.entry.severity;
    _symptoms = Set<String>.from(widget.entry.symptoms);
  }

  @override
  void dispose() {
    _foodCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Edit Allergy Entry',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(_fmtDate(widget.entry.loggedAt), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(controller: _foodCtrl, textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: 'Trigger food or ingredient',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 12),
            const Text('Severity', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            Row(children: ['mild', 'moderate', 'severe'].map((s) {
              final sel = _severity == s;
              final color = _severityColors[s]!;
              return Expanded(child: Padding(padding: const EdgeInsets.only(right: 6), child: GestureDetector(
                onTap: () => setState(() => _severity = s),
                child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(color: sel ? color.withOpacity(0.15) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: sel ? color : Colors.grey.shade300, width: sel ? 2 : 1)),
                  child: Center(child: Text(s[0].toUpperCase() + s.substring(1),
                    style: TextStyle(fontSize: 12, fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                      color: sel ? color : Colors.grey.shade700)))),
              )));
            }).toList()),
            const SizedBox(height: 12),
            const Text('Symptoms', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: widget.symptomOptions.map((s) {
              final sel = _symptoms.contains(s);
              return FilterChip(label: Text(s, style: const TextStyle(fontSize: 12)),
                selected: sel, selectedColor: Colors.red.shade100,
                onSelected: (_) => setState(() => sel ? _symptoms.remove(s) : _symptoms.add(s)));
            }).toList()),
            const SizedBox(height: 10),
            TextField(controller: _noteCtrl, decoration: InputDecoration(
              labelText: 'Additional notes (optional)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('Delete', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                    onPressed: () => Navigator.pop(context, {'delete': true}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Save'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
                    onPressed: () {
                      if (_foodCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter the trigger food')),
                        );
                        return;
                      }
                      Navigator.pop(context, {
                        'delete': false,
                        'triggerFood': _foodCtrl.text.trim(),
                        'severity': _severity,
                        'symptoms': _symptoms.toList(),
                        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 4 — GLP-1 TRACKER (unified onto Supabase this session)
// ─────────────────────────────────────────────────────────────────────────────

class _Glp1Tab extends StatefulWidget {
  const _Glp1Tab();

  @override
  State<_Glp1Tab> createState() => _Glp1TabState();
}

class _Glp1TabState extends State<_Glp1Tab> {
  List<Glp1Entry> _entries = [];
  bool _loading = true;
  bool _noUser = false;
  String _medication = 'Semaglutide (Ozempic/Wegovy)';
  final _doseCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final Set<String> _sideEffects = {};

  static const _medications = [
    'Semaglutide (Ozempic/Wegovy)', 'Tirzepatide (Mounjaro/Zepbound)',
    'Liraglutide (Saxenda/Victoza)', 'Dulaglutide (Trulicity)',
    'Exenatide (Byetta/Bydureon)', 'Other GLP-1',
  ];

  static const _sideEffectOptions = [
    'Nausea', 'Vomiting', 'Diarrhea', 'Constipation', 'Stomach pain',
    'Fatigue', 'Headache', 'Injection site reaction', 'Loss of appetite', 'None'
  ];

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _doseCtrl.dispose(); _noteCtrl.dispose(); super.dispose(); }

  /// One-time migration of legacy ext_tracker_glp1 local data into
  /// bari_glp1_log via BariFeaturesService, preserving each entry's
  /// original date. Clears the old key once done so this doesn't re-run.
  Future<void> _migrateOldGlp1Data() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kGlp1);
    if (raw == null) return;

    try {
      final list = jsonDecode(raw) as List;
      for (final j in list) {
        final map = j as Map<String, dynamic>;
        final medication = map['medication'] as String? ?? '';
        if (medication.isEmpty) continue;
        final doseMg = (map['doseMg'] as num?)?.toDouble();
        if (doseMg == null) continue;
        final date = map['date'] as String? ?? '';
        final loggedAt = DateTime.tryParse(date) ?? DateTime.now();
        await BariFeaturesService.logGlp1Dose(
          medication: medication,
          doseMg: doseMg,
          sideEffects: List<String>.from(map['sideEffects'] ?? []),
          notes: map['note'] as String?,
          loggedAt: loggedAt,
        );
      }
    } catch (_) {
      // Malformed legacy data — nothing safe to migrate, fall through to
      // clearing the key below so it doesn't keep failing on every load.
    }

    await prefs.remove(_kGlp1);
  }

  Future<void> _load() async {
    final userId = AuthService.currentUserId;
    if (userId == null) {
      if (mounted) setState(() { _loading = false; _noUser = true; });
      return;
    }

    await _migrateOldGlp1Data();
    final entries = await BariFeaturesService.getGlp1Log(from: _fullHistoryFrom());
    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
  }

  Future<void> _log() async {
    final dose = double.tryParse(_doseCtrl.text.trim());
    if (dose == null || dose <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid dose')));
      return;
    }
    final medication = _medication;
    await BariFeaturesService.logGlp1Dose(
      medication: medication,
      doseMg: dose,
      sideEffects: _sideEffects.toList(),
      notes: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    );
    await _load();

    _doseCtrl.clear(); _noteCtrl.clear();
    if (mounted) {
      setState(() => _sideEffects.clear());
      ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Dose logged: ${dose}mg $medication'), backgroundColor: Colors.teal.shade700));
    }
  }

  // ── Section 12: Tracker Detail Screen ──────────────────────────────
  Future<void> _showDetail(Glp1Entry entry) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _Glp1DetailSheet(
        entry: entry,
        medications: _medications,
        sideEffectOptions: _sideEffectOptions,
      ),
    );
    if (result == null || !mounted) return;

    if (result['delete'] == true) {
      final confirmed = await _confirmDelete(context, 'GLP-1 dose');
      if (!confirmed) return;
      await BariFeaturesService.deleteGlp1Entry(entry.id!);
    } else {
      await BariFeaturesService.updateGlp1Entry(
        entry.id!,
        medication: result['medication'] as String,
        doseMg: result['dose'] as double,
        sideEffects: List<String>.from(result['sideEffects'] as List),
        notes: result['note'] as String?,
      );
    }
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['delete'] == true ? 'Entry deleted' : 'Entry updated'),
        backgroundColor: Colors.teal.shade700,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_noUser) {
      return Center(
        child: Text('Please sign in to track GLP-1 doses.',
            style: TextStyle(color: Colors.grey.shade600)),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 2,
          child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Log GLP-1 Dose', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _medication,
              decoration: InputDecoration(labelText: 'Medication',
                isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              items: _medications.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: (v) => setState(() => _medication = v ?? _medication)),
            const SizedBox(height: 10),
            TextField(controller: _doseCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
              decoration: InputDecoration(labelText: 'Dose (mg)', hintText: 'e.g. 0.5',
                isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 12),
            const Text('Side Effects Today', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: _sideEffectOptions.map((s) {
              final sel = _sideEffects.contains(s);
              return FilterChip(label: Text(s, style: const TextStyle(fontSize: 12)),
                selected: sel, selectedColor: Colors.teal.shade100,
                onSelected: (_) => setState(() {
                  if (s == 'None') { _sideEffects.clear(); if (!sel) _sideEffects.add('None'); }
                  else { _sideEffects.remove('None'); sel ? _sideEffects.remove(s) : _sideEffects.add(s); }
                }));
            }).toList()),
            const SizedBox(height: 10),
            TextField(controller: _noteCtrl, decoration: InputDecoration(
              hintText: 'Notes (optional)', isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: _log, icon: const Icon(Icons.vaccines_rounded), label: const Text('Log Dose'),
              style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade700))),
          ])),
        ),
        const SizedBox(height: 16),
        Row(children: [
          const Text('Dose History', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const Spacer(),
          if (_entries.isNotEmpty)
            Text('Tap to edit', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ]),
        const SizedBox(height: 8),
        if (_entries.isEmpty)
          Text('No doses logged yet.', style: TextStyle(color: Colors.grey.shade500))
        else
          ..._entries.take(20).map((e) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: ListTile(dense: true,
              onTap: () => _showDetail(e),
              leading: Icon(Icons.vaccines_rounded, color: Colors.teal.shade700, size: 22),
              title: Text('${e.doseMg}mg · ${e.medication.split(' ').first}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: e.sideEffects.isNotEmpty ? Text(e.sideEffects.join(', '), style: const TextStyle(fontSize: 11)) : null,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_fmtDate(e.loggedAt), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey.shade400),
              ])),
          )),
      ]),
    );
  }
}

class _Glp1DetailSheet extends StatefulWidget {
  final Glp1Entry entry;
  final List<String> medications;
  final List<String> sideEffectOptions;

  const _Glp1DetailSheet({
    required this.entry,
    required this.medications,
    required this.sideEffectOptions,
  });

  @override
  State<_Glp1DetailSheet> createState() => _Glp1DetailSheetState();
}

class _Glp1DetailSheetState extends State<_Glp1DetailSheet> {
  late final TextEditingController _doseCtrl;
  late final TextEditingController _noteCtrl;
  late String _medication;
  late final Set<String> _sideEffects;

  @override
  void initState() {
    super.initState();
    _doseCtrl = TextEditingController(text: widget.entry.doseMg.toString());
    _noteCtrl = TextEditingController(text: widget.entry.notes ?? '');
    _medication = widget.medications.contains(widget.entry.medication)
        ? widget.entry.medication
        : widget.medications.first;
    _sideEffects = Set<String>.from(widget.entry.sideEffects);
  }

  @override
  void dispose() {
    _doseCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Edit GLP-1 Dose',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(_fmtDate(widget.entry.loggedAt), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _medication,
              decoration: InputDecoration(labelText: 'Medication',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              items: widget.medications.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: (v) => setState(() => _medication = v ?? _medication)),
            const SizedBox(height: 12),
            TextField(controller: _doseCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
              decoration: InputDecoration(labelText: 'Dose (mg)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 12),
            const Text('Side Effects', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: widget.sideEffectOptions.map((s) {
              final sel = _sideEffects.contains(s);
              return FilterChip(label: Text(s, style: const TextStyle(fontSize: 12)),
                selected: sel, selectedColor: Colors.teal.shade100,
                onSelected: (_) => setState(() {
                  if (s == 'None') { _sideEffects.clear(); if (!sel) _sideEffects.add('None'); }
                  else { _sideEffects.remove('None'); sel ? _sideEffects.remove(s) : _sideEffects.add(s); }
                }));
            }).toList()),
            const SizedBox(height: 10),
            TextField(controller: _noteCtrl, decoration: InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('Delete', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                    onPressed: () => Navigator.pop(context, {'delete': true}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Save'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade700),
                    onPressed: () {
                      final dose = double.tryParse(_doseCtrl.text.trim());
                      if (dose == null || dose <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a valid dose')),
                        );
                        return;
                      }
                      Navigator.pop(context, {
                        'delete': false,
                        'medication': _medication,
                        'dose': dose,
                        'sideEffects': _sideEffects.toList(),
                        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 5 — WELLNESS CHECK-IN (unified onto Supabase this session)
// ─────────────────────────────────────────────────────────────────────────────

class _WellnessTab extends StatefulWidget {
  const _WellnessTab();

  @override
  State<_WellnessTab> createState() => _WellnessTabState();
}

class _WellnessTabState extends State<_WellnessTab> {
  List<WellnessEntry> _entries = [];
  bool _loading = true;
  bool _noUser = false;
  bool _saving = false;

  int _mood = 3;
  int _energy = 3;
  int _sleep = 7;
  int _pain = 0;
  final _noteCtrl = TextEditingController();

  static const _moodEmojis = {1: '😔', 2: '😕', 3: '😐', 4: '🙂', 5: '😊'};
  static const _energyEmojis = {1: '🪫', 2: '😴', 3: '😌', 4: '⚡', 5: '🔥'};
  static const _painLabels = {0: 'None', 1: 'Very mild', 2: 'Mild', 3: 'Moderate', 4: 'Significant', 5: 'Severe'};

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _noteCtrl.dispose(); super.dispose(); }

  /// One-time migration of legacy ext_tracker_wellness local data into
  /// bari_wellness_log via BariFeaturesService (upserted by date, since
  /// wellness is one-check-in-per-day). Clears the old key once done so
  /// this doesn't re-run.
  Future<void> _migrateOldWellnessData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kWellness);
    if (raw == null) return;

    try {
      final list = jsonDecode(raw) as List;
      for (final j in list) {
        final map = j as Map<String, dynamic>;
        final date = map['date'] as String? ?? '';
        if (date.isEmpty) continue;
        final checkinDate = DateTime.tryParse(date);
        if (checkinDate == null) continue;
        await BariFeaturesService.upsertWellnessCheckin(
          checkinDate: checkinDate,
          mood: map['mood'] as int? ?? 3,
          energy: map['energy'] as int? ?? 3,
          sleepHours: map['sleep'] as int? ?? 7,
          pain: map['pain'] as int? ?? 0,
          notes: map['note'] as String?,
        );
      }
    } catch (_) {
      // Malformed legacy data — nothing safe to migrate, fall through to
      // clearing the key below so it doesn't keep failing on every load.
    }

    await prefs.remove(_kWellness);
  }

  Future<void> _load() async {
    final userId = AuthService.currentUserId;
    if (userId == null) {
      if (mounted) setState(() { _loading = false; _noUser = true; });
      return;
    }

    await _migrateOldWellnessData();
    final entries = await BariFeaturesService.getWellnessLog(from: _fullHistoryFrom());

    // Pre-fill the check-in form with today's entry if it exists.
    final today = _fmtDate(DateTime.now());
    final existing = entries.where((e) => _fmtDate(e.checkinDate) == today).firstOrNull;
    if (existing != null) {
      _mood = existing.mood; _energy = existing.energy;
      _sleep = existing.sleepHours; _pain = existing.pain;
      _noteCtrl.text = existing.notes ?? '';
    }

    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
  }

  Future<void> _checkIn() async {
    setState(() => _saving = true);
    await BariFeaturesService.upsertWellnessCheckin(
      checkinDate: DateTime.now(),
      mood: _mood,
      energy: _energy,
      sleepHours: _sleep,
      pain: _pain,
      notes: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    );
    await _load();
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Wellness check-in saved ✓'), backgroundColor: Colors.purple));
    }
  }

  // ── Section 12: Tracker Detail Screen ──────────────────────────────
  Future<void> _showDetail(WellnessEntry entry) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _WellnessDetailSheet(entry: entry),
    );
    if (result == null || !mounted) return;

    if (result['delete'] == true) {
      final confirmed = await _confirmDelete(context, 'wellness check-in');
      if (!confirmed) return;
      await BariFeaturesService.deleteWellnessEntry(entry.id!);
    } else {
      // Wellness is one-per-day: re-upserting the same checkinDate
      // overwrites in place, so no separate "update" method is needed.
      await BariFeaturesService.upsertWellnessCheckin(
        checkinDate: entry.checkinDate,
        mood: result['mood'] as int,
        energy: result['energy'] as int,
        sleepHours: result['sleep'] as int,
        pain: result['pain'] as int,
        notes: result['note'] as String?,
      );
    }
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['delete'] == true ? 'Entry deleted' : 'Entry updated'),
        backgroundColor: Colors.purple.shade700,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_noUser) {
      return Center(
        child: Text('Please sign in to track wellness check-ins.',
            style: TextStyle(color: Colors.grey.shade600)),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 2,
          child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text("Today's Check-in", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(DateTime.now().toString().split(' ').first,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ]),
            const SizedBox(height: 16),

            // Mood
            _WellnessSlider(label: 'Mood', value: _mood, emojis: _moodEmojis,
              color: Colors.amber.shade700, onChanged: (v) => setState(() => _mood = v)),
            const SizedBox(height: 12),

            // Energy
            _WellnessSlider(label: 'Energy', value: _energy, emojis: _energyEmojis,
              color: Colors.orange.shade700, onChanged: (v) => setState(() => _energy = v)),
            const SizedBox(height: 12),

            // Sleep
            Row(children: [
              Icon(Icons.bedtime_rounded, size: 18, color: Colors.indigo.shade700),
              const SizedBox(width: 6),
              Text('Sleep: ${_sleep}h', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.indigo.shade700)),
            ]),
            Slider(value: _sleep.toDouble(), min: 2, max: 12, divisions: 10,
              activeColor: Colors.indigo.shade700,
              onChanged: (v) => setState(() => _sleep = v.round())),

            const SizedBox(height: 4),

            // Pain
            Row(children: [
              Icon(Icons.healing_rounded, size: 18, color: Colors.red.shade600),
              const SizedBox(width: 6),
              Text('Pain: ${_painLabels[_pain]}',
                style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red.shade600)),
            ]),
            Slider(value: _pain.toDouble(), min: 0, max: 5, divisions: 5,
              activeColor: _pain == 0 ? Colors.green : _pain <= 2 ? Colors.orange : Colors.red,
              onChanged: (v) => setState(() => _pain = v.round())),

            const SizedBox(height: 10),
            TextField(controller: _noteCtrl, maxLines: 2,
              decoration: InputDecoration(hintText: 'How are you feeling today? (optional)',
                isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: _saving ? null : _checkIn,
              icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_rounded),
              label: const Text('Save Check-in'),
              style: FilledButton.styleFrom(backgroundColor: Colors.purple.shade700))),
          ])),
        ),

        const SizedBox(height: 16),
        Row(children: [
          const Text('Recent Check-ins', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const Spacer(),
          if (_entries.isNotEmpty)
            Text('Tap to edit', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ]),
        const SizedBox(height: 8),
        if (_entries.isEmpty)
          Text('No check-ins yet.', style: TextStyle(color: Colors.grey.shade500))
        else
          ..._entries.take(14).map((e) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: ListTile(dense: true,
              onTap: () => _showDetail(e),
              leading: Text(_moodEmojis[e.mood] ?? '😐', style: const TextStyle(fontSize: 22)),
              title: Row(children: [
                Text('${_energyEmojis[e.energy]} ', style: const TextStyle(fontSize: 14)),
                Text('${e.sleepHours}h sleep', style: const TextStyle(fontSize: 13)),
                if (e.pain > 0) ...[
                  const SizedBox(width: 8),
                  Text('Pain: ${_painLabels[e.pain]}',
                    style: TextStyle(fontSize: 12, color: Colors.red.shade600))
                ],
              ]),
              subtitle: e.notes != null ? Text(e.notes!, style: const TextStyle(fontSize: 11)) : null,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_fmtDate(e.checkinDate), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey.shade400),
              ])),
          )),
      ]),
    );
  }
}

class _WellnessDetailSheet extends StatefulWidget {
  final WellnessEntry entry;

  const _WellnessDetailSheet({required this.entry});

  @override
  State<_WellnessDetailSheet> createState() => _WellnessDetailSheetState();
}

class _WellnessDetailSheetState extends State<_WellnessDetailSheet> {
  late int _mood;
  late int _energy;
  late int _sleep;
  late int _pain;
  late final TextEditingController _noteCtrl;

  static const _moodEmojis = {1: '😔', 2: '😕', 3: '😐', 4: '🙂', 5: '😊'};
  static const _energyEmojis = {1: '🪫', 2: '😴', 3: '😌', 4: '⚡', 5: '🔥'};
  static const _painLabels = {0: 'None', 1: 'Very mild', 2: 'Mild', 3: 'Moderate', 4: 'Significant', 5: 'Severe'};

  @override
  void initState() {
    super.initState();
    _mood = widget.entry.mood;
    _energy = widget.entry.energy;
    _sleep = widget.entry.sleepHours;
    _pain = widget.entry.pain;
    _noteCtrl = TextEditingController(text: widget.entry.notes ?? '');
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Edit Check-in',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(_fmtDate(widget.entry.checkinDate), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 16),
            _WellnessSlider(label: 'Mood', value: _mood, emojis: _moodEmojis,
              color: Colors.amber.shade700, onChanged: (v) => setState(() => _mood = v)),
            const SizedBox(height: 12),
            _WellnessSlider(label: 'Energy', value: _energy, emojis: _energyEmojis,
              color: Colors.orange.shade700, onChanged: (v) => setState(() => _energy = v)),
            const SizedBox(height: 12),
            Row(children: [
              Icon(Icons.bedtime_rounded, size: 18, color: Colors.indigo.shade700),
              const SizedBox(width: 6),
              Text('Sleep: ${_sleep}h', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.indigo.shade700)),
            ]),
            Slider(value: _sleep.toDouble(), min: 2, max: 12, divisions: 10,
              activeColor: Colors.indigo.shade700,
              onChanged: (v) => setState(() => _sleep = v.round())),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.healing_rounded, size: 18, color: Colors.red.shade600),
              const SizedBox(width: 6),
              Text('Pain: ${_painLabels[_pain]}',
                style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red.shade600)),
            ]),
            Slider(value: _pain.toDouble(), min: 0, max: 5, divisions: 5,
              activeColor: _pain == 0 ? Colors.green : _pain <= 2 ? Colors.orange : Colors.red,
              onChanged: (v) => setState(() => _pain = v.round())),
            const SizedBox(height: 10),
            TextField(controller: _noteCtrl, maxLines: 2,
              decoration: InputDecoration(labelText: 'Note (optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('Delete', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                    onPressed: () => Navigator.pop(context, {'delete': true}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Save'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.purple.shade700),
                    onPressed: () {
                      Navigator.pop(context, {
                        'delete': false,
                        'mood': _mood,
                        'energy': _energy,
                        'sleep': _sleep,
                        'pain': _pain,
                        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _WellnessSlider extends StatelessWidget {
  final String label;
  final int value;
  final Map<int, String> emojis;
  final Color color;
  final void Function(int) onChanged;

  const _WellnessSlider({required this.label, required this.value,
      required this.emojis, required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('${emojis[value]} ', style: const TextStyle(fontSize: 18)),
        Text('$label: $value/5',
          style: TextStyle(fontWeight: FontWeight.w600, color: color)),
      ]),
      Slider(value: value.toDouble(), min: 1, max: 5, divisions: 4,
        activeColor: color, onChanged: (v) => onChanged(v.round())),
    ]);
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _StatCard({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25))),
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        FittedBox(child: Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color))),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
    ));
  }
}

class _UnitToggle extends StatelessWidget {
  final List<String> options;
  final String selected;
  final Color color;
  final void Function(String) onChanged;

  const _UnitToggle({required this.options, required this.selected, required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: options.map((o) {
        final sel = selected == o;
        return GestureDetector(
          onTap: () => onChanged(o),
          child: AnimatedContainer(duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? color : Colors.transparent,
              borderRadius: BorderRadius.circular(8)),
            child: Text(o, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: sel ? Colors.white : Colors.grey.shade600))),
        );
      }).toList()),
    );
  }
}

class _MiniLineChart extends StatelessWidget {
  final List<double> values;
  final Color color;
  final String unit;

  const _MiniLineChart({required this.values, required this.color, required this.unit});

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return const SizedBox.shrink();
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final range = (max - min).abs();

    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: values.map((v) {
          final normalized = range == 0 ? 0.5 : (v - min) / range;
          final barH = (normalized * 56).clamp(4.0, 56.0);
          return Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Container(height: barH,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.7),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)))),
            ]),
          ));
        }).toList(),
      ),
    );
  }
}