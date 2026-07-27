// lib/services/premium_service.dart
// FIXED: Proper scan counting with no negative numbers
import 'package:shared_preferences/shared_preferences.dart';
import 'profile_service.dart';
import 'auth_service.dart';
import 'profile_data_access.dart';

class PremiumService {
  static const int freeDailyScans = 3;
  static const String scanCountKey = 'daily_scan_count';
  static const String lastScanDateKey = 'last_scan_date';

  // ==================================================
  // CHECK IF USER IS PREMIUM
  // ==================================================
  static Future<bool> isPremiumUser() async {
    if (!AuthService.isLoggedIn) return false;

    try {
      final profile = await ProfileService.getUserProfile(AuthService.currentUserId!);
      return profile?['is_premium'] ?? false;
    } catch (e) {

      return false;
    }
  }

  // ==================================================
  // CHECK ACCESS TO PREMIUM FEATURES
  // ==================================================
  static Future<bool> canAccessPremiumFeature() async {
    return await isPremiumUser();
  }

  // ==================================================
  // SET PREMIUM STATUS
  // ==================================================
  static Future<void> setPremiumStatus(bool isPremium) async {
    if (!AuthService.isLoggedIn) {
      throw Exception('User must be logged in to set premium status');
    }

    await ProfileDataAccess.setPremium(AuthService.currentUserId!, isPremium);
  }

  // ==================================================
  // REMAINING SCAN COUNT FOR FREE USERS
  // ==================================================
  static Future<int> getRemainingScanCount() async {
    final isPremium = await isPremiumUser();
    if (isPremium) return -1; // Unlimited

    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    final lastScanDate = prefs.getString(lastScanDateKey) ?? '';
    final currentCount = prefs.getInt(scanCountKey) ?? 0;

    // Reset at midnight for new day
    if (lastScanDate != today) {
      await prefs.setString(lastScanDateKey, today);
      await prefs.setInt(scanCountKey, 0);
      return freeDailyScans;
    }

    // ⭐ FIXED: Ensure we never return negative numbers
    final remaining = freeDailyScans - currentCount;
    return remaining.clamp(0, freeDailyScans);
  }

  // ==================================================
  // GET TOTAL SCANS USED TODAY
  // ==================================================
  static Future<int> getScansUsedToday() async {
    final isPremium = await isPremiumUser();
    if (isPremium) return 0; // Premium doesn't track usage

    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    final lastScanDate = prefs.getString(lastScanDateKey) ?? '';
    
    // Reset if new day
    if (lastScanDate != today) {
      return 0;
    }

    return prefs.getInt(scanCountKey) ?? 0;
  }

  // ==================================================
  // USE A SCAN (INCREMENT)
  // ==================================================
  static Future<bool> useScan() async {
    final isPremium = await isPremiumUser();
    if (isPremium) return true; // Unlimited scans

    final remaining = await getRemainingScanCount();
    if (remaining <= 0) return false;

    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    await prefs.setString(lastScanDateKey, today);
    
    final currentCount = prefs.getInt(scanCountKey) ?? 0;
    await prefs.setInt(scanCountKey, currentCount + 1);

    return true;
  }

  // Backward compatibility
  static Future<bool> incrementScanCount() async => await useScan();

  // ==================================================
  // ⭐ NEW: RESET SCAN COUNT (for testing or manual reset)
  // ==================================================
  static Future<void> resetDailyScanCount() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    await prefs.setString(lastScanDateKey, today);
    await prefs.setInt(scanCountKey, 0);
  }
}