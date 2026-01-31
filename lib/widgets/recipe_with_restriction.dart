// lib/widgets/recipe_with_restriction.dart - OPTIMIZED: Uses cached premium status
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/premium_service.dart';

class RecipeWithRestriction extends StatefulWidget {
  final String recipeName;
  final String ingredients;
  final String directions;

  const RecipeWithRestriction({
    super.key,
    required this.recipeName,
    required this.ingredients,
    required this.directions,
  });

  @override
  State<RecipeWithRestriction> createState() => _RecipeWithRestrictionState();
}

class _RecipeWithRestrictionState extends State<RecipeWithRestriction> {
  bool _isPremium = false;
  bool _isLoading = true;

  static const String _premiumCacheKey = 'is_premium_cached';
  static const String _premiumCacheTimeKey = 'premium_cache_time';
  static const Duration _cacheDuration = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _checkPremiumStatus();
  }

  Future<void> _checkPremiumStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Try to load from cache first
      final cachedPremium = prefs.getBool(_premiumCacheKey);
      final cachedTime = prefs.getInt(_premiumCacheTimeKey);
      
      if (cachedPremium != null && cachedTime != null) {
        final cacheAge = DateTime.now().millisecondsSinceEpoch - cachedTime;
        
        if (cacheAge < _cacheDuration.inMilliseconds) {
          // Cache is valid
          if (mounted) {
            setState(() {
              _isPremium = cachedPremium;
              _isLoading = false;
            });
          }
          return;
        }
      }
      
      // Cache miss or stale, check with service
      final isPremium = await PremiumService.canAccessPremiumFeature();
      
      // Save to cache
      await prefs.setBool(_premiumCacheKey, isPremium);
      await prefs.setInt(_premiumCacheTimeKey, DateTime.now().millisecondsSinceEpoch);
      
      if (mounted) {
        setState(() {
          _isPremium = isPremium;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error checking premium status: $e');
      
      // On error, try to use cached value even if stale
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedPremium = prefs.getBool(_premiumCacheKey);
        if (cachedPremium != null && mounted) {
          setState(() {
            _isPremium = cachedPremium;
            _isLoading = false;
          });
          return;
        }
      } catch (_) {}
      
      if (mounted) {
        setState(() {
          _isPremium = false;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Card(
        margin: EdgeInsets.all(16),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.all(16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.restaurant, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.recipeName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (!_isPremium) ...[
                  Icon(Icons.star, color: Colors.amber, size: 20),
                ],
              ],
            ),
            SizedBox(height: 16),
            
            if (_isPremium) ...[
              // Show full recipe for premium users
              Text(
                'Ingredients:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 8),
              Text(widget.ingredients),
              SizedBox(height: 16),
              Text(
                'Directions:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 8),
              Text(widget.directions),
            ] else ...[
              // Show limited preview for free users
              Text(
                'Ingredients:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 8),
              Text(
                widget.ingredients.length > 50 
                    ? '${widget.ingredients.substring(0, 50)}...' 
                    : widget.ingredients,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              SizedBox(height: 16),
              
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.star, color: Colors.amber),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Upgrade to Premium to see the full recipe!',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/premium');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.white,
                        ),
                        child: Text('Upgrade Now'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}