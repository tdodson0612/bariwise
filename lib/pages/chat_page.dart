// lib/pages/chat_page.dart - FIXED: Badge in AppBar + proper drawer
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../widgets/menu_icon_with_badge.dart';
import '../widgets/app_drawer.dart';

import '../services/auth_service.dart';
import '../services/error_handling_service.dart';
import '../services/messaging_service.dart';


class ChatPage extends StatefulWidget {
  final String friendId;
  final String friendName;
  final String? friendAvatar;

  const ChatPage({
    super.key,
    required this.friendId,
    required this.friendName,
    this.friendAvatar,
  });

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;

  String get _cacheKey => 'messages_${AuthService.currentUserId}_${widget.friendId}';

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  // ✅ NEW: Clear iOS badge using native platform channel
  static const platform = MethodChannel('com.bariwise/badge');
  
  Future<void> _clearIOSBadge() async {
    try {
      await platform.invokeMethod('clearBadge');
      print('✅ iOS badge cleared');
    } catch (e) {
      print('⚠️ Error clearing iOS badge: $e');
    }
  }

  // ✅ FIXED: Proper initialization with delayed badge refresh + iOS badge clearing
  Future<void> _initializeChat() async {
    // Load messages first
    await _loadMessages();
    
    // Mark messages as read AFTER messages are loaded
    await _markMessagesAsRead();
    
    // ✅ NEW: Clear iOS badge
    await _clearIOSBadge();
    
    // ✅ CRITICAL FIX: Wait for database to commit, then force refresh
    await Future.delayed(Duration(milliseconds: 500));
    await _refreshBadgeAfterRead();
  }

  // ✅ NEW: Dedicated method for badge refresh after marking as read
  Future<void> _refreshBadgeAfterRead() async {
    try {
      // Force invalidate cache
      await MenuIconWithBadge.invalidateCache();
      await AppDrawer.invalidateUnreadCache();
      
      // Force the badge widget to reload with fresh data
      MenuIconWithBadge.globalKey.currentState?.refresh();
      
      print('✅ Badge refreshed after marking messages as read');
    } catch (e) {
      print('⚠️ Error refreshing badge: $e');
    }
  }

  Future<void> _markMessagesAsRead() async {
    try {
      // Mark messages as read in database
      await MessagingService.markMessagesAsReadFrom(widget.friendId);
      print('✅ Messages marked as read for friend: ${widget.friendId}');
    } catch (e) {
      print('⚠️ Error marking messages as read: $e');
    }
  }

  @override
  void dispose() {
    // ✅ FIXED: Final refresh when leaving chat with proper async handling
    _performFinalCleanup();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ✅ NEW: Async cleanup that doesn't block dispose
  void _performFinalCleanup() {
    Future.microtask(() async {
      try {
        await MenuIconWithBadge.invalidateCache();
        await AppDrawer.invalidateUnreadCache();
        
        // Force refresh the badge widget
        MenuIconWithBadge.globalKey.currentState?.refresh();
        
        print('✅ Final cleanup completed');
      } catch (e) {
        print('⚠️ Error in final cleanup: $e');
      }
    });
  }

  Future<void> _loadMessages() async {
    try {
      setState(() => _isLoading = true);
      
      // Load from cache immediately
      final cachedMessages = await _loadMessagesFromCache();
      if (cachedMessages.isNotEmpty && mounted) {
        setState(() {
          _messages = cachedMessages;
          _isLoading = false;
        });
        _scrollToBottom();
      }
      
      // Fetch from server
      final serverMessages = await MessagingService.getMessages(widget.friendId);
      
      if (mounted) {
        serverMessages.sort((a, b) {
          try {
            final timeA = DateTime.parse(a['created_at'] ?? '');
            final timeB = DateTime.parse(b['created_at'] ?? '');
            return timeA.compareTo(timeB);
          } catch (e) {
            return 0;
          }
        });
        
        await _saveMessagesToCache(serverMessages);
        
        setState(() {
          _messages = serverMessages;
          _isLoading = false;
        });
        
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        
        if (_messages.isEmpty) {
          await ErrorHandlingService.handleError(
            context: context,
            error: e,
            category: ErrorHandlingService.databaseError,
            showSnackBar: true,
            customMessage: 'Unable to load messages',
            onRetry: _loadMessages,
          );
        } else {
          print('Failed to refresh messages from server, using cache: $e');
        }
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadMessagesFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_cacheKey);
      
      if (cachedJson != null) {
        final List<dynamic> decoded = json.decode(cachedJson);
        return decoded.map((item) => Map<String, dynamic>.from(item)).toList();
      }
    } catch (e) {
      print('Error loading messages from cache: $e');
    }
    return [];
  }

  Future<void> _saveMessagesToCache(List<Map<String, dynamic>> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = json.encode(messages);
      await prefs.setString(_cacheKey, jsonString);
    } catch (e) {
      print('Error saving messages to cache: $e');
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending) return;

    final tempMessage = {
      'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
      'sender': AuthService.currentUserId,
      'receiver': widget.friendId,
      'content': content,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'is_temp': true,
    };

    setState(() {
      _isSending = true;
      _messages.add(tempMessage);
    });

    _messageController.clear();
    _scrollToBottom();

    await _saveMessagesToCache(_messages);

    try {
      await MessagingService.sendMessage(widget.friendId, content);
      
      // ✅ FIXED: Proper badge refresh after sending
      await Future.delayed(Duration(milliseconds: 300));
      await MenuIconWithBadge.invalidateCache();
      await AppDrawer.invalidateUnreadCache();
      MenuIconWithBadge.globalKey.currentState?.refresh();
      
      if (mounted) {
        await _loadMessages();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.removeWhere((msg) => msg['is_temp'] == true);
        });
        
        await _saveMessagesToCache(_messages);
        _messageController.text = content;
        
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Failed to send message',
          onRetry: _sendMessage,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatMessageTime(String timestamp) {
    try {
      final utcDateTime = DateTime.parse(timestamp).toUtc();
      final localDateTime = utcDateTime.toLocal();
      final now = DateTime.now();
      final difference = now.difference(localDateTime);

      if (difference.inDays == 0 && localDateTime.day == now.day) {
        return DateFormat('h:mm a').format(localDateTime);
      }
      else if (difference.inDays == 1 || 
              (localDateTime.day == now.day - 1 && localDateTime.month == now.month)) {
        return 'Yesterday ${DateFormat('h:mm a').format(localDateTime)}';
      }
      else if (difference.inDays < 7) {
        return DateFormat('EEE h:mm a').format(localDateTime);
      }
      else if (localDateTime.year == now.year) {
        return DateFormat('MMM d, h:mm a').format(localDateTime);
      }
      else {
        return DateFormat('MMM d, y').format(localDateTime);
      }
    } catch (e) {
      print('Error formatting time: $e');
      return '';
    }
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final isMe = message['sender'] == AuthService.currentUserId;
    final isTemp = message['is_temp'] == true;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20).copyWith(
            bottomRight: isMe ? Radius.circular(4) : Radius.circular(20),
            bottomLeft: isMe ? Radius.circular(20) : Radius.circular(4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message['content'] ?? '',
              style: TextStyle(
                color: isMe ? Colors.white : Colors.black,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatMessageTime(message['created_at'] ?? ''),
                  style: TextStyle(
                    color: isMe ? Colors.white70 : Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
                if (isMe && isTemp) ...[
                  SizedBox(width: 4),
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _sendMessage(),
                enabled: !_isSending,
              ),
            ),
            SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: _isSending ? Colors.grey : Colors.blue,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: _isSending ? null : _sendMessage,
                icon: _isSending
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Icon(Icons.send, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // ✅ FIXED: Proper async handling when leaving chat + clear iOS badge
        await _clearIOSBadge();
        await MenuIconWithBadge.invalidateCache();
        await AppDrawer.invalidateUnreadCache();
        
        // Force refresh the badge widget
        await Future.delayed(Duration(milliseconds: 200));
        MenuIconWithBadge.globalKey.currentState?.refresh();
        
        print('✅ Leaving chat, badge refreshed and iOS badge cleared');
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          // ✅ CRITICAL FIX: Add badge to AppBar leading
          leading: Builder(
            builder: (context) => IconButton(
              icon: MenuIconWithBadge(key: MenuIconWithBadge.globalKey),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          title: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: widget.friendAvatar != null
                    ? NetworkImage(widget.friendAvatar!)
                    : null,
                child: widget.friendAvatar == null
                    ? Text(
                        widget.friendName.isNotEmpty
                            ? widget.friendName[0].toUpperCase()
                            : 'U',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.friendName,
                  style: TextStyle(fontSize: 18),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 1,
          actions: [
            IconButton(
              onPressed: () async {
                try {
                  await _loadMessages();
                  if (mounted) {
                    ErrorHandlingService.showSuccess(context, 'Messages refreshed');
                  }
                } catch (e) {
                  if (mounted) {
                    await ErrorHandlingService.handleError(
                      context: context,
                      error: e,
                      category: ErrorHandlingService.databaseError,
                      showSnackBar: true,
                      customMessage: 'Failed to refresh messages',
                    );
                  }
                }
              },
              icon: Icon(Icons.refresh),
              tooltip: 'Refresh messages',
            ),
          ],
        ),
        // ✅ CRITICAL FIX: Add drawer
        drawer: AppDrawer(currentPage: 'messages'),
        body: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            'Loading messages...',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    )
                  : _messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'No messages yet',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Send a message to start the conversation!',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadMessages,
                          child: ListView.builder(
                            controller: _scrollController,
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              return _buildMessageBubble(_messages[index]);
                            },
                          ),
                        ),
            ),
            _buildMessageInput(),
          ],
        ),
      ),
    );
  }
}

// ✅ COMPLETE - All badge clearing functionality added!