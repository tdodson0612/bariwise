// lib/services/feed_posts_service.dart - COMPLETE VERSION WITH ADVANCED FEATURES
import 'database_service_core.dart';
import 'auth_service.dart';
import '../config/app_config.dart';
import 'feed_notifications_service.dart';

class FeedPostsService {
  /// Create a text post with visibility setting
  static Future<void> createTextPost({
    required String content,
    required String visibility, // 'public' or 'friends'
    List<String>? taggedUserIds, // 🔥 NEW: Tagged friends
  }) async {
    try {
      final userId = AuthService.currentUserId;
      final username = await AuthService.fetchCurrentUsername();

      if (userId == null || username == null) {
        throw Exception('User not authenticated');
      }

      if (content.trim().isEmpty) {
        throw Exception('Post content cannot be empty');
      }

      // Insert into feed_posts table with visibility
      final postResult = await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'feed_posts',
        data: {
          'user_id': userId,
          'username': username,
          'content': content.trim(),
          'post_type': 'text',
          'visibility': visibility,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Text post created with visibility: $visibility');

      // 🔥 NEW: Create tags if any
      if (taggedUserIds != null && taggedUserIds.isNotEmpty && postResult != null) {
        final postId = postResult['id']?.toString() ?? postResult.toString();
        await _createTags(
          postId: postId,
          taggedUserIds: taggedUserIds,
          taggerId: userId,
          taggerUsername: username,
        );
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Error creating text post: $e');
      throw Exception('Failed to create post: $e');
    }
  }

  /// Create a photo post with R2 URL
  static Future<void> createPhotoPost({
    required String caption,
    required String photoUrl,
    required String visibility,
    List<String>? taggedUserIds, // 🔥 NEW
  }) async {
    try {
      final userId = AuthService.currentUserId;
      final username = await AuthService.fetchCurrentUsername();

      if (userId == null || username == null) {
        throw Exception('User not authenticated');
      }

      final postResult = await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'feed_posts',
        data: {
          'user_id': userId,
          'username': username,
          'content': caption.trim(),
          'post_type': 'photo',
          'photo_url': photoUrl,
          'visibility': visibility,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Photo post created with visibility: $visibility');

      // 🔥 NEW: Create tags
      if (taggedUserIds != null && taggedUserIds.isNotEmpty && postResult != null) {
        final postId = postResult['id']?.toString() ?? postResult.toString();
        await _createTags(
          postId: postId,
          taggedUserIds: taggedUserIds,
          taggerId: userId,
          taggerUsername: username,
        );
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Error creating photo post: $e');
      throw Exception('Failed to create photo post: $e');
    }
  }

  /// Share a recipe to the feed
  static Future<void> shareRecipeToFeed({
    required String recipeName,
    String? description,
    required String ingredients,
    required String directions,
    required String visibility,
  }) async {
    try {
      final userId = AuthService.currentUserId;
      final username = await AuthService.fetchCurrentUsername();

      if (userId == null || username == null) {
        throw Exception('User not authenticated');
      }

      final postContent = _formatRecipeForFeed(
        recipeName: recipeName,
        description: description,
        ingredients: ingredients,
        directions: directions,
      );

      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'feed_posts',
        data: {
          'user_id': userId,
          'username': username,
          'content': postContent,
          'post_type': 'recipe_share',
          'recipe_name': recipeName,
          'visibility': visibility,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Recipe shared to feed: $recipeName');
    } catch (e) {
      AppConfig.debugPrint('❌ Error sharing recipe to feed: $e');
      throw Exception('Failed to share recipe: $e');
    }
  }

  static String _formatRecipeForFeed({
    required String recipeName,
    String? description,
    required String ingredients,
    required String directions,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('🍽️ **$recipeName**');
    buffer.writeln();
    if (description != null && description.trim().isNotEmpty) {
      buffer.writeln(description);
      buffer.writeln();
    }
    buffer.writeln('📋 **Ingredients:**');
    buffer.writeln(ingredients);
    buffer.writeln();
    buffer.writeln('👨‍🍳 **Directions:**');
    buffer.writeln(directions);
    return buffer.toString();
  }

  // 🔥 NEW: Create tags for post or comment
  static Future<void> _createTags({
    String? postId,
    String? commentId,
    required List<String> taggedUserIds,
    required String taggerId,
    required String taggerUsername,
  }) async {
    try {
      for (final taggedUserId in taggedUserIds) {
        // Don't tag yourself
        if (taggedUserId == taggerId) continue;

        await DatabaseServiceCore.workerQuery(
          action: 'insert',
          table: 'feed_tags',
          data: {
            if (postId != null) 'post_id': postId,
            if (commentId != null) 'comment_id': commentId,
            'tagged_user_id': taggedUserId,
            'tagger_user_id': taggerId,
            'created_at': DateTime.now().toIso8601String(),
          },
        );

        // Create tag notification
        await FeedNotificationsService.createTagNotification(
          postId: postId,
          commentId: commentId,
          taggedUserId: taggedUserId,
          taggerUserId: taggerId,
          taggerUsername: taggerUsername,
        );
      }

      AppConfig.debugPrint('✅ Created ${taggedUserIds.length} tags');
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error creating tags: $e');
      // Don't throw - tags are not critical
    }
  }

  /// Get feed posts based on current user's friend status
  static Future<List<Map<String, dynamic>>> getFeedPosts({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final userId = AuthService.currentUserId;
      
      AppConfig.debugPrint('🔍 getFeedPosts called - userId: $userId');
      
      if (userId == null) {
        AppConfig.debugPrint('⚠️ User not authenticated, showing only public posts');
        return await _getPublicPostsOnly(limit: limit, offset: offset);
      }

      AppConfig.debugPrint('📱 Loading feed for authenticated user: $userId');

      final friendIds = await _getFriendIds(userId);
      AppConfig.debugPrint('👥 Total friends (including self): ${friendIds.length}');

      final publicPosts = await _getPublicPosts(limit: 100);
      AppConfig.debugPrint('✅ Found ${publicPosts.length} public posts');

      List<Map<String, dynamic>> friendsPosts = [];
      
      if (friendIds.length > 1) {
        AppConfig.debugPrint('📡 Querying FRIENDS-ONLY posts...');
        friendsPosts = await _getFriendsOnlyPosts(friendIds, limit: 100);
        AppConfig.debugPrint('✅ Found ${friendsPosts.length} friends-only posts');
      }

      final allPosts = [...publicPosts, ...friendsPosts];
      final uniquePosts = _deduplicateAndSort(allPosts);
      final paginatedPosts = _applyPagination(uniquePosts, limit: limit, offset: offset);

      AppConfig.debugPrint('✅ Returning ${paginatedPosts.length} posts (total: ${uniquePosts.length})');

      return paginatedPosts;
    } catch (e, stackTrace) {
      AppConfig.debugPrint('❌ Error loading feed: $e');
      AppConfig.debugPrint('Stack trace: $stackTrace');
      return [];
    }
  }

  static Future<Set<String>> _getFriendIds(String userId) async {
    final friendIds = <String>{userId};
    
    try {
      final friendsResult = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'friend_requests',
        filters: {'status': 'accepted'},
        columns: ['sender_id', 'receiver_id'],
      );

      if (friendsResult != null && (friendsResult as List).isNotEmpty) {
        for (final friendship in friendsResult) {
          final sender = friendship['sender_id']?.toString();
          final receiver = friendship['receiver_id']?.toString();
          
          if (sender == userId && receiver != null) {
            friendIds.add(receiver);
          } else if (receiver == userId && sender != null) {
            friendIds.add(sender);
          }
        }
      }
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error fetching friend IDs: $e');
    }

    return friendIds;
  }

  static Future<List<Map<String, dynamic>>> _getPublicPosts({int limit = 100}) async {
    try {
      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_posts',
        filters: {'visibility': 'public'},
        orderBy: 'created_at',
        ascending: false,
        limit: limit,
      );

      if (result == null || (result as List).isEmpty) {
        return [];
      }

      return List<Map<String, dynamic>>.from(result as List);
    } catch (e) {
      AppConfig.debugPrint('❌ Error fetching public posts: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> _getFriendsOnlyPosts(
    Set<String> friendIds, {
    int limit = 100,
  }) async {
    final friendsPosts = <Map<String, dynamic>>[];

    try {
      for (final friendId in friendIds) {
        final result = await DatabaseServiceCore.workerQuery(
          action: 'select',
          table: 'feed_posts',
          filters: {
            'visibility': 'friends',
            'user_id': friendId,
          },
          orderBy: 'created_at',
          ascending: false,
          limit: 50,
        );

        if (result != null && (result as List).isNotEmpty) {
          friendsPosts.addAll(List<Map<String, dynamic>>.from(result as List));
        }
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Error fetching friends-only posts: $e');
    }

    return friendsPosts;
  }

  static List<Map<String, dynamic>> _deduplicateAndSort(List<Map<String, dynamic>> posts) {
    final seenIds = <String>{};
    final uniquePosts = posts.where((post) {
      final id = post['id']?.toString();
      if (id == null || seenIds.contains(id)) return false;
      seenIds.add(id);
      return true;
    }).toList();

    uniquePosts.sort((a, b) {
      final aTime = a['created_at']?.toString() ?? '';
      final bTime = b['created_at']?.toString() ?? '';
      return bTime.compareTo(aTime);
    });

    return uniquePosts;
  }

  static List<Map<String, dynamic>> _applyPagination(
    List<Map<String, dynamic>> posts, {
    required int limit,
    required int offset,
  }) {
    if (posts.isEmpty) return [];
    
    final startIndex = offset.clamp(0, posts.length);
    final endIndex = (offset + limit).clamp(0, posts.length);
    
    if (startIndex >= posts.length) return [];
    
    return posts.sublist(startIndex, endIndex);
  }

  static Future<List<Map<String, dynamic>>> _getPublicPostsOnly({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_posts',
        filters: {'visibility': 'public'},
        orderBy: 'created_at',
        ascending: false,
        limit: limit + offset + 10,
      );

      if (result == null || (result as List).isEmpty) {
        return [];
      }

      final allPosts = List<Map<String, dynamic>>.from(result as List);
      return _applyPagination(allPosts, limit: limit, offset: offset);
    } catch (e) {
      AppConfig.debugPrint('❌ Error loading public posts: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getFeedPostsFromFriends({
    int limit = 20,
    int offset = 0,
  }) async {
    return getFeedPosts(limit: limit, offset: offset);
  }

  static Future<void> reportPost({
    required String postId,
    required String reason,
  }) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final existingReport = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'post_reports',
        filters: {
          'post_id': postId,
          'reporter_user_id': userId,
        },
        limit: 1,
      );

      if (existingReport != null && (existingReport as List).isNotEmpty) {
        throw Exception('You have already reported this post');
      }

      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'post_reports',
        data: {
          'post_id': postId,
          'reporter_user_id': userId,
          'reason': reason,
          'status': 'pending',
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Post reported: $postId, Reason: $reason');
    } catch (e) {
      AppConfig.debugPrint('❌ Error reporting post: $e');
      throw Exception('Failed to report post: $e');
    }
  }

  static Future<void> deletePost(String postId) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final postCheck = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_posts',
        filters: {'id': postId},
        limit: 1,
      );

      if (postCheck == null || (postCheck as List).isEmpty) {
        throw Exception('Post not found');
      }

      final post = (postCheck as List).first;
      final postOwnerId = post['user_id']?.toString();
      
      if (postOwnerId != userId) {
        throw Exception('You can only delete your own posts');
      }

      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'feed_posts',
        filters: {
          'id': postId.toString(),
          'user_id': userId.toString(),
        },
      );

      AppConfig.debugPrint('✅ Post deleted successfully: $postId');
    } catch (e, stackTrace) {
      AppConfig.debugPrint('❌ Error deleting post: $e');
      AppConfig.debugPrint('Stack trace: $stackTrace');
      throw Exception('Failed to delete post: $e');
    }
  }

  static Future<void> likePost(String postId) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'feed_post_likes',
        data: {
          'post_id': postId,
          'user_id': userId,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Post liked: $postId');
      
      try {
        final username = await AuthService.fetchCurrentUsername();
        
        final postResult = await DatabaseServiceCore.workerQuery(
          action: 'select',
          table: 'feed_posts',
          filters: {'id': postId},
          limit: 1,
        );
        
        if (postResult != null && (postResult as List).isNotEmpty) {
          final post = (postResult as List).first;
          final postOwnerId = post['user_id']?.toString();
          
          if (postOwnerId != null && username != null) {
            await FeedNotificationsService.createLikeNotification(
              postId: postId,
              postOwnerId: postOwnerId,
              likerUserId: userId,
              likerUsername: username,
            );
          }
        }
      } catch (notifError) {
        AppConfig.debugPrint('⚠️ Failed to create like notification: $notifError');
      }
      
    } catch (e) {
      AppConfig.debugPrint('❌ Error liking post: $e');
      
      if (e.toString().toLowerCase().contains('duplicate')) {
        throw Exception('You have already liked this post');
      }
      
      throw Exception('Failed to like post: $e');
    }
  }

  static Future<void> unlikePost(String postId) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'feed_post_likes',
        filters: {
          'post_id': postId,
          'user_id': userId,
        },
      );

      AppConfig.debugPrint('✅ Post unliked: $postId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error unliking post: $e');
      throw Exception('Failed to unlike post: $e');
    }
  }

  static Future<bool> hasUserLikedPost(String postId) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        return false;
      }

      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_post_likes',
        filters: {
          'post_id': postId,
          'user_id': userId,
        },
        limit: 1,
      );

      return result != null && (result as List).isNotEmpty;
    } catch (e) {
      AppConfig.debugPrint('❌ Error checking like status: $e');
      return false;
    }
  }

  static Future<int> getPostLikeCount(String postId) async {
    try {
      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_post_likes',
        filters: {'post_id': postId},
      );

      if (result == null || (result as List).isEmpty) {
        return 0;
      }

      return (result as List).length;
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting like count: $e');
      return 0;
    }
  }

  /// Get comments for a post (with replies nested)
  static Future<List<Map<String, dynamic>>> getPostComments(
    String postId, {
    int limit = 50,
  }) async {
    try {
      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_post_comments',
        filters: {'post_id': postId, 'parent_comment_id': null}, // Only top-level comments
        orderBy: 'created_at',
        ascending: true,
        limit: limit,
      );

      if (result == null || (result as List).isEmpty) {
        return [];
      }

      final comments = List<Map<String, dynamic>>.from(result as List);

      // 🔥 NEW: Load replies for each comment
      for (var comment in comments) {
        final commentId = comment['id']?.toString();
        if (commentId != null) {
          comment['replies'] = await getCommentReplies(commentId);
          comment['like_count'] = await getCommentLikeCount(commentId);
          comment['user_has_liked'] = await hasUserLikedComment(commentId);
        }
      }

      return comments;
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting comments: $e');
      return [];
    }
  }

  // 🔥 NEW: Get replies to a comment
  static Future<List<Map<String, dynamic>>> getCommentReplies(String commentId) async {
    try {
      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_post_comments',
        filters: {'parent_comment_id': commentId},
        orderBy: 'created_at',
        ascending: true,
      );

      if (result == null || (result as List).isEmpty) {
        return [];
      }

      final replies = List<Map<String, dynamic>>.from(result as List);

      // Load like data for replies
      for (var reply in replies) {
        final replyId = reply['id']?.toString();
        if (replyId != null) {
          reply['like_count'] = await getCommentLikeCount(replyId);
          reply['user_has_liked'] = await hasUserLikedComment(replyId);
        }
      }

      return replies;
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting comment replies: $e');
      return [];
    }
  }

  /// Add a comment to a post (or reply to a comment)
  static Future<void> addComment({
    required String postId,
    required String content,
    String? parentCommentId, // 🔥 NEW: For replies
    String? photoUrl, // 🔥 NEW: For photos
    List<String>? taggedUserIds, // 🔥 NEW: For tags
  }) async {
    try {
      final userId = AuthService.currentUserId;
      final username = await AuthService.fetchCurrentUsername();

      if (userId == null || username == null) {
        throw Exception('User not authenticated');
      }

      if (content.trim().isEmpty && photoUrl == null) {
        throw Exception('Comment cannot be empty');
      }

      final commentResult = await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'feed_post_comments',
        data: {
          'post_id': postId,
          'user_id': userId,
          'username': username,
          'content': content.trim(),
          if (parentCommentId != null) 'parent_comment_id': parentCommentId,
          if (photoUrl != null) 'photo_url': photoUrl,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Comment added to post: $postId');

      final commentId = commentResult?['id']?.toString() ?? commentResult.toString();
      
      // 🔥 Create tags if any
      if (taggedUserIds != null && taggedUserIds.isNotEmpty) {
        await _createTags(
          commentId: commentId,
          taggedUserIds: taggedUserIds,
          taggerId: userId,
          taggerUsername: username,
        );
      }
      
      // Create notification
      try {
        if (parentCommentId != null) {
          // 🔥 NEW: Notify parent comment owner about reply
          final parentResult = await DatabaseServiceCore.workerQuery(
            action: 'select',
            table: 'feed_post_comments',
            filters: {'id': parentCommentId},
            limit: 1,
          );

          if (parentResult != null && (parentResult as List).isNotEmpty) {
            final parentComment = (parentResult as List).first;
            final parentOwnerId = parentComment['user_id']?.toString();

            if (parentOwnerId != null && parentOwnerId != userId) {
              await FeedNotificationsService.createCommentReplyNotification(
                postId: postId,
                parentCommentId: parentCommentId,
                parentCommentOwnerId: parentOwnerId,
                replierId: userId,
                replierUsername: username,
                replyPreview: content.trim(),
              );
            }
          }
        } else {
          // Notify post owner about comment
          final postResult = await DatabaseServiceCore.workerQuery(
            action: 'select',
            table: 'feed_posts',
            filters: {'id': postId},
            limit: 1,
          );
          
          if (postResult != null && (postResult as List).isNotEmpty) {
            final post = (postResult as List).first;
            final postOwnerId = post['user_id']?.toString();
            
            if (postOwnerId != null) {
              await FeedNotificationsService.createCommentNotification(
                postId: postId,
                postOwnerId: postOwnerId,
                commenterId: userId,
                commenterUsername: username,
                commentPreview: content.trim(),
              );
            }
          }
        }
      } catch (notifError) {
        AppConfig.debugPrint('⚠️ Failed to create comment notification: $notifError');
      }
      
    } catch (e) {
      AppConfig.debugPrint('❌ Error adding comment: $e');
      throw Exception('Failed to add comment: $e');
    }
  }

  static Future<void> deleteComment(String commentId) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'feed_post_comments',
        filters: {
          'id': commentId,
          'user_id': userId,
        },
      );

      AppConfig.debugPrint('✅ Comment deleted: $commentId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error deleting comment: $e');
      throw Exception('Failed to delete comment: $e');
    }
  }

  // 🔥 NEW: Like a comment
  static Future<void> likeComment(String commentId) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'feed_comment_likes',
        data: {
          'comment_id': commentId,
          'user_id': userId,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Comment liked: $commentId');
      
      // Create notification for comment owner
      try {
        final username = await AuthService.fetchCurrentUsername();
        
        final commentResult = await DatabaseServiceCore.workerQuery(
          action: 'select',
          table: 'feed_post_comments',
          filters: {'id': commentId},
          limit: 1,
        );
        
        if (commentResult != null && (commentResult as List).isNotEmpty) {
          final comment = (commentResult as List).first;
          final commentOwnerId = comment['user_id']?.toString();
          final postId = comment['post_id']?.toString();
          
          if (commentOwnerId != null && username != null && postId != null) {
            await FeedNotificationsService.createCommentLikeNotification(
              postId: postId,
              commentId: commentId,
              commentOwnerId: commentOwnerId,
              likerUserId: userId,
              likerUsername: username,
            );
          }
        }
      } catch (notifError) {
        AppConfig.debugPrint('⚠️ Failed to create comment like notification: $notifError');
      }
      
    } catch (e) {
      AppConfig.debugPrint('❌ Error liking comment: $e');
      
      if (e.toString().toLowerCase().contains('duplicate')) {
        throw Exception('You have already liked this comment');
      }
      
      throw Exception('Failed to like comment: $e');
    }
  }

  // 🔥 NEW: Unlike a comment
  static Future<void> unlikeComment(String commentId) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'feed_comment_likes',
        filters: {
          'comment_id': commentId,
          'user_id': userId,
        },
      );

      AppConfig.debugPrint('✅ Comment unliked: $commentId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error unliking comment: $e');
      throw Exception('Failed to unlike comment: $e');
    }
  }

  // 🔥 NEW: Check if user has liked a comment
  static Future<bool> hasUserLikedComment(String commentId) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        return false;
      }

      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_comment_likes',
        filters: {
          'comment_id': commentId,
          'user_id': userId,
        },
        limit: 1,
      );

      return result != null && (result as List).isNotEmpty;
    } catch (e) {
      AppConfig.debugPrint('❌ Error checking comment like status: $e');
      return false;
    }
  }

  // 🔥 NEW: Get comment like count
  static Future<int> getCommentLikeCount(String commentId) async {
    try {
      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_comment_likes',
        filters: {'comment_id': commentId},
      );

      if (result == null || (result as List).isEmpty) {
        return 0;
      }

      return (result as List).length;
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting comment like count: $e');
      return 0;
    }
  }

  static Future<void> savePost(String postId) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'feed_post_saves',
        data: {
          'post_id': postId,
          'user_id': userId,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Post saved: $postId');
      
      try {
        final username = await AuthService.fetchCurrentUsername();
        
        final postResult = await DatabaseServiceCore.workerQuery(
          action: 'select',
          table: 'feed_posts',
          filters: {'id': postId},
          limit: 1,
        );
        
        if (postResult != null && (postResult as List).isNotEmpty) {
          final post = (postResult as List).first;
          final postOwnerId = post['user_id']?.toString();
          
          if (postOwnerId != null && username != null) {
            await FeedNotificationsService.createSaveNotification(
              postId: postId,
              postOwnerId: postOwnerId,
              saverId: userId,
              saverUsername: username,
            );
          }
        }
      } catch (notifError) {
        AppConfig.debugPrint('⚠️ Failed to create save notification: $notifError');
      }
      
    } catch (e) {
      AppConfig.debugPrint('❌ Error saving post: $e');
      
      if (e.toString().toLowerCase().contains('duplicate')) {
        throw Exception('You have already saved this post');
      }
      
      throw Exception('Failed to save post: $e');
    }
  }

  static Future<void> unsavePost(String postId) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'feed_post_saves',
        filters: {
          'post_id': postId,
          'user_id': userId,
        },
      );

      AppConfig.debugPrint('✅ Post unsaved: $postId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error unsaving post: $e');
      throw Exception('Failed to unsave post: $e');
    }
  }

  static Future<bool> hasUserSavedPost(String postId) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        return false;
      }

      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_post_saves',
        filters: {
          'post_id': postId,
          'user_id': userId,
        },
        limit: 1,
      );

      return result != null && (result as List).isNotEmpty;
    } catch (e) {
      AppConfig.debugPrint('❌ Error checking save status: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getSavedPosts({
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final savedResult = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_post_saves',
        filters: {'user_id': userId},
        orderBy: 'created_at',
        ascending: false,
      );

      if (savedResult == null || (savedResult as List).isEmpty) {
        return [];
      }

      final savedPostIds = (savedResult as List)
          .map((save) => save['post_id']?.toString())
          .where((id) => id != null)
          .toSet();

      if (savedPostIds.isEmpty) {
        return [];
      }

      final posts = <Map<String, dynamic>>[];
      
      for (final postId in savedPostIds) {
        final postResult = await DatabaseServiceCore.workerQuery(
          action: 'select',
          table: 'feed_posts',
          filters: {'id': postId},
          limit: 1,
        );

        if (postResult != null && (postResult as List).isNotEmpty) {
          posts.add((postResult as List).first);
        }
      }

      posts.sort((a, b) {
        final aTime = a['created_at']?.toString() ?? '';
        final bTime = b['created_at']?.toString() ?? '';
        return bTime.compareTo(aTime);
      });

      return _applyPagination(posts, limit: limit, offset: offset);
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting saved posts: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getUserPosts({
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_posts',
        filters: {'user_id': userId},
        orderBy: 'created_at',
        ascending: false,
      );

      if (result == null || (result as List).isEmpty) {
        return [];
      }

      final allPosts = List<Map<String, dynamic>>.from(result as List);
      
      return _applyPagination(allPosts, limit: limit, offset: offset);
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting user posts: $e');
      return [];
    }
  }

  static Future<Map<String, int>> getPostStats(String postId) async {
    try {
      final likeCount = await getPostLikeCount(postId);
      final comments = await getPostComments(postId);
      final commentCount = comments.length;

      return {
        'likes': likeCount,
        'comments': commentCount,
        'shares': 0,
      };
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting post stats: $e');
      return {'likes': 0, 'comments': 0, 'shares': 0};
    }
  }
}