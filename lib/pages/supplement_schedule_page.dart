// lib/pages/supplement_schedule_page.dart
// Manage bariatric supplement schedules and mark them as taken.
// Post-bariatric patients require lifelong supplementation (iron, B12, calcium, D3, etc.)
// Route: '/supplement-schedule'

import 'package:flutter/material.dart';
import '../models/bari_models.dart';
import '../services/bari_features_service.dart';
import '../services/bari_notification_service.dart';
import '../services/recent_activity_tracker.dart';
import '../config/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupplementSchedulePage extends StatefulWidget {
  const SupplementSchedulePage({super.key});

  @override
  State<SupplementSchedulePage> createState() =>
      _SupplementSchedulePageState();
}

class _SupplementSchedulePageState extends State<SupplementSchedulePage> {
  List<SupplementSchedule> _schedules = [];
  List<SupplementTakenEntry> _takenToday = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    RecentActivityTracker.recordScreen(label: 'Supplements', route: '/supplement-schedule');
  }

  Future<void> _load() async {
    try {
      final schedules =
          await BariFeaturesService.getSupplementSchedules();
      final today = DateTime.now();
      final takenLog = await BariFeaturesService.getSupplementTakenLog(
        from: DateTime(today.year, today.month, today.day),
        to: DateTime(today.year, today.month, today.day + 1),
      );

      if (mounted) {
        setState(() {
          _schedules = schedules;
          _takenToday = takenLog;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      AppConfig.debugPrint('Supplement load error: $e');
    }
  }

  bool _isTakenToday(SupplementSchedule s) {
    return _takenToday
        .any((t) => t.scheduleId == s.id || t.name == s.name);
  }

  Future<void> _markTaken(SupplementSchedule s) async {
    try {
      await BariFeaturesService.logSupplementTaken(
        name: s.name,
        dose: s.dose,
        scheduleId: s.id,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('💊 ${s.name} marked as taken!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteSchedule(SupplementSchedule s) async {
    if (s.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Supplement'),
        content: Text('Remove "${s.name}" from your schedule?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.red),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await BariFeaturesService.deactivateSupplementSchedule(s.id!);
      await _load();
      await BariNotificationService.scheduleSupplementReminders(
          _schedules);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showAddDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _AddSupplementSheet(
        onSaved: (schedule) async {
          try {
            final uid = Supabase.instance.client.auth.currentUser?.id;
            if (uid == null) return;
            await BariFeaturesService.createSupplementSchedule(
                schedule.copyWith());
            await _load();
            await BariNotificationService.scheduleSupplementReminders(
                _schedules);
            if (mounted) Navigator.pop(ctx);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error saving: $e')),
              );
            }
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Supplement Schedule'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add supplement',
            onPressed: _showAddDialog,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _schedules.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('💊', style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 12),
                      const Text(
                        'No supplements scheduled yet',
                        style: TextStyle(
                            fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Add First Supplement'),
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange.shade700),
                        onPressed: _showAddDialog,
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _schedules.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final s = _schedules[i];
                    final taken = _isTakenToday(s);
                    return Card(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: taken
                              ? Colors.orange.shade100
                              : Colors.grey.shade100,
                          child: Text(
                            taken ? '✓' : '💊',
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                        title: Text(s.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            '${s.dose}  •  ${s.timeOfDay}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!taken)
                              TextButton(
                                onPressed: () => _markTaken(s),
                                child: const Text('Mark Taken'),
                              ),
                            if (taken)
                              const Chip(
                                label: Text('Taken',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white)),
                                backgroundColor: Colors.green,
                                padding: EdgeInsets.zero,
                              ),
                            IconButton(
                              icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                  size: 20),
                              onPressed: () => _deleteSchedule(s),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: _schedules.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _showAddDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add Supplement'),
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
            ),
    );
  }
}

// ----------------------------------------------------------------
// Add supplement bottom sheet
// ----------------------------------------------------------------

class _AddSupplementSheet extends StatefulWidget {
  final Future<void> Function(SupplementSchedule) onSaved;

  const _AddSupplementSheet({required this.onSaved});

  @override
  State<_AddSupplementSheet> createState() => _AddSupplementSheetState();
}

class _AddSupplementSheetState extends State<_AddSupplementSheet> {
  final _nameCtrl = TextEditingController();
  final _doseCtrl = TextEditingController();
  String _timeOfDay = '08:00';
  bool _saving = false;

  // Common post-bariatric supplement timing options
  final List<String> _timeOptions = [
    '06:00', '07:00', '08:00', '09:00',
    '12:00', '14:00', '18:00', '20:00', '21:00',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _doseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Add Supplement',
              style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: 'Supplement name',
              hintText: 'e.g. Iron, Vitamin B12, Calcium Citrate',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _doseCtrl,
            decoration: InputDecoration(
              labelText: 'Dose',
              hintText: 'e.g. 500mg, 1 tablet, 2 chewables',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _timeOfDay,
            decoration: InputDecoration(
              labelText: 'Time of day',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            items: _timeOptions
                .map((t) =>
                    DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (v) =>
                setState(() => _timeOfDay = v ?? '08:00'),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded),
              label: Text(_saving ? 'Saving…' : 'Save Supplement'),
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange.shade700),
              onPressed: _saving
                  ? null
                  : () async {
                      if (_nameCtrl.text.trim().isEmpty ||
                          _doseCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(
                          content: Text(
                              'Please fill in name and dose'),
                        ));
                        return;
                      }
                      setState(() => _saving = true);
                      final schedule = SupplementSchedule(
                        userId: uid,
                        name: _nameCtrl.text.trim(),
                        dose: _doseCtrl.text.trim(),
                        timeOfDay: _timeOfDay,
                      );
                      await widget.onSaved(schedule);
                      if (mounted) {
                        setState(() => _saving = false);
                      }
                    },
            ),
          ),
        ],
      ),
    );
  }
}