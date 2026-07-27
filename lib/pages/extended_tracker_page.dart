// lib/pages/extended_tracker_page.dart
// Section 11 — Extended Tracker Workspaces
// Route: '/extended-tracker'
//
// Five tabs:
//   1. Weight        — log daily weight, view trend chart
//   2. Food Tolerance — log how well specific foods are tolerated post-op
//   3. Allergy       — track allergic reactions and trigger foods
//   4. GLP-1         — track GLP-1 medication doses and side effects
//   5. Wellness      — daily mood, energy, sleep, and pain check-in
//
// Storage: SharedPreferences (UI/UX-only phase — no Supabase)
//
// ── Section 12 addition (this session) ──────────────────────────────────
// Tracker Detail Screen: tap any history row in any tab to open a modal
// bottom sheet (same pattern as grocery_list.dart / list_generator_page.dart)
// to edit or delete that entry. Additive only — no existing method, field,
// or widget was removed or restructured.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/recent_activity_tracker.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SHARED PREF KEYS
// ─────────────────────────────────────────────────────────────────────────────

const _kWeight       = 'ext_tracker_weight';
const _kTolerance    = 'ext_tracker_tolerance';
const _kAllergy      = 'ext_tracker_allergy';
const _kGlp1         = 'ext_tracker_glp1';
const _kWellness     = 'ext_tracker_wellness';

String _todayKey() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

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
// TAB 1 — WEIGHT TRACKER
// ─────────────────────────────────────────────────────────────────────────────

class _WeightEntry {
  final String date;
  final double weightKg;
  final String? note;

  _WeightEntry({required this.date, required this.weightKg, this.note});

  Map<String, dynamic> toJson() =>
      {'date': date, 'weightKg': weightKg, 'note': note};

  factory _WeightEntry.fromJson(Map<String, dynamic> j) => _WeightEntry(
        date: j['date'] ?? '',
        weightKg: (j['weightKg'] as num).toDouble(),
        note: j['note'],
      );
}

class _WeightTab extends StatefulWidget {
  const _WeightTab();

  @override
  State<_WeightTab> createState() => _WeightTabState();
}

class _WeightTabState extends State<_WeightTab> {
  List<_WeightEntry> _entries = [];
  bool _loading = true;
  String _unit = 'lbs';
  final _weightCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _saving = false;

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

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kWeight);
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      _entries = list.map((j) => _WeightEntry.fromJson(j)).toList();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kWeight, jsonEncode(_entries.map((e) => e.toJson()).toList()));
  }

  Future<void> _logWeight() async {
    final val = double.tryParse(_weightCtrl.text.trim());
    if (val == null || val <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid weight')),
      );
      return;
    }
    setState(() => _saving = true);
    final kg = _unit == 'lbs' ? val * 0.453592 : val;
    final today = _todayKey();
    final existing = _entries.indexWhere((e) => e.date == today);
    final entry = _WeightEntry(
        date: today, weightKg: kg, note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim());

    setState(() {
      if (existing >= 0) {
        _entries[existing] = entry;
      } else {
        _entries.insert(0, entry);
      }
    });
    await _save();
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

  double _displayWeight(_WeightEntry e) =>
      _unit == 'lbs' ? e.weightKg / 0.453592 : e.weightKg;

  // ── Section 12: Tracker Detail Screen ──────────────────────────────
  Future<void> _showDetail(_WeightEntry entry) async {
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

    if (result['delete'] == true) {
      final confirmed = await _confirmDelete(context, 'weight');
      if (!confirmed) return;
      setState(() => _entries.removeWhere((e) => e.date == entry.date));
      await _save();
    } else {
      final newVal = result['weight'] as double;
      final newUnit = result['unit'] as String;
      final newNote = result['note'] as String?;
      final kg = newUnit == 'lbs' ? newVal * 0.453592 : newVal;
      setState(() {
        final idx = _entries.indexWhere((e) => e.date == entry.date);
        if (idx >= 0) {
          _entries[idx] = _WeightEntry(date: entry.date, weightKg: kg, note: newNote);
        }
      });
      await _save();
    }
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
            const Text('Last 30 Days',
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
          ..._entries.take(14).map((e) => ListTile(
                dense: true,
                onTap: () => _showDetail(e),
                leading: Icon(Icons.monitor_weight_outlined, color: Colors.blue.shade700, size: 20),
                title: Text('${_displayWeight(e).toStringAsFixed(1)} $_unit'),
                subtitle: e.note != null ? Text(e.note!) : null,
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
  final _WeightEntry entry;
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
    _noteCtrl = TextEditingController(text: widget.entry.note ?? '');
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
// TAB 2 — FOOD TOLERANCE TRACKER
// ─────────────────────────────────────────────────────────────────────────────

class _ToleranceEntry {
  final String id;
  final String date;
  final String foodName;
  final int toleranceScore; // 1–5
  final String? symptoms;
  final String? note;

  _ToleranceEntry({required this.id, required this.date, required this.foodName,
      required this.toleranceScore, this.symptoms, this.note});

  Map<String, dynamic> toJson() => {'id': id, 'date': date, 'foodName': foodName,
      'toleranceScore': toleranceScore, 'symptoms': symptoms, 'note': note};

  factory _ToleranceEntry.fromJson(Map<String, dynamic> j) => _ToleranceEntry(
        id: j['id'] ?? '', date: j['date'] ?? '', foodName: j['foodName'] ?? '',
        toleranceScore: j['toleranceScore'] ?? 3, symptoms: j['symptoms'], note: j['note']);
}

class _ToleranceTab extends StatefulWidget {
  const _ToleranceTab();

  @override
  State<_ToleranceTab> createState() => _ToleranceTabState();
}

class _ToleranceTabState extends State<_ToleranceTab> {
  List<_ToleranceEntry> _entries = [];
  bool _loading = true;
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

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kTolerance);
    if (raw != null) {
      _entries = (jsonDecode(raw) as List).map((j) => _ToleranceEntry.fromJson(j)).toList();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTolerance, jsonEncode(_entries.map((e) => e.toJson()).toList()));
  }

  Future<void> _log() async {
    if (_foodCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a food name')));
      return;
    }
    setState(() => _saving = true);
    final entry = _ToleranceEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: _todayKey(), foodName: _foodCtrl.text.trim(),
      toleranceScore: _score, symptoms: _symptoms,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    );
    setState(() { _entries.insert(0, entry); _saving = false; });
    await _save();
    _foodCtrl.clear(); _noteCtrl.clear();
    setState(() { _score = 3; _symptoms = null; });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Logged: ${entry.foodName} (${_scoreLabels[_score]})'), backgroundColor: Colors.green.shade700));
    }
  }

  // ── Section 12: Tracker Detail Screen ──────────────────────────────
  Future<void> _showDetail(_ToleranceEntry entry) async {
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
      setState(() => _entries.removeWhere((e) => e.id == entry.id));
    } else {
      setState(() {
        final idx = _entries.indexWhere((e) => e.id == entry.id);
        if (idx >= 0) {
          _entries[idx] = _ToleranceEntry(
            id: entry.id,
            date: entry.date,
            foodName: result['foodName'] as String,
            toleranceScore: result['score'] as int,
            symptoms: result['symptoms'] as String?,
            note: result['note'] as String?,
          );
        }
      });
    }
    await _save();
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
              leading: CircleAvatar(radius: 14, backgroundColor: Color(_scoreColors[e.toleranceScore]!.toARGB32()).withValues(alpha: 0.15),
                child: Text('${e.toleranceScore}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _scoreColors[e.toleranceScore]))),
              title: Text(e.foodName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text([if (e.symptoms != null) e.symptoms!, if (e.note != null) e.note!].join(' · '),
                style: const TextStyle(fontSize: 11)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(e.date, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey.shade400),
              ])),
          )),
      ]),
    );
  }
}

class _ToleranceDetailSheet extends StatefulWidget {
  final _ToleranceEntry entry;
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
    _noteCtrl = TextEditingController(text: widget.entry.note ?? '');
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
                Text(widget.entry.date, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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
// TAB 3 — ALLERGY TRACKER
// ─────────────────────────────────────────────────────────────────────────────

class _AllergyEntry {
  final String id;
  final String date;
  final String triggerFood;
  final String severity; // mild, moderate, severe
  final List<String> symptoms;
  final String? note;

  _AllergyEntry({required this.id, required this.date, required this.triggerFood,
      required this.severity, required this.symptoms, this.note});

  Map<String, dynamic> toJson() => {'id': id, 'date': date, 'triggerFood': triggerFood,
      'severity': severity, 'symptoms': symptoms, 'note': note};

  factory _AllergyEntry.fromJson(Map<String, dynamic> j) => _AllergyEntry(
        id: j['id'] ?? '', date: j['date'] ?? '', triggerFood: j['triggerFood'] ?? '',
        severity: j['severity'] ?? 'mild',
        symptoms: List<String>.from(j['symptoms'] ?? []), note: j['note']);
}

class _AllergyTab extends StatefulWidget {
  const _AllergyTab();

  @override
  State<_AllergyTab> createState() => _AllergyTabState();
}

class _AllergyTabState extends State<_AllergyTab> {
  List<_AllergyEntry> _entries = [];
  bool _loading = true;
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

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAllergy);
    if (raw != null) _entries = (jsonDecode(raw) as List).map((j) => _AllergyEntry.fromJson(j)).toList();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAllergy, jsonEncode(_entries.map((e) => e.toJson()).toList()));
  }

  Future<void> _log() async {
    if (_foodCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter the trigger food')));
      return;
    }
    final entry = _AllergyEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: _todayKey(), triggerFood: _foodCtrl.text.trim(),
      severity: _severity, symptoms: _symptoms.toList(),
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    );
    setState(() => _entries.insert(0, entry));
    await _save();
    _foodCtrl.clear(); _noteCtrl.clear();
    setState(() { _severity = 'mild'; _symptoms.clear(); });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Reaction logged: ${entry.triggerFood}'), backgroundColor: Colors.orange.shade700));
    }
  }

  // ── Section 12: Tracker Detail Screen ──────────────────────────────
  Future<void> _showDetail(_AllergyEntry entry) async {
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
      setState(() => _entries.removeWhere((e) => e.id == entry.id));
    } else {
      setState(() {
        final idx = _entries.indexWhere((e) => e.id == entry.id);
        if (idx >= 0) {
          _entries[idx] = _AllergyEntry(
            id: entry.id,
            date: entry.date,
            triggerFood: result['triggerFood'] as String,
            severity: result['severity'] as String,
            symptoms: List<String>.from(result['symptoms'] as List),
            note: result['note'] as String?,
          );
        }
      });
    }
    await _save();
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
                  decoration: BoxDecoration(color: sel ? color.withValues(alpha: 0.15) : Colors.grey.shade100,
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
                  Text(e.date, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                  Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey.shade400),
                ])));
          }),
      ]),
    );
  }
}

class _AllergyDetailSheet extends StatefulWidget {
  final _AllergyEntry entry;
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
    _noteCtrl = TextEditingController(text: widget.entry.note ?? '');
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
                Text(widget.entry.date, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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
                  decoration: BoxDecoration(color: sel ? color.withValues(alpha: 0.15) : Colors.grey.shade100,
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
// TAB 4 — GLP-1 TRACKER
// ─────────────────────────────────────────────────────────────────────────────

class _Glp1Entry {
  final String id;
  final String date;
  final String medication; // Ozempic, Wegovy, Mounjaro, etc.
  final double doseMg;
  final List<String> sideEffects;
  final String? note;

  _Glp1Entry({required this.id, required this.date, required this.medication,
      required this.doseMg, required this.sideEffects, this.note});

  Map<String, dynamic> toJson() => {'id': id, 'date': date, 'medication': medication,
      'doseMg': doseMg, 'sideEffects': sideEffects, 'note': note};

  factory _Glp1Entry.fromJson(Map<String, dynamic> j) => _Glp1Entry(
        id: j['id'] ?? '', date: j['date'] ?? '', medication: j['medication'] ?? '',
        doseMg: (j['doseMg'] as num).toDouble(),
        sideEffects: List<String>.from(j['sideEffects'] ?? []), note: j['note']);
}

class _Glp1Tab extends StatefulWidget {
  const _Glp1Tab();

  @override
  State<_Glp1Tab> createState() => _Glp1TabState();
}

class _Glp1TabState extends State<_Glp1Tab> {
  List<_Glp1Entry> _entries = [];
  bool _loading = true;
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

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kGlp1);
    if (raw != null) _entries = (jsonDecode(raw) as List).map((j) => _Glp1Entry.fromJson(j)).toList();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kGlp1, jsonEncode(_entries.map((e) => e.toJson()).toList()));
  }

  Future<void> _log() async {
    final dose = double.tryParse(_doseCtrl.text.trim());
    if (dose == null || dose <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid dose')));
      return;
    }
    final entry = _Glp1Entry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: _todayKey(), medication: _medication, doseMg: dose,
      sideEffects: _sideEffects.toList(),
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    );
    setState(() => _entries.insert(0, entry));
    await _save();
    _doseCtrl.clear(); _noteCtrl.clear();
    setState(() => _sideEffects.clear());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Dose logged: ${dose}mg $_medication'), backgroundColor: Colors.teal.shade700));
    }
  }

  // ── Section 12: Tracker Detail Screen ──────────────────────────────
  Future<void> _showDetail(_Glp1Entry entry) async {
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
      setState(() => _entries.removeWhere((e) => e.id == entry.id));
    } else {
      setState(() {
        final idx = _entries.indexWhere((e) => e.id == entry.id);
        if (idx >= 0) {
          _entries[idx] = _Glp1Entry(
            id: entry.id,
            date: entry.date,
            medication: result['medication'] as String,
            doseMg: result['dose'] as double,
            sideEffects: List<String>.from(result['sideEffects'] as List),
            note: result['note'] as String?,
          );
        }
      });
    }
    await _save();
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
                Text(e.date, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey.shade400),
              ])),
          )),
      ]),
    );
  }
}

class _Glp1DetailSheet extends StatefulWidget {
  final _Glp1Entry entry;
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
    _noteCtrl = TextEditingController(text: widget.entry.note ?? '');
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
                Text(widget.entry.date, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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
// TAB 5 — WELLNESS CHECK-IN
// ─────────────────────────────────────────────────────────────────────────────

class _WellnessEntry {
  final String date;
  final int mood;      // 1–5
  final int energy;    // 1–5
  final int sleep;     // hours
  final int pain;      // 0–5
  final String? note;

  _WellnessEntry({required this.date, required this.mood, required this.energy,
      required this.sleep, required this.pain, this.note});

  Map<String, dynamic> toJson() => {'date': date, 'mood': mood, 'energy': energy,
      'sleep': sleep, 'pain': pain, 'note': note};

  factory _WellnessEntry.fromJson(Map<String, dynamic> j) => _WellnessEntry(
        date: j['date'] ?? '', mood: j['mood'] ?? 3, energy: j['energy'] ?? 3,
        sleep: j['sleep'] ?? 7, pain: j['pain'] ?? 0, note: j['note']);
}

class _WellnessTab extends StatefulWidget {
  const _WellnessTab();

  @override
  State<_WellnessTab> createState() => _WellnessTabState();
}

class _WellnessTabState extends State<_WellnessTab> {
  List<_WellnessEntry> _entries = [];
  bool _loading = true;
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

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kWellness);
    if (raw != null) _entries = (jsonDecode(raw) as List).map((j) => _WellnessEntry.fromJson(j)).toList();
    // Pre-fill with today's entry if it exists
    final today = _todayKey();
    final existing = _entries.where((e) => e.date == today).firstOrNull;
    if (existing != null) {
      _mood = existing.mood; _energy = existing.energy;
      _sleep = existing.sleep; _pain = existing.pain;
      _noteCtrl.text = existing.note ?? '';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kWellness, jsonEncode(_entries.map((e) => e.toJson()).toList()));
  }

  Future<void> _checkIn() async {
    setState(() => _saving = true);
    final today = _todayKey();
    final entry = _WellnessEntry(date: today, mood: _mood, energy: _energy,
        sleep: _sleep, pain: _pain,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim());
    final idx = _entries.indexWhere((e) => e.date == today);
    setState(() { idx >= 0 ? _entries[idx] = entry : _entries.insert(0, entry); _saving = false; });
    await _save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Wellness check-in saved ✓'), backgroundColor: Colors.purple));
    }
  }

  // ── Section 12: Tracker Detail Screen ──────────────────────────────
  Future<void> _showDetail(_WellnessEntry entry) async {
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
      setState(() => _entries.removeWhere((e) => e.date == entry.date));
    } else {
      setState(() {
        final idx = _entries.indexWhere((e) => e.date == entry.date);
        if (idx >= 0) {
          final updated = _WellnessEntry(
            date: entry.date,
            mood: result['mood'] as int,
            energy: result['energy'] as int,
            sleep: result['sleep'] as int,
            pain: result['pain'] as int,
            note: result['note'] as String?,
          );
          _entries[idx] = updated;
          // Keep the live edit form in sync if we just edited today's entry.
          if (entry.date == _todayKey()) {
            _mood = updated.mood; _energy = updated.energy;
            _sleep = updated.sleep; _pain = updated.pain;
            _noteCtrl.text = updated.note ?? '';
          }
        }
      });
    }
    await _save();
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
                Text('${e.sleep}h sleep', style: const TextStyle(fontSize: 13)),
                if (e.pain > 0) ...[
                  const SizedBox(width: 8),
                  Text('Pain: ${_painLabels[e.pain]}',
                    style: TextStyle(fontSize: 12, color: Colors.red.shade600))
                ],
              ]),
              subtitle: e.note != null ? Text(e.note!, style: const TextStyle(fontSize: 11)) : null,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(e.date, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey.shade400),
              ])),
          )),
      ]),
    );
  }
}

class _WellnessDetailSheet extends StatefulWidget {
  final _WellnessEntry entry;

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
    _sleep = widget.entry.sleep;
    _pain = widget.entry.pain;
    _noteCtrl = TextEditingController(text: widget.entry.note ?? '');
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
                Text(widget.entry.date, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25))),
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
                  color: color.withValues(alpha: 0.7),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)))),
            ]),
          ));
        }).toList(),
      ),
    );
  }
}