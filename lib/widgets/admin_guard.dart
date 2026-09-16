// lib/widgets/admin_guard.dart
// Wraps any page that should only be accessible to admin users.
// Usage: wrap the page widget in the route definition, not in the page itself.
//
// In main.dart:
//   '/admin-page': (context) => const AdminGuard(child: SomeAdminPage()),
//
// What counts as admin:
//   - AuthService.currentUser email must be in _adminEmails
//
// ✅ FIXED THIS SESSION: previously also required AppConfig.isDevelopment
// to be true, via a hardcoded `const bool isProduction = false` in
// app_config.dart that was disconnected from the app's real
// environment-detection system (Environment.isProduction in
// environment.dart, which correctly reads a build-time flag). This
// meant that if anyone ever "corrected" that hardcoded flag before a
// real release — a very plausible action given its name — admin
// access would have broken completely for everyone, permanently,
// while the real production flag stayed unaffected. Removed the
// isDevelopment requirement entirely: admin access is now gated purely
// by the email whitelist below, working identically in development and
// production. This also now matches the server-side admin check added
// to the Cloudflare Worker this session (same two emails) — previously
// this client-side gate had no server-side equivalent at all, so
// anyone could bypass it by hitting the Worker's endpoint directly.
//
// iOS 14 Compatible | Production Ready

import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class AdminGuard extends StatelessWidget {
  final Widget child;

  const AdminGuard({super.key, required this.child});

  // ── Admin email list ───────────────────────────────────────────────────────
  // Separate from premium emails intentionally.
  // Add emails here to grant admin access without affecting premium status.
  // ⚠️ Kept in sync manually with ADMIN_EMAILS in the Cloudflare Worker —
  // two separate deployables, no shared source of truth between them.
  // If this list ever changes, update both places.
  static const Set<String> _adminEmails = {
    'terryd0612@gmail.com',
    'liverdiseasescanner@gmail.com',
  };

  static bool get isAdmin {
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
                'This page is only accessible to admin users.',
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