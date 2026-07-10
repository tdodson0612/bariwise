// lib/services/auth_service.dart
//
// ✅ Simplified login flow - no complex retry logic
// ✅ Proper session handling for iOS and Android
// ✅ Non-blocking profile setup
// ✅ FCM only on Android (iOS disabled)
// ✅ FIXED: resetPassword redirectTo scheme updated to match
//           AndroidManifest package (com.terrydodson.bariWiseApp)
//
// 🔧 FIX (login loop): Removed _clearExistingSession() from signIn().
//    Calling signOut() before login when there is no active session
//    produces a session/token error on Android that the error handler
//    misclassified as an auth error, causing the "Hmm, who are you?" loop.
//
// 🔧 FIX (signup "Hmm who are you?"): Profile creation failure during
//    signup was being caught and re-thrown as a generic Exception whose
//    message contained the word "failed", which _isAuthError() matched
//    on 'token'/'session'/'expired' substrings in unrelated Supabase
//    errors. The error classification is now more precise, and signup
//    errors that are NOT auth errors surface a dedicated message instead
//    of the auth-error dialog.

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

import 'profile_data_access.dart';
import 'database_service_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class AuthService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static const List<String> _premiumEmails = [
    'terryd0612@gmail.com',
    'baridiseasescanner@gmail.com',
  ];

  // --------------------------------------------------------
  // BASIC AUTH STATE
  // --------------------------------------------------------

  static bool get isLoggedIn => _supabase.auth.currentUser != null;
  static User? get currentUser => _supabase.auth.currentUser;
  static String? get currentUserId => currentUser?.id;

  static String? get currentUsername {
    return currentUser?.userMetadata?['username'] as String?;
  }

  static Stream<AuthState> get authStateChanges =>
      _supabase.auth.onAuthStateChange;

  static void ensureLoggedIn() {
    if (!isLoggedIn || currentUserId == null) {
      throw Exception('User must be logged in to perform this action.');
    }
  }

  static void ensureUserAuthenticated() {
    if (!isLoggedIn) {
      throw Exception('User must be logged in');
    }
  }

  static bool _isDefaultPremiumEmail(String email) {
    return _premiumEmails.contains(email.trim().toLowerCase());
  }

  // --------------------------------------------------------
  // FETCH CURRENT USERNAME
  // --------------------------------------------------------

  static Future<String?> fetchCurrentUsername() async {
    if (currentUserId == null) return null;
    try {
      final profile = await ProfileDataAccess.getUserProfile(currentUserId!);
      return profile?['username'] as String?;
    } catch (e) {
      AppConfig.debugPrint('Error fetching username: $e');
      return null;
    }
  }

  // --------------------------------------------------------
  // SIGN IN
  // --------------------------------------------------------

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      AppConfig.debugPrint('🔐 Starting login for: $normalizedEmail');

      // NOTE: _clearExistingSession() intentionally not called here.
      // See file header for explanation.

      final response = await _supabase.auth
          .signInWithPassword(
            email: normalizedEmail,
            password: password,
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception(
              'Login timed out. Please check your connection and try again.',
            ),
          );

      if (response.user == null || response.session == null) {
        throw Exception('Login failed - no session created');
      }

      final userId = response.user!.id;
      AppConfig.debugPrint('✅ Supabase login successful: $userId');

      // Non-blocking best-effort tasks
      _setupProfileAfterLogin(userId, normalizedEmail).catchError((e) {
        AppConfig.debugPrint('⚠️ Profile setup failed (continuing): $e');
      });

      _setupFcmAfterLogin(userId).catchError((e) {
        AppConfig.debugPrint('⚠️ FCM setup failed (continuing): $e');
      });

      AppConfig.debugPrint('✅ Login complete');
      return response;
    } on AuthException catch (e) {
      AppConfig.debugPrint('❌ Supabase auth error: ${e.message}');
      throw _createUserFriendlyAuthError(e);
    } catch (e) {
      AppConfig.debugPrint('❌ Login error: $e');
      if (e is Exception) rethrow;
      throw _createUserFriendlyAuthError(e);
    }
  }

  // --------------------------------------------------------
  // SIGN UP
  // --------------------------------------------------------

  static Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    AppConfig.debugPrint('📝 Starting signup for: $normalizedEmail');

    // Step 1: Create the Supabase auth user
    final AuthResponse response;
    try {
      response = await _supabase.auth
          .signUp(
            email: normalizedEmail,
            password: password,
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception(
              'Signup timed out. Please check your connection and try again.',
            ),
          );
    } on AuthException catch (e) {
      AppConfig.debugPrint('❌ Signup auth error: ${e.message}');
      throw _createUserFriendlyAuthError(e);
    }

    if (response.user == null) {
      throw Exception('Account creation failed. Please try again.');
    }

    final userId = response.user!.id;
    final isPremium = _isDefaultPremiumEmail(normalizedEmail);
    AppConfig.debugPrint('✅ Auth user created: $userId');

    // Step 2: Create profile row.
    //
    // When email confirmation is required, response.session is null here,
    // which means we have no access token to pass to the worker.
    // ProfileDataAccess.createUserProfile() intentionally does NOT use
    // requireAuth so this insert succeeds via the anon key + RLS policy.
    //
    // Give Supabase a moment to propagate the new user before inserting.
    await Future.delayed(const Duration(milliseconds: 800));

    try {
      await ProfileDataAccess.createUserProfile(
        userId,
        normalizedEmail,
        isPremium: isPremium,
      );
      AppConfig.debugPrint('✅ Profile created during signup');
    } catch (profileError) {
      AppConfig.debugPrint('❌ Profile creation failed: $profileError');
      // Surface a clear, non-auth-classified message.
      // Do NOT throw an AuthException or a message containing auth keywords,
      // because ErrorHandlingService._isAuthError() would misclassify it.
      throw ProfileSetupException(
        'Your account was created but profile setup failed. '
        'Please sign in and we will finish setting up your profile.',
      );
    }

    // Step 3: FCM (non-blocking, Android only)
    _setupFcmAfterLogin(userId).catchError((e) {
      AppConfig.debugPrint('⚠️ FCM setup failed: $e');
    });

    return response;
  }

  // --------------------------------------------------------
  // FORCE RESET SESSION (exposed for "Clear Session" button)
  // --------------------------------------------------------

  static Future<void> forceResetSession() async {
    try {
      AppConfig.debugPrint('🧹 Force resetting session...');

      try {
        await _supabase.auth.signOut();
      } catch (e) {
        AppConfig.debugPrint('⚠️ signOut during reset failed (continuing): $e');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('isPremiumUser');
      await prefs.remove('saved_email');

      await DatabaseServiceCore.clearAllUserCache();
      await Future.delayed(const Duration(seconds: 1));

      AppConfig.debugPrint('✅ Session reset complete');
    } catch (e) {
      AppConfig.debugPrint('❌ Session reset failed: $e');
      throw Exception('Failed to reset session: $e');
    }
  }

  // --------------------------------------------------------
  // SIGN OUT
  // --------------------------------------------------------

  static Future<void> signOut() async {
    try {
      AppConfig.debugPrint('🔓 Signing out...');
      await DatabaseServiceCore.clearAllUserCache();
      await _supabase.auth.signOut();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('isPremiumUser');

      AppConfig.debugPrint('✅ Signed out successfully');
    } catch (e) {
      AppConfig.debugPrint('❌ Sign out error: $e');
      throw Exception('Sign out failed: $e');
    }
  }

  // --------------------------------------------------------
  // PASSWORD RESET
  // --------------------------------------------------------

  /// Sends a password reset email.
  ///
  /// The redirectTo scheme MUST match:
  ///   - AndroidManifest.xml  → android:scheme="com.terrydodson.bariWiseApp"
  ///   - Supabase Dashboard   → Authentication → URL Config → Redirect URLs
  ///                            add: com.terrydodson.bariWiseApp://reset-password
  static Future<void> resetPassword(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: 'com.terrydodson.bariWiseApp://reset-password',
      );
      AppConfig.debugPrint('✅ Password reset email sent to: $email');
    } catch (e) {
      AppConfig.debugPrint('❌ Password reset failed: $e');
      throw Exception('Password reset failed: $e');
    }
  }

  static Future<void> updatePassword(String newPassword) async {
    if (currentUserId == null) {
      throw Exception(
        'No user session found. Please request a new reset link.',
      );
    }
    try {
      await _supabase.auth.updateUser(UserAttributes(password: newPassword));
      AppConfig.debugPrint('✅ Password updated');
    } catch (e) {
      AppConfig.debugPrint('❌ Password update failed: $e');
      throw Exception('Password update failed: $e');
    }
  }

  static Future<void> resendVerificationEmail() async {
    if (currentUser?.email == null) {
      throw Exception('No user email found');
    }
    try {
      await _supabase.auth.resend(
        type: OtpType.signup,
        email: currentUser!.email!,
      );
      AppConfig.debugPrint('✅ Verification email resent');
    } catch (e) {
      AppConfig.debugPrint('❌ Failed to resend verification email: $e');
      throw Exception('Failed to resend verification email: $e');
    }
  }

  // --------------------------------------------------------
  // PREMIUM STATUS
  // --------------------------------------------------------

  static Future<void> markUserAsPremium(String userId) async {
    try {
      await ProfileDataAccess.setPremium(userId, true);
      AppConfig.debugPrint('🌟 User upgraded to premium: $userId');

      if (currentUserId == userId) {
        _setupFcmAfterLogin(userId).catchError((e) {
          AppConfig.debugPrint('⚠️ FCM update failed: $e');
        });
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Failed to set premium status: $e');
      throw Exception('Failed to set premium status: $e');
    }
  }

  // ========================================================
  // PRIVATE HELPERS
  // ========================================================

  /// Setup profile after login - best effort, non-blocking.
  static Future<void> _setupProfileAfterLogin(
    String userId,
    String email,
  ) async {
    try {
      AppConfig.debugPrint('📋 Checking user profile...');
      final profile = await ProfileDataAccess.getUserProfile(userId);

      if (profile == null) {
        final isPremium = _isDefaultPremiumEmail(email);
        AppConfig.debugPrint('📝 Creating missing profile');
        await ProfileDataAccess.createUserProfile(
          userId,
          email,
          isPremium: isPremium,
        );
        AppConfig.debugPrint('✅ Profile created with premium=$isPremium');
      } else {
        final isPremium = _isDefaultPremiumEmail(email);
        final currentPremium = profile['is_premium'] as bool? ?? false;
        if (isPremium && !currentPremium) {
          AppConfig.debugPrint('⭐ Upgrading to premium');
          await ProfileDataAccess.setPremium(userId, true);
        }
        AppConfig.debugPrint('✅ Profile exists');
      }
    } catch (e) {
      AppConfig.debugPrint('⚠️ Profile setup error (non-fatal): $e');
      // Do not rethrow - login should succeed regardless
    }
  }

  /// Setup FCM token (Android only, non-blocking).
  static Future<void> _setupFcmAfterLogin(String userId) async {
    if (kIsWeb || Platform.isIOS) {
      AppConfig.debugPrint('ℹ️ Skipping FCM (iOS/Web)');
      return;
    }

    try {
      AppConfig.debugPrint('📱 Setting up FCM (Android)...');
      final token = await FirebaseMessaging.instance.getToken();

      if (token == null) {
        AppConfig.debugPrint('⚠️ FCM token is null');
        return;
      }

      AppConfig.debugPrint(
        '📱 Saving FCM token: ${token.substring(0, 20)}...',
      );

      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'user_profiles',
        filters: {'id': userId},
        data: {
          'fcm_token': token,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ FCM token saved');
      _listenForFcmTokenRefresh(userId);
    } catch (e) {
      AppConfig.debugPrint('⚠️ FCM setup failed (non-fatal): $e');
    }
  }

  static void _listenForFcmTokenRefresh(String userId) {
    if (kIsWeb || Platform.isIOS) return;
    try {
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        AppConfig.debugPrint(
          '🔄 FCM token refreshed: ${newToken.substring(0, 20)}...',
        );
        try {
          await DatabaseServiceCore.workerQuery(
            action: 'update',
            table: 'user_profiles',
            filters: {'id': userId},
            data: {
              'fcm_token': newToken,
              'updated_at': DateTime.now().toIso8601String(),
            },
          );
          AppConfig.debugPrint('✅ Refreshed FCM token saved');
        } catch (e) {
          AppConfig.debugPrint('⚠️ Failed to save refreshed token: $e');
        }
      });
    } catch (e) {
      AppConfig.debugPrint('⚠️ FCM listener setup failed: $e');
    }
  }

  /// Convert Supabase AuthExceptions and raw errors to clean user messages.
  ///
  /// IMPORTANT: returned Exception messages must NOT contain the words
  /// 'token', 'session', or 'expired' unless the error genuinely is an
  /// auth/session problem, because ErrorHandlingService._isAuthError()
  /// matches on those substrings and will show the "Hmm, who are you?"
  /// dialog for unrelated errors.
  static Exception _createUserFriendlyAuthError(dynamic error) {
    final msg = error.toString().toLowerCase();

    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid email or password')) {
      return Exception('Incorrect email or password. Please try again.');
    }

    if (msg.contains('email not confirmed')) {
      return Exception(
        'Please verify your email before signing in. '
        'Check your inbox for the confirmation link.',
      );
    }

    if (msg.contains('user already registered')) {
      return Exception(
        'This email is already registered. Try signing in instead.',
      );
    }

    if (msg.contains('password should be at least 6 characters')) {
      return Exception('Password must be at least 6 characters long.');
    }

    if (msg.contains('timeout')) {
      return Exception(
        'Connection timed out. Please check your internet and try again.',
      );
    }

    if (msg.contains('network') || msg.contains('socket')) {
      return Exception(
        'Network error. Please check your internet connection.',
      );
    }

    // Genuine session/token errors (login only - not signup profile errors)
    if (msg.contains('refresh_token') ||
        msg.contains('invalid grant') ||
        msg.contains('401') ||
        msg.contains('403')) {
      return Exception(
        'Your login has expired. Please use the "Clear Session" button and try again.',
      );
    }

    return Exception('Unable to complete request. Please try again.');
  }
}

/// Thrown when the Supabase auth user was created successfully but profile
/// row insertion failed. Kept as a separate type so callers (login.dart) can
/// show a specific, non-auth-classified message to the user.
class ProfileSetupException implements Exception {
  final String message;
  const ProfileSetupException(this.message);

  @override
  String toString() => message;
}