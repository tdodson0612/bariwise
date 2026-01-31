// lib/services/feed_posts_service.dart - COMPLETE VERSION WITH PHOTO SUPPORT
import 'database_service_core.dart';
import 'auth_service.dart';
import '../config/app_config.dart';

class FeedPostsService {
  /// Create a text post with visibility setting
  static Future<void> createTextPost({
    required String content,
    required String visibility, // 'public' or 'friends'
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
      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'feed_posts',
        data: {
          'user_id': userId,
          'username': username,
          'content': content.trim(),
          'post_type': 'text',
          'visibility': visibility, // 'public' or 'friends'
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Text post created with visibility: $visibility');
    } catch (e) {
      AppConfig.debugPrint('❌ Error creating text post: $e');
      throw Exception('Failed to create post: $e');
    }
  }

  /// 🔥 NEW: Create a photo post with R2 URL
  static Future<void> createPhotoPost({
    required String caption,
    required String photoUrl,
    required String visibility, // 'public' or 'friends'
  }) async {
    try {
      final userId = AuthService.currentUserId;
      final username = await AuthService.fetchCurrentUsername();

      if (userId == null || username == null) {
        throw Exception('User not authenticated');
      }

      // Insert into feed_posts table with photo URL
      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'feed_posts',
        data: {
          'user_id': userId,
          'username': username,
          'content': caption.trim(),
          'post_type': 'photo',
          'photo_url': photoUrl, // R2 public URL
          'visibility': visibility,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Photo post created with visibility: $visibility');
    } catch (e) {
      AppConfig.debugPrint('❌ Error creating photo post: $e');
      throw Exception('Failed to create photo post: $e');
    }
  }

  /// Share a recipe to the feed
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

  /// Get feed posts based on current user's friend status
  /// Shows: Public posts + Friends-only posts from friends
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

      // Step 1: Get friend IDs
      final friendIds = await _getFriendIds(userId);
      AppConfig.debugPrint('👥 Total friends (including self): ${friendIds.length}');

      // Step 2: Get public posts
      AppConfig.debugPrint('📡 Querying PUBLIC posts...');
      final publicPosts = await _getPublicPosts(limit: 100);
      AppConfig.debugPrint('✅ Found ${publicPosts.length} public posts');

      // Step 3: Get friends-only posts
      List<Map<String, dynamic>> friendsPosts = [];
      
      if (friendIds.length > 1) {
        AppConfig.debugPrint('📡 Querying FRIENDS-ONLY posts...');
        friendsPosts = await _getFriendsOnlyPosts(friendIds, limit: 100);
        AppConfig.debugPrint('✅ Found ${friendsPosts.length} friends-only posts');
      }

      // Step 4: Combine, deduplicate, and sort
      final allPosts = [...publicPosts, ...friendsPosts];
      final uniquePosts = _deduplicateAndSort(allPosts);

      // Step 5: Apply pagination safely
      final paginatedPosts = _applyPagination(uniquePosts, limit: limit, offset: offset);

      AppConfig.debugPrint('✅ Returning ${paginatedPosts.length} posts (total: ${uniquePosts.length})');

      return paginatedPosts;
    } catch (e, stackTrace) {
      AppConfig.debugPrint('❌ Error loading feed: $e');
      AppConfig.debugPrint('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Get friend IDs for the current user
  static Future<Set<String>> _getFriendIds(String userId) async {
    final friendIds = <String>{userId}; // Include self
    
    try {
      final friendsResult = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'friend_requests',
        filters: {'status': 'accepted'},
        columns: ['sender', 'receiver'],
      );

      if (friendsResult != null && (friendsResult as List).isNotEmpty) {
        AppConfig.debugPrint('👥 Found ${(friendsResult as List).length} accepted friendships');
        
        for (final friendship in friendsResult) {
          final sender = friendship['sender']?.toString();
          final receiver = friendship['receiver']?.toString();
          
          if (sender == userId && receiver != null) {
            friendIds.add(receiver);
          } else if (receiver == userId && sender != null) {
            friendIds.add(sender);
          }
        }
      } else {
        AppConfig.debugPrint('👥 No accepted friend requests found');
      }
    } catch (e) {
      AppConfig.debugPrint('⚠️ Error fetching friend IDs: $e');
    }

    return friendIds;
  }

  /// Get public posts ONLY (filter by visibility)
  static Future<List<Map<String, dynamic>>> _getPublicPosts({
    int limit = 100,
  }) async {
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
        AppConfig.debugPrint('⚠️ No public posts found in database');
        return [];
      }

      final posts = List<Map<String, dynamic>>.from(result as List);
      AppConfig.debugPrint('✅ Fetched ${posts.length} public posts from database');
      
      return posts;
    } catch (e) {
      AppConfig.debugPrint('❌ Error fetching public posts: $e');
      return [];
    }
  }

  /// Get friends-only posts from friend list
  static Future<List<Map<String, dynamic>>> _getFriendsOnlyPosts(
    Set<String> friendIds, {
    int limit = 100,
  }) async {
    final friendsPosts = <Map<String, dynamic>>[];

    try {
      // Query friends-only posts for each friend
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
      
      AppConfig.debugPrint('✅ Found ${friendsPosts.length} friends-only posts total');
      
    } catch (e) {
      AppConfig.debugPrint('❌ Error fetching friends-only posts: $e');
    }

    return friendsPosts;
  }

  /// Deduplicate posts by ID and sort by created_at descending
  static List<Map<String, dynamic>> _deduplicateAndSort(
    List<Map<String, dynamic>> posts,
  ) {
    // Remove duplicates
    final seenIds = <String>{};
    final uniquePosts = posts.where((post) {
      final id = post['id']?.toString();
      if (id == null || seenIds.contains(id)) return false;
      seenIds.add(id);
      return true;
    }).toList();

    // Sort by created_at descending (newest first)
    uniquePosts.sort((a, b) {
      final aTime = a['created_at']?.toString() ?? '';
      final bTime = b['created_at']?.toString() ?? '';
      return bTime.compareTo(aTime);
    });

    return uniquePosts;
  }

  /// Apply pagination safely with bounds checking
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

  /// Get only public posts (for unauthenticated users)
  static Future<List<Map<String, dynamic>>> _getPublicPostsOnly({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      AppConfig.debugPrint('🌍 Loading PUBLIC posts only...');
      
      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_posts',
        filters: {'visibility': 'public'},
        orderBy: 'created_at',
        ascending: false,
        limit: limit + offset + 10,
      );

      if (result == null || (result as List).isEmpty) {
        AppConfig.debugPrint('❌ No public posts found');
        return [];
      }

      final allPosts = List<Map<String, dynamic>>.from(result as List);
      final paginatedPosts = _applyPagination(allPosts, limit: limit, offset: offset);

      AppConfig.debugPrint('✅ Found ${paginatedPosts.length} public posts (total: ${allPosts.length})');
      return paginatedPosts;
    } catch (e) {
      AppConfig.debugPrint('❌ Error loading public posts: $e');
      return [];
    }
  }

  /// LEGACY: Keep this for compatibility (redirects to new method)
  static Future<List<Map<String, dynamic>>> getFeedPostsFromFriends({
    int limit = 20,
    int offset = 0,
  }) async {
    return getFeedPosts(limit: limit, offset: offset);
  }

  /// Report a post for harassment or inappropriate content
  static Future<void> reportPost({
    required String postId,
    required String reason,
  }) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Check if user has already reported this post
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

      // Create new report
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

  /// Delete a post (only post owner can delete)
  static Future<void> deletePost(String postId) async {
    try {
      final userId = AuthService.currentUserId;
      
      AppConfig.debugPrint('🗑️ Attempting to delete post: $postId');
      AppConfig.debugPrint('👤 Current user ID: $userId');
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // First, verify the post exists and belongs to the user
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
      
      AppConfig.debugPrint('📝 Post owner ID: $postOwnerId');
      AppConfig.debugPrint('🆔 Post ID type: ${post['id'].runtimeType}');
      AppConfig.debugPrint('👤 User ID type: ${userId.runtimeType}');
      
      if (postOwnerId != userId) {
        throw Exception('You can only delete your own posts');
      }

      // Delete the post - make sure we're passing the ID correctly
      // If the database expects UUID, pass it as a string
      final result = await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'feed_posts',
        filters: {
          'id': postId.toString(), // Ensure it's a string
          'user_id': userId.toString(), // Ensure it's a string
        },
      );

      AppConfig.debugPrint('✅ Post deleted successfully: $postId');
      AppConfig.debugPrint('📊 Delete result: $result');
    } catch (e, stackTrace) {
      AppConfig.debugPrint('❌ Error deleting post: $e');
      AppConfig.debugPrint('Stack trace: $stackTrace');
      throw Exception('Failed to delete post: $e');
    }
  }
  /// Like a post
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
    } catch (e) {
      AppConfig.debugPrint('❌ Error liking post: $e');
      
      // Check if error is duplicate (user already liked)
      if (e.toString().toLowerCase().contains('duplicate')) {
        throw Exception('You have already liked this post');
      }
      
      throw Exception('Failed to like post: $e');
    }
  }

  /// Unlike a post
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

  /// Check if current user has liked a post
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

  /// Get total like count for a post
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

  /// Get comments for a post
  static Future<List<Map<String, dynamic>>> getPostComments(
    String postId, {
    int limit = 50,
  }) async {
    try {
      final result = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'feed_post_comments',
        filters: {'post_id': postId},
        orderBy: 'created_at',
        ascending: true, // Oldest first for comments
        limit: limit,
      );

      if (result == null || (result as List).isEmpty) {
        return [];
      }

      return List<Map<String, dynamic>>.from(result as List);
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting comments: $e');
      return [];
    }
  }

  /// Add a comment to a post
  static Future<void> addComment({
    required String postId,
    required String content,
  }) async {
    try {
      final userId = AuthService.currentUserId;
      final username = await AuthService.fetchCurrentUsername();

      if (userId == null || username == null) {
        throw Exception('User not authenticated');
      }

      if (content.trim().isEmpty) {
        throw Exception('Comment cannot be empty');
      }

      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'feed_post_comments',
        data: {
          'post_id': postId,
          'user_id': userId,
          'username': username,
          'content': content.trim(),
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      AppConfig.debugPrint('✅ Comment added to post: $postId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error adding comment: $e');
      throw Exception('Failed to add comment: $e');
    }
  }

  /// Delete a comment (only comment owner can delete)
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
          'user_id': userId, // Security: only delete your own comments
        },
      );

      AppConfig.debugPrint('✅ Comment deleted: $commentId');
    } catch (e) {
      AppConfig.debugPrint('❌ Error deleting comment: $e');
      throw Exception('Failed to delete comment: $e');
    }
  }
  /// Save a post for later viewing
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
    } catch (e) {
      AppConfig.debugPrint('❌ Error saving post: $e');
      
      // Check if error is duplicate (user already saved)
      if (e.toString().toLowerCase().contains('duplicate')) {
        throw Exception('You have already saved this post');
      }
      
      throw Exception('Failed to save post: $e');
    }
  }

  /// Unsave a post
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

  /// Check if current user has saved a post
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

  /// Get all saved posts for current user
  static Future<List<Map<String, dynamic>>> getSavedPosts({
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final userId = AuthService.currentUserId;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Get saved post IDs
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

      // Get actual posts
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

      // Sort by created_at descending
      posts.sort((a, b) {
        final aTime = a['created_at']?.toString() ?? '';
        final bTime = b['created_at']?.toString() ?? '';
        return bTime.compareTo(aTime);
      });

      // Apply pagination
      return _applyPagination(posts, limit: limit, offset: offset);
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting saved posts: $e');
      return [];
    }
  }

  /// Get all posts created by current user
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
      
      // Apply pagination
      return _applyPagination(allPosts, limit: limit, offset: offset);
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting user posts: $e');
      return [];
    }
  }

  /// Get post stats (likes, comments, shares) for a specific post
  static Future<Map<String, int>> getPostStats(String postId) async {
    try {
      // Get like count
      final likeCount = await getPostLikeCount(postId);

      // Get comment count
      final comments = await getPostComments(postId);
      final commentCount = comments.length;

      return {
        'likes': likeCount,
        'comments': commentCount,
        'shares': 0, // Not implemented yet
      };
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting post stats: $e');
      return {'likes': 0, 'comments': 0, 'shares': 0};
    }
  }
}