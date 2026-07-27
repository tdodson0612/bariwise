// lib/pages/settings_page.dart
// User settings: notifications, account info, premium status, display theme.
// Route: '/settings'
// iOS 14 Compatible | Production Ready

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../services/premium_service.dart';
import '../widgets/app_drawer.dart';

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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
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

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This action is permanent and cannot be undone. '
          'All your data, recipes, and progress will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please contact support to delete your account.'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
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
        _ToggleTile(
          label: 'Weekly Progress Summary',
          subtitle: 'Bariatric health report every week',
          value: _notifWeeklyProgress,
          onChanged: (v) {
            setState(() => _notifWeeklyProgress = v);
            _saveBool('notif_weekly_progress', v);
          },
        ),
        _ToggleTile(
          label: 'Symptom Reminders',
          subtitle: 'Daily prompt to log how you feel',
          value: _notifSymptomReminders,
          onChanged: (v) {
            setState(() => _notifSymptomReminders = v);
            _saveBool('notif_symptom_reminders', v);
          },
        ),
        _ToggleTile(
          label: 'Hydration Reminders',
          subtitle: 'Hourly water intake nudges',
          value: _notifHydrationReminders,
          onChanged: (v) {
            setState(() => _notifHydrationReminders = v);
            _saveBool('notif_hydration_reminders', v);
          },
        ),
        _ToggleTile(
          label: 'New Recipe Suggestions',
          subtitle: 'When personalized recipes are available',
          value: _notifRecipeUpdates,
          onChanged: (v) {
            setState(() => _notifRecipeUpdates = v);
            _saveBool('notif_recipe_updates', v);
          },
        ),
        _ToggleTile(
          label: 'Messages',
          subtitle: 'Alerts for new direct messages',
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