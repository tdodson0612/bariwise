// lib/services/profile_service.dart
// Handles user profile creation, updates, premium status, and picture getters
// BARIATRIC VERSION - Updated for BariWise

import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import 'database_service_core.dart';
import 'profile_data_access.dart';

class ProfileService {
  
  // ==================================================
  // FETCH PROFILE
  // ==================================================

  static Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final result = await ProfileDataAccess.getUserProfile(userId);
      return result;
    } catch (e) {
      throw Exception('Failed to get user profile: $e');
    }
  }

  static Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    final userId = DatabaseServiceCore.currentUserId;
    if (userId == null) return null;
    return getUserProfile(userId);
  }

  // ==================================================
  // UPDATE PROFILE
  // ==================================================

  static Future<void> updateProfile({
    String? username,
    String? email,
    String? firstName,
    String? lastName,
    String? avatarUrl,
    String? profilePicture,
  }) async {
    final userId = DatabaseServiceCore.currentUserId;
    if (userId == null) throw Exception('Please sign in');

    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (username != null) updates['username'] = username;
      if (email != null) updates['email'] = email;
      if (firstName != null) updates['first_name'] = firstName;
      if (lastName != null) updates['last_name'] = lastName;
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
      if (profilePicture != null) updates['profile_picture'] = profilePicture;

      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'profiles',
        filters: {'id': userId},
        data: updates,
      );

      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');
    } catch (e) {
      if (e.toString().contains('duplicate') ||
          e.toString().contains('unique constraint')) {
        throw Exception('Username is already taken. Please choose another.');
      }
      throw Exception('Failed to update profile: $e');
    }
  }

  // ==================================================
  // PREMIUM STATUS
  // ==================================================

  static Future<bool> isPremiumUser() async {
    final userId = DatabaseServiceCore.currentUserId;
    if (userId == null) return false;

    try {
      final profile = await getUserProfile(userId);
      return profile?['is_premium'] ?? false;
    } catch (_) {
      return false;
    }
  }

  // ==================================================
  // PICTURE GETTERS
  // ==================================================

  static Future<String?> getProfilePicture(String userId) async {
    try {
      final profile = await getUserProfile(userId);
      return profile?['profile_picture'] as String?;
    } catch (e) {
      AppConfig.debugPrint('Error getting profile picture: $e');
      return null;
    }
  }

  static Future<String?> getCurrentProfilePicture() async {
    final userId = DatabaseServiceCore.currentUserId;
    if (userId == null) return null;
    return getProfilePicture(userId);
  }

  static Future<String?> getBackgroundPicture(String userId) async {
    try {
      final profile = await getUserProfile(userId);
      return profile?['profile_background'] as String?;
    } catch (e) {
      AppConfig.debugPrint('Error getting background picture: $e');
      return null;
    }
  }

  static Future<String?> getCurrentBackgroundPicture() async {
    final userId = DatabaseServiceCore.currentUserId;
    if (userId == null) return null;
    return getBackgroundPicture(userId);
  }

  // ==================================================
  // 🆕 BARIATRIC SURGERY TYPE MANAGEMENT
  // ==================================================

  /// Get user's bariatric surgery type from Supabase
  static Future<String?> getSurgeryType(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('bariatric_surgery_type')
          .eq('id', userId)
          .single();

      final surgeryType = response['bariatric_surgery_type'] as String?;
      AppConfig.debugPrint('📋 Surgery type fetched: $surgeryType');
      return surgeryType;
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting surgery type: $e');
      return null;
    }
  }

  /// Update user's bariatric surgery type in Supabase
  static Future<void> updateSurgeryType(String userId, String surgeryType) async {
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({
            'bariatric_surgery_type': surgeryType,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);

      // Clear cache to force fresh data
      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');
      
      AppConfig.debugPrint('✅ Surgery type updated to: $surgeryType');
    } catch (e) {
      AppConfig.debugPrint('❌ Error updating surgery type: $e');
      throw Exception('Failed to update surgery type: $e');
    }
  }

  /// Get current user's surgery type
  static Future<String?> getCurrentSurgeryType() async {
    final userId = DatabaseServiceCore.currentUserId;
    if (userId == null) return null;
    return getSurgeryType(userId);
  }

  // ==================================================
  // HEIGHT & WEIGHT MANAGEMENT
  // ==================================================
  
  /// Get user's height in cm
  static Future<double?> getHeight(String userId) async {
    try {
      final profile = await getUserProfile(userId);
      final height = profile?['height_cm'];
      return height != null ? (height as num).toDouble() : null;
    } catch (e) {
      AppConfig.debugPrint('Error getting height: $e');
      return null;
    }
  }
  
  /// Update user's height in cm
  static Future<void> updateHeight(String userId, double heightCm) async {
    try {
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'profiles',
        filters: {'id': userId},
        data: {
          'height_cm': heightCm,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );
      
      // Clear cache to force fresh data
      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');
      
      AppConfig.debugPrint('✅ Height updated to: ${heightCm}cm');
    } catch (e) {
      AppConfig.debugPrint('❌ Error updating height: $e');
      throw Exception('Failed to update height: $e');
    }
  }
  
  /// Get current user's height
  static Future<double?> getCurrentHeight() async {
    final userId = DatabaseServiceCore.currentUserId;
    if (userId == null) return null;
    return getHeight(userId);
  }
  
  /// Get weight visibility setting
  static Future<bool> getWeightVisibility(String userId) async {
    try {
      final profile = await getUserProfile(userId);
      return profile?['weight_visible'] as bool? ?? false;
    } catch (e) {
      AppConfig.debugPrint('Error getting weight visibility: $e');
      return false;
    }
  }
  
  /// Update weight visibility setting
  static Future<void> updateWeightVisibility(String userId, bool visible) async {
    try {
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'profiles',
        filters: {'id': userId},
        data: {
          'weight_visible': visible,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );
      
      // Clear cache to force fresh data
      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');
      
      AppConfig.debugPrint('✅ Weight visibility updated to: $visible');
    } catch (e) {
      AppConfig.debugPrint('❌ Error updating weight visibility: $e');
      throw Exception('Failed to update weight visibility: $e');
    }
  }
  
  /// Get current user's weight visibility
  static Future<bool> getCurrentWeightVisibility() async {
    final userId = DatabaseServiceCore.currentUserId;
    if (userId == null) return false;
    return getWeightVisibility(userId);
  }

  /// Get weight loss visibility setting
  static Future<bool> getWeightLossVisibility(String userId) async {
    try {
      final profile = await getUserProfile(userId);
      return profile?['weight_loss_visible'] as bool? ?? false;
    } catch (e) {
      AppConfig.debugPrint('Error getting weight loss visibility: $e');
      return false;
    }
  }
  
  /// Update weight loss visibility setting
  static Future<void> updateWeightLossVisibility(String userId, bool visible) async {
    try {
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'profiles',
        filters: {'id': userId},
        data: {
          'weight_loss_visible': visible,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );
      
      // Clear cache to force fresh data
      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');
      
      AppConfig.debugPrint('✅ Weight loss visibility updated to: $visible');
    } catch (e) {
      AppConfig.debugPrint('❌ Error updating weight loss visibility: $e');
      throw Exception('Failed to update weight loss visibility: $e');
    }
  }
  
  /// Get current user's weight loss visibility
  static Future<bool> getCurrentWeightLossVisibility() async {
    final userId = DatabaseServiceCore.currentUserId;
    if (userId == null) return false;
    return getWeightLossVisibility(userId);
  }

  /// Update user's location for regional database priority
  static Future<void> updateUserLocation(String userId, String country) async {
    try {
      // Validate country code (basic check)
      if (country.trim().isEmpty || country.length > 3) {
        throw Exception('Invalid country code');
      }

      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'profiles',
        filters: {'id': userId},
        data: {
          'location_country': country.toUpperCase(),
          'location_detected_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      // Clear profile cache to force refresh
      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');

      AppConfig.debugPrint('✅ User location updated to: $country');
    } catch (e) {
      AppConfig.debugPrint('❌ Error updating user location: $e');
      // Don't throw - location is not critical
    }
  }

  /// Get user's country for regional database priority
  /// Returns 'US' if not set or error
  static Future<String> getUserCountry(String userId) async {
    try {
      final profile = await getUserProfile(userId);
      final country = profile?['location_country'] as String?;

      return country ?? 'US';
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting user country: $e');
      return 'US';
    }
  }

  /// Get current user's country
  static Future<String> getCurrentUserCountry() async {
    final userId = DatabaseServiceCore.currentUserId;
    if (userId == null) return 'US';
    return getUserCountry(userId);
  }

  /// Detect user location from device (iOS 14 compatible)
  static Future<String> detectUserLocation() async {
    try {
      // TODO: Implement actual location detection using device location
      // For now, return 'US' as default
      AppConfig.debugPrint('ℹ️ Using default location: US');
      return 'US';
    } catch (e) {
      AppConfig.debugPrint('❌ Error detecting location: $e');
      return 'US';
    }
  }

  /// Update current user's location based on device detection
  static Future<void> updateCurrentUserLocationFromDevice() async {
    final userId = DatabaseServiceCore.currentUserId;
    if (userId == null) return;

    try {
      final country = await detectUserLocation();
      await updateUserLocation(userId, country);
    } catch (e) {
      AppConfig.debugPrint('⚠️ Failed to update location from device: $e');
      // Silent fail - not critical
    }
  }
}