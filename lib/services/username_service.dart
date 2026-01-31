// lib/services/username_service.dart
// Handles username availability checks.

import 'database_service_core.dart'; // workerQuery

class UsernameService {
  // ==================================================
  // CHECK USERNAME AVAILABILITY
  // ==================================================

  static Future<bool> isUsernameAvailable(String username) async {
    try {
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'profiles',
        columns: ['id'],
        filters: {'username': username},
        limit: 1,
      );

      // Username is available if the returned list is empty
      return response == null || (response as List).isEmpty;
    } catch (e) {
      throw Exception('Failed to check username availability: $e');
    }
  }
}
