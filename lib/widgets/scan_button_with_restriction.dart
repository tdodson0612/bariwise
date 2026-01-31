// lib/widgets/scan_button_with_restrictions.dart - OPTIMIZED: Reduced database calls
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/premium_service.dart';
import '../services/auth_service.dart';

class ScanButtonWithRestriction extends StatelessWidget {
  final VoidCallback onScanAllowed;
  final Widget child;

  const ScanButtonWithRestriction({
    super.key,
    required this.onScanAllowed,
    required this.child,
  });

  static const String _scanCountKey = 'daily_scan_count';
  static const String _scanDateKey = 'daily_scan_date';
  static const String _premiumCacheKey = 'is_premium_cached';
  static const String _premiumCacheTimeKey = 'premium_cache_time';
  static const Duration _premiumCacheDuration = Duration(minutes: 5);

  /// Check if premium status from cache is still valid
  Future<bool?> _getCachedPremiumStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isPremium = prefs.getBool(_premiumCacheKey);
      final cacheTime = prefs.getInt(_premiumCacheTimeKey);
      
      if (isPremium != null && cacheTime != null) {
        final cacheAge = DateTime.now().millisecondsSinceEpoch - cacheTime;
        if (cacheAge < _premiumCacheDuration.inMilliseconds) {
          return isPremium;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Cache premium status
  Future<void> _cachePremiumStatus(bool isPremium) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_premiumCacheKey, isPremium);
      await prefs.setInt(_premiumCacheTimeKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      print('Error caching premium status: $e');
    }
  }

  /// Get or verify premium status with caching
  Future<bool> _checkPremiumStatus() async {
    // Try cache first
    final cached = await _getCachedPremiumStatus();
    if (cached != null) {
      return cached;
    }
    
    // Cache miss or stale, check with service
    final isPremium = await PremiumService.canAccessPremiumFeature();
    await _cachePremiumStatus(isPremium);
    return isPremium;
  }

  /// Check local scan count before hitting database
  Future<bool> _canScanLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check if user is premium (cached)
      final isPremium = await _checkPremiumStatus();
      if (isPremium) {
        return true; // Premium users have unlimited scans
      }
      
      // For free users, check local scan count
      final today = DateTime.now().toIso8601String().split('T')[0];
      final savedDate = prefs.getString(_scanDateKey);
      
      // Reset count if it's a new day
      if (savedDate != today) {
        await prefs.setString(_scanDateKey, today);
        await prefs.setInt(_scanCountKey, 0);
        return true;
      }
      
      // Check if under limit
      final scanCount = prefs.getInt(_scanCountKey) ?? 0;
      return scanCount < 3; // Free tier limit
      
    } catch (e) {
      print('Error checking local scan count: $e');
      return false;
    }
  }

  /// Increment local scan count
  Future<void> _incrementScanCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scanCount = prefs.getInt(_scanCountKey) ?? 0;
      await prefs.setInt(_scanCountKey, scanCount + 1);
    } catch (e) {
      print('Error incrementing scan count: $e');
    }
  }

  Future<void> _handleScanTap(BuildContext context) async {
    if (!AuthService.isLoggedIn) {
      _showLoginDialog(context);
      return;
    }

    // First check locally to avoid database call
    final canScanLocal = await _canScanLocally();
    if (!canScanLocal) {
      _showScanLimitDialog(context);
      return;
    }

    // Verify with server and actually use a scan
    final canScan = await PremiumService.useScan();
    if (!canScan) {
      _showScanLimitDialog(context);
      return;
    }

    // Increment local count for free users
    final isPremium = await _checkPremiumStatus();
    if (!isPremium) {
      await _incrementScanCount();
    }

    onScanAllowed();
  }

  void _showLoginDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Login Required'),
        content: Text('Please sign in to scan products.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/login');
            },
            child: Text('Sign In'),
          ),
        ],
      ),
    );
  }

  void _showScanLimitDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.star, color: Colors.amber),
            SizedBox(width: 8),
            Text('Daily Limit Reached'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You\'ve reached your daily scan limit.'),
            SizedBox(height: 12),
            Text('Upgrade to Premium for:', 
              style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('• Unlimited daily scans'),
            Text('• Full recipe access'),
            Text('• Personal grocery list'),
            Text('• Priority support'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Maybe Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/premium');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.white,
            ),
            child: Text('Upgrade Now'),
          ),
        ],
      ),
    );
  }

  /// Invalidate premium cache (call when user upgrades/downgrades)
  static Future<void> invalidatePremiumCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_premiumCacheKey);
    await prefs.remove(_premiumCacheTimeKey);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _handleScanTap(context),
      child: child,
    );
  }
}