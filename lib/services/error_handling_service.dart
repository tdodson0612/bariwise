// lib/services/error_handling_service.dart
//
// Centralized error handling service for the entire app.
// Apple-compliant: No technical jargon, user-friendly messages, retry options.
//
// 🔧 FIX: _isAuthError() was matching on 'token', 'session', and 'expired'
//    which are common substrings that appear in many unrelated Supabase /
//    HTTP error messages. This caused profile-creation failures, network
//    errors, and other non-auth errors to be misclassified, surfacing the
//    "Hmm, who are you?" dialog when the user hadn't done anything wrong.
//
//    The fix:
//      • _isAuthError() now requires more specific auth signals
//        (HTTP 401/403 codes, or explicit Supabase auth phrases).
//      • A dedicated _isProfileSetupError() category was added for the
//        signup profile-creation failure path.
//      • _isDatabaseError() no longer matches 'fetch' or 'query' — too broad.
//      • _isImageError() no longer matches 'image' or 'photo' — too broad.
//      • _isAdError() no longer matches bare 'ad' — too broad.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../logger.dart';
import '../widgets/bari_error_overlay.dart';

class ErrorHandlingService {
  static final ErrorHandlingService _instance =
      ErrorHandlingService._internal();
  factory ErrorHandlingService() => _instance;
  ErrorHandlingService._internal();

  // Error category constants
  static const String networkError = 'NETWORK_ERROR';
  static const String authError = 'AUTH_ERROR';
  static const String profileSetupError = 'PROFILE_SETUP_ERROR';
  static const String premiumError = 'PREMIUM_ERROR';
  static const String databaseError = 'DATABASE_ERROR';
  static const String scanError = 'SCAN_ERROR';
  static const String imageError = 'IMAGE_ERROR';
  static const String adError = 'AD_ERROR';
  static const String validationError = 'VALIDATION_ERROR';
  static const String initializationError = 'INITIALIZATION_ERROR';
  static const String navigationError = 'NAVIGATION_ERROR';
  static const String unknownError = 'UNKNOWN_ERROR';

  // --------------------------------------------------------
  // MAIN ENTRY POINT
  // --------------------------------------------------------

  static Future<void> handleError({
    required BuildContext context,
    required dynamic error,
    String? category,
    String? customMessage,
    bool showDialog = true,
    bool showSnackBar = false,
    VoidCallback? onRetry,
    VoidCallback? onCancel,
  }) async {
    try {
      final errorInfo = _categorizeError(error, category);
      await _logError(errorInfo, error);

      if (!context.mounted) return;

      if (showDialog) {
        _showErrorDialog(
          context: context,
          errorInfo: errorInfo,
          customMessage: customMessage,
          onRetry: onRetry,
          onCancel: onCancel,
        );
      }

      if (showSnackBar) {
        _showErrorSnackBar(
          context: context,
          errorInfo: errorInfo,
          customMessage: customMessage,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error handler failed: $e');
      if (context.mounted) _showFallbackError(context);
    }
  }

  // --------------------------------------------------------
  // ERROR CATEGORIZATION
  // --------------------------------------------------------

  static ErrorInfo _categorizeError(dynamic error, String? category) {
    final s = error.toString().toLowerCase();

    // Network / connection issues — check first (broad but safe)
    if (_isNetworkError(s) || category == networkError) {
      return ErrorInfo(
        category: networkError,
        title: 'Oopsie! Lost connection',
        message:
            'Looks like the internet got shy! Can you check your WiFi?',
        userMessage: 'I need the internet to help you stay healthy! 🌐',
        icon: Icons.wifi_off_rounded,
        color: Colors.orange,
        canRetry: true,
        isUserFacingError: true,
      );
    }

    // ⚠️ Auth errors — must be SPECIFIC.
    // Do NOT match generic words like 'failed', 'error', 'token', 'session'.
    // Those appear in database, network, and profile errors too.
    if (_isAuthError(s) || category == authError) {
      return ErrorInfo(
        category: authError,
        title: 'Hmm, who are you?',
        message:
            'I don\'t recognize you! Let\'s log in again so I know it\'s really you.',
        userMessage:
            'Your login might have timed out - happens to the best of us! 😊',
        icon: Icons.lock_outline_rounded,
        color: Colors.blue,
        canRetry: false,
        redirectRoute: '/login',
        isUserFacingError: true,
      );
    }

    // Profile setup errors (signup only)
    if (_isProfileSetupError(s) || category == profileSetupError) {
      return ErrorInfo(
        category: profileSetupError,
        title: 'Almost there!',
        message:
            'Your account was created but we had trouble finishing setup. '
            'Please sign in and we\'ll sort it out!',
        userMessage:
            'If this keeps happening, try the "Clear Session" button on the login screen. 🔄',
        icon: Icons.person_add_alt_1_rounded,
        color: Colors.teal,
        canRetry: false,
        redirectRoute: '/login',
        isUserFacingError: true,
      );
    }

    // Premium features
    if (_isPremiumError(s) || category == premiumError) {
      return ErrorInfo(
        category: premiumError,
        title: 'This is a VIP feature!',
        message:
            'Want unlimited scans? Upgrade to Premium and I\'ll be your personal health buddy! ⭐',
        userMessage: 'Premium unlocks ALL my best features!',
        icon: Icons.star_rounded,
        color: Colors.amber,
        canRetry: false,
        redirectRoute: '/purchase',
        isUserFacingError: true,
      );
    }

    // Database / sync issues
    if (_isDatabaseError(s) || category == databaseError) {
      return ErrorInfo(
        category: databaseError,
        title: 'Uh oh, sync hiccup!',
        message:
            'I tried to grab your data but got a little mixed up. Let\'s try that again!',
        userMessage: 'Sometimes I need a second to catch my breath! 💨',
        icon: Icons.sync_problem_rounded,
        color: Colors.red.shade400,
        canRetry: true,
        isUserFacingError: true,
      );
    }

    // Barcode scanning
    if (_isScanError(s) || category == scanError) {
      return ErrorInfo(
        category: scanError,
        title: 'Couldn\'t read that!',
        message:
            'That barcode was a bit blurry for me! Try again with better lighting?',
        userMessage: 'Make sure the barcode is nice and clear - I\'m trying my best! 🔍',
        icon: Icons.qr_code_scanner_rounded,
        color: Colors.purple,
        canRetry: true,
        isUserFacingError: true,
      );
    }

    // Camera / image
    if (_isImageError(s) || category == imageError) {
      return ErrorInfo(
        category: imageError,
        title: 'Camera shy?',
        message:
            'I need to use your camera, but it\'s blocked! Can you let me in through Settings?',
        userMessage: 'Pretty please? I promise to only take healthy pics! 📸',
        icon: Icons.camera_alt_rounded,
        color: Colors.indigo,
        canRetry: true,
        redirectRoute: null,
        isUserFacingError: true,
      );
    }

    // Ad loading (silent)
    if (_isAdError(s) || category == adError) {
      return ErrorInfo(
        category: adError,
        title: 'Ad Unavailable',
        message: 'Continuing without ad.',
        userMessage: 'You can continue using the app.',
        icon: Icons.ad_units_rounded,
        color: Colors.grey,
        canRetry: false,
        isUserFacingError: false,
      );
    }

    // Validation
    if (_isValidationError(s) || category == validationError) {
      return ErrorInfo(
        category: validationError,
        title: 'Whoopsie!',
        message:
            'Some of that info doesn\'t look quite right. Double check and try again?',
        userMessage: 'I\'m picky about details - helps me keep you healthy! 📝',
        icon: Icons.error_outline_rounded,
        color: Colors.orange,
        canRetry: false,
        isUserFacingError: true,
      );
    }

    // Initialization
    if (_isInitializationError(s) || category == initializationError) {
      return ErrorInfo(
        category: initializationError,
        title: 'Starting up...',
        message: 'I got a little dizzy on startup! Mind if we restart?',
        userMessage:
            'Just close me and open me back up - I\'ll be ready! 🔄',
        icon: Icons.refresh_rounded,
        color: Colors.blue,
        canRetry: true,
        isUserFacingError: true,
      );
    }

    // Navigation
    if (_isNavigationError(s) || category == navigationError) {
      return ErrorInfo(
        category: navigationError,
        title: 'Lost my way!',
        message:
            'That page wandered off somewhere! Let me take you back home.',
        userMessage: 'Home is where the health is! 🏠',
        icon: Icons.home_rounded,
        color: Colors.teal,
        canRetry: false,
        redirectRoute: '/home',
        isUserFacingError: true,
      );
    }

    // Unknown / unexpected
    return ErrorInfo(
      category: unknownError,
      title: 'Well, that\'s awkward...',
      message:
          'Something weird just happened and I\'m not quite sure what! Wanna try again?',
      userMessage: 'If this keeps happening, try giving me a restart! 🤔',
      icon: Icons.error_outline_rounded,
      color: Colors.red.shade400,
      canRetry: true,
      isUserFacingError: true,
    );
  }

  // --------------------------------------------------------
  // ERROR DETECTION HELPERS
  // --------------------------------------------------------

  static bool _isNetworkError(String s) {
    return s.contains('socket') ||
        s.contains('timeout') ||
        s.contains('network') ||
        s.contains('connection') ||
        s.contains('internet') ||
        s.contains('unreachable') ||
        s.contains('failed host lookup') ||
        s.contains('no address associated') ||
        (s.contains('http') && s.contains('exception'));
  }

  /// Auth errors must be SPECIFIC to avoid false positives.
  ///
  /// ❌ Do NOT add: 'token', 'session', 'expired', 'failed', 'error'
  ///    These appear in many non-auth error messages and would cause
  ///    the "Hmm, who are you?" dialog to show for unrelated problems.
  ///
  /// ✅ DO match: explicit HTTP status codes, Supabase error phrases,
  ///    and the exact strings Supabase auth returns.
  static bool _isAuthError(String s) {
    return s.contains('invalid login credentials') ||
        s.contains('invalid email or password') ||
        s.contains('email not confirmed') ||
        s.contains('invalid grant') ||
        s.contains('refresh_token') ||
        s.contains('not authenticated') ||
        s.contains('jwt') ||
        s.contains('unauthorized') ||
        // HTTP status codes as strings (from worker error messages)
        s.contains('status: 401') ||
        s.contains('status: 403') ||
        s.contains('(401)') ||
        s.contains('(403)') ||
        // Supabase-specific phrases
        s.contains('user not found') ||
        s.contains('login has expired');
  }

  /// Profile setup failures during signup (distinct from auth errors).
  static bool _isProfileSetupError(String s) {
    return s.contains('profile setup failed') ||
        s.contains('failed to create user profile') ||
        s.contains('profile creation failed') ||
        s.contains('finish setting up your profile');
  }

  static bool _isPremiumError(String s) {
    return s.contains('premium') ||
        s.contains('subscription') ||
        s.contains('upgrade') ||
        s.contains('limit reached') ||
        s.contains('scan limit');
  }

  /// Database errors — deliberately narrower than before.
  /// Removed 'fetch' and 'query' as they appear in too many innocent contexts.
  static bool _isDatabaseError(String s) {
    return s.contains('database') ||
        s.contains('supabase') ||
        s.contains('postgrest') ||
        s.contains('row-level security') ||
        s.contains('rls') ||
        s.contains('worker query failed') ||
        s.contains('failed to execute worker');
  }

  static bool _isScanError(String s) {
    return s.contains('barcode') ||
        s.contains('scan') ||
        s.contains('mlkit') ||
        s.contains('product not found') ||
        s.contains('no barcode found');
  }

  /// Image errors — deliberately narrower than before.
  /// Removed 'image' and 'photo' as they're too broad (e.g. "profile image
  /// upload failed" for a database error would wrongly match).
  static bool _isImageError(String s) {
    return s.contains('camera') ||
        s.contains('image picker') ||
        s.contains('pickimage') ||
        s.contains('picker') ||
        s.contains('permission denied') ||
        s.contains('access denied');
  }

  /// Ad errors — bare 'ad' deliberately removed, too short and matches
  /// unrelated words like 'upload', 'read', 'admin', etc.
  static bool _isAdError(String s) {
    return s.contains('admob') ||
        s.contains('interstitial') ||
        s.contains('rewarded');
  }

  static bool _isValidationError(String s) {
    return s.contains('validation') ||
        s.contains('invalid') ||
        s.contains('required field') ||
        s.contains('format');
  }

  static bool _isInitializationError(String s) {
    return s.contains('initialization') ||
        s.contains('initialize') ||
        s.contains('startup') ||
        s.contains('init failed') ||
        s.contains('bootstrap');
  }

  static bool _isNavigationError(String s) {
    return s.contains('navigation') ||
        s.contains('navigator') ||
        s.contains('page not found') ||
        s.contains('could not find');
  }

  // --------------------------------------------------------
  // DIALOG / SNACKBAR
  // --------------------------------------------------------

  static void _showErrorDialog({
    required BuildContext context,
    required ErrorInfo errorInfo,
    String? customMessage,
    VoidCallback? onRetry,
    VoidCallback? onCancel,
  }) {
    if (!context.mounted || !errorInfo.isUserFacingError) {
      if (kDebugMode && !errorInfo.isUserFacingError) {
        debugPrint('Silent error: ${errorInfo.category}');
      }
      return;
    }

    String? actionButtonText;
    VoidCallback? actionCallback;

    if (errorInfo.canRetry && onRetry != null) {
      actionButtonText = 'Try again!';
      actionCallback = onRetry;
    } else if (errorInfo.redirectRoute != null) {
      actionButtonText = switch (errorInfo.redirectRoute) {
        '/login' => 'Log in',
        '/purchase' => 'Upgrade',
        '/home' => 'Go home',
        _ => 'Continue',
      };
      actionCallback = () =>
          Navigator.pushNamed(context, errorInfo.redirectRoute!);
    } else {
      actionButtonText = 'Got it!';
      actionCallback = null;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BariErrorOverlay(
        title: errorInfo.title,
        message: customMessage ?? errorInfo.message,
        helpText: errorInfo.userMessage,
        icon: errorInfo.icon,
        color: errorInfo.color,
        onRetry: errorInfo.canRetry && onRetry != null ? onRetry : null,
        onNavigate:
            errorInfo.redirectRoute != null ? actionCallback : null,
        onDismiss: () {
          Navigator.of(dialogContext).pop();
          onCancel?.call();
        },
        actionButtonText: actionButtonText,
      ),
    );
  }

  static void _showErrorSnackBar({
    required BuildContext context,
    required ErrorInfo errorInfo,
    String? customMessage,
  }) {
    if (!context.mounted || !errorInfo.isUserFacingError) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(errorInfo.icon, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                customMessage ?? errorInfo.message,
                style:
                    const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ],
        ),
        backgroundColor: errorInfo.color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  static void _showFallbackError(BuildContext context) {
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Oops!'),
        content:
            const Text('Something unexpected happened. Please try again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------
  // LOGGING
  // --------------------------------------------------------

  static Future<void> _logError(
    ErrorInfo errorInfo,
    dynamic originalError,
  ) async {
    try {
      if (kDebugMode) {
        logger.e(
          'Error [${errorInfo.category}]: ${errorInfo.title}',
          error: originalError,
          stackTrace: StackTrace.current,
        );
      }

      final prefs = await SharedPreferences.getInstance();
      final errorLog = {
        'timestamp': DateTime.now().toIso8601String(),
        'category': errorInfo.category,
        'title': errorInfo.title,
        'error': originalError
            .toString()
            .substring(
              0,
              originalError.toString().length > 200
                  ? 200
                  : originalError.toString().length,
            ),
      };

      final logs = prefs.getStringList('error_logs') ?? [];
      logs.add(json.encode(errorLog));
      if (logs.length > 50) {
        logs.removeRange(0, logs.length - 50);
      }
      await prefs.setStringList('error_logs', logs);
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to log error: $e');
    }
  }

  // --------------------------------------------------------
  // CONVENIENCE METHODS
  // --------------------------------------------------------

  static Future<void> handleNetworkError(
    BuildContext context,
    dynamic error, {
    VoidCallback? onRetry,
  }) async {
    await handleError(
      context: context,
      error: error,
      category: networkError,
      onRetry: onRetry,
    );
  }

  static Future<void> handleAuthError(
    BuildContext context,
    dynamic error,
  ) async {
    await handleError(
      context: context,
      error: error,
      category: authError,
    );
  }

  static Future<void> handlePremiumError(
    BuildContext context,
    dynamic error,
  ) async {
    await handleError(
      context: context,
      error: error,
      category: premiumError,
    );
  }

  static Future<void> handleScanError(
    BuildContext context,
    dynamic error, {
    VoidCallback? onRetry,
  }) async {
    await handleError(
      context: context,
      error: error,
      category: scanError,
      onRetry: onRetry,
    );
  }

  static Future<void> handleInitializationError(
    BuildContext context,
    dynamic error, {
    VoidCallback? onRetry,
  }) async {
    await handleError(
      context: context,
      error: error,
      category: initializationError,
      onRetry: onRetry,
    );
  }

  static Future<void> handleNavigationError(
    BuildContext context,
    dynamic error, {
    VoidCallback? onRetry,
  }) async {
    await handleError(
      context: context,
      error: error,
      category: navigationError,
      onRetry: onRetry,
    );
  }

  static void showSimpleError(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text('🫀 $message')),
          ],
        ),
        backgroundColor: Colors.red.shade400,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  static void showSuccess(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.white,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '🫀 $message',
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange.shade600,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  static Future<List<Map<String, dynamic>>> getErrorLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logs = prefs.getStringList('error_logs') ?? [];
      return logs
          .map((l) => json.decode(l) as Map<String, dynamic>)
          .toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> clearErrorLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('error_logs');
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to clear logs: $e');
    }
  }
}

// --------------------------------------------------------
// ERROR INFO MODEL
// --------------------------------------------------------

class ErrorInfo {
  final String category;
  final String title;
  final String message;
  final String? userMessage;
  final IconData icon;
  final Color color;
  final bool canRetry;
  final String? redirectRoute;
  final bool isUserFacingError;

  ErrorInfo({
    required this.category,
    required this.title,
    required this.message,
    this.userMessage,
    required this.icon,
    required this.color,
    this.canRetry = true,
    this.redirectRoute,
    this.isUserFacingError = true,
  });
}