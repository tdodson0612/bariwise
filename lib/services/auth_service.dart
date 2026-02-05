// lib/services/auth_service.dart - DEBUG VERSION WITH COMPREHENSIVE LOGGING
// ✅ FIX #1: Login timeout 15s → 30s + iOS FCM skip
// ✅ FIX #2: Password reset deep link fixed
// 🔵 DEBUG: Added extensive logging to diagnose signup/login issues

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  static bool get isLoggedIn => _supabase.auth.currentUser != null;
  static User? get currentUser => _supabase.auth.currentUser;
  static String? get currentUserId => currentUser?.id;

  static String? get currentUsername {
    final username = currentUser?.userMetadata?['username'] as String?;
    if (username != null) return username;
    return null;
  }

  static void ensureLoggedIn() {
    if (!isLoggedIn || currentUserId == null) {
      throw Exception('User must be logged in to perform this action.');
    }
  }

  static Future<String?> fetchCurrentUsername() async {
    if (currentUserId == null) return null;

    try {
      final profile = await ProfileDataAccess.getUserProfile(currentUserId!);
      return profile?['username'] as String?;
    } catch (e) {
      print('Error fetching username: $e');
      return null;
    }
  }

  static Stream<AuthState> get authStateChanges =>
      _supabase.auth.onAuthStateChange;

  static bool _isDefaultPremiumEmail(String email) {
    final normalizedEmail = email.trim().toLowerCase();
    return _premiumEmails.contains(normalizedEmail);
  }

  // --------------------------------------------------------
  // PLATFORM-CONDITIONAL FCM TOKEN SAVE
  // --------------------------------------------------------
  static Future<void> _saveFcmTokenIfAndroid(String userId) async {
    if (!kIsWeb && Platform.isIOS) {
      print("🔵 DEBUG: iOS detected - skipping FCM token save");
      return;
    }

    try {
      print("🔵 DEBUG: Getting FCM token (Android)...");
      final token = await FirebaseMessaging.instance.getToken();

      if (token == null) {
        print("🔵 DEBUG: FCM token is null, skipping save");
        return;
      }

      print("🔵 DEBUG: Saving FCM token: ${token.substring(0, 20)}...");

      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'profiles',
        filters: {'id': userId},
        data: {
          'fcm_token': token,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );
      
      print("🔵 DEBUG: ✅ FCM token saved successfully");
    } catch (e) {
      print("🔵 DEBUG: ⚠️ Failed to save FCM token (non-critical): $e");
    }
  }

  static void _listenForFcmTokenRefreshIfAndroid(String userId) {
    if (!kIsWeb && Platform.isIOS) {
      print("🔵 DEBUG: iOS detected - skipping FCM token refresh listener");
      return;
    }

    try {
      print("🔵 DEBUG: Setting up FCM token refresh listener...");
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        print("🔵 DEBUG: FCM token refreshed: ${newToken.substring(0, 20)}...");

        try {
          await DatabaseServiceCore.workerQuery(
            action: 'update',
            table: 'profiles',
            filters: {'id': userId},
            data: {
              'fcm_token': newToken,
              'updated_at': DateTime.now().toIso8601String(),
            },
          );
          print("🔵 DEBUG: ✅ Refreshed FCM token saved");
        } catch (e) {
          print("🔵 DEBUG: ⚠️ Failed to save refreshed FCM token: $e");
        }
      });
      print("🔵 DEBUG: ✅ FCM listener set up");
    } catch (e) {
      print("🔵 DEBUG: ⚠️ FCM token refresh listener failed: $e");
    }
  }

  // --------------------------------------------------------
  // 🔵 SIGN UP - WITH COMPREHENSIVE DEBUG LOGGING
  // --------------------------------------------------------
  static Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    print('\n========================================');
    print('🔵 SIGNUP DEBUG: Starting signup process');
    print('========================================');
    print('🔵 SIGNUP DEBUG: Email: ${email.trim().toLowerCase()}');
    print('🔵 SIGNUP DEBUG: Password length: ${password.length}');
    print('🔵 SIGNUP DEBUG: Platform: ${kIsWeb ? "Web" : Platform.operatingSystem}');
    
    try {
      print('🔵 SIGNUP DEBUG: Calling Supabase signUp...');
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );

      print('🔵 SIGNUP DEBUG: Supabase signUp returned');
      print('  - User ID: ${response.user?.id}');
      print('  - User Email: ${response.user?.email}');
      print('  - Session exists: ${response.session != null}');
      print('  - Access token exists: ${response.session?.accessToken != null}');
      
      if (response.session != null) {
        print('  - Token preview: ${response.session!.accessToken.substring(0, 20)}...');
        print('  - Token expires at: ${response.session!.expiresAt}');
      }

      if (response.user != null) {
        final normalizedEmail = email.trim().toLowerCase();
        final isPremium = _isDefaultPremiumEmail(normalizedEmail);
        final userId = response.user!.id;

        print('🔵 SIGNUP DEBUG: User created, waiting 1 second before profile creation...');
        await Future.delayed(const Duration(seconds: 1));

        print('🔵 SIGNUP DEBUG: Creating user profile...');
        print('  - User ID: $userId');
        print('  - Email: $normalizedEmail');
        print('  - Is Premium: $isPremium');

        try {
          await ProfileDataAccess.createUserProfile(
            userId,
            email,
            isPremium: isPremium,
          );

          print('🔵 SIGNUP DEBUG: ✅ Profile created successfully');
        } catch (profileError) {
          print('🔵 SIGNUP DEBUG: ❌ Profile creation FAILED');
          print('🔵 SIGNUP DEBUG: Error type: ${profileError.runtimeType}');
          print('🔵 SIGNUP DEBUG: Error message: $profileError');
          print('🔵 SIGNUP DEBUG: Stack trace: ${StackTrace.current}');

          throw Exception(
              'Signup succeeded but profile setup failed. Please sign in.');
        }

        // FCM token save (non-blocking)
        print('🔵 SIGNUP DEBUG: Attempting FCM token save...');
        _saveFcmTokenIfAndroid(userId).catchError((error) {
          print("🔵 SIGNUP DEBUG: FCM save error (non-critical): $error");
        });

        print('🔵 SIGNUP DEBUG: Setting up FCM listener...');
        _listenForFcmTokenRefreshIfAndroid(userId);

        print('🔵 SIGNUP DEBUG: ✅ Signup process complete');
        print('🔵 SIGNUP DEBUG: Final check - Session valid: ${response.session != null}');
      } else {
        print('🔵 SIGNUP DEBUG: ⚠️ No user returned from Supabase');
      }

      print('========================================');
      print('🔵 SIGNUP DEBUG: Returning AuthResponse');
      print('  - User: ${response.user?.id}');
      print('  - Session: ${response.session != null ? "EXISTS" : "NULL"}');
      print('========================================\n');

      return response;
    } catch (e) {
      print('🔵 SIGNUP DEBUG: ❌ FATAL ERROR in signup');
      print('🔵 SIGNUP DEBUG: Error type: ${e.runtimeType}');
      print('🔵 SIGNUP DEBUG: Error message: $e');
      print('🔵 SIGNUP DEBUG: Stack trace: ${StackTrace.current}');
      print('========================================\n');
      
      throw Exception('Sign up failed: $e');
    }
  }

  // --------------------------------------------------------
  // 🔵 SIGN IN - WITH COMPREHENSIVE DEBUG LOGGING
  // --------------------------------------------------------
  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    const maxRetries = 3;
    int attempt = 0;

    print('\n========================================');
    print('🔵 LOGIN DEBUG: Starting login process');
    print('========================================');
    print('🔵 LOGIN DEBUG: Email: ${email.trim().toLowerCase()}');
    print('🔵 LOGIN DEBUG: Platform: ${kIsWeb ? "Web" : Platform.operatingSystem}');
    print('🔵 LOGIN DEBUG: Max retries: $maxRetries');

    while (attempt < maxRetries) {
      attempt++;
      
      print('\n🔵 LOGIN DEBUG: ===== Attempt $attempt/$maxRetries =====');
      
      try {
        // Clear existing session
        try {
          final currentSession = _supabase.auth.currentSession;
          if (currentSession != null) {
            print('🔵 LOGIN DEBUG: Existing session found, clearing...');
            await _supabase.auth.signOut();
            await Future.delayed(const Duration(milliseconds: 500));
            print('🔵 LOGIN DEBUG: ✅ Session cleared');
          } else {
            print('🔵 LOGIN DEBUG: No existing session to clear');
          }
        } catch (clearError) {
          print('🔵 LOGIN DEBUG: ⚠️ Session clear error: $clearError');
        }

        print('🔵 LOGIN DEBUG: Calling Supabase signInWithPassword...');
        final startTime = DateTime.now();
        
        final response = await _supabase.auth.signInWithPassword(
          email: email,
          password: password,
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            print('🔵 LOGIN DEBUG: ❌ TIMEOUT after 30 seconds');
            throw Exception('Connection timed out. Please try again.');
          },
        );

        final duration = DateTime.now().difference(startTime);
        print('🔵 LOGIN DEBUG: Login call completed in ${duration.inMilliseconds}ms');

        print('🔵 LOGIN DEBUG: Response received:');
        print('  - User ID: ${response.user?.id}');
        print('  - User Email: ${response.user?.email}');
        print('  - Session exists: ${response.session != null}');
        print('  - Access token exists: ${response.session?.accessToken != null}');

        // ✅ SUCCESS PATH
        if (response.user != null && response.session != null) {
          final userId = response.user!.id;
          final normalizedEmail = email.trim().toLowerCase();

          print('🔵 LOGIN DEBUG: ✅ Login successful!');
          print('  - User ID: $userId');
          print('  - Token preview: ${response.session!.accessToken.substring(0, 20)}...');

          // Ensure profile exists
          print('🔵 LOGIN DEBUG: Checking user profile...');
          try {
            await _ensureUserProfileExists(userId, email);
            print('🔵 LOGIN DEBUG: ✅ Profile check complete');
          } catch (profileError) {
            print('🔵 LOGIN DEBUG: ⚠️ Profile check failed: $profileError');
          }

          // Set premium if applicable
          if (_isDefaultPremiumEmail(normalizedEmail)) {
            print('🔵 LOGIN DEBUG: Setting premium status...');
            try {
              await ProfileDataAccess.setPremium(userId, true);
              print('🔵 LOGIN DEBUG: ✅ Premium status set');
            } catch (premiumError) {
              print('🔵 LOGIN DEBUG: ⚠️ Premium setup failed: $premiumError');
            }
          }

          // FCM token (non-blocking)
          print('🔵 LOGIN DEBUG: Saving FCM token...');
          _saveFcmTokenIfAndroid(userId).catchError((error) {
            print("🔵 LOGIN DEBUG: FCM save error (non-critical): $error");
          });

          _listenForFcmTokenRefreshIfAndroid(userId);

          print('========================================');
          print('🔵 LOGIN DEBUG: ✅ LOGIN SUCCESS - Returning response');
          print('========================================\n');

          return response;
        }

        print('🔵 LOGIN DEBUG: ❌ No user or session in response');
        throw Exception('Login failed: No user or session returned');

      } catch (e) {
        final errorStr = e.toString().toLowerCase();
        
        print('🔵 LOGIN DEBUG: ❌ Attempt $attempt failed');
        print('  - Error: $e');
        print('  - Error type: ${e.runtimeType}');

        // Session error retry logic
        final isSessionError = errorStr.contains('session') ||
                            errorStr.contains('expired') ||
                            errorStr.contains('invalid_grant') ||
                            errorStr.contains('refresh_token') ||
                            errorStr.contains('jwt');

        if (isSessionError && attempt < maxRetries) {
          print('🔵 LOGIN DEBUG: 🔄 Session error detected, will retry...');
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }

        // Fatal errors - don't retry
        if (errorStr.contains('invalid login credentials') ||
            errorStr.contains('invalid email or password')) {
          print('🔵 LOGIN DEBUG: ❌ FATAL: Invalid credentials');
          throw Exception('Invalid email or password. Please try again.');
        }
        
        if (errorStr.contains('email not confirmed')) {
          print('🔵 LOGIN DEBUG: ❌ FATAL: Email not confirmed');
          throw Exception('Please verify your email before signing in.');
        }
        
        if (errorStr.contains('network') || errorStr.contains('socket')) {
          print('🔵 LOGIN DEBUG: ❌ FATAL: Network error');
          throw Exception('Network error. Please check your internet connection.');
        }

        if (attempt >= maxRetries) {
          print('🔵 LOGIN DEBUG: ❌ All $maxRetries attempts exhausted');
          print('========================================\n');
          throw Exception('Sign in failed after $maxRetries attempts. Please try again later.');
        }

        print('🔵 LOGIN DEBUG: ⚠️ Will retry (non-fatal error)');
        await Future.delayed(Duration(milliseconds: 500 * attempt));
        continue;
      }
    }

    print('🔵 LOGIN DEBUG: ❌ Should not reach here - all retries failed');
    print('========================================\n');
    throw Exception('Login failed after $maxRetries attempts');
  }

  static Future<void> forceResetSession() async {
    print('\n🔵 DEBUG: Force resetting session...');
    try {
      await _supabase.auth.signOut();
      await DatabaseServiceCore.clearAllUserCache();
      await Future.delayed(const Duration(seconds: 1));
      print('🔵 DEBUG: ✅ Session reset complete\n');
    } catch (e) {
      print('🔵 DEBUG: ⚠️ Session reset error: $e\n');
      throw Exception('Failed to reset session: $e');
    }
  }

  static Future<void> _ensureUserProfileExists(
      String userId, String email) async {
    try {
      print('🔵 DEBUG: Fetching profile for user: $userId');
      final profile = await ProfileDataAccess.getUserProfile(userId);

      if (profile == null) {
        print('🔵 DEBUG: Profile missing, creating...');
        await ProfileDataAccess.createUserProfile(
          userId,
          email,
          isPremium: false,
        );
        print('🔵 DEBUG: ✅ Profile created');
      } else {
        print('🔵 DEBUG: ✅ Profile exists');
      }
    } catch (e) {
      print('🔵 DEBUG: ❌ Profile check failed: $e');
      rethrow;
    }
  }

  static Future<void> signOut() async {
    try {
      print('🔵 DEBUG: Signing out...');
      await DatabaseServiceCore.clearAllUserCache();
      await _supabase.auth.signOut();
      print('🔵 DEBUG: ✅ Signed out');
    } catch (e) {
      print('🔵 DEBUG: ❌ Sign out error: $e');
      throw Exception('Sign out failed: $e');
    }
  }

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
      throw Exception('No user logged in');
    }

    try {
      await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      AppConfig.debugPrint('✅ Password updated for user: $currentUserId');
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
      AppConfig.debugPrint('✅ Verification email resent to: ${currentUser!.email}');
    } catch (e) {
      AppConfig.debugPrint('❌ Failed to resend verification email: $e');
      throw Exception('Failed to resend verification email: $e');
    }
  }

  static void ensureUserAuthenticated() {
    if (!isLoggedIn) {
      throw Exception('User must be logged in');
    }
  }

  static Future<void> markUserAsPremium(String userId) async {
    try {
      await ProfileDataAccess.setPremium(userId, true);
      AppConfig.debugPrint("🌟 User upgraded to premium: $userId");

      if (currentUserId == userId) {
        _saveFcmTokenIfAndroid(userId).catchError((error) {
          AppConfig.debugPrint("⚠️ FCM token save failed: $error");
        });
      }
    } catch (e) {
      AppConfig.debugPrint("❌ Failed to set premium status: $e");
      throw Exception("Failed to set premium status: $e");
    }
  }
}