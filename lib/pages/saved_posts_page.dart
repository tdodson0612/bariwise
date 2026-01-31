// lib/pages/saved_posts_page.dart
import 'package:flutter/material.dart';
import 'package:bari_wise/services/feed_posts_service.dart';
import 'package:bari_wise/services/auth_service.dart';
import 'package:bari_wise/config/app_config.dart';
import 'package:bari_wise/widgets/app_drawer.dart';

class SavedPostsPage extends StatefulWidget {
  const SavedPostsPage({super.key});

  @override
  State<SavedPostsPage> createState() => _SavedPostsPageState();
}

class _SavedPostsPageState extends State<SavedPostsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  List<Map<String, dynamic>> _savedPosts = [];
  List<Map<String, dynamic>> _myPosts = [];
  
  bool _isLoadingSaved = false;
  bool _isLoadingMy = false;
  
  Map<String, bool> _expandedComments = {};
  Map<String, List<Map<String, dynamic>>> _postComments = {};
  final Map<String, TextEditingController> _commentControllers = {};
  Map<String, Map<String, int>> _postStats = {}; // postId -> {likes, comments, saves}

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSavedPosts();
    _loadMyPosts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (var controller in _commentControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSavedPosts() async {
    setState(() => _isLoadingSaved = true);
    
    try {
      final posts = await FeedPostsService.getSavedPosts(limit: 100);
      
      if (mounted) {
        setState(() {
          _savedPosts = posts;
          _isLoadingSaved = false;
        });
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Error loading saved posts: $e');
      if (mounted) {
        setState(() => _isLoadingSaved = false);
      }
    }
  }

  Future<void> _loadMyPosts() async {
    setState(() => _isLoadingMy = true);
    
    try {
      final posts = await FeedPostsService.getUserPosts(limit: 100);
      
      // Load stats for each post
      for (final post in posts) {
        final postId = post['id']?.toString();
        if (postId != null) {
          final stats = await FeedPostsService.getPostStats(postId);
          _postStats[postId] = stats;
        }
      }
      
      if (mounted) {
        setState(() {
          _myPosts = posts;
          _isLoadingMy = false;
        });
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Error loading my posts: $e');
      if (mounted) {
        setState(() => _isLoadingMy = false);
      }
    }
  }

  Future<void> _toggleComments(String postId) async {
    final isCurrentlyExpanded = _expandedComments[postId] ?? false;
    
    if (!isCurrentlyExpanded) {
      await _loadComments(postId);
    }
    
    setState(() {
      _expandedComments[postId] = !isCurrentlyExpanded;
    });
  }

  Future<void> _loadComments(String postId) async {
    try {
      final comments = await FeedPostsService.getPostComments(postId);
      
      if (mounted) {
        setState(() {
          _postComments[postId] = comments;
        });
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Error loading comments: $e');
    }
  }

  Future<void> _postComment(String postId) async {
    final controller = _commentControllers[postId];
    if (controller == null || controller.text.trim().isEmpty) return;

    try {
      await FeedPostsService.addComment(
        postId: postId,
        content: controller.text.trim(),
      );

      controller.clear();
      await _loadComments(postId);
      
      // Refresh stats
      final stats = await FeedPostsService.getPostStats(postId);
      setState(() {
        _postStats[postId] = stats;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Comment posted!'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to post comment: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteComment(String postId, String commentId) async {
    try {
      await FeedPostsService.deleteComment(commentId);
      await _loadComments(postId);
      
      // Refresh stats
      final stats = await FeedPostsService.getPostStats(postId);
      setState(() {
        _postStats[postId] = stats;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Comment deleted'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete comment'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _unsavePost(String postId) async {
    try {
      await FeedPostsService.unsavePost(postId);
      
      setState(() {
        _savedPosts.removeWhere((post) => post['id'].toString() == postId);
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Post removed from saved'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to unsave post'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteMyPost(String postId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Post'),
        content: const Text('Are you sure you want to delete this post? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FeedPostsService.deletePost(postId);
      
      setState(() {
        _myPosts.removeWhere((post) => post['id'].toString() == postId);
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Post deleted'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete post'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildSavedPostsList() {
    if (_isLoadingSaved) {
      return Center(child: CircularProgressIndicator());
    }

    if (_savedPosts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bookmark_border, size: 64, color: Colors.grey.shade400),
              SizedBox(height: 16),
              Text(
                'No Saved Posts',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Posts you save will appear here',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSavedPosts,
      child: ListView.builder(
        padding: EdgeInsets.all(12),
        itemCount: _savedPosts.length,
        itemBuilder: (context, index) {
          final post = _savedPosts[index];
          return _buildPostCard(post, showUnsave: true);
        },
      ),
    );
  }

  Widget _buildMyPostsList() {
    if (_isLoadingMy) {
      return Center(child: CircularProgressIndicator());
    }

    if (_myPosts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.post_add, size: 64, color: Colors.grey.shade400),
              SizedBox(height: 16),
              Text(
                'No Posts Yet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Your posts will appear here',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMyPosts,
      child: ListView.builder(
        padding: EdgeInsets.all(12),
        itemCount: _myPosts.length,
        itemBuilder: (context, index) {
          final post = _myPosts[index];
          return _buildPostCard(post, showStats: true, showDelete: true);
        },
      ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> post, {bool showUnsave = false, bool showStats = false, bool showDelete = false}) {
    final postId = post['id']?.toString();
    final visibility = post['visibility']?.toString() ?? 'public';
    final isExpanded = _expandedComments[postId] ?? false;
    final comments = _postComments[postId] ?? [];
    final stats = _postStats[postId];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.orange.shade100,
                  backgroundImage: post['avatar_url'] != null && post['avatar_url'].toString().isNotEmpty
                      ? NetworkImage(post['avatar_url'])
                      : null,
                  child: (post['avatar_url'] == null || post['avatar_url'].toString().isEmpty)
                      ? Icon(Icons.person, color: Colors.orange.shade700)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            post['username'] ?? 'Anonymous',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: visibility == 'public' 
                                ? Colors.blue.shade50 
                                : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: visibility == 'public' 
                                  ? Colors.blue.shade200 
                                  : Colors.orange.shade200,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  visibility == 'public' ? Icons.public : Icons.people,
                                  size: 10,
                                  color: visibility == 'public' 
                                    ? Colors.blue.shade700 
                                    : Colors.orange.shade700,
                                ),
                                SizedBox(width: 3),
                                Text(
                                  visibility == 'public' ? 'Public' : 'Friends',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: visibility == 'public' 
                                      ? Colors.blue.shade700 
                                      : Colors.orange.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _formatPostTime(post['created_at']),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (showUnsave)
                  IconButton(
                    icon: Icon(Icons.bookmark_remove, color: Colors.blue),
                    onPressed: () => _unsavePost(postId!),
                    tooltip: 'Remove from saved',
                  ),
                if (showDelete)
                  IconButton(
                    icon: Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteMyPost(postId!),
                    tooltip: 'Delete post',
                  ),
              ],
            ),
          ),
          
          // Content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (post['content'] != null && post['content'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      post['content'],
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                
                if (post['photo_url'] != null && post['photo_url'].toString().isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      post['photo_url'],
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 200,
                          color: Colors.grey.shade200,
                          child: Center(
                            child: Icon(Icons.broken_image, size: 48, color: Colors.grey.shade400),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Stats (for My Posts tab)
          if (showStats && stats != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem(Icons.favorite, stats['likes'] ?? 0, 'Likes'),
                    _buildStatItem(Icons.comment, stats['comments'] ?? 0, 'Comments'),
                    _buildStatItem(Icons.bookmark, stats['saves'] ?? 0, 'Saves'),
                  ],
                ),
              ),
            ),

          if (showStats && stats != null)
            const SizedBox(height: 8),

          // Action buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: InkWell(
              onTap: () => _toggleComments(postId!),
              child: Row(
                children: [
                  Icon(Icons.comment_outlined, size: 20, color: Colors.grey.shade700),
                  const SizedBox(width: 4),
                  Text(
                    comments.isNotEmpty ? 'View ${comments.length} comment${comments.length == 1 ? '' : 's'}' : 'View comments',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Spacer(),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey.shade700,
                  ),
                ],
              ),
            ),
          ),
          
          if (isExpanded) _buildCommentsSection(postId!),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, int count, String label) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey.shade700),
            SizedBox(width: 4),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildCommentsSection(String postId) {
    final comments = _postComments[postId] ?? [];
    _commentControllers.putIfAbsent(postId, () => TextEditingController());
    final controller = _commentControllers[postId]!;

    return Container(
      color: Colors.grey.shade50,
      padding: EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (comments.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  'No comments yet. Be the first!',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ),
            )
          else
            ...comments.map((comment) => _buildCommentItem(comment, postId)),
          
          Divider(),
          
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: 'Write a comment...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _postComment(postId),
                ),
              ),
              SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.send, color: Colors.orange),
                onPressed: () => _postComment(postId),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommentItem(Map<String, dynamic> comment, String postId) {
    final currentUserId = AuthService.currentUserId;
    final isOwnComment = comment['user_id'] == currentUserId;

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: Colors.orange.shade100,
                child: Icon(Icons.person, size: 16, color: Colors.orange.shade700),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comment['username'] ?? 'Anonymous',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      _formatPostTime(comment['created_at']),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (isOwnComment)
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  onPressed: () => _deleteComment(postId, comment['id'].toString()),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
            ],
          ),
          SizedBox(height: 6),
          Text(
            comment['content'] ?? '',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
          ),
        ],
      ),
    );
  }

  String _formatPostTime(dynamic timestamp) {
    try {
      final DateTime postTime = timestamp is String 
          ? DateTime.parse(timestamp) 
          : DateTime.fromMillisecondsSinceEpoch(timestamp);
      final now = DateTime.now();
      final difference = now.difference(postTime);
      
      if (difference.inMinutes < 1) return 'Just now';
      if (difference.inHours < 1) return '${difference.inMinutes}m ago';
      if (difference.inDays < 1) return '${difference.inHours}h ago';
      if (difference.inDays < 7) return '${difference.inDays}d ago';
      return '${postTime.month}/${postTime.day}/${postTime.year}';
    } catch (e) {
      return 'Recently';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Posts'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Saved Posts'),
            Tab(text: 'My Posts'),
          ],
        ),
      ),
      drawer: AppDrawer(currentPage: 'saved_posts'),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSavedPostsList(),
          _buildMyPostsList(),
        ],
      ),
    );
  }
}