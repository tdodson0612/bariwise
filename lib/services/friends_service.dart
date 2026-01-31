// lib/services/friends_service.dart
// Handles friend requests, accepting, declining, removing, and visibility settings.
// Uses ONLY Dart-side filtering because Cloudflare Worker cannot handle OR filters.

import 'dart:convert';
import 'database_service_core.dart';
import 'auth_service.dart';
import '../exceptions/friend_request_exception.dart';

class FriendsService {
  // ==================================================
  // GET FRIENDS FOR CURRENT USER (CACHED)
  // ==================================================
  static Future<List<Map<String, dynamic>>> getFriends() async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    final userId = AuthService.currentUserId!;
    final cacheKey = 'cache_friends_$userId';

    try {
      // Try cache
      final cached = await DatabaseServiceCore.getCachedData(cacheKey);
      if (cached != null) {
        final decoded = List<Map<String, dynamic>>.from(jsonDecode(cached));
        return decoded;
      }

      // Fetch ALL rows (Worker can't OR-filter)
      final all = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'friend_requests',
        columns: ['*'],
      );

      final List<Map<String, dynamic>> friends = [];

      for (var row in all as List) {
        if (row['status'] != 'accepted') continue;

        if (row['sender'] == userId || row['receiver'] == userId) {
          final friendId = row['sender'] == userId ? row['receiver'] : row['sender'];

          final profile = await DatabaseServiceCore.workerQuery(
            action: 'select',
            table: 'profiles',
            columns: ['id','email','username','first_name','last_name','avatar_url'],
            filters: {'id': friendId},
            limit: 1,
          );

          if (profile != null && (profile as List).isNotEmpty) {
            friends.add(profile[0]);
          }
        }
      }

      // Cache result
      await DatabaseServiceCore.cacheData(cacheKey, jsonEncode(friends));
      return friends;
    } catch (e) {
      throw Exception('Failed to load friends: $e');
    }
  }

  // ==================================================
  // GET FRIENDS FOR ANY USER (not cached)
  // ==================================================
  static Future<List<Map<String, dynamic>>> getUserFriends(String userId) async {
    try {
      final all = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'friend_requests',
        columns: ['*'],
      );

      final List<Map<String, dynamic>> friends = [];

      for (var row in all as List) {
        if (row['status'] != 'accepted') continue;

        if (row['sender'] == userId || row['receiver'] == userId) {
          final friendId = row['sender'] == userId ? row['receiver'] : row['sender'];

          final profile = await DatabaseServiceCore.workerQuery(
            action: 'select',
            table: 'profiles',
            columns: ['id','email','username','first_name','last_name','avatar_url'],
            filters: {'id': friendId},
            limit: 1,
          );

          if (profile != null && (profile as List).isNotEmpty) {
            friends.add(profile[0]);
          }
        }
      }

      return friends;
    } catch (e) {
      throw Exception('Failed to load user friends: $e');
    }
  }

  // ==================================================
  // SEND FRIEND REQUEST
  // ==================================================
  static Future<String?> sendFriendRequest(String receiverId) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    final currentUser = AuthService.currentUserId!;
    if (receiverId == currentUser) {
      throw Exception('Cannot send a friend request to yourself');
    }

    try {
      final all = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'friend_requests',
        columns: ['*'],
      );

      for (var row in all as List) {
        final sender = row['sender'];
        final receiver = row['receiver'];
        final status = row['status'];

        final match = 
            (sender == currentUser && receiver == receiverId) ||
            (sender == receiverId && receiver == currentUser);

        if (match) {
          if (status == 'accepted') {
            throw FriendRequestException(
              'You are already friends',
              FriendRequestErrorType.alreadyFriends,
            );
          }
          if (status == 'pending' && sender == currentUser) {
            throw FriendRequestException(
              'Friend request already sent',
              FriendRequestErrorType.alreadySent,
            );
          }
          if (status == 'pending' && sender == receiverId) {
            throw FriendRequestException(
              'This user already sent you a request',
              FriendRequestErrorType.alreadyReceived,
            );
          }
        }
      }

      final response = await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'friend_requests',
        data: {
          'sender': currentUser,
          'receiver': receiverId,
          'status': 'pending',
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      if (response is Map && response['id'] != null) {
        return response['id'].toString();
      }
      if (response is List && response.isNotEmpty) {
        return response[0]['id'].toString();
      }

      return null;
    } catch (e) {
      // Re-throw custom exceptions as-is
      if (e is FriendRequestException) {
        rethrow;
      }
      throw Exception('Failed to send friend request: $e');
    }
  }

  // ==================================================
  // ACCEPT FRIEND REQUEST
  // ==================================================
  static Future<void> acceptFriendRequest(String requestId) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    final userId = AuthService.currentUserId!;

    try {
      final req = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'friend_requests',
        columns: ['receiver','status'],
        filters: {'id': requestId},
        limit: 1,
      );

      if (req == null || (req as List).isEmpty) {
        throw Exception('Request not found');
      }

      final row = req[0];

      if (row['receiver'] != userId) {
        throw Exception('Not allowed to accept this request');
      }

      if (row['status'] != 'pending') {
        throw Exception('This request is already ${row['status']}');
      }

      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'friend_requests',
        filters: {'id': requestId},
        data: {
          'status': 'accepted',
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      await DatabaseServiceCore.clearCache('cache_friends_$userId');

    } catch (e) {
      throw Exception('Failed to accept friend request: $e');
    }
  }

  // ==================================================
  // DECLINE FRIEND REQUEST
  // ==================================================
  static Future<void> declineFriendRequest(String requestId) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    try {
      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'friend_requests',
        filters: {'id': requestId},
      );
    } catch (e) {
      throw Exception('Failed to decline friend request: $e');
    }
  }

  // ==================================================
  // CANCEL A SENT FRIEND REQUEST
  // ==================================================
  static Future<void> cancelFriendRequest(String receiverId) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    final userId = AuthService.currentUserId!;

    try {
      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'friend_requests',
        filters: {
          'sender': userId,
          'receiver': receiverId,
        },
      );
    } catch (e) {
      throw Exception('Failed to cancel friend request: $e');
    }
  }

  // ==================================================
  // REMOVE FRIEND
  // ==================================================
  static Future<void> removeFriend(String friendId) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    final me = AuthService.currentUserId!;

    try {
      final all = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'friend_requests',
        columns: ['id','sender','receiver','status'],
      );

      for (var row in all as List) {
        if (row['status'] != 'accepted') continue;

        final match =
            (row['sender'] == me && row['receiver'] == friendId) ||
            (row['sender'] == friendId && row['receiver'] == me);

        if (match) {
          await DatabaseServiceCore.workerQuery(
            action: 'delete',
            table: 'friend_requests',
            filters: {'id': row['id']},
          );
        }
      }

      await DatabaseServiceCore.clearCache('cache_friends_$me');

    } catch (e) {
      throw Exception('Failed to remove friend: $e');
    }
  }

  // ==================================================
  // GET INCOMING FRIEND REQUESTS
  // ==================================================
  static Future<List<Map<String, dynamic>>> getFriendRequests() async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    final me = AuthService.currentUserId!;

    try {
      final all = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'friend_requests',
        columns: ['*'],
      );

      final List<Map<String, dynamic>> requests = [];

      for (var row in all as List) {
        if (row['receiver'] == me && row['status'] == 'pending') {
          final senderId = row['sender'];

          final profile = await DatabaseServiceCore.workerQuery(
            action: 'select',
            table: 'profiles',
            columns: ['id','email','username','first_name','last_name','avatar_url'],
            filters: {'id': senderId},
            limit: 1,
          );

          if (profile != null && (profile as List).isNotEmpty) {
            requests.add({
              'id': row['id'],
              'created_at': row['created_at'],
              'sender': profile[0],
            });
          }
        }
      }

      return requests;
    } catch (e) {
      throw Exception('Failed to load friend requests: $e');
    }
  }

  // ==================================================
  // GET SENT FRIEND REQUESTS
  // ==================================================
  static Future<List<Map<String, dynamic>>> getSentFriendRequests() async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    final me = AuthService.currentUserId!;

    try {
      final all = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'friend_requests',
        columns: ['*'],
      );

      final List<Map<String, dynamic>> requests = [];

      for (var row in all as List) {
        if (row['sender'] == me && row['status'] == 'pending') {
          final receiverId = row['receiver'];

          final profile = await DatabaseServiceCore.workerQuery(
            action: 'select',
            table: 'profiles',
            columns: ['id','email','username','first_name','last_name','avatar_url'],
            filters: {'id': receiverId},
            limit: 1,
          );

          if (profile != null && (profile as List).isNotEmpty) {
            requests.add({
              'id': row['id'],
              'created_at': row['created_at'],
              'receiver': profile[0],
            });
          }
        }
      }

      return requests;
    } catch (e) {
      throw Exception('Failed to load sent requests: $e');
    }
  }

  // ==================================================
  // CHECK FRIENDSHIP STATUS
  // ==================================================
  static Future<Map<String, dynamic>> checkFriendshipStatus(String userId) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    final me = AuthService.currentUserId!;

    if (userId == me) {
      return {
        'status': 'self',
        'requestId': null,
        'canSendRequest': false,
        'isOutgoing': false,
        'message': 'This is you!',
      };
    }

    try {
      final all = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'friend_requests',
        columns: ['*'],
      );

      for (var row in all as List) {
        final sender = row['sender'];
        final receiver = row['receiver'];
        final status = row['status'];

        final match =
            (sender == me && receiver == userId) ||
            (sender == userId && receiver == me);

        if (match) {
          final isOutgoing = sender == me;

          if (status == 'accepted') {
            return {
              'status': 'accepted',
              'requestId': row['id'],
              'canSendRequest': false,
              'isOutgoing': isOutgoing,
              'message': 'Friends',
            };
          }

          if (status == 'pending') {
            return {
              'status': isOutgoing ? 'pending_sent' : 'pending_received',
              'requestId': row['id'],
              'canSendRequest': false,
              'isOutgoing': isOutgoing,
              'message': isOutgoing ? 'Friend request sent' : 'Friend request received',
            };
          }
        }
      }

      return {
        'status': 'none',
        'requestId': null,
        'canSendRequest': true,
        'isOutgoing': false,
        'message': 'Not friends',
      };

    } catch (e) {
      return {
        'status': 'error',
        'requestId': null,
        'canSendRequest': false,
        'isOutgoing': false,
        'message': 'Error checking status',
      };
    }
  }

  // ==================================================
  // FRIENDS LIST VISIBILITY
  // ==================================================
  static Future<void> updateFriendsListVisibility(bool isVisible) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    final me = AuthService.currentUserId!;

    try {
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'profiles',
        filters: {'id': me},
        data: {
          'friends_list_visible': isVisible,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      await DatabaseServiceCore.clearCache('cache_user_profile_$me');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$me');

    } catch (e) {
      throw Exception('Failed to update visibility: $e');
    }
  }
}