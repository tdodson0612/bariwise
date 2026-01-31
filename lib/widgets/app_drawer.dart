// lib/widgets/app_drawer.dart - FIXED: Removed duplicate Premium sections and debug button

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bari_wise/services/messaging_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../controllers/premium_gate_controller.dart';
import '../services/auth_service.dart';
import '../services/database_service_core.dart';

class AppDrawer extends StatefulWidget {
  final String currentPage;
  
  const AppDrawer({
    super.key,
    required this.currentPage,
  });

  @override
  State<AppDrawer> createState() => _AppDrawerState();
  
  static const String _cacheKey = 'cached_unread_count';
  static const String _cacheTimeKey = 'cached_unread_count_time';
  
  static final GlobalKey<_AppDrawerState> globalKey = GlobalKey<_AppDrawerState>();
  
  static Future<void> invalidateUnreadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheTimeKey);
      
      print('🔄 AppDrawer cache invalidated');
      
      await globalKey.currentState?.refresh();
    } catch (e) {
      print('⚠️ Error invalidating AppDrawer cache: $e');
    }
  }
}

class _AppDrawerState extends State<AppDrawer> with WidgetsBindingObserver {
  late final PremiumGateController _controller;
  int _unreadCount = 0;
  Timer? _autoRefreshTimer;

  static const Duration _cacheDuration = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _controller = PremiumGateController();
    _controller.addListener(_onPremiumStateChanged);
    
    WidgetsBinding.instance.addObserver(this);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUnreadCount(forceRefresh: true);
    });
    
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) {
        if (mounted) {
          print('⏰ AppDrawer auto-refresh triggered');
          _loadUnreadCount(forceRefresh: true);
        }
      },
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _controller.removeListener(_onPremiumStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print('📱 App resumed, refreshing AppDrawer badge...');
      _loadUnreadCount(forceRefresh: true);
    }
  }

  void _onPremiumStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> refresh() async {
    await _loadUnreadCount(forceRefresh: true);
  }

  Future<void> _loadUnreadCount({bool forceRefresh = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (!forceRefresh) {
        final cachedCount = prefs.getInt(AppDrawer._cacheKey);
        final cachedTime = prefs.getInt(AppDrawer._cacheTimeKey);
        
        if (cachedCount != null && cachedTime != null) {
          final cacheAge = DateTime.now().millisecondsSinceEpoch - cachedTime;
          final isCacheValid = cacheAge < _cacheDuration.inMilliseconds;
          
          if (isCacheValid) {
            if (mounted) {
              setState(() => _unreadCount = cachedCount);
            }
            print('✅ AppDrawer: Using valid cache: $cachedCount (${(cacheAge / 1000).toStringAsFixed(1)}s old)');
            return;
          } else {
            print('⏰ AppDrawer: Cache STALE (${(cacheAge / 1000).toStringAsFixed(1)}s old) - refreshing...');
          }
        } else {
          print('❌ AppDrawer: No cache found - fetching fresh...');
        }
      } else {
        print('🔄 AppDrawer: Force refresh requested');
      }
      
      print('📡 AppDrawer: Fetching from MessagingService.getUnreadMessageCount()...');
      final count = await MessagingService.getUnreadMessageCount();
      
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(AppDrawer._cacheKey, count);
      await prefs.setInt(AppDrawer._cacheTimeKey, now);
      
      if (mounted) {
        setState(() => _unreadCount = count);
      }
      
      print('✅ AppDrawer: Fresh count = $count (cached at $now)');
      
    } catch (e) {
      print('❌ AppDrawer: Error loading unread count: $e');
      
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedCount = prefs.getInt(AppDrawer._cacheKey);
        if (cachedCount != null && mounted) {
          setState(() => _unreadCount = cachedCount);
          print('⚠️ AppDrawer: Using stale cache due to error: $cachedCount');
        } else {
          if (mounted) {
            setState(() => _unreadCount = 0);
          }
        }
      } catch (_) {
        if (mounted) {
          setState(() => _unreadCount = 0);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = AuthService.currentUser?.email;

    return Drawer(
      child: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.orange, Colors.orange.shade700],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'bari Food Scanner',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  
                  if (userEmail != null) ...[
                    Text(
                      userEmail,
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    SizedBox(height: 8),
                  ],
                  
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _controller.isPremium ? Colors.amber : Colors.grey,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _controller.isPremium ? Icons.star : Icons.person,
                          color: Colors.white,
                          size: 16,
                        ),
                        SizedBox(width: 4),
                        Text(
                          _controller.isPremium ? 'Premium' : 'Free Account',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  if (!_controller.isPremium) ...[
                    SizedBox(height: 4),
                    Text(
                      'Scans used: ${_controller.totalScansUsed}/3',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            
            ListTile(
              leading: Icon(
                Icons.home,
                color: widget.currentPage == 'home' ? Colors.orange : null,
              ),
              title: Text(
                'Home',
                style: TextStyle(
                  fontWeight: widget.currentPage == 'home' ? FontWeight.bold : FontWeight.normal,
                  color: widget.currentPage == 'home' ? Colors.orange : null,
                ),
              ),
              selected: widget.currentPage == 'home',
              onTap: () {
                Navigator.pop(context);
                if (widget.currentPage != 'home') {
                  Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
                }
              },
            ),
            
            ListTile(
              leading: Icon(
                Icons.person,
                color: widget.currentPage == 'profile' ? Colors.orange : null,
              ),
              title: Text(
                'Profile',
                style: TextStyle(
                  fontWeight: widget.currentPage == 'profile' ? FontWeight.bold : FontWeight.normal,
                  color: widget.currentPage == 'profile' ? Colors.orange : null,
                ),
              ),
              selected: widget.currentPage == 'profile',
              onTap: () {
                Navigator.pop(context);
                if (widget.currentPage != 'profile') {
                  Navigator.pushNamed(context, '/profile');
                }
              },
            ),
            
            ListTile(
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    Icons.chat,
                    color: widget.currentPage == 'messages' ? Colors.orange : null,
                  ),
                  if (_unreadCount > 0)
                    Positioned(
                      right: -8,
                      top: -4,
                      child: Container(
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          _unreadCount > 99 ? '99+' : '$_unreadCount',
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
                'Messages',
                style: TextStyle(
                  fontWeight: widget.currentPage == 'messages' ? FontWeight.bold : FontWeight.normal,
                  color: widget.currentPage == 'messages' ? Colors.orange : null,
                ),
              ),
              trailing: _unreadCount > 0
                  ? Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _unreadCount > 99 ? '99+' : '$_unreadCount',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : null,
              selected: widget.currentPage == 'messages',
              onTap: () async {
                Navigator.pop(context);
                
                if (widget.currentPage != 'messages') {
                  await Navigator.pushNamed(context, '/messages');
                  
                  print('🔄 User returned from messages, refreshing badges...');
                  
                  await Future.delayed(Duration(milliseconds: 800));
                  
                  await MessagingService.refreshUnreadBadge();
                  
                  if (mounted) {
                    await _loadUnreadCount(forceRefresh: true);
                  }
                  
                  print('✅ Badge refresh complete');
                }
              },
            ),
            
            ListTile(
              leading: Icon(
                Icons.bookmark,
                color: widget.currentPage == 'saved_posts' ? Colors.orange : null,
              ),
              title: Text(
                'Saved Posts',
                style: TextStyle(
                  fontWeight: widget.currentPage == 'saved_posts' ? FontWeight.bold : FontWeight.normal,
                  color: widget.currentPage == 'saved_posts' ? Colors.orange : null,
                ),
              ),
              selected: widget.currentPage == 'saved_posts',
              onTap: () {
                Navigator.pop(context);
                if (widget.currentPage != 'saved_posts') {
                  Navigator.pushNamed(context, '/saved-posts');
                }
              },
            ),

            ListTile(
              leading: Icon(
                Icons.person_search,
                color: widget.currentPage == 'find_friends' ? Colors.orange : null,
              ),
              title: Text(
                'Find Friends',
                style: TextStyle(
                  fontWeight: widget.currentPage == 'find_friends' ? FontWeight.bold : FontWeight.normal,
                  color: widget.currentPage == 'find_friends' ? Colors.orange : null,
                ),
              ),
              selected: widget.currentPage == 'find_friends',
              onTap: () {
                Navigator.pop(context);
                if (widget.currentPage != 'find_friends') {
                  Navigator.pushNamed(context, '/search-users');
                }
              },
            ),
            
            if (_controller.isPremium) ...[
              ListTile(
                leading: Icon(
                  Icons.favorite,
                  color: widget.currentPage == 'favorite_recipes' ? Colors.orange : null,
                ),
                title: Text(
                  'Favorite Recipes',
                  style: TextStyle(
                    fontWeight: widget.currentPage == 'favorite_recipes' ? FontWeight.bold : FontWeight.normal,
                    color: widget.currentPage == 'favorite_recipes' ? Colors.orange : null,
                  ),
                ),
                selected: widget.currentPage == 'favorite_recipes',
                onTap: () {
                  Navigator.pop(context);
                  if (widget.currentPage != 'favorite_recipes') {
                    Navigator.pushNamed(context, '/favorite-recipes');
                  }
                },
              ),
              
              ListTile(
                leading: const Icon(Icons.book),
                title: const Text('My Cookbook'),
                onTap: () {
                  Navigator.pushNamed(context, '/my-cookbook');
                },
              ),

              ListTile(
                leading: Icon(Icons.shopping_cart),
                title: Text('My Grocery List'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/grocery-list');
                },
              ),

              ListTile(
                leading: Icon(Icons.bookmark, color: Colors.orange),
                title: Text("Saved Ingredients"),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/saved-ingredients');
                },
              ),
              
              ListTile(
                leading: Icon(Icons.add_circle),
                title: Text('Submit Recipe'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/submit-recipe');
                },
              ),
            ] else ...[
              ListTile(
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite, color: Colors.grey),
                    SizedBox(width: 4),
                    Icon(Icons.lock, color: Colors.red, size: 16),
                  ],
                ),
                title: Row(
                  children: [
                    Text('Favorite Recipes', style: TextStyle(color: Colors.grey)),
                    SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'PREMIUM',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/purchase');
                },
              ),
              
              ListTile(
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shopping_cart, color: Colors.grey),
                    SizedBox(width: 4),
                    Icon(Icons.lock, color: Colors.red, size: 16),
                  ],
                ),
                title: Row(
                  children: [
                    Text('Grocery List', style: TextStyle(color: Colors.grey)),
                    SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'PREMIUM',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/purchase');
                },
              ),
              
              ListTile(
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_circle, color: Colors.grey),
                    SizedBox(width: 4),
                    Icon(Icons.lock, color: Colors.red, size: 16),
                  ],
                ),
                title: Row(
                  children: [
                    Text('Submit Recipe', style: TextStyle(color: Colors.grey)),
                    SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'PREMIUM',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/purchase');
                },
              ),
            ],
            
            Divider(),
            
            ListTile(
              leading: Icon(
                Icons.contact_mail,
                color: widget.currentPage == 'contact' ? Colors.orange : null,
              ),
              title: Text(
                'Contact Us',
                style: TextStyle(
                  fontWeight: widget.currentPage == 'contact' ? FontWeight.bold : FontWeight.normal,
                  color: widget.currentPage == 'contact' ? Colors.orange : null,
                ),
              ),
              selected: widget.currentPage == 'contact',
              onTap: () {
                Navigator.pop(context);
                if (widget.currentPage != 'contact') {
                  Navigator.pushNamed(context, '/contact');
                }
              },
            ),
            
            ListTile(
              leading: Icon(
                Icons.star,
                color: _controller.isPremium ? Colors.amber : Colors.grey,
              ),
              title: Text(
                _controller.isPremium ? 'Premium Active' : 'Upgrade to Premium',
                style: TextStyle(
                  color: _controller.isPremium ? Colors.amber : null,
                  fontWeight: _controller.isPremium ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              trailing: _controller.isPremium 
                  ? Icon(Icons.check_circle, color: Colors.orange)
                  : Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/purchase');
              },
            ),
            
            Divider(),
            
            ListTile(
              leading: Icon(Icons.logout, color: Colors.red),
              title: Text(
                'Sign Out',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () => _showSignOutDialog(context),
            ),
            
            SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showSignOutDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: Text('Sign Out'),
        content: Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _performLogout(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  Future<void> _performLogout(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (loadingContext) => WillPopScope(
        onWillPop: () async => false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Signing out...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_route');
      await AuthService.signOut();
      await prefs.clear();
      await DatabaseServiceCore.clearAllUserCache();
      
      if (context.mounted) {
        Navigator.of(context).pop();
      }
      
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      print('Error during logout: $e');
      
      if (context.mounted) {
        Navigator.of(context).pop();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error signing out. Please try again.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }
}