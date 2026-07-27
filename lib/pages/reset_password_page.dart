// lib/pages/reset_password_page.dart
//
// ✅ Works with onAuthStateChange password recovery flow in main.dart
// ✅ Session is already active when this page opens — no setSession needed
// ✅ Handles expired/invalid links gracefully (no black screen)
// ✅ Signs user out after reset so they log in fresh
// ✅ Matches app orange theme

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../config/app_config.dart';

class ResetPasswordPage extends StatefulWidget {
  // Session is passed in for reference but Supabase has already applied
  // it via onAuthStateChange before this page is pushed. A null session
  // means the link was invalid or expired.
  final Session? session;

  const ResetPasswordPage({super.key, this.session});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _passwordController = TextEditingController();
  final _confirmController  = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm  = true;
  bool _loading         = false;
  bool _success         = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    final confirm  = _confirmController.text;

    if (password.isEmpty || confirm.isEmpty) {
      _showError('Please fill all fields.');
      return;
    }
    if (password != confirm) {
      _showError('Passwords do not match.');
      return;
    }
    if (password.length < 6) {
      _showError('Password must be at least 6 characters long.');
      return;
    }

    setState(() => _loading = true);

    try {
      // The session was already set by Supabase's onAuthStateChange
      // (passwordRecovery event) in main.dart before this page was pushed.
      // We just call updatePassword directly — no setSession needed.
      AppConfig.debugPrint('🔑 Submitting new password...');
      await AuthService.updatePassword(password);
      AppConfig.debugPrint('✅ Password updated successfully');

      if (!mounted) return;
      setState(() => _success = true);

      // Brief pause so user sees the success state, then sign out
      // and redirect so they log in fresh with the new password.
      await Future.delayed(const Duration(seconds: 2));

      try {
        await Supabase.instance.client.auth.signOut();
      } catch (e) {
        AppConfig.debugPrint(
            '⚠️ signOut after reset failed (continuing): $e');
      }

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
          context, '/login', (route) => false);
    } catch (e) {
      AppConfig.debugPrint('❌ Password reset error: $e');
      _showError(
        'Failed to reset password. Your link may have expired — '
        'please request a new one.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _goToLogin() {
    Navigator.pushNamedAndRemoveUntil(
        context, '/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet    = screenWidth > 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset Password'),
        centerTitle: true,
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goToLogin,
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/backgrounds/login_background.jpeg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isTablet ? 32.0 : 24.0),
              child: Container(
                constraints: BoxConstraints(
                    maxWidth: isTablet ? 500.0 : screenWidth),
                padding: EdgeInsets.all(isTablet ? 40.0 : 28.0),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: _success
                    ? _buildSuccess()
                    : widget.session == null
                        ? _buildInvalidLink()
                        : _buildForm(isTablet),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Success state ──────────────────────────────────────────────

  Widget _buildSuccess() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_circle_rounded,
            size: 72,
            color: Colors.green.shade600,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Password Updated!',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Your password has been changed successfully. '
          'Redirecting you to sign in...',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        const CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
        ),
      ],
    );
  }

  // ── Invalid / expired link state ───────────────────────────────

  Widget _buildInvalidLink() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.link_off_rounded,
            size: 72,
            color: Colors.orange.shade600,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Link Expired or Invalid',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'This password reset link has expired or is no longer valid. '
          'Please go back and request a new one.',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 52,
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _goToLogin,
            icon: const Icon(Icons.arrow_back),
            label: const Text(
              'Back to Sign In',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Password form ──────────────────────────────────────────────

  Widget _buildForm(bool isTablet) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.lock_reset_rounded,
          size: isTablet ? 72 : 60,
          color: Colors.orange.shade600,
        ),
        SizedBox(height: isTablet ? 24 : 16),
        Text(
          'Create New Password',
          style: TextStyle(
            fontSize: isTablet ? 26 : 22,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Enter your new password below.',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: isTablet ? 36 : 28),

        // New Password
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'New Password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: () => setState(
                  () => _obscurePassword = !_obscurePassword),
            ),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
        ),
        const SizedBox(height: 16),

        // Confirm Password
        TextField(
          controller: _confirmController,
          obscureText: _obscureConfirm,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Confirm Password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirm
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
        ),
        const SizedBox(height: 28),

        // Submit Button
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _loading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade600,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 2,
            ),
            child: _loading
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Updating...',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ],
                  )
                : const Text(
                    'Reset Password',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
        const SizedBox(height: 16),

        // Back to login
        TextButton(
          onPressed: _goToLogin,
          child: Text(
            'Back to Sign In',
            style: TextStyle(
              color: Colors.orange.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}