// lib/widgets/levi_error_overlay.dart
import 'package:flutter/material.dart';
import 'dart:async';

/// Levi the bari character showing error messages in a cute way
class LeviErrorOverlay extends StatefulWidget {
  final String title;
  final String message;
  final String? helpText;
  final IconData icon;
  final Color color;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;
  final VoidCallback? onNavigate;
  final String? actionButtonText;

  const LeviErrorOverlay({
    super.key,
    required this.title,
    required this.message,
    this.helpText,
    required this.icon,
    required this.color,
    this.onRetry,
    this.onDismiss,
    this.onNavigate,
    this.actionButtonText,
  });

  @override
  State<LeviErrorOverlay> createState() => _LeviErrorOverlayState();
}

class _LeviErrorOverlayState extends State<LeviErrorOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() async {
    await _controller.reverse();
    widget.onDismiss?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: GestureDetector(
        onTap: () {
          // Tapping outside does nothing - must tap button to dismiss
        },
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: GestureDetector(
                onTap: () {}, // Prevent dismissal by tapping the dialog
                child: Container(
                  margin: const EdgeInsets.all(32),
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Levi character
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/levibari.jpeg',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.favorite,
                                size: 60,
                                color: Colors.red.shade300,
                              );
                            },
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Speech bubble
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Icon
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: widget.color.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                widget.icon,
                                color: widget.color,
                                size: 32,
                              ),
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Title
                            Text(
                              widget.title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            
                            const SizedBox(height: 12),
                            
                            // Message
                            Text(
                              widget.message,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.grey.shade700,
                                height: 1.4,
                              ),
                            ),
                            
                            // Help text
                            if (widget.helpText != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: widget.color.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: widget.color.withOpacity(0.2),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.lightbulb_outline,
                                      size: 18,
                                      color: widget.color,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        widget.helpText!,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            
                            const SizedBox(height: 20),
                            
                            // Buttons
                            Row(
                              children: [
                                if (widget.onRetry != null || widget.onNavigate != null) ...[
                                  Expanded(
                                    child: TextButton(
                                      onPressed: _dismiss,
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                      child: Text(
                                        'Not now',
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () {
                                      _dismiss();
                                      if (widget.onRetry != null) {
                                        widget.onRetry!();
                                      } else if (widget.onNavigate != null) {
                                        widget.onNavigate!();
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: widget.color,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: Text(
                                      widget.actionButtonText ?? 
                                        (widget.onRetry != null ? 'Try again!' : 'Got it!'),
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}