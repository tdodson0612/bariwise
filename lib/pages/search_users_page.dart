// lib/pages/search_users_page.dart
// Search Users with caching, debounced "search as you type", animated UI, and suggested friends

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

// REPLACED DATABASE SERVICE WITH SPECIFIC SERVICES
import '../services/user_search_service.dart';
import '../services/friends_service.dart';
import '../exceptions/friend_request_exception.dart';

import 'user_profile_page.dart';
import '../widgets/app_drawer.dart';

class SearchUsersPage extends StatefulWidget {
  final String? initialQuery;

  const SearchUsersPage({super.key, this.initialQuery});

  @override
  State<SearchUsersPage> createState() => _SearchUsersPageState();
}

class _SearchUsersPageState extends State<SearchUsersPage>
    with SingleTickerProviderStateMixin {
  late TextEditingController _searchController;
  final Logger _logger = Logger();

  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _suggestedFriends = [];
  Map<String, Map<String, dynamic>> _friendshipStatuses = {};

  bool _isLoading = false;
  bool _isLoadingSuggested = false;
  bool _hasSearched = false;
  String? _errorMessage;

  // 🔥 UPDATED: App owner emails instead of IDs
  static const List<String> _ownerEmails = [
    'terryd0612@gmail.com',           // Terry D.
    'bbrc2021bbc1298.442@icloud.com', // Admit Britt (Co-owner)
  ];

  // simple fade animation for main content
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // debounce for "search as you type"
  Timer? _debounce;
  static const _debounceDuration = Duration(milliseconds: 400);

  // Cache configuration
  static const Duration _searchCacheDuration = Duration(minutes: 5);
  static const Duration _friendshipCacheDuration = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();

    _searchController = TextEditingController(text: widget.initialQuery ?? '');
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeAnimation =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut);

    // initial query (e.g. when coming from another page)
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _searchUsers(widget.initialQuery!);
    } else {
      // Load suggested friends on initial load
      _loadSuggestedFriends();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _fadeController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // -------------------- CACHE HELPERS --------------------

  String _getSearchCacheKey(String query) =>
      'search_results_${query.toLowerCase().trim()}';
  String _getFriendshipCacheKey(String userId) =>
      'friendship_status_$userId';

  Future<List<Map<String, dynamic>>?> _getCachedSearchResults(
      String query) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_getSearchCacheKey(query));
      if (cached == null) return null;

      final data = json.decode(cached);
      final timestamp = data['_cached_at'] as int?;
      if (timestamp == null) return null;

      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > _searchCacheDuration.inMilliseconds) return null;

      final results = (data['results'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      _logger.d(
          '📦 Using cached search results for "$query" (${results.length} users)');
      return results;
    } catch (e) {
      _logger.e('Error loading cached search: $e');
      return null;
    }
  }

  Future<void> _cacheSearchResults(
      String query, List<Map<String, dynamic>> results) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'results': results,
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(_getSearchCacheKey(query), json.encode(cacheData));
      _logger.d('💾 Cached search results for "$query"');
    } catch (e) {
      _logger.e('Error caching search results: $e');
    }
  }

  Future<Map<String, dynamic>?> _getCachedFriendshipStatus(
      String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_getFriendshipCacheKey(userId));
      if (cached == null) return null;

      final data = json.decode(cached);
      final timestamp = data['_cached_at'] as int?;
      if (timestamp == null) return null;

      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > _friendshipCacheDuration.inMilliseconds) return null;

      return Map<String, dynamic>.from(data['data']);
    } catch (e) {
      _logger.e('Error loading cached friendship status: $e');
      return null;
    }
  }

  Future<void> _cacheFriendshipStatus(
      String userId, Map<String, dynamic> status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'data': status,
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(
          _getFriendshipCacheKey(userId), json.encode(cacheData));
    } catch (e) {
      _logger.e('Error caching friendship status: $e');
    }
  }

  // -------------------- 🔥 FIXED: SUGGESTED FRIENDS WITH ERROR HANDLING --------------------

  Future<void> _loadSuggestedFriends() async {
    if (!mounted) return;
    
    setState(() {
      _isLoadingSuggested = true;
      _errorMessage = null;  // 🔥 Clear any previous errors
    });

    try {
      _logger.d('👥 Loading suggested friends (app owners by email)...');

      // 🔥 ADDED: Wrap in try-catch for better error handling
      List<Map<String, dynamic>> suggested;
      try {
        suggested = await UserSearchService.getSuggestedFriendsByEmail(_ownerEmails);
      } catch (e) {
        _logger.e('❌ Error fetching suggested friends from service: $e');
        
        if (!mounted) return;
        setState(() {
          _suggestedFriends = [];
          _isLoadingSuggested = false;
          _errorMessage = 'Unable to load suggested friends. Please check your connection.';
        });
        return;
      }
      
      if (suggested.isEmpty) {
        _logger.w('⚠️ No owner accounts found with emails: $_ownerEmails');
        if (!mounted) return;
        setState(() {
          _suggestedFriends = [];
          _isLoadingSuggested = false;
        });
        return;
      }

      _logger.d('✅ Found ${suggested.length} owner accounts');

      // 🔥 FIXED: Better error handling for friendship status checks
      final statusMap = <String, Map<String, dynamic>>{};
      final filteredSuggested = <Map<String, dynamic>>[];
      
      for (final user in suggested) {
        final userId = user['id'];
        
        if (userId == null) {
          _logger.w('⚠️ User missing ID, skipping: ${user['email']}');
          continue;
        }
        
        // 🔥 ADDED: Try-catch for each friendship status check
        Map<String, dynamic>? status;
        try {
          status = await _getCachedFriendshipStatus(userId);
          if (status == null) {
            status = await FriendsService.checkFriendshipStatus(userId);
            await _cacheFriendshipStatus(userId, status);
          }
        } catch (e) {
          _logger.e('❌ Error checking friendship status for ${user['email']}: $e');
          // 🔥 Use default status on error
          status = {
            'status': 'none',
            'canSendRequest': true,
            'isOutgoing': false,
          };
        }
        
        // Only add to suggested if NOT already friends
        if (status['status'] != 'accepted') {
          filteredSuggested.add(user);
          statusMap[userId] = status;
          _logger.d('  ✓ ${user['email']} - Status: ${status['status']}');
        } else {
          _logger.d('  ✗ ${user['email']} - Already friends, skipping');
        }
      }

      if (!mounted) return;
      setState(() {
        _suggestedFriends = filteredSuggested;
        _friendshipStatuses = statusMap;
        _isLoadingSuggested = false;
        _errorMessage = null;  // 🔥 Clear error on success
      });

      if (filteredSuggested.isNotEmpty) {
        _fadeController.forward(from: 0.0);
        _logger.i('👥 Showing ${filteredSuggested.length} suggested friends');
      } else {
        _logger.i('👥 All owners are already friends - no suggestions to show');
      }
    } catch (e, stackTrace) {
      _logger.e('❌ Error loading suggested friends: $e');
      _logger.e('Stack trace: $stackTrace');
      
      if (!mounted) return;
      setState(() {
        _isLoadingSuggested = false;
        _suggestedFriends = [];
        _errorMessage = 'Error loading suggested friends: ${e.toString()}';
      });
      
      // 🔥 ADDED: Show user-friendly error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to load suggested friends. Please try again.'),
          backgroundColor: Colors.orange,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: _loadSuggestedFriends,
          ),
        ),
      );
    }
  }

  // -------------------- DEBUG TEST --------------------

  Future<void> _runDebugTest() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await UserSearchService.debugTestUserSearch();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debug test completed! Check your console logs.'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      _logger.e('❌ Debug test error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Debug test error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // -------------------- 🔥 FIXED: SEARCH LOGIC WITH ERROR HANDLING --------------------

  Future<void> _searchUsers([String? forcedQuery]) async {
    final query = (forcedQuery ?? _searchController.text).trim();

    if (query.isEmpty) {
      setState(() {
        _errorMessage = null;  // 🔥 Don't show error for empty search
        _searchResults = [];
        _friendshipStatuses = {};
        _hasSearched = false;
      });
      // Reload suggested friends when search is cleared
      _loadSuggestedFriends();
      return;
    }

    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _errorMessage = null;
      _suggestedFriends = []; // Clear suggested friends when searching
    });

    _fadeController.reset();

    try {
      _logger.d('🔎 Starting user search from UI for "$query"...');

      // 1) Try cache
      final cachedResults = await _getCachedSearchResults(query);
      List<Map<String, dynamic>> results;

      if (cachedResults != null) {
        results = cachedResults;
        _logger.i('📱 Using cached results: ${results.length} users');
      } else {
        // 2) 🔥 ADDED: Better error handling for fetch
        try {
          results = await UserSearchService.searchUsers(query);
          _logger.i('📱 Fetched fresh results: ${results.length} users');
          await _cacheSearchResults(query, results);
        } catch (e) {
          _logger.e('❌ Error fetching search results: $e');
          
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _searchResults = [];
            _errorMessage = 'Search failed. Please check your connection and try again.';
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error searching users. Please try again.'),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () => _searchUsers(query),
              ),
            ),
          );
          return;
        }
      }

      // 3) 🔥 IMPROVED: Friendship status per user with better error handling
      final statusMap = <String, Map<String, dynamic>>{};
      int cachedStatuses = 0;
      int freshStatuses = 0;
      int failedStatuses = 0;

      for (final user in results) {
        final userId = user['id'];
        
        if (userId == null) {
          _logger.w('⚠️ User missing ID in search results: ${user['email'] ?? user['username']}');
          continue;
        }

        try {
          var status = await _getCachedFriendshipStatus(userId);
          if (status != null) {
            cachedStatuses++;
          } else {
            status = await FriendsService.checkFriendshipStatus(userId);
            freshStatuses++;
            await _cacheFriendshipStatus(userId, status);
          }
          statusMap[userId] = status;
        } catch (e) {
          _logger.e('❌ Error checking friendship status for user $userId: $e');
          failedStatuses++;
          // 🔥 Use default status on error
          statusMap[userId] = {
            'status': 'none',
            'canSendRequest': true,
            'isOutgoing': false,
          };
        }
      }

      _logger.i(
          '👥 Friendship statuses: $cachedStatuses cached, $freshStatuses fresh, $failedStatuses failed');

      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _friendshipStatuses = statusMap;
        _isLoading = false;

        if (results.isEmpty) {
          _errorMessage = 'No users found matching "$query"';
        } else {
          _errorMessage = null;  // 🔥 Clear error on success
        }
      });

      // run fade-in after we have new content
      _fadeController.forward(from: 0.0);
    } catch (e, stackTrace) {
      _logger.e('❌ UI search error: $e');
      _logger.e('Stack trace: $stackTrace');
      
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Search error. Please try again.';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error searching users. Please try again.'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => _searchUsers(query),
          ),
        ),
      );
    }
  }

  // debounced "search as you type"
  void _onSearchChanged(String value) {
    _debounce?.cancel();

    // don't auto-search on empty / short queries – just clear state and reload suggested
    if (value.trim().length < 2) {
      setState(() {
        _hasSearched = false;
        _searchResults = [];
        _friendshipStatuses = {};
        _errorMessage = null;
      });
      if (value.trim().isEmpty) {
        _loadSuggestedFriends();
      }
      return;
    }

    _debounce = Timer(_debounceDuration, () {
      _searchUsers(value);
    });
  }

  // -------------------- 🔥 IMPROVED: FRIEND REQUESTS WITH BETTER ERROR HANDLING --------------------

  Future<void> _sendFriendRequest(String userId) async {
    try {
      await FriendsService.sendFriendRequest(userId);

      final newStatus = {
        'status': 'pending',
        'isOutgoing': true,
        'canSendRequest': false,
      };

      await _cacheFriendshipStatus(userId, newStatus);

      if (!mounted) return;
      setState(() {
        _friendshipStatuses[userId] = newStatus;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Friend request sent!'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    } on FriendRequestException catch (e) {
      _logger.w('Friend request exception: ${e.type} - ${e.message}');
      
      if (!mounted) return;
      
      // 🔥 Pretty green banner for "already sent" case
      if (e.type == FriendRequestErrorType.alreadySent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Friend request already sent'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        // Other friend request errors (already friends, etc.)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e, stackTrace) {
      _logger.e('❌ Error sending friend request: $e');
      _logger.e('Stack trace: $stackTrace');
      
      if (!mounted) return;
      
      // 🔥 IMPROVED: More helpful error message
      String errorMessage = 'Failed to send friend request.';
      
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('network') || errorString.contains('socket')) {
        errorMessage = 'Network error. Please check your connection.';
      } else if (errorString.contains('timeout')) {
        errorMessage = 'Request timed out. Please try again.';
      } else if (errorString.contains('authentication')) {
        errorMessage = 'Authentication error. Please sign out and back in.';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => _sendFriendRequest(userId),
          ),
        ),
      );
    }
  }

  Future<void> _cancelFriendRequest(String userId) async {
    try {
      await FriendsService.cancelFriendRequest(userId);

      final newStatus = {
        'status': 'none',
        'canSendRequest': true,
      };

      await _cacheFriendshipStatus(userId, newStatus);

      if (!mounted) return;
      setState(() {
        _friendshipStatuses[userId] = newStatus;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Friend request cancelled'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e, stackTrace) {
      _logger.e('❌ Error cancelling friend request: $e');
      _logger.e('Stack trace: $stackTrace');
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to cancel request. Please try again.'),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => _cancelFriendRequest(userId),
          ),
        ),
      );
    }
  }

  // -------------------- UI HELPERS --------------------

  Widget _buildFriendshipButton(Map<String, dynamic> user) {
    final userId = user['id'];
    final status = _friendshipStatuses[userId];

    if (status == null) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    switch (status['status']) {
      case 'accepted':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.orange,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check, color: Colors.white, size: 16),
              SizedBox(width: 4),
              Text(
                'Friends',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );

      case 'pending':
        if (status['isOutgoing'] == true) {
          return ElevatedButton(
            onPressed: () => _cancelFriendRequest(userId),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            child: const Text('Cancel', style: TextStyle(fontSize: 12)),
          );
        } else {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Request Received',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }

      case 'none':
      default:
        return ElevatedButton.icon(
          onPressed: () => _sendFriendRequest(userId),
          icon: const Icon(Icons.person_add, size: 16),
          label: const Text('Add', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
        );
    }
  }

  String _buildUserDisplayName(Map<String, dynamic> user) {
    final firstName = user['first_name'];
    final lastName = user['last_name'];
    final username = user['username'];

    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    } else if (firstName != null) {
      return firstName;
    } else if (lastName != null) {
      return lastName;
    } else if (username != null) {
      return username;
    } else {
      return 'No name';
    }
  }

  String _buildUserSubtitle(Map<String, dynamic> user) {
    final username = user['username'];
    final email = user['email'];
    final firstName = user['first_name'];
    final lastName = user['last_name'];

    if ((firstName != null || lastName != null) && username != null) {
      return '@$username';
    } else if (email != null) {
      return email;
    } else {
      return '';
    }
  }

  Widget _buildUserTile(Map<String, dynamic> user) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: 1,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ListTile(
          leading: CircleAvatar(
            backgroundImage: user['avatar_url'] != null
                ? NetworkImage(user['avatar_url'])
                : user['profile_picture_url'] != null
                    ? NetworkImage(user['profile_picture_url'])
                    : null,
            child: (user['avatar_url'] == null && user['profile_picture_url'] == null)
                ? Text(
                    _buildUserDisplayName(user)[0].toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  )
                : null,
          ),
          title: Text(
            _buildUserDisplayName(user),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            _buildUserSubtitle(user),
            style: TextStyle(color: Colors.grey.shade600),
          ),
          trailing: _buildFriendshipButton(user),
          onTap: () async {
            try {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      UserProfilePage(userId: user['id']),
                ),
              );

              // Refresh friendship status after returning
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove(_getFriendshipCacheKey(user['id']));

              final freshStatus =
                  await FriendsService.checkFriendshipStatus(user['id']);
              await _cacheFriendshipStatus(user['id'], freshStatus);

              if (!mounted) return;
              setState(() {
                _friendshipStatuses[user['id']] = freshStatus;
              });
            } catch (e) {
              _logger.e('❌ Error navigating to user profile: $e');
              if (!mounted) return;
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Unable to open profile. Please try again.'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildInitialPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Search for Friends',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Find friends by their first name, last name, username, or email',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Even works with typos!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange.shade400,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _runDebugTest,
            icon: const Icon(Icons.bug_report),
            label: const Text('Run Debug Test'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade700,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Check console logs after running',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade400,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_search,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'No users found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different search term',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _runDebugTest,
            icon: const Icon(Icons.bug_report, size: 18),
            label: const Text('Debug: Check Database'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestedFriendsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            border: Border.all(color: Colors.orange.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.star, color: Colors.orange.shade700, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Suggested friends - Connect with the app creators!',
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _suggestedFriends.length,
          itemBuilder: (context, index) => _buildUserTile(_suggestedFriends[index]),
        ),
      ],
    );
  }

  // -------------------- BUILD --------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('Find Friends'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            tooltip: 'Run Debug Test',
            onPressed: _runDebugTest,
          ),
        ],
      ),
      drawer: AppDrawer(currentPage: 'find_friends'),
      body: SafeArea(
        child: Column(
          children: [
            // Sticky search bar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText:
                            'Search by name, username, or email...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide:
                              BorderSide(color: Colors.grey.shade300),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                      ),
                      onChanged: _onSearchChanged,
                      onSubmitted: (_) => _searchUsers(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _searchUsers,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(12),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.search),
                  ),
                ],
              ),
            ),

            // Optional error banner
            if (_errorMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.orange.shade900),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () {
                        setState(() {
                          _errorMessage = null;
                        });
                      },
                    ),
                  ],
                ),
              ),

            // Main content area with fade animation
            Expanded(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: _isLoading || _isLoadingSuggested
                    ? const Center(child: CircularProgressIndicator())
                    : !_hasSearched && _suggestedFriends.isNotEmpty
                        ? SingleChildScrollView(
                            child: _buildSuggestedFriendsSection(),
                          )
                        : !_hasSearched
                            ? _buildInitialPrompt()
                            : _searchResults.isEmpty
                                ? _buildEmptyResults()
                                : ListView.builder(
                                    itemCount: _searchResults.length,
                                    itemBuilder: (context, index) =>
                                        _buildUserTile(
                                            _searchResults[index]),
                                  ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}