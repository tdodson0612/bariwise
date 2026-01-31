// lib/widgets/menu_icon_with_badge.dart
// ✅ HOTFIX: Force refresh on every build + auto-refresh timer

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bari_wise/services/messaging_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MenuIconWithBadge extends StatefulWidget {
  const MenuIconWithBadge({super.key});

  @override
  State<MenuIconWithBadge> createState() => _MenuIconWithBadgeState();
  
  static const String _cacheKey = 'cached_unread_count';
  static const String _cacheTimeKey = 'cached_unread_count_time';
  
  static final GlobalKey<_MenuIconWithBadgeState> globalKey = GlobalKey<_MenuIconWithBadgeState>();
  
  static Future<void> invalidateCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheTimeKey);
      
      print('🔄 MenuIcon cache invalidated');
      
      // Force immediate refresh
      globalKey.currentState?.refresh();
    } catch (e) {
      print('⚠️ Error invalidating MenuIcon cache: $e');
    }
  }
}

class _MenuIconWithBadgeState extends State<MenuIconWithBadge> with WidgetsBindingObserver {
  int _unreadCount = 0;
  bool _isLoading = false;
  Timer? _autoRefreshTimer;
  
  // ✅ HOTFIX: Reduced cache duration to 2 seconds
  static const Duration _cacheDuration = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Load immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUnreadCount(forceRefresh: true);
    });
    
    // ✅ HOTFIX: Auto-refresh every 3 seconds
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) {
        if (mounted) {
          print('⏰ Auto-refresh timer triggered for MenuIcon');
          _loadUnreadCount(forceRefresh: true);
        }
      },
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print('📱 App resumed, refreshing MenuIcon badge...');
      _loadUnreadCount(forceRefresh: true);
    }
  }

  // Public refresh method
  Future<void> refresh() async {
    print('🔄 MenuIcon.refresh() called - forcing full reload');
    await _loadUnreadCount(forceRefresh: true);
  }

  Future<void> _loadUnreadCount({bool forceRefresh = false}) async {
    if (_isLoading && !forceRefresh) {
      print('⏭️ MenuIcon already loading, skipping...');
      return;
    }

    try {
      setState(() => _isLoading = true);

      final prefs = await SharedPreferences.getInstance();
      
      // Check cache freshness
      if (!forceRefresh) {
        final cachedCount = prefs.getInt(MenuIconWithBadge._cacheKey);
        final cachedTime = prefs.getInt(MenuIconWithBadge._cacheTimeKey);
        
        if (cachedCount != null && cachedTime != null) {
          final cacheAge = DateTime.now().millisecondsSinceEpoch - cachedTime;
          final isCacheValid = cacheAge < _cacheDuration.inMilliseconds;
          
          if (isCacheValid) {
            if (mounted) {
              setState(() {
                _unreadCount = cachedCount;
                _isLoading = false;
              });
            }
            print('✅ MenuIcon: Using valid cache: $cachedCount (${(cacheAge / 1000).toStringAsFixed(1)}s old)');
            return;
          } else {
            print('⏰ MenuIcon: Cache STALE (${(cacheAge / 1000).toStringAsFixed(1)}s old) - refreshing...');
          }
        } else {
          print('❌ MenuIcon: No cache found - fetching fresh...');
        }
      } else {
        print('🔄 MenuIcon: Force refresh requested');
      }
      
      // Fetch fresh count
      print('📡 MenuIcon: Fetching from MessagingService.getUnreadMessageCount()...');
      final count = await MessagingService.getUnreadMessageCount();
      
      // Save to cache with current timestamp
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(MenuIconWithBadge._cacheKey, count);
      await prefs.setInt(MenuIconWithBadge._cacheTimeKey, now);
      
      if (mounted) {
        setState(() {
          _unreadCount = count;
          _isLoading = false;
        });
      }
      
      print('✅ MenuIcon: Fresh count = $count (cached at $now)');
      
    } catch (e) {
      print('❌ MenuIcon: Error loading unread count: $e');
      
      // Try to use stale cache on error
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedCount = prefs.getInt(MenuIconWithBadge._cacheKey);
        if (cachedCount != null && mounted) {
          setState(() {
            _unreadCount = cachedCount;
            _isLoading = false;
          });
          print('⚠️ MenuIcon: Using stale cache due to error: $cachedCount');
        } else {
          if (mounted) {
            setState(() {
              _unreadCount = 0;
              _isLoading = false;
            });
          }
        }
      } catch (_) {
        print('❌ MenuIcon: Could not load cached count');
        if (mounted) {
          setState(() {
            _unreadCount = 0;
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.menu),
        if (_unreadCount > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              constraints: const BoxConstraints(
                minWidth: 16,
                minHeight: 16,
              ),
              child: Text(
                _unreadCount > 9 ? '9+' : '$_unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}