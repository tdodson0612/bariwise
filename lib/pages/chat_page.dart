// lib/pages/chat_page.dart
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
import '../services/sound_service.dart';

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

  String get _cacheKey =>
      'messages_${AuthService.currentUserId}_${widget.friendId}';

  // ✅ Clear iOS badge using native platform channel
  static const platform = MethodChannel('com.bariwise/badge');

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  @override
  void dispose() {
    // ✅ FIXED: Final refresh when leaving chat with proper async handling
    _performFinalCleanup();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> _initializeChat() async {
    // Load messages first
    await _loadMessages();

    // Mark messages as read AFTER messages are loaded
    await _markMessagesAsRead();

    // Clear iOS badge
    await _clearIOSBadge();

    // ✅ CRITICAL FIX: Wait for database to commit, then force refresh
    await Future.delayed(const Duration(milliseconds: 500));
    await _refreshBadgeAfterRead();
  }

  // ── Badge helpers ─────────────────────────────────────────────────────────

  Future<void> _clearIOSBadge() async {
    try {
      await platform.invokeMethod('clearBadge');

    // ignore: empty_catches
    } catch (e) {

    }
  }

  Future<void> _refreshBadgeAfterRead() async {
    try {
      await MenuIconWithBadge.invalidateCache();
      await AppDrawer.invalidateUnreadCache();
      MenuIconWithBadge.globalKey.currentState?.refresh();

    // ignore: empty_catches
    } catch (e) {

    }
  }

  void _performFinalCleanup() {
    Future.microtask(() async {
      try {
        await MenuIconWithBadge.invalidateCache();
        await AppDrawer.invalidateUnreadCache();
        MenuIconWithBadge.globalKey.currentState?.refresh();

      // ignore: empty_catches
      } catch (e) {

      }
    });
  }

  Future<void> _markMessagesAsRead() async {
    try {
      await MessagingService.markMessagesAsReadFrom(widget.friendId);

    // ignore: empty_catches
    } catch (e) {

    }
  }

  // ── Message loading ───────────────────────────────────────────────────────

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
      final serverMessages =
          await MessagingService.getMessages(widget.friendId);

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

        // 🔔 Play chime if new incoming messages arrived since last load
        final currentUserId = AuthService.currentUserId;
        final previousIds = _messages.map((m) => m['id']).toSet();
        final hasNewIncoming = serverMessages.any((m) =>
            !previousIds.contains(m['id']) &&
            m['sender'] == widget.friendId &&
            m['sender'] != currentUserId);

        if (hasNewIncoming) {
          await SoundService.playMessageChime();
        }

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
        return decoded
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
    // ignore: empty_catches
    } catch (e) {

    }
    return [];
  }

  Future<void> _saveMessagesToCache(
      List<Map<String, dynamic>> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = json.encode(messages);
      await prefs.setString(_cacheKey, jsonString);
    // ignore: empty_catches
    } catch (e) {

    }
  }

  // ── Send ──────────────────────────────────────────────────────────────────

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
      await Future.delayed(const Duration(milliseconds: 300));
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

  // ── Scroll ────────────────────────────────────────────────────────────────

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Formatting ────────────────────────────────────────────────────────────

  String _formatMessageTime(String timestamp) {
    try {
      final utcDateTime = DateTime.parse(timestamp).toUtc();
      final localDateTime = utcDateTime.toLocal();
      final now = DateTime.now();
      final difference = now.difference(localDateTime);

      if (difference.inDays == 0 && localDateTime.day == now.day) {
        return DateFormat('h:mm a').format(localDateTime);
      } else if (difference.inDays == 1 ||
          (localDateTime.day == now.day - 1 &&
              localDateTime.month == now.month)) {
        return 'Yesterday ${DateFormat('h:mm a').format(localDateTime)}';
      } else if (difference.inDays < 7) {
        return DateFormat('EEE h:mm a').format(localDateTime);
      } else if (localDateTime.year == now.year) {
        return DateFormat('MMM d, h:mm a').format(localDateTime);
      } else {
        return DateFormat('MMM d, y').format(localDateTime);
      }
    } catch (e) {

      return '';
    }
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final isMe = message['sender'] == AuthService.currentUserId;
    final isTemp = message['is_temp'] == true;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20).copyWith(
            bottomRight:
                isMe ? const Radius.circular(4) : const Radius.circular(20),
            bottomLeft:
                isMe ? const Radius.circular(20) : const Radius.circular(4),
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
            const SizedBox(height: 4),
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
                  const SizedBox(width: 4),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white70),
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
      padding: const EdgeInsets.all(16),
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
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                ),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _sendMessage(),
                enabled: !_isSending,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: _isSending ? Colors.grey : Colors.blue,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: _isSending ? null : _sendMessage,
                icon: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.send, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // ignore: deprecated_member_use
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) async {
        if (didPop) {
          await _clearIOSBadge();
          await MenuIconWithBadge.invalidateCache();
          await AppDrawer.invalidateUnreadCache();
          await Future.delayed(const Duration(milliseconds: 200));
          MenuIconWithBadge.globalKey.currentState?.refresh();
        }
      },
      child: Scaffold(
        appBar: AppBar(
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
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.friendName,
                  style: const TextStyle(fontSize: 18),
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
                    ErrorHandlingService.showSuccess(
                        context, 'Messages refreshed');
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
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh messages',
            ),
          ],
        ),
        drawer: const AppDrawer(currentPage: 'messages'),
        body: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            'Loading messages...',
                            style:
                                TextStyle(color: Colors.grey.shade600),
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
                              const SizedBox(height: 16),
                              Text(
                                'No messages yet',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
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
                              return _buildMessageBubble(
                                  _messages[index]);
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