// lib/pages/user_profile_page.dart - COMPLETE PROFILE VIEW WITH ALL SECTIONS
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../services/profile_service.dart';
import '../services/friends_service.dart';
import '../services/friends_visibility_service.dart';
import '../services/picture_service.dart';
import '../services/submitted_recipes_service.dart';
import '../services/favorite_recipes_service.dart';
import '../services/auth_service.dart';
import '../services/error_handling_service.dart';
import '../models/submitted_recipe.dart';
import '../widgets/recipe_card.dart';
import '../widgets/cookbook_section.dart';
import 'chat_page.dart';
import 'recipe_detail_page.dart';

class UserProfilePage extends StatefulWidget {
  final String userId;

  const UserProfilePage({super.key, required this.userId});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  Map<String, dynamic>? userProfile;
  Map<String, dynamic>? friendshipStatus;
  List<String> _pictures = [];
  List<SubmittedRecipe> _submittedRecipes = [];
  List<Map<String, dynamic>> _friends = [];
  bool _friendsListVisible = true;
  int _favoriteRecipesCount = 0;
  
  bool isLoading = true;
  bool isActionLoading = false;
  bool _isLoadingPictures = false;
  bool _isLoadingRecipes = false;
  bool _isLoadingFriends = false;
  bool _isLoadingFavoritesCount = false;

  // Expandable sections state
  bool _picturesExpanded = true;
  bool _recipesExpanded = true;
  bool _friendsExpanded = true;

  // Cache durations
  static const Duration _profileCacheDuration = Duration(minutes: 10);
  static const Duration _friendshipCacheDuration = Duration(seconds: 30);
  static const Duration _picturesCacheDuration = Duration(minutes: 10);
  static const Duration _recipesCacheDuration = Duration(minutes: 5);
  static const Duration _friendsCacheDuration = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData({bool forceRefresh = false}) async {
    await _loadUserProfile(forceRefresh: forceRefresh);
    
    // Load additional data in parallel
    await Future.wait([
      _loadPictures(forceRefresh: forceRefresh),
      _loadSubmittedRecipes(forceRefresh: forceRefresh),
      _loadFriends(forceRefresh: forceRefresh),
      _loadFavoriteRecipesCount(),
    ]);
  }

  // ========== CACHE HELPERS ==========
  
  String _getProfileCacheKey() => 'user_profile_${widget.userId}';
  String _getFriendshipCacheKey() => 'friendship_status_${widget.userId}';
  String _getPicturesCacheKey() => 'user_pictures_${widget.userId}';
  String _getRecipesCacheKey() => 'user_recipes_${widget.userId}';
  String _getFriendsCacheKey() => 'user_friends_${widget.userId}';

  Map<String, dynamic>? _getCachedProfile(SharedPreferences prefs, {bool ignoreExpiry = false}) {
    try {
      final cached = prefs.getString(_getProfileCacheKey());
      if (cached == null) return null;
      
      final data = json.decode(cached);
      final timestamp = data['_cached_at'] as int?;
      if (timestamp == null) return null;
      
      if (!ignoreExpiry) {
        final age = DateTime.now().millisecondsSinceEpoch - timestamp;
        if (age > _profileCacheDuration.inMilliseconds) return null;
      }
      
      return Map<String, dynamic>.from(data['data']);
    } catch (e) {
      return null;
    }
  }

  Map<String, dynamic>? _getCachedFriendship(SharedPreferences prefs, {bool ignoreExpiry = false}) {
    try {
      final cached = prefs.getString(_getFriendshipCacheKey());
      if (cached == null) return null;
      
      final data = json.decode(cached);
      final timestamp = data['_cached_at'] as int?;
      if (timestamp == null) return null;
      
      if (!ignoreExpiry) {
        final age = DateTime.now().millisecondsSinceEpoch - timestamp;
        if (age > _friendshipCacheDuration.inMilliseconds) return null;
      }
      
      return Map<String, dynamic>.from(data['data']);
    } catch (e) {
      return null;
    }
  }

  List<String>? _getCachedPictures(SharedPreferences prefs) {
    try {
      final cached = prefs.getString(_getPicturesCacheKey());
      if (cached == null) return null;
      
      final data = json.decode(cached);
      final timestamp = data['_cached_at'] as int?;
      if (timestamp == null) return null;
      
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > _picturesCacheDuration.inMilliseconds) return null;
      
      return List<String>.from(data['pictures']);
    } catch (e) {
      return null;
    }
  }

  List<SubmittedRecipe>? _getCachedRecipes(SharedPreferences prefs) {
    try {
      final cached = prefs.getString(_getRecipesCacheKey());
      if (cached == null) return null;
      
      final data = json.decode(cached);
      final timestamp = data['_cached_at'] as int?;
      if (timestamp == null) return null;
      
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > _recipesCacheDuration.inMilliseconds) return null;
      
      return (data['recipes'] as List)
          .map((e) => SubmittedRecipe.fromJson(e))
          .toList();
    } catch (e) {
      return null;
    }
  }

  List<Map<String, dynamic>>? _getCachedFriends(SharedPreferences prefs) {
    try {
      final cached = prefs.getString(_getFriendsCacheKey());
      if (cached == null) return null;
      
      final data = json.decode(cached);
      final timestamp = data['_cached_at'] as int?;
      if (timestamp == null) return null;
      
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > _friendsCacheDuration.inMilliseconds) return null;
      
      return (data['friends'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      return null;
    }
  }

  Future<void> _cacheProfile(SharedPreferences prefs, Map<String, dynamic> profile) async {
    try {
      final cacheData = {
        'data': profile,
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(_getProfileCacheKey(), json.encode(cacheData));
    } catch (e) {
      print('Error caching profile: $e');
    }
  }

  Future<void> _cacheFriendship(SharedPreferences prefs, Map<String, dynamic> friendship) async {
    try {
      final cacheData = {
        'data': friendship,
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(_getFriendshipCacheKey(), json.encode(cacheData));
    } catch (e) {
      print('Error caching friendship: $e');
    }
  }

  Future<void> _cachePictures(SharedPreferences prefs, List<String> pictures) async {
    try {
      final cacheData = {
        'pictures': pictures,
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(_getPicturesCacheKey(), json.encode(cacheData));
    } catch (e) {
      print('Error caching pictures: $e');
    }
  }

  Future<void> _cacheRecipes(SharedPreferences prefs, List<SubmittedRecipe> recipes) async {
    try {
      final cacheData = {
        'recipes': recipes.map((r) => r.toJson()).toList(),
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(_getRecipesCacheKey(), json.encode(cacheData));
    } catch (e) {
      print('Error caching recipes: $e');
    }
  }

  Future<void> _cacheFriends(SharedPreferences prefs, List<Map<String, dynamic>> friends) async {
    try {
      final cacheData = {
        'friends': friends,
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(_getFriendsCacheKey(), json.encode(cacheData));
    } catch (e) {
      print('Error caching friends: $e');
    }
  }

  // ========== LOAD FUNCTIONS ==========

  Future<void> _loadUserProfile({bool forceRefresh = false}) async {
    try {
      setState(() => isLoading = true);
      
      final prefs = await SharedPreferences.getInstance();
      
      if (!forceRefresh) {
        final cachedProfile = _getCachedProfile(prefs);
        final cachedFriendship = _getCachedFriendship(prefs);
        
        if (cachedProfile != null && cachedFriendship != null) {
          if (mounted) {
            setState(() {
              userProfile = cachedProfile;
              friendshipStatus = cachedFriendship;
              isLoading = false;
            });
          }
          return;
        } else if (cachedProfile != null) {
          if (mounted) {
            setState(() {
              userProfile = cachedProfile;
            });
          }
        }
      }
      
      final results = await Future.wait([
        ProfileService.getUserProfile(widget.userId),
        FriendsService.checkFriendshipStatus(widget.userId),
      ]);
      
      final profile = results[0];
      final friendship = results[1];
      
      if (profile != null) await _cacheProfile(prefs, profile);
      if (friendship != null) await _cacheFriendship(prefs, friendship);
      
      if (mounted) {
        setState(() {
          userProfile = profile;
          friendshipStatus = friendship;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        
        final prefs = await SharedPreferences.getInstance();
        final staleProfile = _getCachedProfile(prefs, ignoreExpiry: true);
        final staleFriendship = _getCachedFriendship(prefs, ignoreExpiry: true);
        
        if (staleProfile != null && staleFriendship != null) {
          setState(() {
            userProfile = staleProfile;
            friendshipStatus = staleFriendship;
          });
        }
      }
    }
  }

  Future<void> _loadPictures({bool forceRefresh = false}) async {
    if (!mounted) return;
    
    setState(() => _isLoadingPictures = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (!forceRefresh) {
        final cachedPictures = _getCachedPictures(prefs);
        if (cachedPictures != null) {
          if (mounted) {
            setState(() {
              _pictures = cachedPictures;
              _isLoadingPictures = false;
            });
          }
          return;
        }
      }
      
      final pictures = await PictureService.getUserPictures(widget.userId);
      await _cachePictures(prefs, pictures);
      
      if (mounted) {
        setState(() {
          _pictures = pictures;
          _isLoadingPictures = false;
        });
      }
    } catch (e) {
      print('Error loading pictures: $e');
      if (mounted) {
        setState(() {
          _pictures = [];
          _isLoadingPictures = false;
        });
      }
    }
  }

  Future<void> _loadSubmittedRecipes({bool forceRefresh = false}) async {
    if (!mounted) return;
    
    setState(() => _isLoadingRecipes = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (!forceRefresh) {
        final cachedRecipes = _getCachedRecipes(prefs);
        if (cachedRecipes != null) {
          if (mounted) {
            setState(() {
              _submittedRecipes = cachedRecipes
                  .where((recipe) => recipe.isVerified == true)
                  .toList();
              _isLoadingRecipes = false;
            });
          }
          return;
        }
      }
      
      // Use getSubmittedRecipes and filter by userId
      final allRecipes = await SubmittedRecipesService.getSubmittedRecipes();
      final userRecipes = allRecipes
          .where((recipe) => recipe.userId == widget.userId && recipe.isVerified == true)
          .toList();
      
      await _cacheRecipes(prefs, userRecipes);
      
      if (mounted) {
        setState(() {
          _submittedRecipes = userRecipes;
          _isLoadingRecipes = false;
        });
      }
    } catch (e) {
      print('Error loading recipes: $e');
      if (mounted) {
        setState(() {
          _submittedRecipes = [];
          _isLoadingRecipes = false;
        });
      }
    }
  }

  Future<void> _loadFriends({bool forceRefresh = false}) async {
    if (!mounted) return;
    
    setState(() => _isLoadingFriends = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (!forceRefresh) {
        final cachedFriends = _getCachedFriends(prefs);
        if (cachedFriends != null) {
          // Get visibility setting from user's profile
          final profile = await ProfileService.getUserProfile(widget.userId);
          final visibility = profile?['friends_list_visible'] ?? true;
          
          if (mounted) {
            setState(() {
              _friends = cachedFriends;
              _friendsListVisible = visibility;
              _isLoadingFriends = false;
            });
          }
          return;
        }
      }
      
      final friends = await FriendsVisibilityService.getUserFriends(widget.userId);
      
      // Get visibility setting from user's profile
      final profile = await ProfileService.getUserProfile(widget.userId);
      final visibility = profile?['friends_list_visible'] ?? true;
      
      await _cacheFriends(prefs, friends);
      
      if (mounted) {
        setState(() {
          _friends = friends;
          _friendsListVisible = visibility;
          _isLoadingFriends = false;
        });
      }
    } catch (e) {
      print('Error loading friends: $e');
      if (mounted) {
        setState(() {
          _friends = [];
          _friendsListVisible = true; // Default to visible on error
          _isLoadingFriends = false;
        });
      }
    }
  }

  Future<void> _loadFavoriteRecipesCount() async {
    if (!mounted) return;
    
    setState(() => _isLoadingFavoritesCount = true);
    
    try {
      // Use the getFavoriteRecipesCount method - but this gets current user's count
      // For other users, we need to fetch all favorites and filter
      final allFavorites = await FavoriteRecipesService.getFavoriteRecipes();
      // Note: This will only work if we're viewing our own profile
      // For other users, we may not have access to their favorites
      
      if (mounted) {
        setState(() {
          _favoriteRecipesCount = allFavorites.length;
          _isLoadingFavoritesCount = false;
        });
      }
    } catch (e) {
      print('Error loading favorites count: $e');
      if (mounted) {
        setState(() {
          _favoriteRecipesCount = 0;
          _isLoadingFavoritesCount = false;
        });
      }
    }
  }

  Future<void> _invalidateFriendshipCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_getFriendshipCacheKey());
    } catch (e) {
      print('Error invalidating cache: $e');
    }
  }

  static Future<void> invalidateUserCache(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_profile_$userId');
      await prefs.remove('friendship_status_$userId');
      await prefs.remove('user_pictures_$userId');
      await prefs.remove('user_recipes_$userId');
      await prefs.remove('user_friends_$userId');
    } catch (e) {
      print('Error invalidating user cache: $e');
    }
  }

  // ========== FRIENDSHIP ACTIONS ==========

  Future<void> _sendFriendRequest() async {
    if (isActionLoading) return;
    
    try {
      setState(() => isActionLoading = true);
      
      await FriendsService.sendFriendRequest(widget.userId);
      await _invalidateFriendshipCache();
      
      final status = await FriendsService.checkFriendshipStatus(widget.userId);
      final prefs = await SharedPreferences.getInstance();
      await _cacheFriendship(prefs, status);
      
      if (mounted) {
        setState(() {
          friendshipStatus = status;
          isActionLoading = false;
        });
        
        ErrorHandlingService.showSuccess(context, 'Friend request sent!');
      }
    } catch (e) {
      if (mounted) {
        setState(() => isActionLoading = false);
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to send friend request',
          onRetry: _sendFriendRequest,
        );
      }
    }
  }

  Future<void> _cancelFriendRequest() async {
    if (isActionLoading) return;
    
    try {
      setState(() => isActionLoading = true);
      
      await FriendsService.cancelFriendRequest(widget.userId);
      await _invalidateFriendshipCache();
      
      final status = await FriendsService.checkFriendshipStatus(widget.userId);
      final prefs = await SharedPreferences.getInstance();
      await _cacheFriendship(prefs, status);
      
      if (mounted) {
        setState(() {
          friendshipStatus = status;
          isActionLoading = false;
        });
        
        ErrorHandlingService.showSuccess(context, 'Friend request cancelled');
      }
    } catch (e) {
      if (mounted) {
        setState(() => isActionLoading = false);
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to cancel friend request',
          onRetry: _cancelFriendRequest,
        );
      }
    }
  }

  Future<void> _acceptFriendRequest() async {
    if (isActionLoading || friendshipStatus?['requestId'] == null) return;
    
    try {
      setState(() => isActionLoading = true);
      
      await FriendsService.acceptFriendRequest(friendshipStatus!['requestId']);
      await _invalidateFriendshipCache();
      
      final status = await FriendsService.checkFriendshipStatus(widget.userId);
      final prefs = await SharedPreferences.getInstance();
      await _cacheFriendship(prefs, status);
      
      if (mounted) {
        setState(() {
          friendshipStatus = status;
          isActionLoading = false;
        });
        
        ErrorHandlingService.showSuccess(context, 'Friend request accepted! You are now friends.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => isActionLoading = false);
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to accept friend request',
          onRetry: _acceptFriendRequest,
        );
      }
    }
  }

  Future<void> _declineFriendRequest() async {
    if (isActionLoading || friendshipStatus?['requestId'] == null) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Decline Friend Request'),
        content: const Text('Are you sure you want to decline this friend request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Decline', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    
    try {
      setState(() => isActionLoading = true);
      
      await FriendsService.declineFriendRequest(friendshipStatus!['requestId']);
      await _invalidateFriendshipCache();
      
      final status = await FriendsService.checkFriendshipStatus(widget.userId);
      final prefs = await SharedPreferences.getInstance();
      await _cacheFriendship(prefs, status);
      
      if (mounted) {
        setState(() {
          friendshipStatus = status;
          isActionLoading = false;
        });
        
        ErrorHandlingService.showSuccess(context, 'Friend request declined');
      }
    } catch (e) {
      if (mounted) {
        setState(() => isActionLoading = false);
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to decline friend request',
          onRetry: _declineFriendRequest,
        );
      }
    }
  }

  Future<void> _unfriend() async {
    if (isActionLoading) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Friend'),
        content: Text(
          'Are you sure you want to unfriend ${_getDisplayName()}? You can always send them a friend request again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Unfriend', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    
    try {
      setState(() => isActionLoading = true);
      
      await FriendsService.removeFriend(widget.userId);
      await _invalidateFriendshipCache();
      
      final status = await FriendsService.checkFriendshipStatus(widget.userId);
      final prefs = await SharedPreferences.getInstance();
      await _cacheFriendship(prefs, status);
      
      if (mounted) {
        setState(() {
          friendshipStatus = status;
          isActionLoading = false;
        });
        
        ErrorHandlingService.showSuccess(
          context,
          'You are no longer friends with ${_getDisplayName()}',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => isActionLoading = false);
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to remove friend',
          onRetry: _unfriend,
        );
      }
    }
  }

  void _openChat() {
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(
            friendId: widget.userId,
            friendName: userProfile?['username'] ?? userProfile?['email'] ?? 'Unknown',
            friendAvatar: userProfile?['profile_picture'],
          ),
        ),
      );
    } catch (e) {
      ErrorHandlingService.handleError(
        context: context,
        error: e,
        category: ErrorHandlingService.navigationError,
        showSnackBar: true,
        customMessage: 'Unable to open chat',
      );
    }
  }

  void _showFullScreenImage(String imageUrl, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text('Picture ${index + 1} of ${_pictures.length}'),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error, size: 50, color: Colors.red),
                        SizedBox(height: 10),
                        Text(
                          'Failed to load image',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _navigateToUserProfile(String userId) {
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserProfilePage(userId: userId),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open profile')),
        );
      }
    }
  }

  void _showFullFriendsList() {
    try {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.people, color: Colors.blue),
                SizedBox(width: 8),
                Text('All Friends'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${_getDisplayName()} has ${_friends.length} friends:'),
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: SingleChildScrollView(
                    child: Column(
                      children: _friends
                          .map(
                            (friend) => ListTile(
                              leading: CircleAvatar(
                                backgroundImage: friend['avatar_url'] != null
                                    ? NetworkImage(friend['avatar_url'])
                                    : null,
                                child: friend['avatar_url'] == null
                                    ? Text(
                                        (friend['username'] ?? 'U')[0]
                                            .toUpperCase(),
                                      )
                                    : null,
                              ),
                              title: Text(
                                friend['first_name'] != null &&
                                        friend['last_name'] != null
                                    ? '${friend['first_name']} ${friend['last_name']}'
                                    : friend['username'] ?? 'Unknown',
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                _navigateToUserProfile(friend['id']);
                              },
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      print('Error showing friends dialog: $e');
    }
  }

  // ========== UI BUILDERS ==========

  Widget _sectionContainer({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha((0.9 * 255).toInt()),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }

  Widget _buildActionButton() {
    if (friendshipStatus == null) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (isActionLoading) {
      return SizedBox(
        height: 40,
        child: ElevatedButton(
          onPressed: null,
          child: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
        ),
      );
    }

    final status = friendshipStatus!['status'];
    final isOutgoing = friendshipStatus!['isOutgoing'] ?? false;

    switch (status) {
      case 'accepted':
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openChat,
                icon: const Icon(Icons.message),
                label: const Text('Send Message'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _unfriend,
                icon: const Icon(Icons.person_remove, size: 18),
                label: const Text('Unfriend'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        );

      case 'pending':
        if (isOutgoing) {
          return Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _cancelFriendRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Cancel Friend Request'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Friend request sent',
                style: TextStyle(
                  color: Colors.orange.shade600,
                  fontSize: 12,
                ),
              ),
            ],
          );
        } else {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _acceptFriendRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Accept'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _declineFriendRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Decline'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Friend request received',
                style: TextStyle(
                  color: Colors.blue.shade600,
                  fontSize: 12,
                ),
              ),
            ],
          );
        }

      case 'none':
      default:
        if (friendshipStatus!['canSendRequest'] == true) {
          return SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _sendFriendRequest,
              icon: const Icon(Icons.person_add),
              label: const Text('Send Friend Request'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          );
        } else {
          return const SizedBox.shrink();
        }
    }
  }

  String _getDisplayName() {
    if (userProfile == null) return 'Unknown User';
    
    final firstName = userProfile!['first_name'];
    final lastName = userProfile!['last_name'];
    final username = userProfile!['username'];
    
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    } else if (username != null) {
      return username;
    } else {
      return userProfile!['email'] ?? 'Unknown User';
    }
  }

  String _getSubtitle() {
    if (userProfile == null) return '';
    
    final username = userProfile!['username'];
    final email = userProfile!['email'];
    
    if (username != null && email != null) {
      return '@$username • $email';
    } else if (username != null) {
      return '@$username';
    } else if (email != null) {
      return email;
    } else {
      return '';
    }
  }

  Widget _buildPicturesSection() {
    return _sectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _picturesExpanded = !_picturesExpanded;
              });
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'Pictures (${_pictures.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _picturesExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.grey.shade600,
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          if (_picturesExpanded) ...[
            const SizedBox(height: 12),
            if (_isLoadingPictures) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              ),
            ] else if (_pictures.isEmpty) ...[
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.photo_library,
                      size: 50,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No pictures yet',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemCount: _pictures.length,
                itemBuilder: (context, index) {
                  final pictureUrl = _pictures[index];
                  return GestureDetector(
                    onTap: () => _showFullScreenImage(pictureUrl, index),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          pictureUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                    : null,
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Icon(
                                Icons.broken_image,
                                color: Colors.grey.shade400,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSubmittedRecipesSection() {
    // Only show this section if viewing own profile
    final isOwnProfile = AuthService.currentUserId == widget.userId;
    
    if (!isOwnProfile) {
      // For other users, show a simplified view without edit/delete options
      return _sectionContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  _recipesExpanded = !_recipesExpanded;
                });
              },
              child: Row(
                children: [
                  Text(
                    'Submitted Recipes (${_submittedRecipes.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _recipesExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
            
            if (_recipesExpanded) ...[
              const SizedBox(height: 12),
              if (_isLoadingRecipes) ...[
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                ),
              ] else if (_submittedRecipes.isEmpty) ...[
                Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.restaurant_menu,
                        size: 50,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No recipes submitted yet',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Show simplified recipe cards for other users
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _submittedRecipes.length,
                  itemBuilder: (context, index) {
                    final recipe = _submittedRecipes[index];
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (recipe.isVerified)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 8),
                                    child: Icon(
                                      Icons.verified,
                                      size: 20,
                                      color: Colors.blue,
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    recipe.recipeName,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.restaurant_menu, 
                                          size: 16, color: Colors.grey.shade600),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Ingredients:',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    recipe.ingredients.split('\n')
                                        .where((line) => line.trim().isNotEmpty)
                                        .take(3)
                                        .join('\n') + 
                                        (recipe.ingredients.split('\n').length > 3 ? '\n...' : ''),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade700,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      // Navigate to full recipe view
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => RecipeDetailPage(
                                            recipeName: recipe.recipeName,
                                            ingredients: recipe.ingredients,
                                            directions: recipe.directions,
                                            recipeId: recipe.id ?? 0,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.visibility, size: 16),
                                    label: const Text('View Full Recipe'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.blue,
                                      side: const BorderSide(color: Colors.blue),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ],
        ),
      );
    }
    
    // For own profile, use the full RecipeCard with edit/delete
    return _sectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _recipesExpanded = !_recipesExpanded;
              });
            },
            child: Row(
              children: [
                Text(
                  'Submitted Recipes (${_submittedRecipes.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _recipesExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.grey.shade600,
                ),
              ],
            ),
          ),
          
          if (_recipesExpanded) ...[
            const SizedBox(height: 12),
            if (_isLoadingRecipes) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              ),
            ] else if (_submittedRecipes.isEmpty) ...[
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.restaurant_menu,
                      size: 50,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No recipes submitted yet',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _submittedRecipes.length,
                itemBuilder: (context, index) {
                  final recipe = _submittedRecipes[index];
                  
                  if (recipe.id == null) {
                    return const SizedBox.shrink();
                  }

                  return RecipeCard(
                    recipe: recipe,
                    onDelete: () async {
                      // Delete logic here
                      await _loadSubmittedRecipes(forceRefresh: true);
                    },
                    onEdit: () {
                      // Edit logic here
                    },
                    onRatingChanged: () => _loadSubmittedRecipes(forceRefresh: true),
                  );
                },
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildFriendsSection() {
    return _sectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _friendsExpanded = !_friendsExpanded;
              });
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'Friends (${_friends.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _friendsExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.grey.shade600,
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          if (_friendsExpanded) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _friendsListVisible ? Icons.visibility : Icons.visibility_off,
                  size: 16,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 4),
                Text(
                  _friendsListVisible ? 'Visible to others' : 'Hidden from others',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            if (_isLoadingFriends) ...[
              const Center(child: CircularProgressIndicator()),
            ] else if (!_friendsListVisible) ...[
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.visibility_off,
                      size: 50,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_getDisplayName()}\'s friends list is private',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ] else if (_friends.isEmpty) ...[
              Center(
                child: Text(
                  'No friends yet',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
              ),
            ] else ...[
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.8,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _friends.length > 6 ? 6 : _friends.length,
                itemBuilder: (context, index) {
                  if (index == 5 && _friends.length > 6) {
                    return GestureDetector(
                      onTap: _showFullFriendsList,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.more_horiz,
                                size: 30, color: Colors.grey.shade600),
                            const SizedBox(height: 4),
                            Text(
                              'View All\n${_friends.length} friends',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final friend = _friends[index];
                  return GestureDetector(
                    onTap: () => _navigateToUserProfile(friend['id']),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 25,
                          backgroundImage: friend['avatar_url'] != null
                              ? NetworkImage(friend['avatar_url'])
                              : null,
                          child: friend['avatar_url'] == null
                              ? Text(
                                  (friend['username'] ??
                                              friend['first_name'] ??
                                              friend['email'] ??
                                              'U')[0]
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Text(
                            friend['first_name'] != null &&
                                    friend['last_name'] != null
                                ? '${friend['first_name']} ${friend['last_name']}'
                                : friend['username'] ?? 'Unknown',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              if (_friends.length > 6) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _showFullFriendsList,
                  child: Text('View All ${_friends.length} Friends'),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildFavoriteRecipesSection() {
    return _sectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Favorite Recipes',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          if (_isLoadingFavoritesCount) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            ),
          ] else ...[
            Text(
              _favoriteRecipesCount == 0
                  ? 'No favorite recipes yet'
                  : '$_favoriteRecipesCount favorite ${_favoriteRecipesCount == 1 ? 'recipe' : 'recipes'}',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCookbookSection() {
    return _sectionContainer(
      child: const CookbookSection(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Profile'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () async {
              try {
                await _loadAllData(forceRefresh: true);
                if (mounted) {
                  ErrorHandlingService.showSuccess(context, 'Profile refreshed');
                }
              } catch (e) {
                if (mounted) {
                  await ErrorHandlingService.handleError(
                    context: context,
                    error: e,
                    category: ErrorHandlingService.databaseError,
                    showSnackBar: true,
                    customMessage: 'Failed to refresh profile',
                  );
                }
              }
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh profile',
          ),
        ],
      ),
      body: isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Loading profile...',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            )
          : userProfile == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.person_off,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Profile not found',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This user may have been deleted or is no longer available.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Go Back'),
                      ),
                    ],
                  ),
                )
              : Stack(
                  children: [
                    // Background image
                    Positioned.fill(
                      child: userProfile!['profile_background'] != null
                          ? Image.network(
                              userProfile!['profile_background'],
                              fit: BoxFit.fill,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: Colors.blue.shade50,
                                );
                              },
                            )
                          : Container(
                              color: Colors.blue.shade50,
                            ),
                    ),
                    
                    // Main content
                    RefreshIndicator(
                      onRefresh: () => _loadAllData(forceRefresh: true),
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            // Profile header
                            _sectionContainer(
                              child: Column(
                                children: [
                                  CircleAvatar(
                                    radius: 60,
                                    backgroundColor: Colors.grey.shade200,
                                    backgroundImage: userProfile!['profile_picture'] != null
                                        ? NetworkImage(userProfile!['profile_picture'])
                                        : null,
                                    child: userProfile!['profile_picture'] == null
                                        ? Text(
                                            _getDisplayName()[0].toUpperCase(),
                                            style: const TextStyle(
                                              fontSize: 36,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey,
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(height: 16),
                                  
                                  Text(
                                    _getDisplayName(),
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  
                                  if (_getSubtitle().isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      _getSubtitle(),
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey.shade600,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                  
                                  const SizedBox(height: 24),
                                  
                                  _buildActionButton(),
                                ],
                              ),
                            ),
                            
                            const SizedBox(height: 20),
                            
                            // Pictures section
                            _buildPicturesSection(),
                            
                            const SizedBox(height: 20),
                            
                            // Friends section
                            _buildFriendsSection(),
                            
                            const SizedBox(height: 20),
                            
                            // Submitted recipes section
                            _buildSubmittedRecipesSection(),
                            
                            const SizedBox(height: 20),
                            
                            // Favorite recipes section
                            _buildFavoriteRecipesSection(),
                            
                            const SizedBox(height: 20),
                            
                            // Cookbook section
                            _buildCookbookSection(),
                            
                            const SizedBox(height: 100),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}