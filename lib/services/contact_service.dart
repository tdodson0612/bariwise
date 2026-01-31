// lib/services/contact_service.dart
// Handles submitting contact/support messages through the Worker
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';
import '../services/database_service_core.dart';
import '../services/auth_service.dart';

class ContactService {
  // ==================================================
  // SUBMIT CONTACT MESSAGE
  // ==================================================
  static Future<void> submitContactMessage({
    required String name,
    required String email,
    required String message,
  }) async {
    // User may or may not be logged in — we allow both.
    final userId = AuthService.currentUserId;

    try {
      AppConfig.debugPrint('📨 Submitting contact message...');
      
      // Get device info
      String deviceInfo = 'Unknown';
      String appVersion = 'Unknown';
      
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        appVersion = '${packageInfo.version} (${packageInfo.buildNumber})';
        
        if (kIsWeb) {
          deviceInfo = 'Web Browser';
        } else if (Platform.isAndroid) {
          final androidInfo = await DeviceInfoPlugin().androidInfo;
          deviceInfo = 'Android ${androidInfo.version.release} - ${androidInfo.model}';
        } else if (Platform.isIOS) {
          final iosInfo = await DeviceInfoPlugin().iosInfo;
          deviceInfo = 'iOS ${iosInfo.systemVersion} - ${iosInfo.model}';
        }
      } catch (e) {
        AppConfig.debugPrint('⚠️ Could not get device info: $e');
      }
      
      // Combine name and email into the message body
      final fullMessage = '''
Name: $name
Email: $email

Message:
$message
''';
      
      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'contact_messages',
        data: {
          'message': fullMessage,
          'user_id': userId, // Will be null if not logged in
          'device_info': deviceInfo,
          'app_version': appVersion,
          'metadata': {
            'submitted_name': name,
            'submitted_email': email,
          },
        },
        requireAuth: false, // Don't require auth for contact messages
      );
      
      AppConfig.debugPrint('✅ Contact message submitted successfully');
    } catch (e) {
      AppConfig.debugPrint('❌ Failed to submit contact message: $e');
      throw Exception('Failed to submit contact message: $e');
    }
  }
}