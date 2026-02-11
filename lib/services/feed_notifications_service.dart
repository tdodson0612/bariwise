// lib/services/feed_notifications_service.dart - COMPLETE WITH ALL NOTIFICATION TYPES
import 'database_service_core.dart';
import 'auth_service.dart';
import '../config/app_config.dart';

/// Service for handling feed-related notifications
class FeedNotificationsService {
  
  /// Notification types
  static const String notifLike = 'like';
  static const String notifComment = 'comment';
  static const String notifCommentLike = 'comment_like'; // 🔥 NEW
  static const String notifCommentReply = 'comment_reply'; // 🔥 NEW
  static const String notifSave = 'save';
  static const String notifShare = 'share';
  static const String notifTag = 'tag'; // 🔥 NEW

  /// Create a notification when someone likes a post
  static Future<void> createLikeNotification({
    required String postId,
    required String postOwnerId,
    required String likerUserId,
    required String likerUsername,
  }) async {
    try {
      if (postOwnerId == likerUserId) {
        AppConfig.debugPrint('⏭️ Skipping like notification (user liked own post)');
        return;
      }

      final existing = await _checkExistingNotification(
        userId: postOwnerId,
        postId: postId,
        actorId: likerUserId,
        type: notifLike,
      );

      if (existing) {
        AppConfig.debugPrint('⏭️ Like notification already exists');
        return;
      }

      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'feed_notifications',
        data: {
          'user_id': postOwnerId,
          'post_id': postId,
          'actor_id': likerUserId,
          'actor_username': likerUsername,
          'type': notifLike,
          'is_read': false,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Like notification created for post: $postId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error creating like notification: $e');
    }
  }

  /// Create a notification when someone comments on a post
  static Future<void> createCommentNotification({
    required String postId,
    required String postOwnerId,
    required String commenterId,
    required String commenterUsername,
    required String commentPreview,
  }) async {
    try {
      if (postOwnerId == commenterId) {
        AppConfig.debugPrint('⏭️ Skipping comment notification (user commented on own post)');
        return;
      }

      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'feed_notifications',
        data: {
          'user_id': postOwnerId,
          'post_id': postId,
          'actor_id': commenterId,
          'actor_username': commenterUsername,
          'type': notifComment,
          'content': commentPreview.length > 100 
              ? '${commentPreview.substring(0, 100)}...' 
              : commentPreview,
          'is_read': false,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Comment notification created for post: $postId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error creating comment notification: $e');
    }
  }

  // 🔥 NEW: Create notification when someone likes a comment
  static Future<void> createCommentLikeNotification({
    required String postId,
    required String commentId,
    required String commentOwnerId,
    required String likerUserId,
    required String likerUsername,
  }) async {
    try {
      if (commentOwnerId == likerUserId) {
        AppConfig.debugPrint('⏭️ Skipping comment like notification (user liked own comment)');
        return;
      }

      final existing = await _checkExistingNotification(
        userId: commentOwnerId,
        commentId: commentId,
        actorId: likerUserId,
        type: notifCommentLike,
      );

      if (existing) {
        AppConfig.debugPrint('⏭️ Comment like notification already exists');
        return;
      }

      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'feed_notifications',
        data: {
          'user_id': commentOwnerId,
          'post_id': postId,
          'comment_id': commentId,
          'actor_id': likerUserId,
          'actor_username': likerUsername,
          'type': notifCommentLike,
          'is_read': false,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Comment like notification created for comment: $commentId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error creating comment like notification: $e');
    }
  }

  // 🔥 NEW: Create notification when someone replies to a comment
  static Future<void> createCommentReplyNotification({
    required String postId,
    required String parentCommentId,
    required String parentCommentOwnerId,
    required String replierId,
    required String replierUsername,
    required String replyPreview,
  }) async {
    try {
      if (parentCommentOwnerId == replierId) {
        AppConfig.debugPrint('⏭️ Skipping reply notification (user replied to own comment)');
        return;
      }

      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'feed_notifications',
        data: {
          'user_id': parentCommentOwnerId,
          'post_id': postId,
          'comment_id': parentCommentId,
          'actor_id': replierId,
          'actor_username': replierUsername,
          'type': notifCommentReply,
          'content': replyPreview.length > 100 
              ? '${replyPreview.substring(0, 100)}...' 
              : replyPreview,
          'is_read': false,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Comment reply notification created');
    } catch (e) {
      AppConfig.debugPrint('❌ Error creating comment reply notification: $e');
    }
  }

  /// Create a notification when someone saves a post
  static Future<void> createSaveNotification({
    required String postId,
    required String postOwnerId,
    required String saverId,
    required String saverUsername,
  }) async {
    try {
      if (postOwnerId == saverId) {
        AppConfig.debugPrint('⏭️ Skipping save notification (user saved own post)');
        return;
      }

      final existing = await _checkExistingNotification(
        userId: postOwnerId,
        postId: postId,
        actorId: saverId,
        type: notifSave,
      );

      if (existing) {
        AppConfig.debugPrint('⏭️ Save notification already exists');
        return;
      }

      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'feed_notifications',
        data: {
          'user_id': postOwnerId,
          'post_id': postId,
          'actor_id': saverId,
          'actor_username': saverUsername,
          'type': notifSave,
          'is_read': false,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Save notification created for post: $postId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error creating save notification: $e');
    }
  }

  // 🔥 NEW: Create notification when someone tags you in a post or comment
  static Future<void> createTagNotification({
    String? postId,
    String? commentId,
    required String taggedUserId,
    required String taggerUserId,
    required String taggerUsername,
  }) async {
    try {
      if (taggedUserId == taggerUserId) {
        AppConfig.debugPrint('⏭️ Skipping tag notification (user tagged themselves)');
        return;
      }

      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'feed_notifications',
        data: {
          'user_id': taggedUserId,
          if (postId != null) 'post_id': postId,
          if (commentId != null) 'comment_id': commentId,
          'actor_id': taggerUserId,
          'actor_username': taggerUsername,
          'type': notifTag,
          'is_read': false,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Tag notification created for user: $taggedUserId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error creating tag notification: $e');
    }
  }

  /// Get all notifications for current user
  static Future<List<Map<String, dynamic>>> getNotifications({
    int limit = 50,
    int offset = 0,
    bool unreadOnly = false,
  }) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      AppConfig.debugPrint('📬 Loading notifications for user: $userId');

      final filters = <String, dynamic>{'user_id': userId};
      
      if (unreadOnly) {
        filters['is_read'] = false;
      }

      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_notifications',
        filters: filters,
        orderBy: 'created_at',
        ascending: false,
        limit: limit + offset,
      );

      if (result == null || (result as List).isEmpty) {
        AppConfig.debugPrint('📭 No notifications found');
        return [];
      }

      final allNotifications = List<Map<String, dynamic>>.from(result as List);
      
      final startIndex = offset.clamp(0, allNotifications.length);
      final endIndex = (offset + limit).clamp(0, allNotifications.length);
      
      if (startIndex >= allNotifications.length) {
        return [];
      }

      final notifications = allNotifications.sublist(startIndex, endIndex);
      final enrichedNotifications = await _enrichNotifications(notifications);

      AppConfig.debugPrint('✅ Loaded ${enrichedNotifications.length} notifications');
      
      return enrichedNotifications;
    } catch (e) {
      AppConfig.debugPrint('❌ Error loading notifications: $e');
      return [];
    }
  }

  /// Enrich notifications with post/comment preview data
  static Future<List<Map<String, dynamic>>> _enrichNotifications(
    List<Map<String, dynamic>> notifications,
  ) async {
    final enriched = <Map<String, dynamic>>[];

    for (final notification in notifications) {
      try {
        final postId = notification['post_id']?.toString();
        final commentId = notification['comment_id']?.toString();
        
        // Enrich with post preview
        if (postId != null) {
          final postResult = await DatabaseServiceCore.workerQuery(
            action: 'select',
            table: 'feed_posts',
            filters: {'id': postId},
            limit: 1,
          );

          if (postResult != null && (postResult as List).isNotEmpty) {
            final post = (postResult as List).first;
            
            enriched.add({
              ...notification,
              'post_preview': {
                'content': post['content']?.toString() ?? '',
                'photo_url': post['photo_url'],
                'post_type': post['post_type'],
              },
            });
          } else {
            enriched.add({
              ...notification,
              'post_deleted': true,
            });
          }
        } 
        // Enrich with comment preview (for comment-specific notifications)
        else if (commentId != null) {
          final commentResult = await DatabaseServiceCore.workerQuery(
            action: 'select',
            table: 'feed_post_comments',
            filters: {'id': commentId},
            limit: 1,
          );

          if (commentResult != null && (commentResult as List).isNotEmpty) {
            final comment = (commentResult as List).first;
            
            enriched.add({
              ...notification,
              'comment_preview': {
                'content': comment['content']?.toString() ?? '',
                'photo_url': comment['photo_url'],
              },
            });
          } else {
            enriched.add({
              ...notification,
              'comment_deleted': true,
            });
          }
        } else {
          enriched.add(notification);
        }
      } catch (e) {
        AppConfig.debugPrint('⚠️ Error enriching notification: $e');
        enriched.add(notification);
      }
    }

    return enriched;
  }

  /// Mark a notification as read
  static Future<void> markAsRead(String notificationId) async {
    try {
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'feed_notifications',
        filters: {'id': notificationId},
        data: {'is_read': true},
      );

      AppConfig.debugPrint('✅ Notification marked as read: $notificationId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error marking notification as read: $e');
      throw Exception('Failed to mark notification as read: $e');
    }
  }

  /// Mark all notifications as read
  static Future<void> markAllAsRead() async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'feed_notifications',
        filters: {
          'user_id': userId,
          'is_read': false,
        },
        data: {'is_read': true},
      );

      AppConfig.debugPrint('✅ All notifications marked as read');
    } catch (e) {
      AppConfig.debugPrint('❌ Error marking all notifications as read: $e');
      throw Exception('Failed to mark all notifications as read: $e');
    }
  }

  /// Get unread notification count
  static Future<int> getUnreadCount() async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        return 0;
      }

      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_notifications',
        filters: {
          'user_id': userId,
          'is_read': false,
        },
      );

      if (result == null || (result as List).isEmpty) {
        return 0;
      }

      return (result as List).length;
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting unread count: $e');
      return 0;
    }
  }

  /// Delete a notification
  static Future<void> deleteNotification(String notificationId) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'feed_notifications',
        filters: {
          'id': notificationId,
          'user_id': userId,
        },
      );

      AppConfig.debugPrint('✅ Notification deleted: $notificationId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error deleting notification: $e');
      throw Exception('Failed to delete notification: $e');
    }
  }

  /// Delete all read notifications (cleanup)
  static Future<void> deleteAllRead() async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'feed_notifications',
        filters: {
          'user_id': userId,
          'is_read': true,
        },
      );

      AppConfig.debugPrint('✅ All read notifications deleted');
    } catch (e) {
      AppConfig.debugPrint('❌ Error deleting read notifications: $e');
      throw Exception('Failed to delete read notifications: $e');
    }
  }

  /// Check if a notification already exists (prevent duplicates)
  static Future<bool> _checkExistingNotification({
    required String userId,
    String? postId,
    String? commentId,
    required String actorId,
    required String type,
  }) async {
    try {
      final filters = {
        'user_id': userId,
        'actor_id': actorId,
        'type': type,
      };

      if (postId != null) {
        filters['post_id'] = postId;
      }

      if (commentId != null) {
        filters['comment_id'] = commentId;
      }

      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_notifications',
        filters: filters,
        limit: 1,
      );

      return result != null && (result as List).isNotEmpty;
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error checking existing notification: $e');
      return false;
    }
  }

  /// Group notifications by post (e.g., "John and 5 others liked your post")
  static List<Map<String, dynamic>> groupNotificationsByPost(
    List<Map<String, dynamic>> notifications,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};

    for (final notification in notifications) {
      final postId = notification['post_id']?.toString();
      final commentId = notification['comment_id']?.toString();
      final type = notification['type']?.toString();
      
      if (type == null) continue;
      
      // Group by post+type or comment+type
      final key = postId != null 
          ? '$postId-$type' 
          : commentId != null 
              ? 'comment-$commentId-$type' 
              : 'ungrouped-${notification['id']}';
      
      grouped.putIfAbsent(key, () => []).add(notification);
    }

    final result = <Map<String, dynamic>>[];

    for (final group in grouped.values) {
      if (group.isEmpty) continue;

      if (group.length == 1) {
        result.add(group.first);
      } else {
        final first = group.first;
        final otherCount = group.length - 1;
        
        result.add({
          ...first,
          'is_grouped': true,
          'grouped_count': group.length,
          'other_actors': group.skip(1).map((n) => n['actor_username']).toList(),
          'display_text': _getGroupedDisplayText(
            type: first['type'],
            firstActor: first['actor_username'],
            otherCount: otherCount,
          ),
        });
      }
    }

    result.sort((a, b) {
      final aTime = a['created_at']?.toString() ?? '';
      final bTime = b['created_at']?.toString() ?? '';
      return bTime.compareTo(aTime);
    });

    return result;
  }

  /// Get grouped display text
  static String _getGroupedDisplayText({
    required String type,
    required String firstActor,
    required int otherCount,
  }) {
    final otherText = otherCount == 1 ? '1 other' : '$otherCount others';
    
    switch (type) {
      case notifLike:
        return '$firstActor and $otherText liked your post';
      case notifComment:
        return '$firstActor and $otherText commented on your post';
      case notifCommentLike:
        return '$firstActor and $otherText liked your comment';
      case notifCommentReply:
        return '$firstActor and $otherText replied to your comment';
      case notifSave:
        return '$firstActor and $otherText saved your post';
      case notifTag:
        return '$firstActor and $otherText tagged you';
      default:
        return '$firstActor and $otherText interacted with your post';
    }
  }
}