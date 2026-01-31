// lib/controllers/premium_gate_controller.dart
// FIXED: Proper scan counting with no negative numbers, shows "unlimited" for premium
import 'package:flutter/material.dart';
import 'dart:async';
import '../services/premium_service.dart';
import '../services/auth_service.dart';
import '../logger.dart';

class PremiumGateController extends ChangeNotifier {
  static final PremiumGateController _instance = PremiumGateController._internal();
  factory PremiumGateController() => _instance;
  PremiumGateController._internal();

  // State variables
  bool _isPremium = false;
  bool _isLoading = true;
  int _remainingScans = 3;
  int _totalScansUsed = 0;
  bool _initializationFailed = false;
  
  // Concurrency control
  int _retryCount = 0;
  static const int maxRetries = 3;
  Timer? _retryTimer;
  Completer<void>? _initializationCompleter;
  bool _isDisposed = false;

  // Getters
  bool get isPremium => _isPremium;
  bool get isLoading => _isLoading;
  
  // ⭐ FIXED: Return proper remaining scans (0-3 for free, -1 for premium)
  int get remainingScans => _remainingScans.clamp(-1, 3);
  
  int get totalScansUsed => _totalScansUsed;
  bool get initializationFailed => _initializationFailed;
  
  // ⭐ FIXED: Premium users never run out of scans
  bool get hasUsedAllFreeScans => !_isPremium && _remainingScans <= 0;

  @override
  void dispose() {
    print('DEBUG: Disposing PremiumGateController');
    _isDisposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _initializationCompleter?.complete();
    _initializationCompleter = null;
    super.dispose();
  }

  Future<void> initialize() async {
    if (_initializationCompleter != null && !_initializationCompleter!.isCompleted) {
      print('DEBUG: Initialization already in progress, waiting...');
      return _initializationCompleter!.future;
    }

    if (_isDisposed) {
      print('DEBUG: Controller disposed, skipping initialization');
      return;
    }

    _initializationCompleter = Completer<void>();
    
    print('DEBUG: Starting PremiumGateController initialization (attempt ${_retryCount + 1})');
    _isLoading = true;
    _initializationFailed = false;
    
    if (!_isDisposed) {
      notifyListeners();
    }

    try {
      if (AuthService.isLoggedIn) {
        print('DEBUG: User is logged in, checking premium status');
        
        _isPremium = await _checkPremiumWithTimeout();
        print('DEBUG: Premium status result: $_isPremium');
        
        if (_isPremium) {
          // ⭐ FIXED: Premium users get unlimited scans
          _remainingScans = -1;
          _totalScansUsed = 0;
        } else {
          // ⭐ FIXED: Get remaining scans and ensure no negatives
          final remaining = await _getRemainingScansWithTimeout();
          _remainingScans = remaining.clamp(0, 3);
          _totalScansUsed = 3 - _remainingScans;
        }
      } else {
        print('DEBUG: User is NOT logged in - using defaults');
        _isPremium = false;
        _remainingScans = 3;
        _totalScansUsed = 0;
      }

      _retryCount = 0;
      _initializationFailed = false;
      
    } catch (e, stackTrace) {
      print('DEBUG: Error in initialization (attempt ${_retryCount + 1}): $e');
      logger.e(
        'Error initializing premium status',
        error: e,
        stackTrace: stackTrace,
      );
      
      await _handleInitializationFailure();
    }

    _isLoading = false;
    
    if (!_isDisposed) {
      notifyListeners();
    }
    
    print('DEBUG: Initialization complete. isPremium: $_isPremium, remainingScans: $_remainingScans');
    
    if (!_initializationCompleter!.isCompleted) {
      _initializationCompleter!.complete();
    }
  }

  Future<void> _handleInitializationFailure() async {
    if (_isDisposed) return;
    
    _retryCount++;
    
    if (_retryCount < maxRetries) {
      final delaySeconds = 2 * _retryCount;
      print('DEBUG: Retrying initialization in $delaySeconds seconds...');
      
      _retryTimer?.cancel();
      _retryTimer = Timer(Duration(seconds: delaySeconds), () {
        if (!_isDisposed && _retryCount < maxRetries) {
          print('DEBUG: Executing retry attempt ${_retryCount + 1}');
          initialize();
        }
      });
    } else {
      print('DEBUG: Max retries reached, using fallback values');
      _initializationFailed = true;
      _isPremium = false;
      _remainingScans = 3;
      _totalScansUsed = 0;
    }
  }

  Future<bool> _checkPremiumWithTimeout() async {
    if (_isDisposed) return false;
    
    try {
      return await Future.any([
        PremiumService.isPremiumUser(),
        Future.delayed(Duration(seconds: 10), () => false),
      ]).timeout(Duration(seconds: 12));
    } catch (e) {
      print('DEBUG: Premium check timeout or error: $e');
      return false;
    }
  }

  Future<int> _getRemainingScansWithTimeout() async {
    if (_isDisposed) return 3;
    
    try {
      final result = await Future.any([
        PremiumService.getRemainingScanCount(),
        Future.delayed(Duration(seconds: 10), () => 3),
      ]).timeout(Duration(seconds: 12));
      
      // ⭐ FIXED: Handle premium users returning -1
      if (result == -1) return -1;
      
      // ⭐ FIXED: Ensure no negative numbers for free users
      return result.clamp(0, 3);
    } catch (e) {
      print('DEBUG: Scan count check timeout or error: $e');
      return 3;
    }
  }

  Future<void> refresh() async {
    if (_isDisposed) return;
    
    print('DEBUG: Manual refresh requested');
    _retryTimer?.cancel();
    _retryCount = 0;
    await initialize();
  }

  void reset() {
    print('DEBUG: Resetting PremiumGateController');
    
    _retryTimer?.cancel();
    _retryTimer = null;
    _initializationCompleter?.complete();
    _initializationCompleter = null;
    
    _isPremium = false;
    _isLoading = false;
    _remainingScans = 3;
    _totalScansUsed = 0;
    _initializationFailed = false;
    _retryCount = 0;
    
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  bool canAccessFeature(PremiumFeature feature) {
    if (_isDisposed) return false;
    if (!AuthService.isLoggedIn) return false;
    
    if (_initializationFailed) {
      switch (feature) {
        case PremiumFeature.scan:
          return true;
        default:
          return false;
      }
    }
    
    if (_isPremium) return true;

    switch (feature) {
      case PremiumFeature.basicProfile:
      case PremiumFeature.purchase:
      case PremiumFeature.socialMessaging:
      case PremiumFeature.friendRequests:
      case PremiumFeature.searchUsers:
        return true;
      case PremiumFeature.scan:
        return _remainingScans > 0 || _isLoading;
      case PremiumFeature.groceryList:
      case PremiumFeature.fullRecipes:
      case PremiumFeature.submitRecipes:
      case PremiumFeature.viewRecipes:
      case PremiumFeature.favoriteRecipes:
      case PremiumFeature.healthTracker:
        return false;
    }
  }

  // ⭐ FIXED: Proper scan decrement with bounds checking
  Future<bool> useScan() async {
    if (_isDisposed) return false;
    
    // Premium users always succeed
    if (_isPremium) return true;
    
    // Check if user has scans remaining
    if (_remainingScans <= 0) return false;
    
    try {
      final success = await _incrementScanWithTimeout();
      
      if (success && !_isDisposed) {
        // ⭐ FIXED: Only decrement if we have scans remaining
        if (_remainingScans > 0) {
          _remainingScans--;
          _totalScansUsed = 3 - _remainingScans;
        }
        notifyListeners();
      }
      
      return success;
    } catch (e) {
      logger.e("Error using scan", error: e);
      
      // On error, still allow the scan locally but log the issue
      if (!_isDisposed && _remainingScans > 0) {
        _remainingScans--;
        _totalScansUsed = 3 - _remainingScans;
        notifyListeners();
      }
      return true;
    }
  }

  Future<bool> _incrementScanWithTimeout() async {
    if (_isDisposed) return false;
    
    try {
      return await Future.any([
        PremiumService.incrementScanCount(),
        Future.delayed(Duration(seconds: 5), () => true),
      ]).timeout(Duration(seconds: 7));
    } catch (e) {
      print('DEBUG: Scan increment timeout or error: $e');
      return true;
    }
  }

  Future<void> addBonusScans(int count) async {
    if (_isDisposed || _isPremium) return;

    try {
      _remainingScans += count;
      _remainingScans = _remainingScans.clamp(0, 10);
      _totalScansUsed = (3 - _remainingScans).clamp(0, 3);
      
      if (!_isDisposed) {
        notifyListeners();
      }
      
      print('DEBUG: Added $count bonus scans. New total: $_remainingScans');
    } catch (e, stackTrace) {
      logger.e("Error adding bonus scans", error: e, stackTrace: stackTrace);
    }
  }

  // ⭐ FIXED: Better status messages with no negative numbers
  String getStatusMessage() {
    if (_isDisposed) return "Service unavailable";
    if (_isLoading) return "Loading...";
    if (_initializationFailed) return "Connection issues - features may be limited";
    if (_isPremium) return "Premium: Unlimited scans";
    
    final remaining = _remainingScans.clamp(0, 3);
    return "Free: $remaining scan${remaining == 1 ? '' : 's'} remaining today";
  }

  bool shouldShowUpgradePrompt() {
    return !_isDisposed && !_isPremium && !_isLoading && _remainingScans <= 1;
  }
}

enum PremiumFeature {
  basicProfile,
  purchase,
  scan,
  viewRecipes,
  groceryList,
  fullRecipes,
  submitRecipes,
  favoriteRecipes,
  socialMessaging,
  friendRequests,
  searchUsers,
  healthTracker,
}