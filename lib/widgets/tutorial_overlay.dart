// tutorial_overlay.dart
import 'package:flutter/material.dart';

enum TutorialStep {
  TUTORIAL_INTRO,
  TUTORIAL_ALL_BUTTONS, // NEW: Show all 4 buttons together
  TUTORIAL_AUTO,
  TUTORIAL_SCAN,
  TUTORIAL_MANUAL,
  TUTORIAL_LOOKUP,
  TUTORIAL_UNIFIED_RESULT,
  TUTORIAL_CLOSE,
}

class TutorialOverlay extends StatefulWidget {
  final VoidCallback onComplete;
  final GlobalKey autoButtonKey;
  final GlobalKey scanButtonKey;
  final GlobalKey manualButtonKey;
  final GlobalKey lookupButtonKey;

  const TutorialOverlay({
    Key? key,
    required this.onComplete,
    required this.autoButtonKey,
    required this.scanButtonKey,
    required this.manualButtonKey,
    required this.lookupButtonKey,
  }) : super(key: key);

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  TutorialStep _currentStep = TutorialStep.TUTORIAL_INTRO;
  late AnimationController _leviController;
  late Animation<Offset> _leviSlideAnimation;
  
  bool _showHighlight = false;
  GlobalKey? _currentHighlightKey;
  double _leviOffset = 0.0;
  
  // NEW: For highlighting all buttons together
  bool _highlightAllButtons = false;
  
  @override
  void initState() {
    super.initState();
    
    _leviController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    _leviSlideAnimation = Tween<Offset>(
      begin: const Offset(1.5, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _leviController,
      curve: Curves.easeOut,
    ));
    
    _leviController.forward();
  }
  
  @override
  void dispose() {
    _leviController.dispose();
    super.dispose();
  }
  
  void _nextStep() {
    print('🎓 _nextStep called - current: $_currentStep');
    _playLeviHop();
    setState(() {
      switch (_currentStep) {
        case TutorialStep.TUTORIAL_INTRO:
          print('🎓 Moving to ALL_BUTTONS step');
          _currentStep = TutorialStep.TUTORIAL_ALL_BUTTONS;
          _highlightAllButtons = true;
          _showHighlight = false;
          _currentHighlightKey = null;
          break;
        case TutorialStep.TUTORIAL_ALL_BUTTONS:
          print('🎓 Moving to AUTO step');
          _currentStep = TutorialStep.TUTORIAL_AUTO;
          _highlightAllButtons = false;
          _updateHighlight(widget.autoButtonKey);
          break;
        case TutorialStep.TUTORIAL_AUTO:
          print('🎓 Moving to SCAN step');
          _currentStep = TutorialStep.TUTORIAL_SCAN;
          _updateHighlight(widget.scanButtonKey);
          break;
        case TutorialStep.TUTORIAL_SCAN:
          print('🎓 Moving to MANUAL step');
          _currentStep = TutorialStep.TUTORIAL_MANUAL;
          _updateHighlight(widget.manualButtonKey);
          break;
        case TutorialStep.TUTORIAL_MANUAL:
          print('🎓 Moving to LOOKUP step');
          _currentStep = TutorialStep.TUTORIAL_LOOKUP;
          _updateHighlight(widget.lookupButtonKey);
          break;
        case TutorialStep.TUTORIAL_LOOKUP:
          print('🎓 Moving to UNIFIED_RESULT step');
          _currentStep = TutorialStep.TUTORIAL_UNIFIED_RESULT;
          _removeHighlight();
          break;
        case TutorialStep.TUTORIAL_UNIFIED_RESULT:
          print('🎓 Moving to CLOSE step');
          _currentStep = TutorialStep.TUTORIAL_CLOSE;
          break;
        case TutorialStep.TUTORIAL_CLOSE:
          print('🎓 Tutorial complete, calling onComplete');
          widget.onComplete();
          break;
      }
    });
  }

  void _playLeviHop() async {
    if (!mounted) return;
    
    for (int i = 0; i < 3; i++) {
      setState(() => _leviOffset = -20.0);
      await Future.delayed(Duration(milliseconds: 150));
      setState(() => _leviOffset = 0.0);
      await Future.delayed(Duration(milliseconds: 150));
    }
  }
  
  void _updateHighlight(GlobalKey newKey) async {
    print('🎯 Updating highlight to new key');
    
    // Fade out previous highlight
    setState(() {
      _showHighlight = false;
      _highlightAllButtons = false; // Also turn off all-buttons highlight
    });
    await Future.delayed(const Duration(milliseconds: 200));
    
    // Wait for layout to complete
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Fade in new highlight
    if (mounted) {
      setState(() {
        _currentHighlightKey = newKey;
        _showHighlight = true;
      });
      
      // Debug: Check if the key has a valid context
      final context = newKey.currentContext;
      if (context == null) {
        print('⚠️ WARNING: New highlight key has no context yet');
      } else {
        final renderBox = context.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          print('✅ Highlight updated - size: ${renderBox.size}');
        }
      }
    }
  }
  
  void _removeHighlight() async {
    setState(() {
      _showHighlight = false;
      _highlightAllButtons = false;
    });
    await Future.delayed(const Duration(milliseconds: 100));
    setState(() => _currentHighlightKey = null);
  }
  
  String _getTalkBubbleText() {
    switch (_currentStep) {
      case TutorialStep.TUTORIAL_INTRO:
        return "Hi there, friend. I am Barry, the belly. Let me walk you through this app and the way we use it to enrich our health and our lives.";
      case TutorialStep.TUTORIAL_ALL_BUTTONS:
        return "These buttons are the 4 different ways you can see the nutrition facts and suggested bariatric friendly recipes for any food you like! Let's walk through them together!";
      case TutorialStep.TUTORIAL_AUTO:
        return "Let's start with Auto. It works fast - just point your camera at the barcode, and it recognizes it automatically.";
      case TutorialStep.TUTORIAL_SCAN:
        return "This is Scan. Tap this when you want to scan a barcode yourself. You'll take a picture, tap Analyze, and we'll show you the nutrition facts and helpful recipe ideas.";
      case TutorialStep.TUTORIAL_MANUAL:
        return "Use Code when a barcode won't scan or is damaged. You can type in the numbers from the bottom of the barcode instead.";
      case TutorialStep.TUTORIAL_LOOKUP:
        return "And this is Search. Tap here to search by name if you don't have a barcode at all.";
      case TutorialStep.TUTORIAL_UNIFIED_RESULT:
        return "No matter which option you choose, you'll see nutrition facts and recipe suggestions for that item. Pick what works best for you.";
      case TutorialStep.TUTORIAL_CLOSE:
        return "That's it! I'll be here if you need help. Let's take care of your health together.";
    }
  }
  
  // NEW: Build highlight for all 4 buttons together
  Widget _buildAllButtonsHighlight() {
    if (!_highlightAllButtons) {
      return const SizedBox.shrink();
    }

    // Get positions of all 4 buttons
    final autoBox = widget.autoButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final scanBox = widget.scanButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final manualBox = widget.manualButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final lookupBox = widget.lookupButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox = context.findRenderObject() as RenderBox?;

    if (autoBox == null || scanBox == null || manualBox == null || lookupBox == null || overlayBox == null) {
      return const SizedBox.shrink();
    }

    // Get global positions
    final autoPos = overlayBox.globalToLocal(autoBox.localToGlobal(Offset.zero));
    final scanPos = overlayBox.globalToLocal(scanBox.localToGlobal(Offset.zero));
    final manualPos = overlayBox.globalToLocal(manualBox.localToGlobal(Offset.zero));
    final lookupPos = overlayBox.globalToLocal(lookupBox.localToGlobal(Offset.zero));

    // Calculate bounding box that contains all 4 buttons
    final left = [autoPos.dx, scanPos.dx, manualPos.dx, lookupPos.dx].reduce((a, b) => a < b ? a : b);
    final top = [autoPos.dy, scanPos.dy, manualPos.dy, lookupPos.dy].reduce((a, b) => a < b ? a : b);
    final right = [
      autoPos.dx + autoBox.size.width,
      scanPos.dx + scanBox.size.width,
      manualPos.dx + manualBox.size.width,
      lookupPos.dx + lookupBox.size.width,
    ].reduce((a, b) => a > b ? a : b);
    final bottom = [
      autoPos.dy + autoBox.size.height,
      scanPos.dy + scanBox.size.height,
      manualPos.dy + manualBox.size.height,
      lookupPos.dy + lookupBox.size.height,
    ].reduce((a, b) => a > b ? a : b);

    final width = right - left;
    final height = bottom - top;

    return Positioned(
      left: left - 8,
      top: top - 8,
      child: AnimatedOpacity(
        opacity: 1.0,
        duration: const Duration(milliseconds: 250),
        child: IgnorePointer(
          child: Container(
            width: width + 16,
            height: height + 16,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.yellow, width: 4),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.yellow.withOpacity(0.35),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildHighlight() {
    if (_currentHighlightKey == null || !_showHighlight) {
      return const SizedBox.shrink();
    }

    final targetBox =
        _currentHighlightKey!.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox = context.findRenderObject() as RenderBox?;

    if (targetBox == null || overlayBox == null) {
      return const SizedBox.shrink();
    }

    final position = overlayBox.globalToLocal(
      targetBox.localToGlobal(Offset.zero),
    );
    final size = targetBox.size;

    return Positioned(
      left: position.dx - 4,
      top: position.dy - 4,
      child: AnimatedOpacity(
        opacity: _showHighlight ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 250),
        child: IgnorePointer(
          child: Container(
            width: size.width + 8,
            height: size.height + 8,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.yellow, width: 4),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.yellow.withOpacity(0.35),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

    
  @override
  Widget build(BuildContext context) {
    print('🎓 TutorialOverlay building - step: $_currentStep');
    
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black.withOpacity(0.7),
        child: GestureDetector(
          onTap: () {
            print('🎓 Tutorial tapped - current step: $_currentStep');
            _nextStep();
          },
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              // Yellow highlight for all buttons
              _buildAllButtonsHighlight(),
              
              // Yellow highlight for individual button
              _buildHighlight(),
              
              Positioned(
                right: 16,
                bottom: 140 + _leviOffset,
                child: SlideTransition(
                  position: _leviSlideAnimation,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.orange.shade700,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/levibari.jpeg',
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          print('❌ Error loading levibari.jpeg: $error');
                          // Fallback to a bari emoji/icon
                          return Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.orange.shade700,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: Text(
                                '🫀',
                                style: TextStyle(fontSize: 60),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              
              // Talk bubble
              Positioned(
                left: 16,
                right: 152,
                bottom: 180,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    _getTalkBubbleText(),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              
              // Tap to continue
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Tap to continue',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              
              // X button (top-right)
              Positioned(
                top: 48,
                right: 16,
                child: GestureDetector(
                  onTap: () {
                    print('🎓 X button tapped - closing tutorial');
                    widget.onComplete();
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.black87,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}