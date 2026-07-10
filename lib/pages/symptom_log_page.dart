// lib/pages/symptom_log_page.dart
// Log post-bariatric symptoms: fatigue, nausea, dumping syndrome, etc.
// Accessed via route '/symptom-log'

import 'package:flutter/material.dart';
import '../models/bari_models.dart';
import '../services/bari_features_service.dart';
import '../services/recent_activity_tracker.dart';
import '../config/app_config.dart';

class SymptomLogPage extends StatefulWidget {
  const SymptomLogPage({super.key});

  @override
  State<SymptomLogPage> createState() => _SymptomLogPageState();
}

class _SymptomLogPageState extends State<SymptomLogPage> {
  final _notesController = TextEditingController();
  SymptomType _selectedType = SymptomType.fatigue;
  int _severity = 3;
  bool _saving = false;
  List<SymptomEntry> _recentEntries = [];
  bool _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    RecentActivityTracker.recordScreen(label: 'Symptoms', route: '/symptom-log');
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final entries = await BariFeaturesService.getSymptomLog(
        from: DateTime.now().subtract(const Duration(days: 14)),
      );
      if (mounted) setState(() {
        _recentEntries = entries;
        _loadingHistory = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingHistory = false);
      AppConfig.debugPrint('Error loading symptom history: $e');
    }
  }

  Future<void> _saveSymptom() async {
    setState(() => _saving = true);
    try {
      await BariFeaturesService.logSymptom(
        symptomType: _selectedType,
        severity: _severity,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
      _notesController.clear();
      setState(() => _severity = 3);
      await _loadHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Symptom logged ✓'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
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

  Future<void> _deleteEntry(SymptomEntry entry) async {
    if (entry.id == null) return;
    try {
      await BariFeaturesService.deleteSymptomEntry(entry.id!);
      await _loadHistory();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Symptom Log'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -- Log new symptom card --
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Log a Symptom',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),

                    // Symptom type chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: SymptomType.values.map((type) {
                        final selected = _selectedType == type;
                        return ChoiceChip(
                          label: Text('${type.emoji} ${type.displayName}'),
                          selected: selected,
                          selectedColor: Colors.green.shade100,
                          onSelected: (_) =>
                              setState(() => _selectedType = type),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 16),
                    Text(
                      'Severity: $_severity / 5',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Slider(
                      value: _severity.toDouble(),
                      min: 1,
                      max: 5,
                      divisions: 4,
                      label: _severityLabel(_severity),
                      activeColor: _severityColor(_severity),
                      onChanged: (v) =>
                          setState(() => _severity = v.round()),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text('Mild', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text('Severe', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),

                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Optional notes…',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
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
                            : const Icon(Icons.save_rounded),
                        label: Text(_saving ? 'Saving…' : 'Save Symptom'),
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.green.shade700),
                        onPressed: _saving ? null : _saveSymptom,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // -- Recent entries --
            const Text(
              'Recent (14 days)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            if (_loadingHistory)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator()))
            else if (_recentEntries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                    child: Text('No symptoms logged yet.',
                        style: TextStyle(color: Colors.grey))),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recentEntries.length,
                itemBuilder: (ctx, i) {
                  final e = _recentEntries[i];
                  return _SymptomEntryTile(
                    entry: e,
                    onDelete: () => _deleteEntry(e),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  String _severityLabel(int s) => switch (s) {
        1 => 'Mild',
        2 => 'Noticeable',
        3 => 'Moderate',
        4 => 'Strong',
        5 => 'Severe',
        _ => '$s',
      };

  Color _severityColor(int s) {
    if (s <= 2) return Colors.green;
    if (s == 3) return Colors.orange;
    return Colors.red;
  }
}

class _SymptomEntryTile extends StatelessWidget {
  final SymptomEntry entry;
  final VoidCallback onDelete;

  const _SymptomEntryTile({required this.entry, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final dateStr = '${entry.loggedAt.month}/${entry.loggedAt.day} '
        '${entry.loggedAt.hour.toString().padLeft(2, "0")}:'
        '${entry.loggedAt.minute.toString().padLeft(2, "0")}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Text(entry.symptomType.emoji,
            style: const TextStyle(fontSize: 24)),
        title: Text(
            '${entry.symptomType.displayName}  •  ${entry.severity}/5',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dateStr,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (entry.notes != null && entry.notes!.isNotEmpty)
              Text(entry.notes!,
                  style: const TextStyle(fontSize: 13)),
          ],
        ),
        isThreeLine: entry.notes != null && entry.notes!.isNotEmpty,
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: onDelete,
          tooltip: 'Delete',
        ),
      ),
    );
  }
}