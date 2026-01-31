// lib/config/environment.dart - Secure environment variable management
import 'package:flutter/foundation.dart';
import 'dart:io';

/// Environment configuration class that handles all sensitive keys and settings
/// This replaces all hardcoded keys throughout the app for security
class Environment {
  // Private constructor to prevent instantiation
  Environment._();

  /// Environment types
  static const String development = 'development';
  static const String staging = 'staging';
  static const String production = 'production';

  /// Current environment - defaults to development
  static String get currentEnvironment {
    return const String.fromEnvironment('ENVIRONMENT', defaultValue: development);
  }

  /// Check if running in production
  static bool get isProduction => currentEnvironment == production;

  /// Check if running in development
  static bool get isDevelopment => currentEnvironment == development;

  /// Check if running in staging
  static bool get isStaging => currentEnvironment == staging;

  // =============================================================================
  // SUPABASE CONFIGURATION
  // =============================================================================
  
  /// Supabase URL - CRITICAL: Replace hardcoded value in main.dart
  static String get supabaseUrl {
    const url = String.fromEnvironment('SUPABASE_URL');
    if (url.isEmpty) {
      if (kDebugMode) {
        print('WARNING: SUPABASE_URL not set, using fallback');
        // Only provide fallback in development
        return isDevelopment 
            ? 'YOUR_DEV_SUPABASE_URL_HERE'
            : throw Exception('SUPABASE_URL environment variable is required');
      }
      throw Exception('SUPABASE_URL environment variable is required');
    }
    return url;
  }

  /// Supabase Anonymous Key - CRITICAL: Replace hardcoded value in main.dart
  static String get supabaseAnonKey {
    const key = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (key.isEmpty) {
      if (kDebugMode) {
        print('WARNING: SUPABASE_ANON_KEY not set, using fallback');
        // Only provide fallback in development
        return isDevelopment 
            ? 'YOUR_DEV_SUPABASE_ANON_KEY_HERE'
            : throw Exception('SUPABASE_ANON_KEY environment variable is required');
      }
      throw Exception('SUPABASE_ANON_KEY environment variable is required');
    }
    return key;
  }

  // =============================================================================
  // GOOGLE ADMOB CONFIGURATION
  // =============================================================================

  /// AdMob App ID
  static String get admobAppId {
    if (Platform.isAndroid) {
      return const String.fromEnvironment(
        'ADMOB_ANDROID_APP_ID',
        defaultValue: 'ca-app-pub-3940256099942544~3347511713', // Test ID
      );
    } else if (Platform.isIOS) {
      return const String.fromEnvironment(
        'ADMOB_IOS_APP_ID',
        defaultValue: 'ca-app-pub-3940256099942544~1458002511', // Test ID
      );
    }
    return '';
  }

  /// Interstitial Ad Unit ID
  static String get interstitialAdUnitId {
    if (isProduction) {
      // Production ad unit IDs
      if (Platform.isAndroid) {
        return const String.fromEnvironment('ADMOB_ANDROID_INTERSTITIAL_ID');
      } else if (Platform.isIOS) {
        return const String.fromEnvironment('ADMOB_IOS_INTERSTITIAL_ID');
      }
    }
    
    // Test ad unit IDs for development/staging
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/1033173712';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/4411468910';
    }
    
    return '';
  }

  /// Rewarded Ad Unit ID
  static String get rewardedAdUnitId {
    if (isProduction) {
      // Production ad unit IDs
      if (Platform.isAndroid) {
        return const String.fromEnvironment('ADMOB_ANDROID_REWARDED_ID');
      } else if (Platform.isIOS) {
        return const String.fromEnvironment('ADMOB_IOS_REWARDED_ID');
      }
    }
    
    // Test ad unit IDs for development/staging
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/5224354917';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/1712485313';
    }
    
    return '';
  }

  /// Banner Ad Unit ID
  static String get bannerAdUnitId {
    if (isProduction) {
      // Production ad unit IDs
      if (Platform.isAndroid) {
        return const String.fromEnvironment('ADMOB_ANDROID_BANNER_ID');
      } else if (Platform.isIOS) {
        return const String.fromEnvironment('ADMOB_IOS_BANNER_ID');
      }
    }
    
    // Test ad unit IDs for development/staging
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/6300978111';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/2934735716';
    }
    
    return '';
  }

  // =============================================================================
  // API CONFIGURATION
  // =============================================================================

  /// OpenFoodFacts API Base URL
  static String get openFoodFactsApiUrl {
    return const String.fromEnvironment(
      'OPENFOODFACTS_API_URL',
      defaultValue: 'https://world.openfoodfacts.org/api/v0/product',
    );
  }

  /// API Timeout in seconds
  static int get apiTimeoutSeconds {
    return const int.fromEnvironment('API_TIMEOUT_SECONDS', defaultValue: 15);
  }

  /// Maximum retry attempts for API calls
  static int get maxRetryAttempts {
    return const int.fromEnvironment('MAX_RETRY_ATTEMPTS', defaultValue: 3);
  }

  // =============================================================================
  // APP CONFIGURATION
  // =============================================================================

  /// App name
  static String get appName {
    return const String.fromEnvironment('APP_NAME', defaultValue: 'Recipe Scanner');
  }

  /// App version
  static String get appVersion {
    return const String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');
  }

  /// Enable debug logging
  static bool get enableDebugLogging {
    const envValue = bool.fromEnvironment('ENABLE_DEBUG_LOGGING');
    const hasEnvValue = bool.hasEnvironment('ENABLE_DEBUG_LOGGING');
    if (hasEnvValue) return envValue;
    return currentEnvironment != production; // Default: true except in production
  }

  /// Enable crash reporting
  static bool get enableCrashReporting {
    const envValue = bool.fromEnvironment('ENABLE_CRASH_REPORTING');
    const hasEnvValue = bool.hasEnvironment('ENABLE_CRASH_REPORTING');
    if (hasEnvValue) return envValue;
    return currentEnvironment == production; // Default: true only in production
  }

  /// Free user scan limit
  static int get freeScanLimit {
    return const int.fromEnvironment('FREE_SCAN_LIMIT', defaultValue: 3);
  }

  /// Premium user scan limit (unlimited = -1)
  static int get premiumScanLimit {
    return const int.fromEnvironment('PREMIUM_SCAN_LIMIT', defaultValue: -1);
  }

  // =============================================================================
  // FEATURE FLAGS
  // =============================================================================

  /// Enable premium features
  static bool get enablePremiumFeatures {
    return const bool.fromEnvironment('ENABLE_PREMIUM_FEATURES', defaultValue: true);
  }

  /// Enable social features
  static bool get enableSocialFeatures {
    return const bool.fromEnvironment('ENABLE_SOCIAL_FEATURES', defaultValue: true);
  }

  /// Enable ads
  static bool get enableAds {
    const envValue = bool.fromEnvironment('ENABLE_ADS');
    const hasEnvValue = bool.hasEnvironment('ENABLE_ADS');
    if (hasEnvValue) return envValue;
    return currentEnvironment != production; // Default: true except in production
  }

  /// Enable analytics
  static bool get enableAnalytics {
    const envValue = bool.fromEnvironment('ENABLE_ANALYTICS');
    const hasEnvValue = bool.hasEnvironment('ENABLE_ANALYTICS');
    if (hasEnvValue) return envValue;
    return currentEnvironment == production; // Default: true only in production
  }

  // =============================================================================
  // VALIDATION & INITIALIZATION
  // =============================================================================

  /// Validate that all required environment variables are set
  static void validateEnvironment() {
    final List<String> errors = [];

    // Check critical Supabase configuration
    try {
      supabaseUrl;
    } catch (e) {
      errors.add('SUPABASE_URL is required');
    }

    try {
      supabaseAnonKey;
    } catch (e) {
      errors.add('SUPABASE_ANON_KEY is required');
    }

    // Check production ad unit IDs if in production and ads are enabled
    if (isProduction && enableAds) {
      const androidInterstitial = String.fromEnvironment('ADMOB_ANDROID_INTERSTITIAL_ID');
      const iosInterstitial = String.fromEnvironment('ADMOB_IOS_INTERSTITIAL_ID');
      const androidRewarded = String.fromEnvironment('ADMOB_ANDROID_REWARDED_ID');
      const iosRewarded = String.fromEnvironment('ADMOB_IOS_REWARDED_ID');

      if (Platform.isAndroid && (androidInterstitial.isEmpty || androidRewarded.isEmpty)) {
        errors.add('Android AdMob unit IDs are required in production');
      }
      if (Platform.isIOS && (iosInterstitial.isEmpty || iosRewarded.isEmpty)) {
        errors.add('iOS AdMob unit IDs are required in production');
      }
    }

    if (errors.isNotEmpty) {
      final errorMessage = 'Environment validation failed:\n${errors.join('\n')}';
      if (kDebugMode) {
        print('ERROR: $errorMessage');
      }
      throw Exception(errorMessage);
    }

    // Log successful validation
    if (enableDebugLogging) {
      print('✅ Environment validation passed');
      print('📍 Current environment: $currentEnvironment');
      print('🔧 Debug logging: $enableDebugLogging');
      print('📊 Crash reporting: $enableCrashReporting');
      print('💰 Premium features: $enablePremiumFeatures');
      print('👥 Social features: $enableSocialFeatures');
      print('📱 Ads enabled: $enableAds');
    }
  }

  /// Initialize environment configuration
  /// Call this in main() before runApp()
  static Future<void> initialize() async {
    try {
      validateEnvironment();
      
      if (enableDebugLogging) {
        print('🚀 Environment initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Environment initialization failed: $e');
      }
      rethrow;
    }
  }

  // =============================================================================
  // UTILITY METHODS
  // =============================================================================

  /// Get all environment variables as a map (for debugging)
  static Map<String, dynamic> getAllConfig() {
    return {
      'environment': currentEnvironment,
      'isProduction': isProduction,
      'isDevelopment': isDevelopment,
      'isStaging': isStaging,
      'appName': appName,
      'appVersion': appVersion,
      'enableDebugLogging': enableDebugLogging,
      'enableCrashReporting': enableCrashReporting,
      'enablePremiumFeatures': enablePremiumFeatures,
      'enableSocialFeatures': enableSocialFeatures,
      'enableAds': enableAds,
      'enableAnalytics': enableAnalytics,
      'freeScanLimit': freeScanLimit,
      'premiumScanLimit': premiumScanLimit,
      'apiTimeoutSeconds': apiTimeoutSeconds,
      'maxRetryAttempts': maxRetryAttempts,
      // Don't include sensitive keys in debug output
      'supabaseUrlConfigured': supabaseUrl.isNotEmpty,
      'supabaseAnonKeyConfigured': supabaseAnonKey.isNotEmpty,
      'admobAppId': enableAds ? admobAppId : 'disabled',
    };
  }

  /// Print current configuration (safe for debugging)
  static void printConfig() {
    if (enableDebugLogging) {
      print('📋 Current Environment Configuration:');
      getAllConfig().forEach((key, value) {
        print('   $key: $value');
      });
    }
  }
}