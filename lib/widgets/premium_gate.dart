// lib/widgets/premium_gate.dart - OPTIMIZED: Assumes controller already caches
// NOTE: This file's optimization depends heavily on PremiumGateController's implementation
// If the controller doesn't cache internally, it should be updated to do so

import 'package:flutter/material.dart';
import '../controllers/premium_gate_controller.dart';
import '../services/auth_service.dart';

class PremiumGate extends StatelessWidget {
  final Widget child;
  final PremiumFeature feature;
  final String featureName;
  final String featureDescription;
  final bool showSoftPreview;
  final VoidCallback? onUpgrade;

  const PremiumGate({
    super.key,
    required this.child,
    required this.feature,
    required this.featureName,
    this.featureDescription = '',
    this.showSoftPreview = false,
    this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    // NOTE: PremiumGateController() should implement caching internally
    // If it creates a new instance each time, consider making it a singleton
    // with internal caching to reduce database calls
    
    return AnimatedBuilder(
      animation: PremiumGateController(),
      builder: (context, _) {
        final controller = PremiumGateController();

        // Show loading
        if (controller.isLoading) {
          return _buildLoadingState();
        }

        // Not logged in - only allow auth page access
        if (!AuthService.isLoggedIn && feature != PremiumFeature.purchase) {
          return _buildLoginRequired(context);
        }

        // Premium user - show content normally
        if (controller.isPremium) {
          return child;
        }

        // Free user - check if they can use this feature
        if (controller.canAccessFeature(feature)) {
          return child;
        }

        // Free user blocked - show upgrade prompt
        if (showSoftPreview) {
          return _buildSoftPreview(context);
        } else {
          return _buildUpgradePrompt(context);
        }
      },
    );
  }

  Widget _buildLoadingState() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading...'),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginRequired(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.login,
            size: 64,
            color: Colors.blue,
          ),
          const SizedBox(height: 16),
          const Text(
            'Sign In Required',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please sign in to access this feature',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/login');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Sign In',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpgradePrompt(BuildContext context) {
    final controller = PremiumGateController();
    
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.star,
              size: 48,
              color: Colors.amber.shade700,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Premium Required',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.amber.shade700,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Upgrade to Access $featureName',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          if (featureDescription.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              featureDescription,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
          ],
          
          const SizedBox(height: 20),
          
          // Show scan usage for scan-related features
          if (feature == PremiumFeature.scan || feature == PremiumFeature.viewRecipes) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                children: [
                  Text(
                    'Free Scan Limit Reached',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You\'ve used all ${controller.totalScansUsed}/3 free daily scans',
                    style: TextStyle(
                      color: Colors.red.shade600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          
          _buildPremiumBenefits(),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: onUpgrade ?? () {
                Navigator.pushNamed(context, '/purchase');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Upgrade to Premium',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoftPreview(BuildContext context) {
    return Stack(
      children: [
        // Show the actual content but disabled
        IgnorePointer(
          ignoring: true,
          child: Opacity(
            opacity: 0.3,
            child: child,
          ),
        ),
        // Overlay with upgrade prompt
        Container(
          color: Colors.white.withOpacity(0.95),
          child: _buildUpgradePrompt(context),
        ),
      ],
    );
  }

  Widget _buildPremiumBenefits() {
    const benefits = [
      'Unlimited daily scans',
      'Full recipe details & directions',
      'Personal grocery list',
      'Save & organize favorite recipes',
      'Submit your own recipes',
      'Priority customer support',
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Premium includes:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.amber.shade700,
            ),
          ),
          const SizedBox(height: 8),
          ...benefits.map((benefit) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  size: 16,
                  color: Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    benefit,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}