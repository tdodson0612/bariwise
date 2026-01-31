// lib/config/app_config.dart
// Complete configuration for BariWise app
// Uses environment variables from .env file for sensitive data

import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  // ============================================================
  // SUPABASE CONFIGURATION (Auth + Database)
  // ============================================================
  
  /// Supabase project URL (BariWise)
  static String get supabaseUrl => 
      dotenv.env['SUPABASE_URL'] ?? 'https://syetprqvxsrbdplieair.supabase.co';
  
  /// Supabase anonymous key for client-side auth (BariWise)
  static String get supabaseAnonKey => 
      dotenv.env['SUPABASE_ANON_KEY'] ?? 
      'sb_publishable_jhuOdV5_8qPn2ET9FZaFng_FqDtJHPj';

  // ============================================================
  // CLOUDFLARE WORKER CONFIGURATION (Single Unified Worker)
  // ============================================================
  
  /// BariWise Cloudflare Worker URL (unified worker)
  static String get cloudflareWorkerUrl => 
      dotenv.env['CLOUDFLARE_WORKER_URL'] ?? 
      'https://bariwise-worker.terryd0612.workers.dev';
  
  /// Database query endpoint
  static String get cloudflareWorkerQueryEndpoint => 
      '$cloudflareWorkerUrl/query';
  
  /// Storage endpoint for file uploads/downloads
  static String get cloudflareWorkerStorageEndpoint => 
      '$cloudflareWorkerUrl/storage';

  // ============================================================
  // GENERAL APP SETTINGS
  // ============================================================
  
  /// App display name
  static const String appName = 'BariWise';
  
  /// Production mode flag (set true for App Store builds)
  static const bool isProduction = false;
  
  /// App version (update this for each release)
  static const String appVersion = '1.0.0';

  // ============================================================
  // API CONFIGURATION
  // ============================================================
  
  /// OpenFoodFacts API base URL
  static const String openFoodFactsUrl = 
      'https://world.openfoodfacts.org/api/v0/product';
  
  /// API request timeout in seconds
  static const int apiTimeoutSeconds = 15;

  // ============================================================
  // FEATURE FLAGS
  // ============================================================
  
  /// Enable debug print statements
  static const bool enableDebugPrints = true;
  
  /// Enable ads in the app
  static const bool enableAds = true;
  
  /// Number of free scans before requiring premium
  static const int freeScanLimit = 3;
  
  /// Enable bariatric surgery tracking
  static const bool enableBariatricTracking = true;
  
  /// Enable weight tracking feature
  static const bool enableWeightTracking = true;

  // ============================================================
  // AD CONFIGURATION (Test IDs)
  // ============================================================
  
  /// Android interstitial ad ID (test mode)
  static const String androidInterstitialAdId = 
      'ca-app-pub-3940256099942544/1033173712';
  
  /// iOS interstitial ad ID (test mode)
  static const String iosInterstitialAdId = 
      'ca-app-pub-3940256099942544/4411468910';
  
  /// Android rewarded ad ID (test mode)
  static const String androidRewardedAdId = 
      'ca-app-pub-3940256099942544/5224354917';
  
  /// iOS rewarded ad ID (test mode)
  static const String iosRewardedAdId = 
      'ca-app-pub-3940256099942544/1712485313';

  // ============================================================
  // AD HELPERS
  // ============================================================
  
  /// Get platform-specific interstitial ad ID
  static String get interstitialAdId => androidInterstitialAdId;
  
  /// Get platform-specific rewarded ad ID
  static String get rewardedAdId => androidRewardedAdId;

  // ============================================================
  // TRACKER SETTINGS
  // ============================================================
  
  /// Number of days to calculate weekly averages
  static const int weeklyAverageDays = 7;
  
  /// Minimum days of tracking to show weekly stats
  static const int minDaysForWeeklyStats = 7;
  
  /// Days required for week-over-week comparison
  static const int daysForWeekComparison = 14;

  // ============================================================
  // CACHE SETTINGS
  // ============================================================
  
  /// Cache duration for profile data (in minutes)
  static const int profileCacheDuration = 30;
  
  /// Cache duration for recipes (in minutes)
  static const int recipeCacheDuration = 60;
  
  /// Cache duration for scan results (in minutes)
  static const int scanCacheDuration = 1440; // 24 hours

  // ============================================================
  // STORAGE KEYS (SharedPreferences)
  // ============================================================
  
  /// Key prefix for tracker data
  static const String trackerStoragePrefix = 'tracker_';
  
  /// Key for tracker disclaimer flag
  static const String trackerDisclaimerKey = 'tracker_disclaimer_shown';
  
  /// Key for day 7 popup flag
  static const String day7PopupKey = 'day7_popup_shown_';

  // ============================================================
  // UTILITY METHODS
  // ============================================================
  
  /// Print debug messages (only when debug mode enabled)
  static void debugPrint(String message) {
    if (enableDebugPrints) {
      // ignore: avoid_print
      print('[DEBUG] $message');
    }
  }
  
  /// Check if app is in development mode
  static bool get isDevelopment => !isProduction;
  
  /// Get full storage URL for a file path
  static String getStorageUrl(String path) {
    return '$cloudflareWorkerStorageEndpoint/$path';
  }
  
  /// Validate configuration on app startup
  static void validateConfig() {
    assert(supabaseUrl.isNotEmpty, 'Supabase URL is required');
    assert(supabaseAnonKey.isNotEmpty, 'Supabase anon key is required');
    assert(cloudflareWorkerUrl.isNotEmpty, 'Cloudflare Worker URL is required');
    
    if (enableDebugPrints) {
      debugPrint('✅ AppConfig validated successfully');
      debugPrint('🔧 Environment: ${isProduction ? "PRODUCTION" : "DEVELOPMENT"}');
      debugPrint('🔧 Worker: $cloudflareWorkerUrl');
      debugPrint('🏥 Bariatric tracking: ${enableBariatricTracking ? "ENABLED" : "DISABLED"}');
      debugPrint('⚖️ Weight tracking: ${enableWeightTracking ? "ENABLED" : "DISABLED"}');
    }
  }
}