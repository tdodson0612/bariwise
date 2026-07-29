// lib/pages/settings_page.dart
// User settings: notifications, account info, premium status, display theme.
// Route: '/settings'
// iOS 14 Compatible | Production Ready
//
// ── Section 14 additions (earlier this session) ────────────────────────────
// - Data Controls: Export My Data (share sheet JSON dump) + Clear Local Data
//   (confirmed, scoped to local-only SharedPreferences trackers/lists only —
//   does NOT touch Supabase-backed data or account/display/premium prefs).
// - Support/About: app version, copyable support email, Privacy Policy /
//   Terms of Use shown honestly as "Coming Soon" rather than dead links,
//   since those documents are marked Not Started in Section 23.
// - Delete Account wired to the existing (previously unused)
//   AccountDeletionService.deleteAccountCompletely(), with a
//   type-DELETE-to-confirm safeguard given it's irreversible.
// - Notification toggles: Hydration + Symptom Reminders now actually call
//   BariNotificationService; Weekly Progress, Recipe Updates, and Messages
//   are honestly labeled "Coming soon" since no corresponding notification
//   type exists yet (verified directly against bari_notification_service.dart,
//   main.dart's FCM handling, and messaging_service.dart — confirmed no
//   message-arrival notification is triggered anywhere).
//
// ✅ NEW THIS SESSION: removed the manual Navigator.of(context)
// .popUntil((route) => route.isFirst) call that used to run after
// signOut() in _showDeleteAccountDialog(). main.dart's onAuthStateChange
// listener now has an explicit `signedOut` branch that redirects to
// /login for ANY sign-out app-wide, including this one. Keeping a second,
// local navigation call here would race against that global listener
// rather than add real coverage, so it's removed rather than left as debt.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../config/app_config.dart';
import '../services/premium_service.dart';
import '../services/bari_notification_service.dart';
import '../services/account_deletion_service.dart';
import '../widgets/app_drawer.dart';

// Local-only SharedPreferences keys eligible for Export/Clear. Duplicated
// here rather than imported, since several are private consts in their
// owning files (extended_tracker_page.dart) and Dart library privacy
// prevents cross-file reuse — same approach used for tracker_landing_page.dart
// and bari_dashboard_page.dart earlier this session.
const List<String> _kLocalDataKeys = [
  'meal_planner_data',
  'list_gen_grocery',
  'list_gen_grocery_archive',
  'list_gen_supplement',
  'list_gen_supplement_archive',
  'list_gen_meal_prep',
  'list_gen_meal_prep_archive',
  'ext_tracker_weight',
  'ext_tracker_tolerance',
  'ext_tracker_allergy',
  'ext_tracker_glp1',
  'ext_tracker_wellness',
];

// Human-readable labels for the confirmation dialog, in the same order.
const List<String> _kLocalDataLabels = [
  'Meal Planner (weekly plans)',
  'Grocery list (List Generator tab)',
  'Grocery list archive (List Generator tab)',
  'Supplement list (List Generator tab)',
  'Supplement list archive (List Generator tab)',
  'Meal prep list (List Generator tab)',
  'Meal prep list archive (List Generator tab)',
  'Weight history (Health Trackers tab)',
  'Food tolerance logs (Health Trackers tab)',
  'Allergy logs (Health Trackers tab)',
  'GLP-1 dose logs (Health Trackers tab)',
  'Wellness check-ins (Health Trackers tab)',
];

// App metadata — hardcoded rather than pulled from a package_info-style
// plugin, since no such dependency was confirmed present this session.
// Flagged in Technical Debt as a placeholder pending a real version source.
const String _kAppVersion = '1.0.0';
const String _kSupportEmail = 'support@bariwise.app';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // ── State ────────────────────────────────────────────────────────────────
  bool _isLoading = true;

  // Account
  String? _displayName;
  String? _email;
  bool _isPremium = false;

  // Notifications
  bool _notifWeeklyProgress = true;
  bool _notifSymptomReminders = true;
  bool _notifHydrationReminders = false;
  bool _notifRecipeUpdates = true;
  bool _notifMessages = true;

  // Display
  bool _useCompactCards = false;
  bool _showHealthScoreBadges = true;
  bool _showNutritionOnCards = true;

  // Data Controls (Section 14 addition)
  bool _exportingData = false;
  bool _clearingData = false;
  bool _deletingAccount = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      // Defensive — safe to call repeatedly, guarded internally by
      // BariNotificationService's own _initialized flag. Ensures the
      // newly-wired toggles below work even if main.dart hasn't already
      // initialized this service.
      await BariNotificationService.initialize();

      final prefs = await SharedPreferences.getInstance();
      final user = Supabase.instance.client.auth.currentUser;

      // Account
      final isPremium = await PremiumService.isPremiumUser();

      if (mounted) {
        setState(() {
          _email = user?.email;
          _displayName = prefs.getString('display_name') ?? user?.email?.split('@').first;
          _isPremium = isPremium;

          // Notifications
          _notifWeeklyProgress    = prefs.getBool('notif_weekly_progress')    ?? true;
          _notifSymptomReminders  = prefs.getBool('notif_symptom_reminders')  ?? true;
          _notifHydrationReminders = prefs.getBool('notif_hydration_reminders') ?? false;
          _notifRecipeUpdates     = prefs.getBool('notif_recipe_updates')     ?? true;
          _notifMessages          = prefs.getBool('notif_messages')           ?? true;

          // Display
          _useCompactCards       = prefs.getBool('display_compact_cards')      ?? false;
          _showHealthScoreBadges = prefs.getBool('display_health_badges')      ?? true;
          _showNutritionOnCards  = prefs.getBool('display_nutrition_on_cards') ?? true;

          _isLoading = false;
        });
      }
    } catch (e) {
      AppConfig.debugPrint('❌ SettingsPage: error loading settings: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  // ── Data Controls (Section 14 addition) ─────────────────────────────────

  Future<void> _exportLocalData() async {
    setState(() => _exportingData = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = Supabase.instance.client.auth.currentUser?.id;

      final export = <String, dynamic>{
        'exportedAt': DateTime.now().toIso8601String(),
        'app': 'BariWise',
      };

      for (int i = 0; i < _kLocalDataKeys.length; i++) {
        final key = _kLocalDataKeys[i];
        final raw = prefs.getString(key);
        if (raw != null) {
          try {
            export[key] = jsonDecode(raw);
          } catch (_) {
            export[key] = raw;
          }
        }
      }

      // Tracker page entries (Weight/Meals/Supplements/Exercise/Water) are
      // keyed per-user via TrackerService's own convention.
      if (userId != null) {
        final trackerRaw = prefs.getString('tracker_entries_$userId');
        if (trackerRaw != null) {
          try {
            export['tracker_entries'] = jsonDecode(trackerRaw);
          } catch (_) {
            export['tracker_entries'] = trackerRaw;
          }
        }
      }

      if (export.length <= 2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No local data found to export yet.')),
          );
        }
        return;
      }

      final jsonString =
          const JsonEncoder.withIndent('  ').convert(export);

      await Share.share(
        jsonString,
        subject: 'BariWise Data Export — ${DateTime.now().toString().split(' ').first}',
      );
    } catch (e) {
      AppConfig.debugPrint('❌ SettingsPage: export error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingData = false);
    }
  }

  Future<void> _showClearDataConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Local Data'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This will permanently delete the following, stored only on this device:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              ..._kLocalDataLabels.map((label) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  '),
                        Expanded(
                            child: Text(label,
                                style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  )),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Text(
                  'Your Hydration, Supplement Schedule, Symptom Log, Alcohol Tracker, and Grocery List data are stored on our servers and will NOT be affected.',
                  style: TextStyle(fontSize: 12, color: Colors.green.shade900),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Consider exporting your data first — this cannot be undone.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear It All'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _clearLocalData();
    }
  }

  Future<void> _clearLocalData() async {
    setState(() => _clearingData = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = Supabase.instance.client.auth.currentUser?.id;

      for (final key in _kLocalDataKeys) {
        await prefs.remove(key);
      }
      if (userId != null) {
        await prefs.remove('tracker_entries_$userId');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Local data cleared.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      AppConfig.debugPrint('❌ SettingsPage: clear data error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear data: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _clearingData = false);
    }
  }

  // ── Support/About (Section 14 addition) ─────────────────────────────────

  void _copySupportEmail() {
    Clipboard.setData(const ClipboardData(text: _kSupportEmail));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Support email copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showComingSoon(String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(
            '$title is being finalized and will be available in a future update.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEF2F7),
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFF0A1628),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      drawer: const AppDrawer(currentPage: 'settings'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                _buildAccountSection(),
                _buildPremiumSection(),
                _buildNotificationsSection(),
                _buildDisplaySection(),
                _buildDataControlsSection(),
                _buildSupportSection(),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  // ── Account section ──────────────────────────────────────────────────────

  Widget _buildAccountSection() {
    return _Section(
      icon: Icons.person_rounded,
      iconColor: Colors.orange.shade700,
      title: 'Account',
      children: [
        _InfoTile(
          label: 'Name',
          value: _displayName ?? '—',
          onTap: _showEditNameDialog,
        ),
        _InfoTile(
          label: 'Email',
          value: _email ?? '—',
        ),
        _ActionTile(
          icon: Icons.lock_outline_rounded,
          label: 'Change Password',
          onTap: () => Navigator.pushNamed(context, '/reset-password'),
        ),
        _ActionTile(
          icon: Icons.delete_outline_rounded,
          label: 'Delete Account',
          labelColor: Colors.red.shade700,
          iconColor: Colors.red.shade700,
          onTap: _showDeleteAccountDialog,
        ),
      ],
    );
  }

  void _showEditNameDialog() {
    final controller = TextEditingController(text: _displayName);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Display Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Display name',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('display_name', name);
              if (mounted) {
                setState(() => _displayName = name);
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Delete Account: wired to the existing AccountDeletionService (which
  // previously existed in the project but was never called from anywhere).
  // Performs real, complete deletion (R2 storage, all DB rows, Auth user,
  // local cache) via that service. Includes a type-to-confirm safeguard
  // since this is irreversible and destructive.
  //
  // ✅ NEW THIS SESSION: no longer navigates manually after sign-out — see
  // file header note. main.dart's onAuthStateChange listener now handles
  // the /login redirect globally for any sign-out event.
  void _showDeleteAccountDialog() {
    final confirmCtrl = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: !_deletingAccount,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final canDelete = confirmCtrl.text.trim() == 'DELETE';
          return AlertDialog(
            title: const Text('Delete Account'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This action is permanent and cannot be undone. '
                    'All your data, recipes, pictures, and progress — '
                    'including everything stored on our servers — will '
                    'be permanently deleted.',
                  ),
                  const SizedBox(height: 16),
                  Text('Type DELETE to confirm:',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: confirmCtrl,
                    enabled: !_deletingAccount,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'DELETE',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  if (_deletingAccount) ...[
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 12),
                        Expanded(child: Text('Deleting your account…')),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: _deletingAccount
                    ? null
                    : () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: (!canDelete || _deletingAccount)
                    ? null
                    : () async {
                        setDialogState(() {});
                        setState(() => _deletingAccount = true);
                        try {
                          await AccountDeletionService
                              .deleteAccountCompletely();
                          try {
                            await Supabase.instance.client.auth.signOut();
                          } catch (_) {
                            // Non-fatal — account data is already deleted
                            // even if the local sign-out call fails.
                          }
                          if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('Your account has been deleted.'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            // ✅ Updated this session: no manual navigation
                            // here anymore. main.dart's onAuthStateChange
                            // listener now has a `signedOut` branch that
                            // redirects to /login for ANY sign-out
                            // app-wide, including this one — a second,
                            // local navigation call here would race
                            // against that global listener rather than
                            // add real coverage.
                          }
                        } catch (e) {
                          if (dialogCtx.mounted) {
                            setState(() => _deletingAccount = false);
                            setDialogState(() {});
                            ScaffoldMessenger.of(dialogCtx).showSnackBar(
                              SnackBar(
                                content:
                                    Text('Failed to delete account: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Delete Forever'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Premium section ──────────────────────────────────────────────────────

  Widget _buildPremiumSection() {
    return _Section(
      icon: Icons.star_rounded,
      iconColor: Colors.amber.shade700,
      title: 'Premium',
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _isPremium
                  ? [Colors.orange.shade700, Colors.orange.shade500]
                  : [Colors.grey.shade700, Colors.grey.shade500],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(
                _isPremium ? Icons.star_rounded : Icons.star_outline_rounded,
                color: Colors.white,
                size: 32,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isPremium ? 'Premium Active' : 'Free Account',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isPremium
                          ? 'All features unlocked'
                          : 'Upgrade to unlock all features',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_isPremium)
                ElevatedButton(
                  onPressed: () => Navigator.pushNamed(context, '/purchase'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Upgrade',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ),
        if (_isPremium)
          _ActionTile(
            icon: Icons.receipt_long_rounded,
            label: 'Manage Subscription',
            onTap: () => Navigator.pushNamed(context, '/purchase'),
          ),
      ],
    );
  }

  // ── Notifications section ────────────────────────────────────────────────

  Widget _buildNotificationsSection() {
    return _Section(
      icon: Icons.notifications_outlined,
      iconColor: Colors.blue.shade600,
      title: 'Notifications',
      children: [
        // This toggle writes to a SharedPreferences key that nothing else
        // reads — verified via direct inspection of
        // bari_notification_service.dart that no "weekly progress"
        // notification exists to wire it to. Rather than silently leaving
        // it looking functional, labeled honestly.
        _ToggleTile(
          label: 'Weekly Progress Summary',
          subtitle: 'Bariatric health report every week · Coming soon',
          value: _notifWeeklyProgress,
          onChanged: (v) {
            setState(() => _notifWeeklyProgress = v);
            _saveBool('notif_weekly_progress', v);
          },
        ),
        // Actually schedules/cancels the daily check-in reminder via
        // BariNotificationService, whose payload already routes to
        // /symptom-log.
        _ToggleTile(
          label: 'Symptom Reminders',
          subtitle: 'Daily prompt to log how you feel',
          value: _notifSymptomReminders,
          onChanged: (v) async {
            setState(() => _notifSymptomReminders = v);
            await _saveBool('notif_symptom_reminders', v);
            await BariNotificationService.setDailyCheckinReminder(
                enabled: v);
          },
        ),
        // Actually schedules/cancels hydration reminders via
        // BariNotificationService.
        _ToggleTile(
          label: 'Hydration Reminders',
          subtitle: 'Hourly water intake nudges',
          value: _notifHydrationReminders,
          onChanged: (v) async {
            setState(() => _notifHydrationReminders = v);
            await _saveBool('notif_hydration_reminders', v);
            await BariNotificationService.setHydrationReminders(
                enabled: v);
          },
        ),
        // No corresponding notification type exists in
        // bari_notification_service.dart — labeled honestly rather than
        // silently left looking functional.
        _ToggleTile(
          label: 'New Recipe Suggestions',
          subtitle: 'When personalized recipes are available · Coming soon',
          value: _notifRecipeUpdates,
          onChanged: (v) {
            setState(() => _notifRecipeUpdates = v);
            _saveBool('notif_recipe_updates', v);
          },
        ),
        // Confirmed via direct inspection of main.dart + messaging_service.dart:
        // there is no push or local notification triggered anywhere when a
        // new message arrives — FCM's onMessage handler only reacts to a
        // 'refresh_profile' data type, and messaging_service.dart only
        // manages unread badge counts/caching, never a notification send.
        // Labeled honestly, matching the two toggles above.
        _ToggleTile(
          label: 'Messages',
          subtitle: 'Alerts for new direct messages · Coming soon',
          value: _notifMessages,
          onChanged: (v) {
            setState(() => _notifMessages = v);
            _saveBool('notif_messages', v);
          },
        ),
      ],
    );
  }

  // ── Display section ──────────────────────────────────────────────────────

  Widget _buildDisplaySection() {
    return _Section(
      icon: Icons.palette_outlined,
      iconColor: Colors.purple.shade600,
      title: 'Display',
      children: [
        _ToggleTile(
          label: 'Compact Recipe Cards',
          subtitle: 'Smaller cards, more visible at once',
          value: _useCompactCards,
          onChanged: (v) {
            setState(() => _useCompactCards = v);
            _saveBool('display_compact_cards', v);
          },
        ),
        _ToggleTile(
          label: 'Health Score Badges',
          subtitle: 'Show score color chip on recipe cards',
          value: _showHealthScoreBadges,
          onChanged: (v) {
            setState(() => _showHealthScoreBadges = v);
            _saveBool('display_health_badges', v);
          },
        ),
        _ToggleTile(
          label: 'Nutrition on Recipe Cards',
          subtitle: 'Show calorie & macro preview',
          value: _showNutritionOnCards,
          onChanged: (v) {
            setState(() => _showNutritionOnCards = v);
            _saveBool('display_nutrition_on_cards', v);
          },
        ),
      ],
    );
  }

  // ── Data Controls section (Section 14 addition) ─────────────────────────

  Widget _buildDataControlsSection() {
    return _Section(
      icon: Icons.storage_rounded,
      iconColor: Colors.teal.shade700,
      title: 'Data Controls',
      children: [
        _ActionTile(
          icon: Icons.ios_share_rounded,
          label: _exportingData ? 'Preparing export…' : 'Export My Data',
          onTap: _exportingData ? () {} : _exportLocalData,
        ),
        _ActionTile(
          icon: Icons.delete_sweep_rounded,
          label: _clearingData ? 'Clearing…' : 'Clear Local Data',
          labelColor: Colors.red.shade700,
          iconColor: Colors.red.shade700,
          onTap: _clearingData ? () {} : _showClearDataConfirmation,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'Export or clear data stored only on this device (Meal Planner, List Generator, and Health Trackers tab entries). Hydration, Supplement Schedule, Symptom Log, Alcohol Tracker, and Grocery List data live on our servers and are not affected.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ),
      ],
    );
  }

  // ── Support/About section (Section 14 addition) ─────────────────────────

  Widget _buildSupportSection() {
    return _Section(
      icon: Icons.help_outline_rounded,
      iconColor: Colors.indigo.shade600,
      title: 'Support & About',
      children: [
        _InfoTile(
          label: 'Version',
          value: _kAppVersion,
        ),
        _ActionTile(
          icon: Icons.email_outlined,
          label: 'Contact Support',
          onTap: _copySupportEmail,
        ),
        _ActionTile(
          icon: Icons.privacy_tip_outlined,
          label: 'Privacy Policy',
          onTap: () => _showComingSoon('Privacy Policy'),
        ),
        _ActionTile(
          icon: Icons.description_outlined,
          label: 'Terms of Use',
          onTap: () => _showComingSoon('Terms of Use'),
        ),
      ],
    );
  }
}

// ── Reusable section wrapper ─────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final List<Widget> children;

  const _Section({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
          child: Row(
            children: [
              Icon(icon, size: 15, color: iconColor),
              const SizedBox(width: 6),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: iconColor,
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

// ── Tile variants ────────────────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _InfoTile({
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
          ],
        ],
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? labelColor;
  final Color? iconColor;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.labelColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon,
          size: 20, color: iconColor ?? Colors.grey.shade700),
      title: Text(label,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: labelColor)),
      trailing: Icon(Icons.chevron_right,
          size: 18, color: Colors.grey.shade400),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      title: Text(label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      value: value,
      activeThumbColor: Colors.orange.shade600,
      onChanged: onChanged,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }
}