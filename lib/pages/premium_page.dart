// lib/pages/premium_page.dart - Lifetime purchase, full original logic preserved
import 'package:flutter/material.dart';
import 'package:bari_wise/services/auth_service.dart';
import 'package:bari_wise/services/premium_service.dart';
import 'package:bari_wise/services/scan_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import '../services/database_service_core.dart';
import '../controllers/premium_gate_controller.dart';

class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key});

  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage>
    with TickerProviderStateMixin {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  bool _isLoading    = true;
  bool _isPurchasing = false;
  bool _isPremium    = false;
  bool _isAvailable  = false;

  int _dailyScans     = 0;
  int _remainingScans = 0;

  /// ⭐ Free tier is default, user must explicitly choose premium
  String? _selectedPlan;

  List<ProductDetails> _products     = <ProductDetails>[];
  bool                 _hasLoadError = false;
  bool                 _isRefreshing = false;

  // PREMIUM ONLY
  static const String premiumProductId = '11.111.0000';
  static const Set<String> _productIds = {premiumProductId};

  // Cache keys
  static const String _premiumStatusCacheKey     = 'cached_premium_status';
  static const String _premiumStatusTimestampKey = 'cached_premium_timestamp';
  static const String _scanCountCacheKey         = 'cached_scan_count';
  static const String _scanCountTimestampKey     = 'cached_scan_timestamp';
  static const String _scanCountDateKey          = 'cached_scan_date';

  static const Duration _premiumStatusCacheExpiry = Duration(hours: 1);
  static const Duration _scanCountCacheExpiry     = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _animationController, curve: Curves.easeInOut),
    );

    _initializePremiumPage();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initializePremiumPage() async {
    try {
      AuthService.ensureUserAuthenticated();
      await _checkPremiumStatus(forceRefresh: false);
      await _initializeInAppPurchase();
      _animationController.forward();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading    = false;
        _hasLoadError = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Unable to load premium details. You can still browse features.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  /// Check if cached data is still valid
  Future<bool> _isCacheValid(String timestampKey, Duration expiry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestampStr = prefs.getString(timestampKey);
      if (timestampStr == null) return false;

      final timestamp = DateTime.parse(timestampStr);
      final age = DateTime.now().difference(timestamp);
      return age < expiry;
    } catch (_) {
      return false;
    }
  }

  /// Check if it's a new day (for daily scan count reset)
  Future<bool> _isNewDay() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedDate = prefs.getString(_scanCountDateKey);
      final today = DateTime.now().toIso8601String().split('T')[0];
      return cachedDate != today;
    } catch (_) {
      return true;
    }
  }

  Future<void> _checkPremiumStatus({bool forceRefresh = false}) async {
    try {
      setState(() => _isLoading = true);

      final userId = DatabaseServiceCore.currentUserId;
      if (userId == null || userId.isEmpty) {
        throw Exception('User not authenticated');
      }

      final prefs = await SharedPreferences.getInstance();

      bool useCache         = !forceRefresh;
      bool premiumFromCache = false;
      int  scansFromCache   = 0;

      // ---- PREMIUM CACHE ----
      if (useCache) {
        final premiumTimestampStr =
            prefs.getString(_premiumStatusTimestampKey);

        if (premiumTimestampStr != null) {
          final storedTime = DateTime.parse(premiumTimestampStr);
          final age = DateTime.now().difference(storedTime);

          if (age < _premiumStatusCacheExpiry) {
            final cachedJson = prefs.getString(_premiumStatusCacheKey);
            if (cachedJson != null) {
              final cached = json.decode(cachedJson);
              premiumFromCache = cached['isPremium'] ?? false;

              if (mounted) {
                setState(() => _isPremium = premiumFromCache);
              }
            }
          } else {
            useCache = false;
          }
        } else {
          useCache = false;
        }
      }

      // ---- SCAN CACHE ----
      if (useCache) {
        final scanTimestampStr = prefs.getString(_scanCountTimestampKey);
        final newDay = await _isNewDay();

        if (!newDay && scanTimestampStr != null) {
          final storedTime = DateTime.parse(scanTimestampStr);
          final age = DateTime.now().difference(storedTime);

          if (age < _scanCountCacheExpiry) {
            scansFromCache = prefs.getInt(_scanCountCacheKey) ?? 0;

            final remaining = premiumFromCache ? -1 : (3 - scansFromCache);

            if (mounted) {
              setState(() {
                _dailyScans     = scansFromCache;
                _remainingScans = remaining;
                _isLoading      = false;
              });
            }

            return; // Used cache successfully
          }
        }
      }

      // ---- FETCH FROM DB (no cache) ----
      final premiumStatus = await PremiumService.isPremiumUser();
      final dailyScans    = await ScanService.getDailyScanCount();
      final today = DateTime.now().toIso8601String().split('T')[0];

      // Cache premium status
      await prefs.setString(
        _premiumStatusCacheKey,
        json.encode({'isPremium': premiumStatus}),
      );
      await prefs.setString(
        _premiumStatusTimestampKey,
        DateTime.now().toIso8601String(),
      );

      // Cache scans
      await prefs.setInt(_scanCountCacheKey, dailyScans);
      await prefs.setString(
          _scanCountTimestampKey, DateTime.now().toIso8601String());
      await prefs.setString(_scanCountDateKey, today);

      // Update legacy key
      await prefs.setBool('isPremiumUser', premiumStatus);

      final remainingScans = premiumStatus ? -1 : (3 - dailyScans);

      if (mounted) {
        setState(() {
          _isPremium      = premiumStatus;
          _dailyScans     = dailyScans;
          _remainingScans = remainingScans;
          _isLoading      = false;
          _isRefreshing   = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading    = false;
          _hasLoadError = true;
          _isRefreshing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to load account status'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  /// Manually refresh premium status (bypasses cache)
  Future<void> _refreshPremiumStatus() async {
    setState(() => _isRefreshing = true);
    await _checkPremiumStatus(forceRefresh: true);
  }

  /// Invalidate cache when user performs a scan
  static Future<void> invalidateScanCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_scanCountCacheKey);
      await prefs.remove(_scanCountTimestampKey);
    } catch (_) {}
  }

  /// Invalidate cache when user purchases premium
  static Future<void> invalidatePremiumCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_premiumStatusCacheKey);
      await prefs.remove(_premiumStatusTimestampKey);
    } catch (_) {}
  }

  Future<void> _initializeInAppPurchase() async {
    try {
      final bool isAvailable = await _inAppPurchase.isAvailable();

      if (mounted) {
        setState(() => _isAvailable = isAvailable);
      }

      if (!isAvailable) {
        if (mounted) {
          setState(() => _hasLoadError = true);

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'In-app purchases are not available on this device'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      // 🔥 Listen to purchase updates
      final Stream<List<PurchaseDetails>> purchaseUpdated =
          _inAppPurchase.purchaseStream;

      _subscription = purchaseUpdated.listen(
        _onPurchaseUpdate,
        onDone: () => _subscription?.cancel(),
        onError: (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Purchase error occurred'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
      );

      await _loadProducts();
    } catch (e) {
      if (mounted) {
        setState(() => _hasLoadError = true);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Unable to initialize purchases'),
            backgroundColor: Colors.orange,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _initializeInAppPurchase,
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadProducts() async {
    if (!_isAvailable) return;

    try {
      final ProductDetailsResponse response =
          await _inAppPurchase.queryProductDetails(_productIds);

      if (response.error != null) {
        throw Exception(
            'Failed to load product details: ${response.error!.message}');
      }

      if (mounted) {
        setState(() {
          _products     = response.productDetails;
          _hasLoadError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _hasLoadError = true);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Unable to load purchase options'),
            backgroundColor: Colors.orange,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _loadProducts,
            ),
          ),
        );
      }
    }
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      switch (purchaseDetails.status) {
        case PurchaseStatus.pending:
          if (mounted) {
            setState(() => _isPurchasing = true);
          }
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _handleSuccessfulPurchase(purchaseDetails);
          break;

        case PurchaseStatus.error:
          if (mounted) {
            setState(() => _isPurchasing = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Purchase failed: ${purchaseDetails.error?.message ?? "Unknown error"}',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          break;

        case PurchaseStatus.canceled:
          if (mounted) {
            setState(() => _isPurchasing = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Purchase was cancelled'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          break;
      }

      if (purchaseDetails.pendingCompletePurchase) {
        _inAppPurchase.completePurchase(purchaseDetails);
      }
    }
  }

  Future<void> _handleSuccessfulPurchase(
      PurchaseDetails purchaseDetails) async {
    try {
      final prefs  = await SharedPreferences.getInstance();
      final userId = AuthService.currentUserId;

      if (userId == null || userId.isEmpty) {
        throw Exception('User not authenticated - invalid user ID');
      }

      // Only premium supported now
      if (purchaseDetails.productID != premiumProductId) {
        throw Exception(
            'Unknown product ID: ${purchaseDetails.productID}');
      }

      // Update database & local cache
      await AuthService.markUserAsPremium(userId);
      await prefs.setBool('isPremiumUser', true);

      // Invalidate old premium cache
      await invalidatePremiumCache();

      if (mounted) {
        setState(() {
          _isPremium = true;
        });
      }

      // Save purchase metadata
      await prefs.setString(
          'purchaseDate', DateTime.now().toIso8601String());
      await prefs.setString('planType', 'lifetime');
      await prefs.setString('productId', purchaseDetails.productID);
      await prefs.setString(
        'transactionId',
        purchaseDetails.transactionDate ??
            DateTime.now().millisecondsSinceEpoch.toString(),
      );

      // Refresh system-wide premium gate
      await PremiumGateController().refresh();

      // Refresh this page's premium data
      await _checkPremiumStatus(forceRefresh: true);

      if (mounted) {
        setState(() {
          _remainingScans = -1; // Unlimited scans
          _isPurchasing   = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Welcome to BariWise Premium! You now have lifetime access.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );

        // Pop after success
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPurchasing = false);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Purchase succeeded, but updating your account failed. '
              'Please contact support.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _purchasePlan() async {
    if (_selectedPlan == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a plan first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!_isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('In-app purchases are not available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isPurchasing = true);

    try {
      // Always premium
      const String productId = premiumProductId;

      ProductDetails? productDetails;
      try {
        productDetails = _products.firstWhere((p) => p.id == productId);
      } catch (_) {
        productDetails = null;
      }

      if (productDetails == null) {
        throw Exception(
            'Product not found. Please try reloading the page.');
      }

      final PurchaseParam purchaseParam =
          PurchaseParam(productDetails: productDetails);

      await _inAppPurchase.buyNonConsumable(
          purchaseParam: purchaseParam);
    } catch (e) {
      if (mounted) {
        setState(() => _isPurchasing = false);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Purchase failed: ${e.toString()}'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _purchasePlan,
            ),
          ),
        );
      }
    }
  }

  Future<void> _restorePurchases() async {
    if (!_isAvailable) return;

    setState(() => _isPurchasing = true);

    try {
      await _inAppPurchase.restorePurchases();

      // Clear premium cache
      await invalidatePremiumCache();
      await _checkPremiumStatus(forceRefresh: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Purchases restored successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPurchasing = false);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to restore purchases'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _restorePurchases,
            ),
          ),
        );
      }
    }
  }

  String _getProductPrice(String productId) {
    try {
      final product = _products.firstWhere((p) => p.id == productId);
      return product.price;
    } catch (e) {
      return '\$9.99'; // fallback price
    }
  }

  // ─────────────────────────────────────────────
  // UI WIDGETS
  // ─────────────────────────────────────────────

  Widget _buildStatusCard() {
    String   title;
    String   subtitle;
    IconData icon;
    Color    iconColor;
    Color    backgroundColor;

    if (_isPremium) {
      title           = 'Lifetime Access Active!';
      subtitle        =
          'You have permanent access to all BariWise premium features.';
      icon            = Icons.workspace_premium;
      iconColor       = Colors.amber.shade600;
      backgroundColor = Colors.amber.shade50;
    } else {
      title           = 'Unlock BariWise Premium';
      subtitle        =
          'One-time payment. No subscriptions. No recurring charges.';
      icon            = Icons.workspace_premium_outlined;
      iconColor       = Colors.grey.shade600;
      backgroundColor = Colors.grey.shade50;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 64, color: iconColor),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
          ),

          if (!_isPremium) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _remainingScans <= 0
                    ? Colors.red.shade50
                    : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _remainingScans <= 0
                      ? Colors.red.shade200
                      : Colors.blue.shade200,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'Free Account Limits',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _remainingScans <= 0
                          ? Colors.red.shade700
                          : Colors.blue.shade700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Daily scans used: $_dailyScans/3',
                    style: TextStyle(
                      color: _remainingScans <= 0
                          ? Colors.red.shade600
                          : Colors.blue.shade600,
                      fontSize: 14,
                    ),
                  ),
                  if (_remainingScans <= 0)
                    Text(
                      'No scans remaining today',
                      style: TextStyle(
                        color: Colors.red.shade600,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFeaturesCard() {
    final premiumFeatures = [
      {'icon': Icons.all_inclusive,     'title': 'Unlimited daily scans'},
      {'icon': Icons.shopping_cart,     'title': 'Personal grocery list'},
      {'icon': Icons.favorite,          'title': 'Save favorite recipes'},
      {'icon': Icons.restaurant_menu,   'title': 'Submit your own recipes'},
      {'icon': Icons.menu_book,         'title': 'Full recipe details & directions'},
      {'icon': Icons.add_shopping_cart, 'title': 'Add recipes to shopping list'},
      {'icon': Icons.support_agent,     'title': 'Priority customer support'},
      {'icon': Icons.sync,              'title': 'Sync across all devices'},
      {'icon': Icons.update,            'title': 'All future features included — free'},
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Everything you get — forever',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 20),

          ...premiumFeatures.map(
            (feature) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(
                    _isPremium
                        ? Icons.check_circle
                        : Icons.check_circle_outline,
                    color: _isPremium ? Colors.green : Colors.amber,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      feature['title'] as String,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanSelection() {
    if (_isPremium) return const SizedBox.shrink();

    if (_hasLoadError) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              'Unable to Load Plans',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "We couldn't load the purchase options. Please check your "
              'internet connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _isLoading    = true;
                  _hasLoadError = false;
                });
                _initializePremiumPage();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Get lifetime access:',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 20),

          // ── Lifetime Premium Plan Card ──
          Card(
            elevation: _selectedPlan == 'premium' ? 8 : 2,
            color:
                _selectedPlan == 'premium' ? Colors.amber.shade50 : null,
            child: InkWell(
              onTap: () => setState(() => _selectedPlan = 'premium'),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Radio<String>(
                      value: 'premium',
                      groupValue: _selectedPlan,
                      onChanged: (value) =>
                          setState(() => _selectedPlan = value),
                      activeColor: Colors.amber.shade600,
                    ),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Lifetime Premium',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'One-time payment — yours forever',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            '• Unlimited label scans\n'
                            '• Full bariatric safety scoring\n'
                            '• Priority support\n'
                            '• All future features included',
                            style: TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _getProductPrice(premiumProductId),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const Text(
                          'one-time',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Purchase Button ──
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isPurchasing ? null : _purchasePlan,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 8,
              ),
              child: _isPurchasing
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text('Processing...'),
                      ],
                    )
                  : Text(
                      _selectedPlan == null
                          ? 'Select a Plan'
                          : 'Get Lifetime Access – '
                              '${_getProductPrice(premiumProductId)}',
                      style: const TextStyle(fontSize: 16),
                    ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Legal Fine Print ──
          Text(
            'This is a one-time purchase of '
            '${_getProductPrice(premiumProductId)}. '
            'You will not be charged again. No subscription or auto-renewal. '
            'Processed securely through '
            '${Platform.isIOS ? 'the App Store' : 'Google Play'}. '
            'All sales are final per '
            '${Platform.isIOS ? "Apple\'s" : "Google\'s"} standard refund policy. '
            'By purchasing, you agree to our Terms of Service and Privacy Policy.',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAlreadyPurchasedCard() {
    if (!_isPremium) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.verified, size: 48, color: Colors.green.shade600),
          const SizedBox(height: 16),
          Text(
            "You're all set!",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You have lifetime access to all BariWise premium features. '
            'Every future feature we add is yours automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.green.shade600,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading subscription plans...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('BariWise Premium'),
        backgroundColor: Colors.amber,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (!_isPremium && _isAvailable)
            TextButton(
              onPressed: _restorePurchases,
              child: const Text(
                'Restore',
                style: TextStyle(color: Colors.white),
              ),
            ),

          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _refreshPremiumStatus,
            tooltip: 'Refresh Status',
          ),
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.amber, Colors.orange],
              ),
            ),
          ),

          FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 30),
                  _buildFeaturesCard(),
                  const SizedBox(height: 30),
                  _buildPlanSelection(),
                  _buildAlreadyPurchasedCard(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}