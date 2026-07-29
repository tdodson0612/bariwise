// lib/widgets/app_drawer.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bari_wise/services/messaging_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../controllers/premium_gate_controller.dart';
import '../services/auth_service.dart';
import '../services/database_service_core.dart';
import '../config/app_config.dart';

class AppDrawer extends StatefulWidget {
  final String currentPage;

  const AppDrawer({
    super.key,
    required this.currentPage,
  });

  @override
  State<AppDrawer> createState() => AppDrawerState();

  static const String _cacheKey = 'cached_unread_count';
  static const String _cacheTimeKey = 'cached_unread_count_time';

  static final GlobalKey<AppDrawerState> globalKey =
      GlobalKey<AppDrawerState>();

  static Future<void> invalidateUnreadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheTimeKey);
      AppConfig.debugPrint('🔄 AppDrawer cache invalidated');
      await globalKey.currentState?.refresh();
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error invalidating AppDrawer cache: $e');
    }
  }
}

class AppDrawerState extends State<AppDrawer> with WidgetsBindingObserver {
  late final PremiumGateController _controller;
  int _unreadCount = 0;
  Timer? _autoRefreshTimer;

  static const Duration _cacheDuration = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _controller = PremiumGateController();
    _controller.addListener(_onPremiumStateChanged);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUnreadCount(forceRefresh: true);
    });
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _loadUnreadCount(forceRefresh: true);
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _controller.removeListener(_onPremiumStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadUnreadCount(forceRefresh: true);
    }
  }

  void _onPremiumStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> refresh() async {
    await _loadUnreadCount(forceRefresh: true);
  }

  Future<void> _loadUnreadCount({bool forceRefresh = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (!forceRefresh) {
        final cachedCount = prefs.getInt(AppDrawer._cacheKey);
        final cachedTime = prefs.getInt(AppDrawer._cacheTimeKey);
        if (cachedCount != null && cachedTime != null) {
          final cacheAge = DateTime.now().millisecondsSinceEpoch - cachedTime;
          if (cacheAge < _cacheDuration.inMilliseconds) {
            if (mounted) setState(() => _unreadCount = cachedCount);
            return;
          }
        }
      }

      final count = await MessagingService.getUnreadMessageCount();
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(AppDrawer._cacheKey, count);
      await prefs.setInt(AppDrawer._cacheTimeKey, now);
      if (mounted) setState(() => _unreadCount = count);
    } catch (e) {
      AppConfig.debugPrint('❌ AppDrawer: Error loading unread count: $e');
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedCount = prefs.getInt(AppDrawer._cacheKey);
        if (cachedCount != null && mounted) {
          setState(() => _unreadCount = cachedCount);
        } else if (mounted) {
          setState(() => _unreadCount = 0);
        }
      } catch (_) {
        if (mounted) setState(() => _unreadCount = 0);
      }
    }
  }

  // ── Navigation helper ──────────────────────────────────────────────────
  void _go(BuildContext context, String route) {
    Navigator.pop(context);
    if (widget.currentPage != route.replaceAll('/', '').replaceAll('-', '_')) {
      Navigator.pushNamed(context, route);
    }
  }

  // ── Tile builders ──────────────────────────────────────────────────────
  Widget _tile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String pageKey,
    required String route,
    Color? iconColor,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final isActive = widget.currentPage == pageKey;
    return ListTile(
      leading: Icon(
        icon,
        color: isActive ? Colors.orange : (iconColor ?? Colors.grey.shade700),
        size: 22,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          color: isActive ? Colors.orange : null,
          fontSize: 14,
        ),
      ),
      selected: isActive,
      selectedTileColor: Colors.orange.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      trailing: trailing,
      onTap: onTap ?? () => _go(context, route),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }

  Widget _lockedTile({
    required BuildContext context,
    required IconData icon,
    required String label,
  }) {
    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, color: Colors.grey.shade400, size: 22),
          Positioned(
            right: -6,
            bottom: -4,
            child: Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                color: Colors.amber,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock, size: 9, color: Colors.white),
            ),
          ),
        ],
      ),
      title: Row(
        children: [
          Text(label,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.amber.shade700,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'PRO',
              style: TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      onTap: () {
        Navigator.pop(context);
        Navigator.pushNamed(context, '/purchase');
      },
    );
  }

  Widget _sectionHeader(String label, {IconData? icon, Color? color}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color ?? Colors.grey.shade500),
            const SizedBox(width: 6),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: color ?? Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Main build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final userEmail = AuthService.currentUser?.email;
    final isPremium = _controller.isPremium;
    final isDev = AppConfig.isDevelopment;

    return Drawer(
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────
            _DrawerHeader(
              email: userEmail,
              isPremium: isPremium,
              scansUsed: _controller.totalScansUsed,
            ),

            // ── Scrollable nav list ────────────────────────────────────
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                children: [
                  // ── Main ──────────────────────────────────────────
                  _sectionHeader('Main'),
                  _tile(
                    context: context,
                    icon: Icons.home_rounded,
                    label: 'Home',
                    pageKey: 'home',
                    route: '/home',
                    onTap: () {
                      Navigator.pop(context);
                      if (widget.currentPage != 'home') {
                        Navigator.pushNamedAndRemoveUntil(
                            context, '/home', (route) => false);
                      }
                    },
                  ),
                  _tile(
                    context: context,
                    icon: Icons.person_rounded,
                    label: 'Profile',
                    pageKey: 'profile',
                    route: '/profile',
                  ),
                  _tile(
                    context: context,
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Messages',
                    pageKey: 'messages',
                    route: '/messages',
                    trailing: _unreadCount > 0
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _unreadCount > 99 ? '99+' : '$_unreadCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : null,
                    onTap: () async {
                      Navigator.pop(context);
                      if (widget.currentPage != 'messages') {
                        await Navigator.pushNamed(context, '/messages');
                        await Future.delayed(
                            const Duration(milliseconds: 800));
                        await MessagingService.refreshUnreadBadge();
                        if (mounted) {
                          await _loadUnreadCount(forceRefresh: true);
                        }
                      }
                    },
                  ),
                  _tile(
                    context: context,
                    icon: Icons.people_outline_rounded,
                    label: 'Find Friends',
                    pageKey: 'find_friends',
                    route: '/search-users',
                  ),
                  _tile(
                    context: context,
                    icon: Icons.bookmark_border_rounded,
                    label: 'Saved Posts',
                    pageKey: 'saved_posts',
                    route: '/saved-posts',
                  ),

                  // ── Nutrition & Scanning ───────────────────────────
                  _sectionHeader('Nutrition & Scanning'),
                  _tile(
                    context: context,
                    icon: Icons.monitor_heart_outlined,
                    label: 'Daily Tracker',
                    pageKey: 'tracker',
                    route: '/tracker',
                  ),
                  _tile(
                    context: context,
                    icon: Icons.search_rounded,
                    label: 'Search Nutrition',
                    pageKey: 'nutrition_search',
                    route: '/nutrition-search',
                  ),
                  _tile(
                    context: context,
                    icon: Icons.edit_outlined,
                    label: 'Enter Barcode',
                    pageKey: 'manual_barcode',
                    route: '/manual-barcode-entry',
                  ),

                  // ── Bariatric Health ───────────────────────────────
                  _sectionHeader(
                    'Bariatric Health',
                    icon: Icons.monitor_weight_rounded,
                    color: Colors.orange.shade700,
                  ),
                  _tile(
                    context: context,
                    icon: Icons.monitor_weight_rounded,
                    label: 'Bariatric Hub',
                    pageKey: 'bari_hub',
                    route: '/bari-hub',
                    iconColor: Colors.orange.shade700,
                  ),
                  _tile(
                    context: context,
                    icon: Icons.water_drop_rounded,
                    label: 'Hydration Log',
                    pageKey: 'hydration_log',
                    route: '/hydration-log',
                    iconColor: Colors.blue.shade600,
                  ),
                  _tile(
                    context: context,
                    icon: Icons.medication_rounded,
                    label: 'Supplements',
                    pageKey: 'supplement_schedule',
                    route: '/supplement-schedule',
                    iconColor: Colors.teal.shade600,
                  ),
                  _tile(
                    context: context,
                    icon: Icons.sick_rounded,
                    label: 'Symptom Log',
                    pageKey: 'symptom_log',
                    route: '/symptom-log',
                    iconColor: Colors.red.shade400,
                  ),
                  _tile(
                    context: context,
                    icon: Icons.bar_chart_rounded,
                    label: 'Progress Dashboard',
                    pageKey: 'bari_dashboard',
                    route: '/bari-dashboard',
                    iconColor: Colors.purple.shade600,
                  ),
                  _tile(
                    context: context,
                    icon: Icons.liquor_rounded,
                    label: 'Alcohol Log',
                    pageKey: 'alcohol_log',
                    route: '/alcohol-log',
                    iconColor: Colors.indigo.shade400,
                  ),

                  // ── Recipes ────────────────────────────────────────
                  _sectionHeader('Recipes'),
                  if (isPremium) ...[
                    _tile(
                      context: context,
                      icon: Icons.favorite_border_rounded,
                      label: 'Favorite Recipes',
                      pageKey: 'favorite_recipes',
                      route: '/favorite-recipes',
                    ),
                    _tile(
                      context: context,
                      icon: Icons.menu_book_rounded,
                      label: 'My Cookbook',
                      pageKey: 'my_cookbook',
                      route: '/my-cookbook',
                    ),
                    _tile(
                      context: context,
                      icon: Icons.add_circle_outline_rounded,
                      label: 'Submit Recipe',
                      pageKey: 'submit_recipe',
                      route: '/submit-recipe',
                    ),
                  ] else ...[
                    _lockedTile(
                      context: context,
                      icon: Icons.favorite_border_rounded,
                      label: 'Favorite Recipes',
                    ),
                    _lockedTile(
                      context: context,
                      icon: Icons.menu_book_rounded,
                      label: 'My Cookbook',
                    ),
                    _lockedTile(
                      context: context,
                      icon: Icons.add_circle_outline_rounded,
                      label: 'Submit Recipe',
                    ),
                  ],

                  // ── Shopping ───────────────────────────────────────
                  _sectionHeader('Shopping'),
                  if (isPremium) ...[
                    _tile(
                      context: context,
                      icon: Icons.shopping_cart_outlined,
                      label: 'Grocery List',
                      pageKey: 'grocery_list',
                      route: '/grocery-list',
                    ),
                    _tile(
                      context: context,
                      icon: Icons.bookmark_added_rounded,
                      label: 'Saved Ingredients',
                      pageKey: 'saved_ingredients',
                      route: '/saved-ingredients',
                    ),
                  ] else ...[
                    _lockedTile(
                      context: context,
                      icon: Icons.shopping_cart_outlined,
                      label: 'Grocery List',
                    ),
                    _lockedTile(
                      context: context,
                      icon: Icons.bookmark_added_rounded,
                      label: 'Saved Ingredients',
                    ),
                  ],

                  // ── Developer Tools (dev mode only) ────────────────
                  if (isDev) ...[
                    _sectionHeader(
                      'Developer Tools',
                      icon: Icons.code_rounded,
                      color: Colors.deepPurple.shade400,
                    ),
                    _tile(
                      context: context,
                      icon: Icons.psychology_rounded,
                      label: 'LoRA Dataset Manager',
                      pageKey: 'lora_dataset',
                      route: '/lora-dataset',
                      iconColor: Colors.deepPurple.shade600,
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'DEV',
                          style: TextStyle(
                            color: Colors.deepPurple.shade800,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],

                  // ── Account ────────────────────────────────────────
                  _sectionHeader('Account'),
                  _tile(
                    context: context,
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    pageKey: 'settings',
                    route: '/settings',
                  ),
                  _tile(
                    context: context,
                    icon: isPremium
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    label: isPremium
                        ? 'Premium Active'
                        : 'Upgrade to Premium',
                    pageKey: 'purchase',
                    route: '/purchase',
                    iconColor:
                        isPremium ? Colors.amber : Colors.grey.shade700,
                    trailing: isPremium
                        ? const Icon(Icons.check_circle,
                            color: Colors.orange, size: 18)
                        : const Icon(Icons.arrow_forward_ios,
                            size: 14, color: Colors.grey),
                  ),
                  _tile(
                    context: context,
                    icon: Icons.mail_outline_rounded,
                    label: 'Contact Us',
                    pageKey: 'contact',
                    route: '/contact',
                  ),

                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 4),

                  // Sign out
                  ListTile(
                    leading: const Icon(Icons.logout_rounded,
                        color: Colors.red, size: 22),
                    title: const Text(
                      'Sign Out',
                      style: TextStyle(
                          color: Colors.red,
                          fontSize: 14,
                          fontWeight: FontWeight.w500),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    onTap: () => _showSignOutDialog(context),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Sign out ───────────────────────────────────────────────────────────
  void _showSignOutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _performLogout(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  Future<void> _performLogout(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (loadingContext) => PopScope(
        canPop: false,
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Signing out...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_route');
      await AuthService.signOut();
      await prefs.clear();
      await DatabaseServiceCore.clearAllUserCache();
      if (context.mounted) Navigator.of(context).pop();
      if (context.mounted) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      AppConfig.debugPrint('Error during logout: $e');
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error signing out. Please try again.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }
}

// ── Drawer header ──────────────────────────────────────────────────────────
class _DrawerHeader extends StatelessWidget {
  final String? email;
  final bool isPremium;
  final int scansUsed;

  const _DrawerHeader({
    required this.email,
    required this.isPremium,
    required this.scansUsed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.orange.shade800, Colors.orange.shade600],
        ),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20,
        right: 20,
        bottom: 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white38, width: 1.5),
            ),
            child: const Icon(Icons.monitor_weight_rounded,
                color: Colors.white, size: 26),
          ),
          const SizedBox(height: 12),

          const Text(
            'BariWise',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),

          if (email != null) ...[
            const SizedBox(height: 2),
            Text(
              email!,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ],

          const SizedBox(height: 10),

          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isPremium
                      ? Colors.amber.shade600
                      : Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPremium ? Icons.star_rounded : Icons.person_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isPremium ? 'Premium' : 'Free Account',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isPremium) ...[
                const SizedBox(width: 8),
                Text(
                  '$scansUsed/3 scans used',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}