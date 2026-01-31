// lib/pages/badge_debug_page.dart
// Temporary diagnostic page to debug badge issues

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/messaging_service.dart';
import '../services/database_service_core.dart';
import '../widgets/menu_icon_with_badge.dart';
import '../widgets/app_drawer.dart';

class BadgeDebugPage extends StatefulWidget {
  const BadgeDebugPage({super.key});

  @override
  State<BadgeDebugPage> createState() => _BadgeDebugPageState();
}

class _BadgeDebugPageState extends State<BadgeDebugPage> {
  Map<String, dynamic> _diagnostics = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _runDiagnostics();
  }

  Future<void> _runDiagnostics() async {
    setState(() => _isLoading = true);

    final results = <String, dynamic>{};

    try {
      // 1. Check SharedPreferences cache
      final prefs = await SharedPreferences.getInstance();
      results['cached_unread_count'] = prefs.getInt('cached_unread_count');
      results['cached_unread_count_time'] = prefs.getInt('cached_unread_count_time');
      
      if (results['cached_unread_count_time'] != null) {
        final age = DateTime.now().millisecondsSinceEpoch - results['cached_unread_count_time'];
        results['cache_age_seconds'] = (age / 1000).toStringAsFixed(1);
      }

      // 2. Query database directly with boolean false
      final unreadMessages = await DatabaseServiceCore.workerQuery(
        action: 'select',
        table: 'messages',
        columns: ['id', 'sender', 'receiver', 'is_read', 'created_at'],
        filters: {
          'receiver': DatabaseServiceCore.currentUserId,
          'is_read': false,
        },
      );
      
      results['db_unread_count_boolean'] = (unreadMessages as List).length;
      results['db_messages_sample'] = unreadMessages.take(3).toList();

      // 3. Query database with integer 0 (old way)
      try {
        final unreadMessagesInt = await DatabaseServiceCore.workerQuery(
          action: 'select',
          table: 'messages',
          columns: ['id'],
          filters: {
            'receiver': DatabaseServiceCore.currentUserId,
            'is_read': 0,
          },
        );
        results['db_unread_count_integer'] = (unreadMessagesInt as List).length;
      } catch (e) {
        results['db_unread_count_integer'] = 'Error: $e';
      }

      // 4. Get count from service
      final serviceCount = await MessagingService.getUnreadMessageCount();
      results['service_unread_count'] = serviceCount;

      // 5. Check all message-related cache keys
      final allKeys = prefs.getKeys();
      final messageCacheKeys = allKeys.where((key) => 
        key.contains('cache_messages_') || 
        key.contains('cache_last_message_time_') ||
        key.contains('cached_unread_')
      ).toList();
      results['all_message_cache_keys'] = messageCacheKeys;

    } catch (e) {
      results['error'] = e.toString();
    }

    setState(() {
      _diagnostics = results;
      _isLoading = false;
    });
  }

  Future<void> _forceClearAllCaches() async {
    try {
      print('🧹 FORCE CLEARING ALL CACHES...');
      
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys().toList();
      
      for (final key in allKeys) {
        await prefs.remove(key);
        print('🗑️ Removed: $key');
      }
      
      print('✅ ALL CACHES CLEARED');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('All caches cleared! Refreshing...'),
          backgroundColor: Colors.orange,
        ),
      );
      
      // Wait a moment
      await Future.delayed(Duration(milliseconds: 500));
      
      // Force refresh badges
      await MenuIconWithBadge.invalidateCache();
      await AppDrawer.invalidateUnreadCache();
      
      // Refresh diagnostics
      await _runDiagnostics();
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _forceRefreshBadges() async {
    try {
      print('🔄 FORCE REFRESHING BADGES...');
      
      await MessagingService.refreshUnreadBadge();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Badges refreshed!'),
          backgroundColor: Colors.orange,
        ),
      );
      
      await _runDiagnostics();
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Badge Diagnostics'),
        backgroundColor: Colors.orange,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _runDiagnostics,
            tooltip: 'Refresh diagnostics',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection('Cache Status', [
                    _buildRow('Cached count', _diagnostics['cached_unread_count']),
                    _buildRow('Cache timestamp', _diagnostics['cached_unread_count_time']),
                    _buildRow('Cache age', _diagnostics['cache_age_seconds'] != null 
                        ? '${_diagnostics['cache_age_seconds']}s' 
                        : 'N/A'),
                  ]),
                  
                  SizedBox(height: 24),
                  
                  _buildSection('Database Query Results', [
                    _buildRow('DB count (boolean false)', _diagnostics['db_unread_count_boolean'], 
                        color: Colors.orange),
                    _buildRow('DB count (integer 0)', _diagnostics['db_unread_count_integer'], 
                        color: Colors.orange),
                    _buildRow('Service count', _diagnostics['service_unread_count'], 
                        color: Colors.blue),
                  ]),
                  
                  SizedBox(height: 24),
                  
                  _buildSection('Sample Unread Messages', [
                    Text(
                      _diagnostics['db_messages_sample']?.toString() ?? 'None',
                      style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ]),
                  
                  SizedBox(height: 24),
                  
                  _buildSection('All Message Cache Keys', [
                    ...(_diagnostics['all_message_cache_keys'] as List<String>? ?? [])
                        .map((key) => Padding(
                              padding: EdgeInsets.symmetric(vertical: 2),
                              child: Text('• $key', style: TextStyle(fontSize: 12)),
                            )),
                  ]),
                  
                  if (_diagnostics['error'] != null) ...[
                    SizedBox(height: 24),
                    _buildSection('Error', [
                      Text(
                        _diagnostics['error'].toString(),
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ]),
                  ],
                  
                  SizedBox(height: 32),
                  
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _forceRefreshBadges,
                          icon: Icon(Icons.refresh),
                          label: Text('Force Refresh Badges'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _forceClearAllCaches,
                          icon: Icon(Icons.delete_forever),
                          label: Text('Clear ALL Caches'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 16),
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

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildRow(String label, dynamic value, {Color? color}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value?.toString() ?? 'null',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}