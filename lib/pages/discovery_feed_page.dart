// // lib/pages/discovery_feed_page.dart - OPTIMIZED VIDEO SUPPORT
// import 'package:flutter/material.dart';
// import 'package:video_player/video_player.dart';
// import '../services/database_service.dart';
// import '../services/error_handling_service.dart';
// import '../widgets/app_drawer.dart';
// import '../pages/create_post_page.dart';
// import '../pages/user_profile_page.dart';

// class DiscoveryFeedPage extends StatefulWidget {
//   const DiscoveryFeedPage({super.key});

//   @override
//   State<DiscoveryFeedPage> createState() => _DiscoveryFeedPageState();
// }

// class _DiscoveryFeedPageState extends State<DiscoveryFeedPage> {
//   List<Map<String, dynamic>> _posts = [];
//   bool _isLoading = false;
//   bool _hasMore = true;
//   int _offset = 0;
//   final int _limit = 20;
//   String _sortBy = 'recent';
  
//   final ScrollController _scrollController = ScrollController();
//   final Map<String, VideoPlayerController> _videoControllers = {};
//   final Map<String, bool> _videoInitialized = {};

//   @override
//   void initState() {
//     super.initState();
//     _loadPosts();
//     _scrollController.addListener(_onScroll);
//   }

//   @override
//   void dispose() {
//     _scrollController.dispose();
//     _disposeAllVideoControllers();
//     super.dispose();
//   }

//   void _disposeAllVideoControllers() {
//     for (var controller in _videoControllers.values) {
//       controller.pause();
//       controller.dispose();
//     }
//     _videoControllers.clear();
//     _videoInitialized.clear();
//   }

//   void _onScroll() {
//     if (_scrollController.position.pixels >= 
//         _scrollController.position.maxScrollExtent - 200) {
//       if (!_isLoading && _hasMore) {
//         _loadMorePosts();
//       }
//     }
//   }

//   Future<void> _loadPosts({bool refresh = false}) async {
//     if (refresh) {
//       setState(() {
//         _offset = 0;
//         _posts = [];
//         _hasMore = true;
//       });
//       _disposeAllVideoControllers();
//     }

//     setState(() {
//       _isLoading = true;
//     });

//     try {
//       final posts = await DatabaseService.getFeedPosts(
//         limit: _limit,
//         offset: _offset,
//         sortBy: _sortBy,
//       );

//       if (mounted) {
//         setState(() {
//           if (refresh) {
//             _posts = posts;
//           } else {
//             _posts.addAll(posts);
//           }
//           _hasMore = posts.length == _limit;
//           _isLoading = false;
//         });
//       }
//     } catch (e) {
//       if (mounted) {
//         setState(() {
//           _isLoading = false;
//         });
        
//         await ErrorHandlingService.handleError(
//           context: context,
//           error: e,
//           category: ErrorHandlingService.databaseError,
//           customMessage: 'Unable to load feed',
//           onRetry: () => _loadPosts(refresh: refresh),
//         );
//       }
//     }
//   }

//   Future<void> _loadMorePosts() async {
//     setState(() {
//       _offset += _limit;
//     });
//     await _loadPosts();
//   }

//   Future<void> _toggleLike(Map<String, dynamic> post, int index) async {
//     final postId = post['id'];
    
//     try {
//       final isLiked = await DatabaseService.hasUserLikedPost(postId);
      
//       if (isLiked) {
//         await DatabaseService.unlikePost(postId);
//       } else {
//         await DatabaseService.likePost(postId);
//       }

//       // Refresh like count
//       final likeCount = await DatabaseService.getPostLikeCount(postId);
//       final userLiked = await DatabaseService.hasUserLikedPost(postId);

//       if (mounted) {
//         setState(() {
//           _posts[index]['like_count'] = likeCount;
//           _posts[index]['user_liked'] = userLiked;
//         });
//       }
//     } catch (e) {
//       if (mounted) {
//         ErrorHandlingService.showSimpleError(context, 'Failed to update like');
//       }
//     }
//   }

//   void _navigateToRecipe(Map<String, dynamic>? recipe) {
//     if (recipe == null) return;
    
//     final recipeName = recipe['recipe_name'] ?? 'Recipe';
//     final ingredients = recipe['ingredients'] ?? '';
//     final directions = recipe['directions'] ?? '';
    
//     showModalBottomSheet(
//       context: context,
//       isScrollControlled: true,
//       backgroundColor: Colors.transparent,
//       builder: (context) => DraggableScrollableSheet(
//         initialChildSize: 0.9,
//         minChildSize: 0.5,
//         maxChildSize: 0.95,
//         builder: (context, scrollController) => Container(
//           decoration: const BoxDecoration(
//             color: Colors.white,
//             borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
//           ),
//           child: Column(
//             children: [
//               Container(
//                 margin: const EdgeInsets.symmetric(vertical: 8),
//                 width: 40,
//                 height: 4,
//                 decoration: BoxDecoration(
//                   color: Colors.grey.shade300,
//                   borderRadius: BorderRadius.circular(2),
//                 ),
//               ),
//               Expanded(
//                 child: SingleChildScrollView(
//                   controller: scrollController,
//                   padding: const EdgeInsets.all(20),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Row(
//                         children: [
//                           const Icon(Icons.restaurant_menu, color: Colors.orange, size: 28),
//                           const SizedBox(width: 12),
//                           Expanded(
//                             child: Text(
//                               recipeName,
//                               style: const TextStyle(
//                                 fontSize: 24,
//                                 fontWeight: FontWeight.bold,
//                               ),
//                             ),
//                           ),
//                         ],
//                       ),
//                       const SizedBox(height: 24),
//                       const Text(
//                         'Ingredients',
//                         style: TextStyle(
//                           fontSize: 20,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                       const SizedBox(height: 12),
//                       Text(
//                         ingredients,
//                         style: const TextStyle(fontSize: 16, height: 1.5),
//                       ),
//                       const SizedBox(height: 24),
//                       const Text(
//                         'Directions',
//                         style: TextStyle(
//                           fontSize: 20,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                       const SizedBox(height: 12),
//                       Text(
//                         directions,
//                         style: const TextStyle(fontSize: 16, height: 1.5),
//                       ),
//                       const SizedBox(height: 24),
//                     ],
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   void _navigateToUserProfile(String userId) {
//     Navigator.push(
//       context,
//       MaterialPageRoute(
//         builder: (context) => UserProfilePage(userId: userId),
//       ),
//     );
//   }

//   void _navigateToCreatePost() async {
//     final result = await Navigator.push(
//       context,
//       MaterialPageRoute(
//         builder: (context) => const CreatePostPage(),
//       ),
//     );

//     if (result == true) {
//       _loadPosts(refresh: true);
//     }
//   }

//   VideoPlayerController? _getOrCreateVideoController(String postId, String videoUrl) {
//     // Return existing controller if already created
//     if (_videoControllers.containsKey(postId)) {
//       return _videoControllers[postId];
//     }
    
//     // Create new controller
//     final controller = VideoPlayerController.network(videoUrl);
//     _videoControllers[postId] = controller;
//     _videoInitialized[postId] = false;
    
//     // Initialize asynchronously
//     controller.initialize().then((_) {
//       if (mounted) {
//         setState(() {
//           _videoInitialized[postId] = true;
//         });
//       }
//     }).catchError((error) {
//       print('❌ Video initialization failed for $postId: $error');
//     });
    
//     // Set to loop
//     controller.setLooping(true);
    
//     return controller;
//   }

//   void _toggleVideoPlayback(String postId) {
//     final controller = _videoControllers[postId];
//     if (controller == null || !(_videoInitialized[postId] ?? false)) return;
    
//     setState(() {
//       if (controller.value.isPlaying) {
//         controller.pause();
//       } else {
//         // Pause all other videos first
//         for (var entry in _videoControllers.entries) {
//           if (entry.key != postId && entry.value.value.isPlaying) {
//             entry.value.pause();
//           }
//         }
//         controller.play();
//       }
//     });
//   }

//   Widget _buildPostCard(Map<String, dynamic> post, int index) {
//     final user = post['user'] ?? {};
//     final recipe = post['recipe'] ?? {};
//     final username = user['username'] ?? 'Unknown User';
//     final recipeName = recipe['recipe_name'] ?? 'Recipe';
//     final caption = post['caption'] ?? '';
//     final imageUrl = post['image_url'];
//     final videoUrl = post['video_url'];
//     final thumbnailUrl = post['thumbnail_url'];
//     final isVideo = videoUrl != null && videoUrl.isNotEmpty;
    
//     return FutureBuilder<Map<String, int>>(
//       future: _getPostStats(post['id']),
//       builder: (context, snapshot) {
//         final stats = snapshot.data ?? {'likes': 0, 'comments': 0};
//         final isLiked = snapshot.data?['is_liked'] == 1;
        
//         return Card(
//           margin: const EdgeInsets.only(bottom: 16),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               // Header: User info
//               ListTile(
//                 leading: GestureDetector(
//                   onTap: () => _navigateToUserProfile(user['id']),
//                   child: CircleAvatar(
//                     backgroundImage: user['avatar_url'] != null
//                         ? NetworkImage(user['avatar_url'])
//                         : null,
//                     child: user['avatar_url'] == null
//                         ? Text(username[0].toUpperCase())
//                         : null,
//                   ),
//                 ),
//                 title: GestureDetector(
//                   onTap: () => _navigateToUserProfile(user['id']),
//                   child: Row(
//                     children: [
//                       Text(
//                         username,
//                         style: const TextStyle(fontWeight: FontWeight.bold),
//                       ),
//                       if (user['level'] != null && user['level'] > 1) ...[
//                         const SizedBox(width: 8),
//                         Container(
//                           padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
//                           decoration: BoxDecoration(
//                             color: Colors.amber.shade100,
//                             borderRadius: BorderRadius.circular(10),
//                             border: Border.all(color: Colors.amber.shade700),
//                           ),
//                           child: Row(
//                             mainAxisSize: MainAxisSize.min,
//                             children: [
//                               Icon(Icons.star, size: 12, color: Colors.amber.shade700),
//                               const SizedBox(width: 2),
//                               Text(
//                                 'Lv ${user['level']}',
//                                 style: TextStyle(
//                                   fontSize: 10,
//                                   fontWeight: FontWeight.bold,
//                                   color: Colors.amber.shade700,
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                       ],
//                     ],
//                   ),
//                 ),
//                 subtitle: Text(
//                   _formatTimeAgo(post['created_at']),
//                   style: const TextStyle(fontSize: 12, color: Colors.grey),
//                 ),
//               ),

//               // Media (Image or Video)
//               if (isVideo) ...[
//                 _buildVideoPlayer(post['id'], videoUrl, thumbnailUrl),
//               ] else if (imageUrl != null && imageUrl.isNotEmpty) ...[
//                 GestureDetector(
//                   onDoubleTap: () => _toggleLike(post, index),
//                   child: Image.network(
//                     imageUrl,
//                     width: double.infinity,
//                     height: 300,
//                     fit: BoxFit.cover,
//                     loadingBuilder: (context, child, loadingProgress) {
//                       if (loadingProgress == null) return child;
//                       return SizedBox(
//                         height: 300,
//                         child: Center(
//                           child: CircularProgressIndicator(
//                             value: loadingProgress.expectedTotalBytes != null
//                                 ? loadingProgress.cumulativeBytesLoaded /
//                                     loadingProgress.expectedTotalBytes!
//                                 : null,
//                           ),
//                         ),
//                       );
//                     },
//                     errorBuilder: (context, error, stackTrace) {
//                       return Container(
//                         height: 300,
//                         color: Colors.grey.shade200,
//                         child: const Center(
//                           child: Icon(Icons.broken_image, size: 50),
//                         ),
//                       );
//                     },
//                   ),
//                 ),
//               ],

//               // Action buttons
//               Padding(
//                 padding: const EdgeInsets.symmetric(horizontal: 8),
//                 child: Row(
//                   children: [
//                     IconButton(
//                       icon: Icon(
//                         isLiked ? Icons.favorite : Icons.favorite_border,
//                         color: isLiked ? Colors.red : null,
//                       ),
//                       onPressed: () => _toggleLike(post, index),
//                     ),
//                     Text('${stats['likes']}'),
//                     const SizedBox(width: 16),
//                     IconButton(
//                       icon: const Icon(Icons.comment_outlined),
//                       onPressed: () => _navigateToRecipe(recipe),
//                     ),
//                     Text('${stats['comments']}'),
//                     const Spacer(),
//                     IconButton(
//                       icon: const Icon(Icons.share),
//                       onPressed: () {
//                         // TODO: Implement share
//                         ErrorHandlingService.showSimpleError(context, 'Share coming soon!');
//                       },
//                     ),
//                   ],
//                 ),
//               ),

//               // Recipe tag
//               Padding(
//                 padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//                 child: GestureDetector(
//                   onTap: () => _navigateToRecipe(recipe),
//                   child: Container(
//                     padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//                     decoration: BoxDecoration(
//                       color: Colors.orange.shade50,
//                       borderRadius: BorderRadius.circular(20),
//                       border: Border.all(color: Colors.orange.shade300),
//                     ),
//                     child: Row(
//                       mainAxisSize: MainAxisSize.min,
//                       children: [
//                         const Icon(Icons.restaurant_menu, size: 16, color: Colors.orange),
//                         const SizedBox(width: 4),
//                         Flexible(
//                           child: Text(
//                             recipeName,
//                             style: TextStyle(
//                               color: Colors.orange.shade800,
//                               fontWeight: FontWeight.w600,
//                             ),
//                             maxLines: 1,
//                             overflow: TextOverflow.ellipsis,
//                           ),
//                         ),
//                         const SizedBox(width: 4),
//                         const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.orange),
//                       ],
//                     ),
//                   ),
//                 ),
//               ),

//               // Caption
//               if (caption.isNotEmpty)
//                 Padding(
//                   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//                   child: RichText(
//                     text: TextSpan(
//                       style: const TextStyle(color: Colors.black),
//                       children: [
//                         TextSpan(
//                           text: '$username ',
//                           style: const TextStyle(fontWeight: FontWeight.bold),
//                         ),
//                         TextSpan(text: caption),
//                       ],
//                     ),
//                   ),
//                 ),

//               const SizedBox(height: 8),
//             ],
//           ),
//         );
//       },
//     );
//   }

//   Widget _buildVideoPlayer(String postId, String videoUrl, String? thumbnailUrl) {
//     final controller = _getOrCreateVideoController(postId, videoUrl);
//     final isInitialized = _videoInitialized[postId] ?? false;
    
//     if (controller == null || !isInitialized) {
//       // Show loading or thumbnail while video initializes
//       return Container(
//         height: 300,
//         color: Colors.black,
//         child: Stack(
//           alignment: Alignment.center,
//           children: [
//             if (thumbnailUrl != null && thumbnailUrl != videoUrl)
//               Image.network(
//                 thumbnailUrl,
//                 width: double.infinity,
//                 height: 300,
//                 fit: BoxFit.cover,
//                 errorBuilder: (context, error, stackTrace) {
//                   return Container(color: Colors.black);
//                 },
//               ),
//             const CircularProgressIndicator(color: Colors.white),
//           ],
//         ),
//       );
//     }
    
//     return GestureDetector(
//       onTap: () => _toggleVideoPlayback(postId),
//       child: Container(
//         height: 300,
//         color: Colors.black,
//         child: Stack(
//           alignment: Alignment.center,
//           children: [
//             Center(
//               child: AspectRatio(
//                 aspectRatio: controller.value.aspectRatio,
//                 child: VideoPlayer(controller),
//               ),
//             ),
//             if (!controller.value.isPlaying)
//               Container(
//                 decoration: BoxDecoration(
//                   color: Colors.black.withOpacity(0.3),
//                 ),
//                 child: const Icon(
//                   Icons.play_circle_outline,
//                   size: 80,
//                   color: Colors.white,
//                 ),
//               ),
//             Positioned(
//               top: 8,
//               right: 8,
//               child: Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                 decoration: BoxDecoration(
//                   color: Colors.black.withOpacity(0.7),
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 child: const Row(
//                   children: [
//                     Icon(Icons.videocam, size: 16, color: Colors.white),
//                     SizedBox(width: 4),
//                     Text(
//                       'VIDEO',
//                       style: TextStyle(color: Colors.white, fontSize: 12),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//             // Show video position indicator
//             if (controller.value.isPlaying)
//               Positioned(
//                 bottom: 0,
//                 left: 0,
//                 right: 0,
//                 child: VideoProgressIndicator(
//                   controller,
//                   allowScrubbing: true,
//                   colors: const VideoProgressColors(
//                     playedColor: Colors.orange,
//                     backgroundColor: Colors.white24,
//                     bufferedColor: Colors.white38,
//                   ),
//                   padding: const EdgeInsets.symmetric(vertical: 2),
//                 ),
//               ),
//           ],
//         ),
//       ),
//     );
//   }

//   Future<Map<String, int>> _getPostStats(String postId) async {
//     try {
//       final likes = await DatabaseService.getPostLikeCount(postId);
//       final isLiked = await DatabaseService.hasUserLikedPost(postId);
//       // TODO: Get comment count when implemented
//       return {
//         'likes': likes,
//         'comments': 0,
//         'is_liked': isLiked ? 1 : 0,
//       };
//     } catch (e) {
//       return {'likes': 0, 'comments': 0, 'is_liked': 0};
//     }
//   }

//   String _formatTimeAgo(String? timestamp) {
//     if (timestamp == null) return '';
    
//     try {
//       final dateTime = DateTime.parse(timestamp);
//       final now = DateTime.now();
//       final difference = now.difference(dateTime);

//       if (difference.inDays > 7) {
//         return '${dateTime.month}/${dateTime.day}/${dateTime.year}';
//       } else if (difference.inDays > 0) {
//         return '${difference.inDays}d ago';
//       } else if (difference.inHours > 0) {
//         return '${difference.inHours}h ago';
//       } else if (difference.inMinutes > 0) {
//         return '${difference.inMinutes}m ago';
//       } else {
//         return 'Just now';
//       }
//     } catch (e) {
//       return '';
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Discovery Feed'),
//         backgroundColor: Colors.orange,
//         foregroundColor: Colors.white,
//         leading: Builder(
//           builder: (context) => IconButton(
//             icon: const Icon(Icons.menu),
//             onPressed: () => Scaffold.of(context).openDrawer(),
//           ),
//         ),
//         actions: [
//           PopupMenuButton<String>(
//             icon: const Icon(Icons.filter_list),
//             onSelected: (value) {
//               setState(() {
//                 _sortBy = value;
//               });
//               _loadPosts(refresh: true);
//             },
//             itemBuilder: (context) => [
//               const PopupMenuItem(
//                 value: 'recent',
//                 child: Row(
//                   children: [
//                     Icon(Icons.access_time, size: 20),
//                     SizedBox(width: 8),
//                     Text('Recent'),
//                   ],
//                 ),
//               ),
//               const PopupMenuItem(
//                 value: 'trending',
//                 child: Row(
//                   children: [
//                     Icon(Icons.trending_up, size: 20),
//                     SizedBox(width: 8),
//                     Text('Trending'),
//                   ],
//                 ),
//               ),
//             ],
//           ),
//         ],
//       ),
//       drawer: const AppDrawer(currentPage: 'feed'),
//       body: RefreshIndicator(
//         onRefresh: () => _loadPosts(refresh: true),
//         child: _posts.isEmpty && _isLoading
//             ? const Center(child: CircularProgressIndicator())
//             : _posts.isEmpty
//                 ? Center(
//                     child: Column(
//                       mainAxisAlignment: MainAxisAlignment.center,
//                       children: [
//                         const Icon(Icons.photo_library, size: 80, color: Colors.grey),
//                         const SizedBox(height: 16),
//                         const Text(
//                           'No posts yet!',
//                           style: TextStyle(
//                             fontSize: 18,
//                             fontWeight: FontWeight.bold,
//                           ),
//                         ),
//                         const SizedBox(height: 8),
//                         const Text(
//                           'Be the first to share your cooking',
//                           style: TextStyle(color: Colors.grey),
//                         ),
//                         const SizedBox(height: 24),
//                         ElevatedButton.icon(
//                           onPressed: _navigateToCreatePost,
//                           icon: const Icon(Icons.add_photo_alternate),
//                           label: const Text('Create Post'),
//                           style: ElevatedButton.styleFrom(
//                             backgroundColor: Colors.orange,
//                             foregroundColor: Colors.white,
//                             padding: const EdgeInsets.symmetric(
//                               horizontal: 24,
//                               vertical: 12,
//                             ),
//                           ),
//                         ),
//                       ],
//                     ),
//                   )
//                 : ListView.builder(
//                     controller: _scrollController,
//                     padding: const EdgeInsets.all(16),
//                     itemCount: _posts.length + (_hasMore ? 1 : 0),
//                     itemBuilder: (context, index) {
//                       if (index == _posts.length) {
//                         return const Center(
//                           child: Padding(
//                             padding: EdgeInsets.all(16),
//                             child: CircularProgressIndicator(),
//                           ),
//                         );
//                       }
//                       return _buildPostCard(_posts[index], index);
//                     },
//                   ),
//       ),
//       floatingActionButton: FloatingActionButton(
//         onPressed: _navigateToCreatePost,
//         backgroundColor: Colors.orange,
//         child: const Icon(Icons.add_photo_alternate, color: Colors.white),
//       ),
//     );
//   }
// }