// lib/services/messaging_service.dart
// ✅ FIXED VERSION - Using boolean true/false instead of integers for is_read

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

import 'auth_service.dart';
import 'friends_service.dart';
import 'database_service_core.dart';
import '../widgets/menu_icon_with_badge.dart';
import '../widgets/app_drawer.dart';

class MessagingService {
  // ✅ Track if we're currently updating read status to prevent race conditions
  static bool _isMarkingAsRead = false;

  // ==============================================
  // GET MESSAGES WITH SMART CACHING
  // ==============================================
  static Future<List<Map<String, dynamic>>> getMessages(
    String friendId, {
    bool forceRefresh = false,
  }) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    try {
      final uid = AuthService.currentUserId!;
      final cacheKey = 'cache_messages_${uid}_$friendId';
      final lastKey = 'cache_last_message_time_${uid}_$friendId';

      // ---------------------------
      // USE CACHED MESSAGES FIRST
      // ---------------------------
      if (!forceRefresh) {
        final cached = await DatabaseServiceCore.getCachedData(cacheKey);
        final timestamp = await DatabaseServiceCore.getCachedData(lastKey);

        if (cached != null && timestamp != null) {
          final cachedList =
              List<Map<String, dynamic>>.from(jsonDecode(cached));

          // Fetch NEW messages from Worker
          final allMessages = await DatabaseServiceCore.workerQuery(
            action: 'select',
            table: 'messages',
            columns: ['*'],
            orderBy: 'created_at',
            ascending: true,
          );

          final newMessages = <Map<String, dynamic>>[];
          for (var msg in allMessages as List) {
            final after = DateTime.parse(msg['created_at'])
                .isAfter(DateTime.parse(timestamp));

            final relevant = (msg['sender'] == uid && msg['receiver'] == friendId) ||
                             (msg['sender'] == friendId && msg['receiver'] == uid);

            if (after && relevant) newMessages.add(msg);
          }

          if (newMessages.isNotEmpty) {
            final combined = [...cachedList, ...newMessages];
            await DatabaseServiceCore.cacheData(cacheKey, jsonEncode(combined));
            await DatabaseServiceCore.cacheData(lastKey, DateTime.now().toUtc().toIso8601String());
            return combined;
          }

          return cachedList;
        }
      }

      // ---------------------------
      // FULL REFRESH FROM WORKER
      // ---------------------------
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'messages',
        columns: ['*'],
        orderBy: 'created_at',
        ascending: true,
      );

      final results = <Map<String, dynamic>>[];

      for (var msg in response as List) {
        if ((msg['sender'] == uid && msg['receiver'] == friendId) ||
            (msg['sender'] == friendId && msg['receiver'] == uid)) {
          results.add(msg);
        }
      }

      await DatabaseServiceCore.cacheData(cacheKey, jsonEncode(results));
      await DatabaseServiceCore.cacheData(lastKey, DateTime.now().toUtc().toIso8601String());

      return results;
    } catch (e) {
      throw Exception('Failed to load messages: $e');
    }
  }

  // ==============================================
  // SEND MESSAGE
  // ==============================================
  static Future<void> sendMessage(String receiverId, String content) async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    try {
      final uid = AuthService.currentUserId!;

      // ✅ FIXED: Use boolean false instead of integer 0
      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'messages',
        data: {
          'sender': uid,
          'receiver': receiverId,
          'content': content,
          'is_read': false, // ← CHANGED from 0 to false
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
      );

      // Clear message cache for both sender and receiver
      await DatabaseServiceCore.clearCache('cache_messages_${uid}_$receiverId');
      await DatabaseServiceCore.clearCache('cache_messages_${receiverId}_$uid');
      await DatabaseServiceCore.clearCache('cache_last_message_time_${uid}_$receiverId');
      await DatabaseServiceCore.clearCache('cache_last_message_time_${receiverId}_$uid');
      
      AppConfig.debugPrint('✅ Message sent, caches invalidated');
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  // ==============================================
  // ✅ FIXED: UNREAD MESSAGE COUNT (using boolean)
  // ==============================================
  static Future<int> getUnreadMessageCount() async {
    if (AuthService.currentUserId == null) {
      print('❌ getUnreadMessageCount: No user ID');
      return 0;
    }

    try {
      final uid = AuthService.currentUserId!;
      print('📬 Fetching unread count for user: $uid');

      // ✅ FIXED: Use boolean false instead of integer 0
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'messages',
        columns: ['id'],
        filters: {
          'receiver': uid,
          'is_read': false, // ← CHANGED from 0 to false
        },
      );

      final count = (response as List).length;
      print('📬 Database returned $count unread messages');
      
      // Show sample of messages for debugging
      if (count > 0 && AppConfig.enableDebugPrints) {
        print('📬 Sample unread messages: ${response.take(3).toList()}');
      }
      
      return count;
    } catch (e) {
      print('⚠️ Error getting unread count: $e');
      return 0;
    }
  }

  // ==============================================
  // ✅ FIXED: MARK SINGLE MESSAGE READ (using boolean)
  // ==============================================
  static Future<void> markMessageAsRead(String messageId) async {
    if (AuthService.currentUserId == null) return;

    try {
      // ✅ FIXED: Use boolean true instead of integer 1
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'messages',
        filters: {'id': messageId},
        data: {'is_read': true}, // ← CHANGED from 1 to true
      );
      
      // ✅ Invalidate unread badge cache immediately
      await MenuIconWithBadge.invalidateCache();
      await AppDrawer.invalidateUnreadCache();
      
      AppConfig.debugPrint('✅ Message $messageId marked as read');
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error marking message as read: $e');
    }
  }

  // ==============================================
  // ✅ FIXED: MARK ALL MESSAGES FROM USER AS READ
  // ==============================================
  static Future<void> markMessagesAsReadFrom(String senderId) async {
    if (AuthService.currentUserId == null) return;
    
    // ✅ Prevent race conditions - only one marking operation at a time
    if (_isMarkingAsRead) {
      AppConfig.debugPrint('⏭️ Already marking messages as read, skipping...');
      return;
    }

    _isMarkingAsRead = true;

    try {
      final uid = AuthService.currentUserId!;

      // ✅ FIXED: Get unread messages using boolean false
      final messages = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'messages',
        columns: ['id'],
        filters: {
          'receiver': uid,
          'sender': senderId,
          'is_read': false, // ← CHANGED from 0 to false
        },
      );

      final messageList = messages as List;
      
      if (messageList.isEmpty) {
        AppConfig.debugPrint('ℹ️ No unread messages to mark');
        return;
      }

      AppConfig.debugPrint('📝 Marking ${messageList.length} messages as read...');

      // ✅ CRITICAL: Update all messages in parallel using boolean true
      final updateFutures = messageList.map((msg) {
        return DatabaseServiceCore.workerQuery(
          action: 'update',
          table: 'messages',
          filters: {'id': msg['id']},
          data: {'is_read': true}, // ← CHANGED from 1 to true
        );
      }).toList();
      
      // Wait for ALL updates to complete
      await Future.wait(updateFutures);
      
      AppConfig.debugPrint('✅ ${messageList.length} messages marked as read in database');
      
      // ✅ CRITICAL: Immediately invalidate caches (don't wait)
      await MenuIconWithBadge.invalidateCache();
      await AppDrawer.invalidateUnreadCache();
      
      // Clear message caches
      await DatabaseServiceCore.clearCache('cache_messages_${uid}_$senderId');
      await DatabaseServiceCore.clearCache('cache_last_message_time_${uid}_$senderId');
      
      AppConfig.debugPrint('✅ All caches invalidated');
      
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error marking messages as read: $e');
    } finally {
      _isMarkingAsRead = false;
    }
  }

  // ==============================================
  // GET CHAT LIST (FRIENDS + LAST MESSAGE)
  // ==============================================
  static Future<List<Map<String, dynamic>>> getChatList() async {
    if (AuthService.currentUserId == null) {
      throw Exception('Please sign in to continue');
    }

    try {
      final uid = AuthService.currentUserId!;
      
      // Get friends list
      final friends = await FriendsService.getFriends();

      // Get all messages
      final allMessages = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'messages',
        columns: ['*'],
        orderBy: 'created_at',
        ascending: false,
      );

      final chats = <Map<String, dynamic>>[];

      for (final f in friends) {
        final fid = f['id'];
        Map<String, dynamic>? lastMessage;
        int unreadCount = 0;

        for (var msg in allMessages as List) {
          final isRelevant = (msg['sender'] == uid && msg['receiver'] == fid) ||
                            (msg['sender'] == fid && msg['receiver'] == uid);
          
          if (isRelevant) {
            // Get last message
            lastMessage ??= msg;
            
            // ✅ FIXED: Check for boolean false instead of integer 0
            // Also handle case where database might return integer 0
            if (msg['receiver'] == uid && (msg['is_read'] == false || msg['is_read'] == 0)) {
              unreadCount++;
            }
          }
        }

        chats.add({
          'friend': f,
          'lastMessage': lastMessage,
          'unreadCount': unreadCount,
        });
      }

      // Sort by last message timestamp
      chats.sort((a, b) {
        final A = a['lastMessage']?['created_at'];
        final B = b['lastMessage']?['created_at'];
        if (A == null && B == null) return 0;
        if (A == null) return 1;
        if (B == null) return -1;
        return B.compareTo(A);
      });

      return chats;
    } catch (e) {
      throw Exception('Failed to load chat list: $e');
    }
  }

  // ==============================================
  // ✅ FIXED: GET UNREAD COUNT PER SENDER (using boolean)
  // ==============================================
  static Future<Map<String, int>> getUnreadCountsBySender() async {
    if (AuthService.currentUserId == null) return {};

    try {
      final uid = AuthService.currentUserId!;

      // ✅ FIXED: Use boolean false instead of integer 0
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'messages',
        columns: ['sender'],
        filters: {
          'receiver': uid,
          'is_read': false, // ← CHANGED from 0 to false
        },
      );

      final counts = <String, int>{};
      for (var msg in response as List) {
        final sender = msg['sender'] as String;
        counts[sender] = (counts[sender] ?? 0) + 1;
      }

      return counts;
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error getting unread counts by sender: $e');
      return {};
    }
  }

  // ==============================================
  // ✅ IMPROVED: REFRESH BADGE (comprehensive refresh)
  // ==============================================
  static Future<void> refreshUnreadBadge() async {
    try {
      print('🔄 refreshUnreadBadge() started');
      
      // Step 1: Invalidate ALL badge caches
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_unread_count');
      await prefs.remove('cached_unread_count_time');
      print('🗑️ Badge caches cleared from SharedPreferences');
      
      // Step 2: Small delay to ensure cache is cleared
      await Future.delayed(Duration(milliseconds: 100));
      
      // Step 3: Force fetch fresh count directly from database
      print('📡 Fetching fresh count from database...');
      final freshCount = await getUnreadMessageCount();
      print('📬 Fresh count from database: $freshCount');
      
      // Step 4: Update cache with new count and fresh timestamp
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt('cached_unread_count', freshCount);
      await prefs.setInt('cached_unread_count_time', now);
      print('💾 New count cached: $freshCount at timestamp $now');
      
      // Step 5: Force both widgets to rebuild with new data
      print('🔄 Triggering widget refreshes...');
      
      // Refresh MenuIconWithBadge
      final menuIconState = MenuIconWithBadge.globalKey.currentState;
      if (menuIconState != null) {
        await menuIconState.refresh();
        print('✅ MenuIconWithBadge refreshed');
      } else {
        print('⚠️ MenuIconWithBadge state not available');
      }
      
      // ✅ FIXED: Call the public refresh() method instead of private _loadUnreadCount
      final drawerState = AppDrawer.globalKey.currentState;
      if (drawerState != null) {
        await drawerState.refresh();
        print('✅ AppDrawer refreshed');
      } else {
        print('⚠️ AppDrawer state not available');
      }
      
      print('✅ Badge refresh complete: displayed count should be $freshCount');
      
    } catch (e) {
      print('❌ Error refreshing badge: $e');
      // Don't rethrow - failing to refresh badge shouldn't crash the app
    }
  }

  // ==============================================
  // ✅ NEW: Force invalidate all message caches
  // ==============================================
  static Future<void> invalidateAllMessageCaches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get all keys that contain message cache data
      final allKeys = prefs.getKeys();
      final messageCacheKeys = allKeys.where((key) => 
        key.contains('cache_messages_') || 
        key.contains('cache_last_message_time_') ||
        key.contains('cached_unread_')
      ).toList();
      
      // Remove all message-related caches
      for (final key in messageCacheKeys) {
        await prefs.remove(key);
      }
      
      print('🗑️ Invalidated ${messageCacheKeys.length} message cache keys');
      
      // Force refresh badges
      await refreshUnreadBadge();
      
    } catch (e) {
      print('⚠️ Error invalidating message caches: $e');
    }
  }

  // ==============================================
  // ✅ NEW: Check if user has any unread messages
  // ==============================================
  static Future<bool> hasUnreadMessages() async {
    final count = await getUnreadMessageCount();
    return count > 0;
  }

  // ==============================================
  // ✅ NEW: Get total message count with user
  // ==============================================
  static Future<int> getTotalMessageCount(String friendId) async {
    if (AuthService.currentUserId == null) return 0;

    try {
      final uid = AuthService.currentUserId!;

      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'messages',
        columns: ['id'],
      );

      int count = 0;
      for (var msg in response as List) {
        if ((msg['sender'] == uid && msg['receiver'] == friendId) ||
            (msg['sender'] == friendId && msg['receiver'] == uid)) {
          count++;
        }
      }

      return count;
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error getting total message count: $e');
      return 0;
    }
  }

  // ==============================================
  // ✅ NEW: Clear message cache for specific user
  // ==============================================
  static Future<void> clearMessageCacheFor(String friendId) async {
    if (AuthService.currentUserId == null) return;

    final uid = AuthService.currentUserId!;
    
    await DatabaseServiceCore.clearCache('cache_messages_${uid}_$friendId');
    await DatabaseServiceCore.clearCache('cache_last_message_time_${uid}_$friendId');
    
    AppConfig.debugPrint('✅ Cleared message cache for friend: $friendId');
  }
}