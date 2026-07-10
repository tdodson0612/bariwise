// lib/widgets/admin_guard.dart
// Wraps any page that should only be accessible to admin users.
// Usage: wrap the page widget in the route definition, not in the page itself.
//
// In main.dart:
//   '/admin-page': (context) => const AdminGuard(child: SomeAdminPage()),
//
// What counts as admin:
//   - AppConfig.isDevelopment must be true (same gate as the drawer entry)
//   - AuthService.currentUser email must be in _adminEmails
//
// Both conditions must be true. This means:
//   - Production builds (isProduction = true) → blocked for everyone
//   - Dev builds with non-admin email → blocked
//   - Dev builds with admin email → allowed
//
// iOS 14 Compatible | Production Ready

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../config/app_config.dart';

class AdminGuard extends StatelessWidget {
  final Widget child;

  const AdminGuard({super.key, required this.child});

  // ── Admin email list ───────────────────────────────────────────────────────
  // Separate from premium emails intentionally.
  // Add emails here to grant admin access without affecting premium status.
  static const Set<String> _adminEmails = {
    'terryd0612@gmail.com',
    'liverdiseasescanner@gmail.com',
  };

  static bool get isAdmin {
    if (!AppConfig.isDevelopment) return false;
    final email = AuthService.currentUser?.email?.trim().toLowerCase();
    if (email == null) return false;
    return _adminEmails.contains(email);
  }

  @override
  Widget build(BuildContext context) {
    if (isAdmin) return child;

    // Not admin — show access denied screen instead of the protected page.
    // Using a post-frame callback to pop immediately if navigated directly,
    // so the user doesn't see a flash of the denied screen in the nav stack.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Admin access required'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Access Denied'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_rounded, size: 72, color: Colors.red.shade300),
              const SizedBox(height: 24),
              const Text(
                'Admin Access Required',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This page is only accessible to admin users in development mode.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else {
                    Navigator.pushReplacementNamed(context, '/home');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}