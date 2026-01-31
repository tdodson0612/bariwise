// lib/pages/messages_page.dart - FIXED: Badge refresh on page load + iOS badge clearing
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bari_wise/services/friends_service.dart';
import 'package:bari_wise/services/messaging_service.dart';
import 'package:logger/logger.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../widgets/app_drawer.dart';
import '../widgets/menu_icon_with_badge.dart';
import 'chat_page.dart';
import 'search_users_page.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  _MessagesPageState createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> with SingleTickerProviderStateMixin {
  final Logger _logger = Logger();
  late TabController _tabController;
  List<Map<String, dynamic>> _chats = [];
  List<Map<String, dynamic>> _friendRequests = [];
  bool _isLoadingChats = true;
  bool _isLoadingRequests = true;

  // ✅ NEW: Platform channel for clearing iOS badge
  static const platform = MethodChannel('com.bariwise/badge');
  
  Future<void> _clearIOSBadge() async {
    try {
      await platform.invokeMethod('clearBadge');
      print('✅ iOS badge cleared from messages page');
    } catch (e) {
      print('⚠️ Error clearing iOS badge: $e');
    }
  }

  // Cache configuration
  static const Duration _chatsCacheDuration = Duration(minutes: 1);
  static const Duration _requestsCacheDuration = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // ✅ CRITICAL FIX: Refresh badge AND clear iOS badge when entering messages page
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _clearIOSBadge();
      await MessagingService.refreshUnreadBadge();
    });
    
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ========== CACHING HELPERS ==========

  Future<List<Map<String, dynamic>>?> _getCachedChats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('user_chats');
      
      if (cached == null) return null;
      
      final data = json.decode(cached);
      final timestamp = data['_cached_at'] as int?;
      
      if (timestamp == null) return null;
      
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > _chatsCacheDuration.inMilliseconds) return null;
      
      final chats = (data['chats'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      
      _logger.d('📦 Using cached chats (${chats.length} found)');
      return chats;
    } catch (e) {
      _logger.e('Error loading cached chats: $e');
      return null;
    }
  }

  Future<void> _cacheChats(List<Map<String, dynamic>> chats) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'chats': chats,
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString('user_chats', json.encode(cacheData));
      _logger.d('💾 Cached ${chats.length} chats');
    } catch (e) {
      _logger.e('Error caching chats: $e');
    }
  }

  Future<void> _invalidateChatsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_chats');
      _logger.d('🗑️ Invalidated chats cache');
    } catch (e) {
      _logger.e('Error invalidating chats cache: $e');
    }
  }

  Future<List<Map<String, dynamic>>?> _getCachedFriendRequests() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('friend_requests');
      
      if (cached == null) return null;
      
      final data = json.decode(cached);
      final timestamp = data['_cached_at'] as int?;
      
      if (timestamp == null) return null;
      
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > _requestsCacheDuration.inMilliseconds) return null;
      
      final requests = (data['requests'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      
      _logger.d('📦 Using cached friend requests (${requests.length} found)');
      return requests;
    } catch (e) {
      _logger.e('Error loading cached requests: $e');
      return null;
    }
  }

  Future<void> _cacheFriendRequests(List<Map<String, dynamic>> requests) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'requests': requests,
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString('friend_requests', json.encode(cacheData));
      _logger.d('💾 Cached ${requests.length} friend requests');
    } catch (e) {
      _logger.e('Error caching friend requests: $e');
    }
  }

  Future<void> _invalidateRequestsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('friend_requests');
      _logger.d('🗑️ Invalidated friend requests cache');
    } catch (e) {
      _logger.e('Error invalidating requests cache: $e');
    }
  }

  // ========== LOAD FUNCTIONS WITH CACHING ==========

  Future<void> _loadData({bool forceRefresh = false}) async {
    await Future.wait([
      _loadChats(forceRefresh: forceRefresh),
      _loadFriendRequests(forceRefresh: forceRefresh),
    ]);
  }

  Future<void> _loadChats({bool forceRefresh = false}) async {
    setState(() => _isLoadingChats = true);
    
    try {
      _logger.d('📨 Loading chat list...');
      
      // Try cache first unless force refresh
      if (!forceRefresh) {
        final cachedChats = await _getCachedChats();
        
        if (cachedChats != null) {
          if (mounted) {
            setState(() {
              _chats = cachedChats;
              _isLoadingChats = false;
            });
          }
          return;
        }
      }

      // Cache miss or force refresh, fetch from database
      final chats = await MessagingService.getChatList();
      
      // Sort chats by last message timestamp (newest first)
      chats.sort((a, b) {
        try {
          final timeA = a['lastMessage']?['created_at'];
          final timeB = b['lastMessage']?['created_at'];
          
          if (timeA == null && timeB == null) return 0;
          if (timeA == null) return 1;
          if (timeB == null) return -1;
          
          final dateA = DateTime.parse(timeA);
          final dateB = DateTime.parse(timeB);
          return dateB.compareTo(dateA);
        } catch (e) {
          return 0;
        }
      });
      
      // Cache the results
      await _cacheChats(chats);
      
      _logger.i('✅ Loaded ${chats.length} chats');
      
      setState(() {
        _chats = chats;
        _isLoadingChats = false;
      });
    } catch (e) {
      _logger.e('❌ Error loading chats: $e');
      
      // Try to use stale cache on error
      if (!forceRefresh) {
        final staleChats = await _getCachedChats();
        if (staleChats != null && mounted) {
          setState(() {
            _chats = staleChats;
            _isLoadingChats = false;
          });
          return;
        }
      }
      
      setState(() => _isLoadingChats = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to load messages'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _loadChats(forceRefresh: true),
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadFriendRequests({bool forceRefresh = false}) async {
    setState(() => _isLoadingRequests = true);
    
    try {
      _logger.d('👥 Loading friend requests...');
      
      // Try cache first unless force refresh
      if (!forceRefresh) {
        final cachedRequests = await _getCachedFriendRequests();
        
        if (cachedRequests != null) {
          if (mounted) {
            setState(() {
              _friendRequests = cachedRequests;
              _isLoadingRequests = false;
            });
          }
          return;
        }
      }

      // Cache miss or force refresh, fetch from database
      final requests = await FriendsService.getFriendRequests();
      
      // Cache the results
      await _cacheFriendRequests(requests);
      
      _logger.i('✅ Loaded ${requests.length} friend requests');
      
      setState(() {
        _friendRequests = requests;
        _isLoadingRequests = false;
      });
    } catch (e) {
      _logger.e('❌ Error loading friend requests: $e');
      
      // Try to use stale cache on error
      if (!forceRefresh) {
        final staleRequests = await _getCachedFriendRequests();
        if (staleRequests != null && mounted) {
          setState(() {
            _friendRequests = staleRequests;
            _isLoadingRequests = false;
          });
          return;
        }
      }
      
      setState(() => _isLoadingRequests = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to load friend requests'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _loadFriendRequests(forceRefresh: true),
            ),
          ),
        );
      }
    }
  }

  Future<void> _acceptFriendRequest(String requestId) async {
    try {
      _logger.d('✅ Accepting friend request: $requestId');
      await FriendsService.acceptFriendRequest(requestId);
      
      // Invalidate both caches (new friend = new chat possibility)
      await _invalidateRequestsCache();
      await _invalidateChatsCache();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Friend request accepted!'),
          backgroundColor: Colors.orange,
        ),
      );
      
      // Refresh both tabs with force refresh
      _loadData(forceRefresh: true);
    } catch (e) {
      _logger.e('❌ Error accepting request: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error accepting request: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _declineFriendRequest(String requestId) async {
    try {
      _logger.d('❌ Declining friend request: $requestId');
      await FriendsService.declineFriendRequest(requestId);
      
      // Invalidate requests cache
      await _invalidateRequestsCache();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Friend request declined'),
          backgroundColor: Colors.orange,
        ),
      );
      
      // Refresh requests tab with force refresh
      _loadFriendRequests(forceRefresh: true);
    } catch (e) {
      _logger.e('❌ Error declining request: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error declining request: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Invalidate chats cache when returning from chat (new message sent)
  static Future<void> invalidateChatsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_chats');
    } catch (e) {
      print('Error invalidating chats cache: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Messages'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(
              text: 'Chats',
              icon: Icon(Icons.chat),
            ),
            Tab(
              text: 'Requests',
              icon: Stack(
                children: [
                  Icon(Icons.person_add),
                  if (_friendRequests.isNotEmpty)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '${_friendRequests.length}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.person_search),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => SearchUsersPage()),
              );
              if (result == true) {
                // Friend request sent, invalidate requests cache
                await _invalidateRequestsCache();
                _loadFriendRequests(forceRefresh: true);
              }
            },
            tooltip: 'Find Friends',
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () => _loadData(forceRefresh: true),
            tooltip: 'Refresh',
          ),
        ],
      ),
      drawer: AppDrawer(currentPage: 'messages'),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChatsTab(),
          _buildRequestsTab(),
        ],
      ),
    );
  }

  Widget _buildChatsTab() {
    if (_isLoadingChats) {
      return Center(child: CircularProgressIndicator());
    }

    if (_chats.isEmpty) {
      return _buildEmptyChatsState();
    }

    return RefreshIndicator(
      onRefresh: () => _loadChats(forceRefresh: true),
      child: ListView.builder(
        itemCount: _chats.length,
        itemBuilder: (context, index) {
          final chat = _chats[index];
          final friend = chat['friend'];
          final lastMessage = chat['lastMessage'];
          final unreadCount = chat['unreadCount'] ?? 0;
          
          return Card(
            margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: Stack(
                children: [
                  CircleAvatar(
                    backgroundImage: friend['avatar_url'] != null
                        ? NetworkImage(friend['avatar_url'])
                        : null,
                    child: friend['avatar_url'] == null
                        ? Text(
                            (friend['username'] ?? friend['email'] ?? 'U')[0].toUpperCase(),
                            style: TextStyle(fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        constraints: BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          unreadCount > 9 ? '9+' : '$unreadCount',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              title: Text(
                friend['username'] ?? friend['email'] ?? 'Unknown User',
                style: TextStyle(
                  fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.w600,
                ),
              ),
              subtitle: lastMessage != null
                  ? Text(
                      lastMessage['content'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: unreadCount > 0 ? Colors.black : Colors.grey[600],
                        fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
                      ),
                    )
                  : Text(
                      'No messages yet',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (lastMessage != null)
                    Text(
                      _formatMessageTime(lastMessage['created_at']),
                      style: TextStyle(
                        color: unreadCount > 0 ? Colors.blue : Colors.grey[500],
                        fontSize: 12,
                        fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  if (unreadCount > 0)
                    Container(
                      margin: EdgeInsets.only(top: 4),
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        unreadCount > 9 ? '9+' : '$unreadCount',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              onTap: () async {
                // ✅ CRITICAL: Invalidate badge BEFORE opening chat
                await MenuIconWithBadge.invalidateCache();
                
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatPage(
                      friendId: friend['id'],
                      friendName: friend['username'] ?? friend['email'] ?? 'Unknown',
                      friendAvatar: friend['avatar_url'],
                    ),
                  ),
                );
                
                // ✅ CRITICAL: Refresh badge AFTER returning from chat
                await MessagingService.refreshUnreadBadge();
                
                if (result == true) {
                  // Message sent, invalidate cache and reload
                  await _invalidateChatsCache();
                  _loadChats(forceRefresh: true);
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildRequestsTab() {
    if (_isLoadingRequests) {
      return Center(child: CircularProgressIndicator());
    }

    if (_friendRequests.isEmpty) {
      return _buildEmptyRequestsState();
    }

    return RefreshIndicator(
      onRefresh: () => _loadFriendRequests(forceRefresh: true),
      child: ListView.builder(
        itemCount: _friendRequests.length,
        itemBuilder: (context, index) {
          final request = _friendRequests[index];
          final sender = request['sender'];
          
          return Card(
            margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundImage: sender['avatar_url'] != null
                    ? NetworkImage(sender['avatar_url'])
                    : null,
                child: sender['avatar_url'] == null
                    ? Text(
                        (sender['username'] ?? sender['email'] ?? 'U')[0].toUpperCase(),
                        style: TextStyle(fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              title: Text(
                sender['username'] ?? sender['email'] ?? 'Unknown User',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('Wants to be friends'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.check, color: Colors.orange),
                    onPressed: () => _acceptFriendRequest(request['id']),
                    tooltip: 'Accept',
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.red),
                    onPressed: () => _declineFriendRequest(request['id']),
                    tooltip: 'Decline',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyChatsState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 80,
              color: Colors.grey[400],
            ),
            SizedBox(height: 24),
            Text(
              'No conversations yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Add friends and start chatting!\nAll messaging features are completely free.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
                height: 1.4,
              ),
            ),
            SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SearchUsersPage()),
                    );
                    if (result == true) {
                      await _invalidateRequestsCache();
                      _loadData(forceRefresh: true);
                    }
                  },
                  icon: Icon(Icons.person_search),
                  label: Text('Find Friends'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
                SizedBox(width: 12),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'FREE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyRequestsState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_add_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            SizedBox(height: 24),
            Text(
              'No friend requests',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 12),
            Text(
              'When someone sends you a friend request,\nit will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
                height: 1.4,
              ),
            ),
            SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SearchUsersPage()),
                );
                if (result == true) {
                  await _invalidateRequestsCache();
                  _loadFriendRequests(forceRefresh: true);
                }
              },
              icon: Icon(Icons.person_search),
              label: Text('Find Friends to Connect'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatMessageTime(String? timestamp) {
    if (timestamp == null) return '';
    
    try {
      final utcDateTime = DateTime.parse(timestamp);
      final localDateTime = utcDateTime.toLocal();
      
      final now = DateTime.now();
      final difference = now.difference(localDateTime);
      
      if (difference.inDays == 0 && localDateTime.day == now.day) {
        return DateFormat('h:mm a').format(localDateTime);
      }
      else if (difference.inDays == 1 || 
               (localDateTime.day == now.day - 1 && localDateTime.month == now.month)) {
        return 'Yesterday';
      }
      else if (difference.inDays < 7) {
        return DateFormat('EEE').format(localDateTime);
      }
      else if (localDateTime.year == now.year) {
        return DateFormat('MMM d').format(localDateTime);
      }
      else {
        return DateFormat('MMM d, y').format(localDateTime);
      }
    } catch (e) {
      return '';
    }
  }
}