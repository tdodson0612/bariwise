// lib/pages/account_preferences_page.dart
// Section 14 — Account Preferences Workspace
// Route: '/account-preferences'
//
// Editable post-onboarding account and health preferences:
//   • Personal Info     — username, display name
//   • Health Profile    — surgery type, surgery date, height, weight
//   • Dietary & Supps  — restrictions and supplement baseline (SharedPreferences)
//   • Privacy           — weight/weight-loss visibility on profile
//   • Notifications     — hydration, supplement, check-in reminders
//
// Uses ProfileService for Supabase fields (same methods as onboarding + tracker).
// Uses SharedPreferences for dietary restrictions and supplement baseline.
// BBRS design language: navy header, glass cards, gold accents.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/profile_service.dart';
import '../services/auth_service.dart';
import '../services/database_service_core.dart';
import '../services/recent_activity_tracker.dart';
import '../services/error_handling_service.dart';
import '../utils/height_utils.dart';
import '../config/app_config.dart';

// ─── BBRS Tokens ──────────────────────────────────────────────────────────────
const _kNavy  = Color(0xFF0A1628);
const _kBg    = Color(0xFFEEF2F7);
const _kGold  = Color(0xFFC9A84C);
const _kBody  = Color(0xFF1A2332);
const _kMuted = Color(0xFF6B7A94);
const _kBorder = Color(0xFFDDE3EE);

class AccountPreferencesPage extends StatefulWidget {
  const AccountPreferencesPage({super.key});

  @override
  State<AccountPreferencesPage> createState() =>
      _AccountPreferencesPageState();
}

class _AccountPreferencesPageState extends State<AccountPreferencesPage> {
  bool _loading = true;
  bool _saving = false;
  String? _userId;

  // ── Personal info ──────────────────────────────────────────────────────────
  final _usernameCtrl    = TextEditingController();
  final _firstNameCtrl   = TextEditingController();
  final _lastNameCtrl    = TextEditingController();

  // ── Health profile ─────────────────────────────────────────────────────────
  String? _surgeryType;
  DateTime? _surgeryDate;
  String _heightUnit = 'imperial';
  final _feetCtrl   = TextEditingController();
  final _inchesCtrl = TextEditingController();
  final _cmCtrl     = TextEditingController();
  String _weightUnit = 'lbs';
  final _currentWeightCtrl = TextEditingController();
  final _startWeightCtrl   = TextEditingController();

  // ── Dietary & supplements ─────────────────────────────────────────────────
  Set<String> _dietaryRestrictions = {};
  Set<String> _supplements         = {};

  // ── Privacy ────────────────────────────────────────────────────────────────
  bool _weightVisible     = false;
  bool _weightLossVisible = false;

  // ── Notifications ─────────────────────────────────────────────────────────
  bool _hydrationReminders  = true;
  bool _supplementReminders = true;
  bool _wellnessCheckIn     = true;

  static const List<String> _surgeryTypes = [
    'Gastric Bypass (RYGB)',
    'Gastric Sleeve (VSG)',
    'Adjustable Gastric Band',
    'Duodenal Switch (BPD/DS)',
    'SADI-S / Loop DS',
    'Gastric Balloon',
    'Revision Surgery',
    'Pre-op / Not yet had surgery',
    'Other',
  ];

  static const List<String> _restrictionOptions = [
    'Lactose intolerant', 'Gluten-free', 'Nut allergy', 'Shellfish allergy',
    'Soy allergy', 'Egg allergy', 'Vegetarian', 'Vegan',
    'Diabetic-friendly only', 'Low-sodium', 'Low-sugar', 'None',
  ];

  static const List<String> _supplementOptions = [
    'Multivitamin', 'Calcium Citrate', 'Vitamin D3', 'Vitamin B12',
    'Iron', 'Folate / Folic Acid', 'Zinc', 'Magnesium',
    'Vitamin B1 (Thiamine)', 'Omega-3 Fish Oil', 'Biotin',
    'Protein Powder', 'Probiotics', 'CoQ10', 'None yet',
  ];

  @override
  void initState() {
    super.initState();
    _userId = AuthService.currentUserId;
    _loadAll();
    RecentActivityTracker.recordScreen(
        label: 'Account Preferences', route: '/account-preferences');
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _feetCtrl.dispose();
    _inchesCtrl.dispose();
    _cmCtrl.dispose();
    _currentWeightCtrl.dispose();
    _startWeightCtrl.dispose();
    super.dispose();
  }

  // ── Load ───────────────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    if (_userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final profile = await ProfileService.getUserProfile(_userId!);
      final heightPref =
          await ProfileService.getHeightUnitPreference(_userId!);
      final weightVis =
          await ProfileService.getWeightVisibility(_userId!);
      final weightLossVis =
          await ProfileService.getWeightLossVisibility(_userId!);
      final prefs = await SharedPreferences.getInstance();

      // Height
      final heightCm = await ProfileService.getHeight(_userId!);

      // Weight — from profiles table if available
      final startKg =
          (profile?['starting_weight_kg'] as num?)?.toDouble();
      final currentKg =
          (profile?['current_weight_kg'] as num?)?.toDouble();

      // Notification prefs (SharedPreferences)
      final hydRemind =
          prefs.getBool('notif_hydration_$_userId') ?? true;
      final suppRemind =
          prefs.getBool('notif_supplement_$_userId') ?? true;
      final wellRemind =
          prefs.getBool('notif_wellness_$_userId') ?? true;

      // Dietary + supplement baseline
      final restrictions = prefs
              .getStringList('intake_dietary_restrictions_$_userId') ??
          [];
      final supps = prefs
              .getStringList('intake_supplement_baseline_$_userId') ??
          [];

      if (mounted) {
        setState(() {
          _usernameCtrl.text =
              profile?['username'] as String? ?? '';
          _firstNameCtrl.text =
              profile?['first_name'] as String? ?? '';
          _lastNameCtrl.text =
              profile?['last_name'] as String? ?? '';
          _surgeryType =
              profile?['bariatric_surgery_type'] as String?;
          _heightUnit = heightPref;

          if (heightCm != null) {
            if (heightPref == 'imperial') {
              final c = HeightUtils.cmToFeetInches(heightCm);
              _feetCtrl.text = c['feet'].toString();
              _inchesCtrl.text = c['inches'].toString();
            } else {
              _cmCtrl.text = heightCm.toStringAsFixed(0);
            }
          }

          if (startKg != null) {
            _startWeightCtrl.text = _weightUnit == 'lbs'
                ? (startKg / 0.453592).toStringAsFixed(1)
                : startKg.toStringAsFixed(1);
          }
          if (currentKg != null) {
            _currentWeightCtrl.text = _weightUnit == 'lbs'
                ? (currentKg / 0.453592).toStringAsFixed(1)
                : currentKg.toStringAsFixed(1);
          }

          final rawDate =
              profile?['surgery_date'] as String?;
          if (rawDate != null) {
            _surgeryDate = DateTime.tryParse(rawDate);
          }

          _weightVisible     = weightVis;
          _weightLossVisible = weightLossVis;
          _hydrationReminders  = hydRemind;
          _supplementReminders = suppRemind;
          _wellnessCheckIn     = wellRemind;
          _dietaryRestrictions = restrictions.toSet();
          _supplements         = supps.toSet();
          _loading = false;
        });
      }
    } catch (e) {
      AppConfig.debugPrint('Account prefs load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _saveAll() async {
    if (_userId == null) return;
    setState(() => _saving = true);

    try {
      // Personal info
      await ProfileService.updateProfile(
        username:  _usernameCtrl.text.trim().isEmpty  ? null : _usernameCtrl.text.trim(),
        firstName: _firstNameCtrl.text.trim().isEmpty ? null : _firstNameCtrl.text.trim(),
        lastName:  _lastNameCtrl.text.trim().isEmpty  ? null : _lastNameCtrl.text.trim(),
      );

      // Surgery type
      if (_surgeryType != null) {
        await ProfileService.updateSurgeryType(_userId!, _surgeryType!);
      }

      // Surgery date
      if (_surgeryDate != null) {
        await DatabaseServiceCore.workerQuery(
          action: 'update',
          table: 'profiles',
          filters: {'id': _userId},
          data: {
            'surgery_date':
                _surgeryDate!.toIso8601String().split('T').first,
            'updated_at': DateTime.now().toIso8601String(),
          },
        );
        await DatabaseServiceCore.clearCache(
            'cache_user_profile_$_userId');
        await DatabaseServiceCore.clearCache(
            'cache_profile_timestamp_$_userId');
      }

      // Height
      double? heightCm;
      if (_heightUnit == 'imperial') {
        final feet   = int.tryParse(_feetCtrl.text.trim()) ?? 0;
        final inches = int.tryParse(_inchesCtrl.text.trim()) ?? 0;
        heightCm = (feet * 30.48) + (inches * 2.54);
      } else {
        heightCm = double.tryParse(_cmCtrl.text.trim());
      }
      if (heightCm != null && heightCm > 0) {
        await ProfileService.updateHeight(_userId!, heightCm);
        await ProfileService.updateHeightUnitPreference(
            _userId!, _heightUnit);
      }

      // Weight
      double? startKg   = double.tryParse(_startWeightCtrl.text.trim());
      double? currentKg = double.tryParse(_currentWeightCtrl.text.trim());
      if (_weightUnit == 'lbs') {
        if (startKg != null)   startKg   = startKg * 0.453592;
        if (currentKg != null) currentKg = currentKg * 0.453592;
      }
      if (startKg != null || currentKg != null) {
        final wData = <String, dynamic>{
          'updated_at': DateTime.now().toIso8601String()
        };
        if (startKg != null)   wData['starting_weight_kg'] = startKg;
        if (currentKg != null) wData['current_weight_kg']  = currentKg;
        await DatabaseServiceCore.workerQuery(
          action: 'update',
          table: 'profiles',
          filters: {'id': _userId},
          data: wData,
        );
        await DatabaseServiceCore.clearCache(
            'cache_user_profile_$_userId');
        await DatabaseServiceCore.clearCache(
            'cache_profile_timestamp_$_userId');
      }

      // Privacy
      await ProfileService.updateWeightVisibility(
          _userId!, _weightVisible);
      await ProfileService.updateWeightLossVisibility(
          _userId!, _weightLossVisible);

      // Notifications + dietary + supplement baseline (SharedPreferences)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
          'notif_hydration_$_userId', _hydrationReminders);
      await prefs.setBool(
          'notif_supplement_$_userId', _supplementReminders);
      await prefs.setBool(
          'notif_wellness_$_userId', _wellnessCheckIn);
      await prefs.setStringList(
          'intake_dietary_restrictions_$_userId',
          _dietaryRestrictions.toList());
      await prefs.setStringList(
          'intake_supplement_baseline_$_userId',
          _supplements.toList());

      if (mounted) {
        ErrorHandlingService.showSuccess(
            context, 'Preferences saved successfully!');
      }
    } catch (e) {
      AppConfig.debugPrint('Account prefs save error: $e');
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          customMessage: 'Failed to save preferences. Please try again.',
          onRetry: _saveAll,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text('Account Preferences'),
        backgroundColor: _kNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveAll,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Save',
                    style: TextStyle(
                        color: _kGold,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _kGold))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPersonalInfo(),
                  const SizedBox(height: 16),
                  _buildHealthProfile(),
                  const SizedBox(height: 16),
                  _buildDietarySupplements(),
                  const SizedBox(height: 16),
                  _buildPrivacy(),
                  const SizedBox(height: 16),
                  _buildNotifications(),
                  const SizedBox(height: 24),
                  _buildSaveButton(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  // ── Sections ───────────────────────────────────────────────────────────────

  Widget _buildPersonalInfo() {
    return _PrefCard(
      title: 'Personal Info',
      icon: Icons.person_rounded,
      children: [
        _PrefField(label: 'Username', controller: _usernameCtrl,
            hint: 'e.g. janedoe_bari'),
        _PrefField(label: 'First Name', controller: _firstNameCtrl,
            hint: 'Jane', capitalize: true),
        _PrefField(label: 'Last Name', controller: _lastNameCtrl,
            hint: 'Doe', capitalize: true),
      ],
    );
  }

  Widget _buildHealthProfile() {
    return _PrefCard(
      title: 'Health Profile',
      icon: Icons.local_hospital_rounded,
      children: [
        // Surgery type
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _FieldLabel('Surgery Type'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _surgeryType,
            hint: const Text('Select surgery type'),
            decoration: _inputDec(),
            items: _surgeryTypes
                .map((t) => DropdownMenuItem(value: t,
                    child: Text(t, style: const TextStyle(fontSize: 13))))
                .toList(),
            onChanged: (v) => setState(() => _surgeryType = v),
          ),
        ]),

        const SizedBox(height: 14),

        // Surgery date
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _FieldLabel('Surgery Date'),
          const SizedBox(height: 6),
          InkWell(
            onTap: _pickSurgeryDate,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: _kBorder),
                borderRadius: BorderRadius.circular(10),
                color: Colors.grey.shade50,
              ),
              child: Row(children: [
                Icon(Icons.calendar_today_rounded,
                    size: 16, color: _kMuted),
                const SizedBox(width: 8),
                Text(
                  _surgeryDate != null
                      ? '${_surgeryDate!.month}/${_surgeryDate!.day}/${_surgeryDate!.year}'
                      : 'Tap to select',
                  style: TextStyle(
                      fontSize: 14,
                      color: _surgeryDate != null ? _kBody : _kMuted),
                ),
              ]),
            ),
          ),
        ]),

        const SizedBox(height: 14),

        // Height
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _FieldLabel('Height'),
          const SizedBox(height: 6),
          _UnitToggle(
            options: const ['Imperial (ft/in)', 'Metric (cm)'],
            values: const ['imperial', 'metric'],
            selected: _heightUnit,
            onChanged: (v) => setState(() => _heightUnit = v),
          ),
          const SizedBox(height: 8),
          if (_heightUnit == 'imperial')
            Row(children: [
              Expanded(child: TextField(controller: _feetCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _inputDec(suffix: 'ft', hint: '5'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _inchesCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _inputDec(suffix: 'in', hint: '7'))),
            ])
          else
            TextField(controller: _cmCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _inputDec(suffix: 'cm', hint: '170')),
        ]),

        const SizedBox(height: 14),

        // Weight
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _FieldLabel('Weight'),
          const SizedBox(height: 6),
          _UnitToggle(
            options: const ['lbs', 'kg'],
            values: const ['lbs', 'kg'],
            selected: _weightUnit,
            onChanged: (v) => setState(() => _weightUnit = v),
          ),
          const SizedBox(height: 8),
          TextField(controller: _startWeightCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _inputDec(
                  label: 'Starting weight (before surgery)',
                  suffix: _weightUnit, hint: '280')),
          const SizedBox(height: 8),
          TextField(controller: _currentWeightCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _inputDec(
                  label: 'Current weight',
                  suffix: _weightUnit, hint: '210')),
        ]),
      ],
    );
  }

  Widget _buildDietarySupplements() {
    return _PrefCard(
      title: 'Dietary & Supplements',
      icon: Icons.checklist_rounded,
      children: [
        const _FieldLabel('Dietary Restrictions'),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: _restrictionOptions.map((o) {
          final sel = _dietaryRestrictions.contains(o);
          return FilterChip(
            label: Text(o, style: const TextStyle(fontSize: 12)),
            selected: sel,
            selectedColor: const Color(0xFFEF5350).withValues(alpha: 0.12),
            checkmarkColor: const Color(0xFFEF5350),
            side: BorderSide(color: sel
                ? const Color(0xFFEF5350).withValues(alpha: 0.5) : _kBorder),
            onSelected: (_) => setState(() {
              if (o == 'None') {
                _dietaryRestrictions.clear();
                if (!sel) _dietaryRestrictions.add('None');
              } else {
                _dietaryRestrictions.remove('None');
                sel ? _dietaryRestrictions.remove(o) : _dietaryRestrictions.add(o);
              }
            }),
          );
        }).toList()),

        const SizedBox(height: 16),
        const _FieldLabel('Current Supplements'),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: _supplementOptions.map((o) {
          final sel = _supplements.contains(o);
          return FilterChip(
            label: Text(o, style: const TextStyle(fontSize: 12)),
            selected: sel,
            selectedColor: const Color(0xFF4FC3F7).withValues(alpha: 0.12),
            checkmarkColor: const Color(0xFF4FC3F7),
            side: BorderSide(color: sel
                ? const Color(0xFF4FC3F7).withValues(alpha: 0.5) : _kBorder),
            onSelected: (_) => setState(() {
              if (o == 'None yet') {
                _supplements.clear();
                if (!sel) _supplements.add('None yet');
              } else {
                _supplements.remove('None yet');
                sel ? _supplements.remove(o) : _supplements.add(o);
              }
            }),
          );
        }).toList()),
      ],
    );
  }

  Widget _buildPrivacy() {
    return _PrefCard(
      title: 'Privacy',
      icon: Icons.lock_outline_rounded,
      children: [
        _SwitchRow(
          label: 'Show weight average on profile',
          subtitle: 'Others can see your average weight',
          value: _weightVisible,
          onChanged: (v) => setState(() => _weightVisible = v),
        ),
        _SwitchRow(
          label: 'Show weight loss on profile',
          subtitle: 'Others can see your total weight lost',
          value: _weightLossVisible,
          onChanged: (v) => setState(() => _weightLossVisible = v),
        ),
      ],
    );
  }

  Widget _buildNotifications() {
    return _PrefCard(
      title: 'Notifications',
      icon: Icons.notifications_outlined,
      children: [
        _SwitchRow(
          label: 'Hydration reminders',
          subtitle: 'Daily nudges to log your water intake',
          value: _hydrationReminders,
          onChanged: (v) => setState(() => _hydrationReminders = v),
        ),
        _SwitchRow(
          label: 'Supplement reminders',
          subtitle: 'Alerts when a scheduled supplement is due',
          value: _supplementReminders,
          onChanged: (v) => setState(() => _supplementReminders = v),
        ),
        _SwitchRow(
          label: 'Wellness check-in',
          subtitle: 'Weekly reminder to log mood, energy, sleep',
          value: _wellnessCheckIn,
          onChanged: (v) => setState(() => _wellnessCheckIn = v),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _saving ? null : _saveAll,
        icon: _saving
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save_rounded),
        label: Text(_saving ? 'Saving…' : 'Save All Preferences'),
        style: FilledButton.styleFrom(
          backgroundColor: _kNavy,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: _kGold.withValues(alpha: 0.4))),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<void> _pickSurgeryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _surgeryDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
              primary: _kNavy, onPrimary: Colors.white,
              secondary: _kGold),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _surgeryDate = picked);
  }

  InputDecoration _inputDec({String? label, String? suffix,
      String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: suffix,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _kGold, width: 2)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────

class _PrefCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _PrefCard(
      {required this.title,
      required this.icon,
      required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: _kGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: _kGold, size: 18),
            ),
            const SizedBox(width: 10),
            Text(title,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _kBody)),
          ]),
          const SizedBox(height: 14),
          const Divider(height: 1, color: _kBorder),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _PrefField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final bool capitalize;

  const _PrefField(
      {required this.label,
      required this.controller,
      required this.hint,
      this.capitalize = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _FieldLabel(label),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          textCapitalization: capitalize
              ? TextCapitalization.words
              : TextCapitalization.none,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kGold, width: 2)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ]),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _kMuted,
          letterSpacing: 0.3));
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow(
      {required this.label,
      required this.subtitle,
      required this.value,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _kBody)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(fontSize: 12, color: _kMuted)),
          ]),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: _kGold,
          activeTrackColor: _kGold.withValues(alpha: 0.3),
        ),
      ]),
    );
  }
}

class _UnitToggle extends StatelessWidget {
  final List<String> options;
  final List<String> values;
  final String selected;
  final ValueChanged<String> onChanged;

  const _UnitToggle(
      {required this.options,
      required this.values,
      required this.selected,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: List.generate(options.length, (i) {
          final sel = selected == values[i];
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(values[i]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: sel ? _kNavy : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(options[i],
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: sel ? Colors.white : _kMuted)),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}