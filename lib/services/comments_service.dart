// lib/services/comments_service.dart
// Handles all recipe comment operations, likes, reports, and lookups.



import 'database_service_core.dart';     // workerQuery + caching


class CommentsService {

  // ==================================================
  // GET COMMENTS FOR A RECIPE (with attached user data)
  // ==================================================
  static Future<List<Map<String, dynamic>>> getRecipeComments(int recipeId) async {
    try {
      // Get all comments for the recipe
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'recipe_comments',
        columns: ['*'],
        filters: {'recipe_id': recipeId},
        orderBy: 'created_at',
        ascending: false,
      );

      final comments = <Map<String, dynamic>>[];

      for (var comment in response as List) {
        final userId = comment['user_id'];

        // Fetch comment owner profile
        final userProfile = await DatabaseServiceCore.workerQuery(
          action: 'select',
          table: 'profiles',
          columns: ['id', 'username', 'avatar_url', 'first_name', 'last_name'],
          filters: {'id': userId},
          limit: 1,
        );

        if (userProfile != null && (userProfile as List).isNotEmpty) {
          comments.add({
            ...comment,
            'user': userProfile[0],
          });
        }
      }

      return comments;
    } catch (e) {
      throw Exception('Failed to load recipe comments: $e');
    }
  }

  // ==================================================
  // ADD COMMENT
  // ==================================================
  static Future<void> addComment({
    required int recipeId,
    required String commentText,
    String? parentCommentId,
  }) async {
    DatabaseServiceCore.ensureUserAuthenticated();

    try {
      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'recipe_comments',
        data: {
          'recipe_id': recipeId,
          'user_id': DatabaseServiceCore.currentUserId!,
          'comment_text': commentText,
          'parent_comment_id': parentCommentId,
          'created_at': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      throw Exception('Failed to add comment: $e');
    }
  }

  // ==================================================
  // DELETE COMMENT
  // ==================================================
  static Future<void> deleteComment(String commentId) async {
    DatabaseServiceCore.ensureUserAuthenticated();

    try {
      // Fetch comment to confirm ownership
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'recipe_comments',
        columns: ['user_id'],
        filters: {'id': commentId},
        limit: 1,
      );

      if (response == null || (response as List).isEmpty) {
        throw Exception('Comment not found');
      }

      if (response[0]['user_id'] != DatabaseServiceCore.currentUserId) {
        throw Exception('You can only delete your own comments');
      }

      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'recipe_comments',
        filters: {'id': commentId},
      );
    } catch (e) {
      throw Exception('Failed to delete comment: $e');
    }
  }

  // ==================================================
  // REPORT COMMENT
  // ==================================================
  static Future<void> reportComment(String commentId, String reason) async {
    DatabaseServiceCore.ensureUserAuthenticated();

    try {
      await DatabaseServiceCore.workerQuery(
        action: 'insert',
        table: 'comment_reports',
        data: {
          'comment_id': commentId,
          'reporter_id': DatabaseServiceCore.currentUserId!,
          'reason': reason,
          'created_at': DateTime.now().toIso8601String(),
          'status': 'pending',
        },
      );
    } catch (e) {
      throw Exception('Failed to report comment: $e');
    }
  }

  // ==================================================
  // HAS USER LIKED THIS COMMENT?
  // ==================================================
  static Future<bool> hasUserLikedPost(String commentId) async {
    DatabaseServiceCore.ensureUserAuthenticated();

    try {
      final response = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'comment_likes',
        columns: ['id'],
        filters: {
          'comment_id': commentId,
          'user_id': DatabaseServiceCore.currentUserId!,
        },
        limit: 1,
      );

      return response != null && (response as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ==================================================
  // LIKE COMMENT
  // ==================================================
  static Future<void> likeComment(String commentId) async {
    DatabaseServiceCore.ensureUserAuthenticated();

    try {
      final alreadyLiked = await hasUserLikedPost(commentId);
      if (!alreadyLiked) {
        await DatabaseServiceCore.workerQuery(
          action: 'insert',
          table: 'comment_likes',
          data: {
            'comment_id': commentId,
            'user_id': DatabaseServiceCore.currentUserId!,
            'created_at': DateTime.now().toIso8601String(),
          },
        );
      }
    } catch (e) {
      throw Exception('Failed to like comment: $e');
    }
  }

  // ==================================================
  // UNLIKE COMMENT
  // ==================================================
  static Future<void> unlikeComment(String commentId) async {
    DatabaseServiceCore.ensureUserAuthenticated();

    try {
      await DatabaseServiceCore.workerQuery(
        action: 'delete',
        table: 'comment_likes',
        filters: {
          'comment_id': commentId,
          'user_id': DatabaseServiceCore.currentUserId!,
        },
      );
    } catch (e) {
      throw Exception('Failed to unlike comment: $e');
    }
  }
}
