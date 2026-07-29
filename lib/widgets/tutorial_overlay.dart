// tutorial_overlay.dart - FIXED VERSION with Barry the Belly
import 'package:flutter/material.dart';

enum TutorialStep {
  tutorialIntro,
  tutorialAllButtons,
  tutorialScan,
  tutorialManual,
  tutorialLookup,
  tutorialUnifiedResult,
  tutorialClose,
}

class TutorialOverlay extends StatefulWidget {
  final VoidCallback onComplete;
  final GlobalKey scanButtonKey;
  final GlobalKey manualButtonKey;
  final GlobalKey lookupButtonKey;

  const TutorialOverlay({
    super.key,
    required this.onComplete,
    required this.scanButtonKey,
    required this.manualButtonKey,
    required this.lookupButtonKey,
  });

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  TutorialStep _currentStep = TutorialStep.tutorialIntro;
  late AnimationController _barryController;
  late Animation<Offset> _barrySlideAnimation;
  
  bool _showHighlight = false;
  GlobalKey? _currentHighlightKey;
  double _barryOffset = 0.0;
  
  bool _highlightAllButtons = false;
  
  @override
  void initState() {
    super.initState();
    
    _barryController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    _barrySlideAnimation = Tween<Offset>(
      begin: const Offset(1.5, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _barryController,
      curve: Curves.easeOut,
    ));
    
    _barryController.forward();
  }
  
  @override
  void dispose() {
    _barryController.dispose();
    super.dispose();
  }
  
  void _nextStep() {

    _playBarryHop();
    setState(() {
      switch (_currentStep) {
        case TutorialStep.tutorialIntro:

          _currentStep = TutorialStep.tutorialAllButtons;
          _highlightAllButtons = true;
          _showHighlight = false;
          _currentHighlightKey = null;
          break;
        case TutorialStep.tutorialAllButtons:

          _currentStep = TutorialStep.tutorialScan;
          _highlightAllButtons = false;
          _updateHighlight(widget.scanButtonKey);
          break;
        case TutorialStep.tutorialScan:

          _currentStep = TutorialStep.tutorialManual;
          _updateHighlight(widget.manualButtonKey);
          break;
        case TutorialStep.tutorialManual:

          _currentStep = TutorialStep.tutorialLookup;
          _updateHighlight(widget.lookupButtonKey);
          break;
        case TutorialStep.tutorialLookup:

          _currentStep = TutorialStep.tutorialUnifiedResult;
          _removeHighlight();
          break;
        case TutorialStep.tutorialUnifiedResult:

          _currentStep = TutorialStep.tutorialClose;
          break;
        case TutorialStep.tutorialClose:

          widget.onComplete();
          break;
      }
    });
  }

  void _playBarryHop() async {
    if (!mounted) return;
    
    for (int i = 0; i < 3; i++) {
      setState(() => _barryOffset = -20.0);
      await Future.delayed(Duration(milliseconds: 150));
      setState(() => _barryOffset = 0.0);
      await Future.delayed(Duration(milliseconds: 150));
    }
  }
  
  void _updateHighlight(GlobalKey newKey) async {

    setState(() {
      _showHighlight = false;
      _highlightAllButtons = false;
    });
    await Future.delayed(const Duration(milliseconds: 200));
    
    await Future.delayed(const Duration(milliseconds: 100));
    
    if (mounted) {
      setState(() {
        _currentHighlightKey = newKey;
        _showHighlight = true;
      });
      
      final context = newKey.currentContext;
      if (context == null) {

      } else {
        // ignore: use_build_context_synchronously
        final renderBox = context.findRenderObject() as RenderBox?;
        if (renderBox != null) {

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
      case TutorialStep.tutorialIntro:
        return "Hi there, friend. I am Barry, the belly. Let me walk you through this app and the way we use it to enrich our health and our lives.";
      case TutorialStep.tutorialAllButtons:
        return "These buttons are the 3 different ways you can see the nutrition facts and suggested bariatric friendly recipes for any food you like! Let's walk through them together!";
      case TutorialStep.tutorialScan:
        return "Let's start with Scan. Tap this when you want to scan a barcode yourself. You'll take a picture, tap Analyze, and we'll show you the nutrition facts and helpful recipe ideas.";
      case TutorialStep.tutorialManual:
        return "Use Code when a barcode won't scan or is damaged. You can type in the numbers from the bottom of the barcode instead.";
      case TutorialStep.tutorialLookup:
        return "And this is Search. Tap here to search by name if you don't have a barcode at all.";
      case TutorialStep.tutorialUnifiedResult:
        return "No matter which option you choose, you'll see nutrition facts and recipe suggestions for that item. Pick what works best for you.";
      case TutorialStep.tutorialClose:
        return "That's it! I'll be here if you need help. Let's take care of your health together.";
    }
  }
  
  Widget _buildAllButtonsHighlight() {
    if (!_highlightAllButtons) {
      return const SizedBox.shrink();
    }

    final scanBox = widget.scanButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final manualBox = widget.manualButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final lookupBox = widget.lookupButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox = context.findRenderObject() as RenderBox?;

    if (scanBox == null || manualBox == null || lookupBox == null || overlayBox == null) {
      return const SizedBox.shrink();
    }

    final scanPos = overlayBox.globalToLocal(scanBox.localToGlobal(Offset.zero));
    final manualPos = overlayBox.globalToLocal(manualBox.localToGlobal(Offset.zero));
    final lookupPos = overlayBox.globalToLocal(lookupBox.localToGlobal(Offset.zero));

    final left = [scanPos.dx, manualPos.dx, lookupPos.dx].reduce((a, b) => a < b ? a : b);
    final top = [scanPos.dy, manualPos.dy, lookupPos.dy].reduce((a, b) => a < b ? a : b);
    final right = [
      scanPos.dx + scanBox.size.width,
      manualPos.dx + manualBox.size.width,
      lookupPos.dx + lookupBox.size.width,
    ].reduce((a, b) => a > b ? a : b);
    final bottom = [
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
                  color: Colors.yellow.withValues(alpha: 0.35),
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
                  color: Colors.yellow.withValues(alpha: 0.35),
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

    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black.withValues(alpha: 0.7),
        child: GestureDetector(
          onTap: () {

            _nextStep();
          },
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              // Yellow highlight for all buttons
              _buildAllButtonsHighlight(),
              
              // Yellow highlight for individual button
              _buildHighlight(),
              
              // 🔥 FIXED: Barry the Belly image
              Positioned(
                right: 16,
                bottom: 140 + _barryOffset,
                child: SlideTransition(
                  position: _barrySlideAnimation,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/baribelly.png',
                        width: 120,
                        height: 120,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {

                          // Fallback to heart emoji
                          return Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.pink.shade100,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.favorite,
                                size: 60,
                                color: Colors.pink.shade400,
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
                        color: Colors.black.withValues(alpha: 0.2),
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
                      color: Colors.white.withValues(alpha: 0.9),
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
                          color: Colors.black.withValues(alpha: 0.2),
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