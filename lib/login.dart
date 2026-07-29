// lib/login.dart
//
// ✅ Auto-clears session before every login attempt to fix Android sign-in loop
// ✅ No competing navigation
// ✅ Proper iOS auth flow
//
// 🔧 FIX: _handleError now distinguishes ProfileSetupException from
//    genuine auth errors. Previously ALL exceptions from _handleSignUp()
//    were routed through the auth error handler, which showed
//    "Hmm, who are you?" even when the real problem was a database
//    profile-creation failure.
//
// 🔧 FIX: _sendPasswordResetEmail no longer uses authError category.
//    A failed reset email is NOT an auth error — using authError caused
//    the "Hmm, who are you?" dialog to appear when the user tapped
//    "Forgot your password?".

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/auth_service.dart';
import 'services/error_handling_service.dart';
import 'config/app_config.dart';
import 'utils/screen_utils.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  StreamSubscription? _authSub;

  String _email = '';
  String _password = '';
  String _confirmPassword = '';
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _rememberMe = true;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rememberMe = prefs.getBool('remember_me') ?? true;
      final savedEmail = prefs.getString('saved_email') ?? '';
      if (mounted) {
        setState(() {
          _rememberMe = rememberMe;
          if (rememberMe && savedEmail.isNotEmpty) {
            _email = savedEmail;
            _emailController.text = savedEmail;
          }
        });
      }
    } catch (e) {
      AppConfig.debugPrint('Error loading saved credentials: $e');
    }
  }

  Future<void> _saveCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', _rememberMe);
      if (_rememberMe) {
        await prefs.setString('saved_email', _email.trim());
      } else {
        await prefs.remove('saved_email');
      }
    } catch (e) {
      AppConfig.debugPrint('Error saving credentials: $e');
    }
  }

  Future<void> _submitForm() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        await _handleLogin();
      } else {
        await _handleSignUp();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _handleError(e, isSignUp: !_isLogin);
      }
    }
  }

  /// Route errors to the right handler based on their type and origin.
  ///
  /// This replaces the old approach of treating ALL signup failures as
  /// auth errors and showing "Hmm, who are you?".
  void _handleError(dynamic error, {bool isSignUp = false}) {
    final errorMessage = error.toString();

    // Profile setup failures (signup only) — dedicated non-auth dialog
    if (error is ProfileSetupException ||
        errorMessage.contains('profile setup failed') ||
        errorMessage.contains('finish setting up your profile') ||
        errorMessage.contains('failed to create user profile')) {
      ErrorHandlingService.handleError(
        context: context,
        error: error,
        category: ErrorHandlingService.profileSetupError,
        showDialog: true,
        customMessage:
            'Your account was created! Please sign in and we\'ll finish '
            'setting up your profile.',
      );
      // Switch to sign-in mode so the user can immediately log in
      if (mounted) setState(() => _isLogin = true);
      return;
    }

    // Map error message → user-friendly string
    final String userFriendlyMessage;

    if (errorMessage.contains('Incorrect email or password') ||
        errorMessage.contains('Invalid login credentials') ||
        errorMessage.contains('Invalid email or password')) {
      userFriendlyMessage = 'Incorrect email or password. Please try again.';
    } else if (errorMessage.contains('verify your email') ||
        errorMessage.contains('Email not confirmed')) {
      userFriendlyMessage =
          'Please verify your email first. Check your inbox for the confirmation link.';
    } else if (errorMessage.contains('already registered')) {
      userFriendlyMessage =
          'This email is already registered. Try signing in instead.';
    } else if (errorMessage.contains('at least 6 characters')) {
      userFriendlyMessage = 'Password must be at least 6 characters long.';
    } else if (errorMessage.contains('timeout') ||
        errorMessage.contains('network')) {
      userFriendlyMessage =
          'Connection timed out. Please check your internet and try again.';
    } else if (errorMessage.contains('Passwords do not match')) {
      userFriendlyMessage = 'The passwords you entered don\'t match.';
    } else if (errorMessage.contains('login has expired') ||
        errorMessage.contains('Clear Session')) {
      userFriendlyMessage =
          'Session error detected. Please try the "Clear Session" button below.';
    } else if (isSignUp) {
      userFriendlyMessage =
          'Unable to create account right now. Please try again.';
    } else {
      userFriendlyMessage = 'Unable to sign in right now. Please try again.';
    }

    // Only use authError for genuine login auth failures
    final category = (!isSignUp &&
            (errorMessage.contains('Incorrect email') ||
                errorMessage.contains('verify your email') ||
                errorMessage.contains('login has expired')))
        ? ErrorHandlingService.authError
        : (isSignUp
            ? ErrorHandlingService.unknownError
            : ErrorHandlingService.authError);

    ErrorHandlingService.handleError(
      context: context,
      error: error,
      category: category,
      showSnackBar: true,
      showDialog: false,
      customMessage: userFriendlyMessage,
      onRetry: _submitForm,
    );
  }

  Future<void> _handleLogin() async {
    try {
      final trimmedEmail = _email.trim().toLowerCase();
      if (trimmedEmail.isEmpty) {
        throw Exception('Please enter your email address');
      }

      AppConfig.debugPrint('🔐 Login attempt for: $trimmedEmail');
      if (_rememberMe) await _saveCredentials();

      // Auto-clear stale session before every login attempt.
      // Fixes the Android "Hmm, who are you?" loop caused by leftover
      // session tokens from a previous sign-out.
      AppConfig.debugPrint('🧹 Auto-clearing session before login...');
      await AuthService.forceResetSession().catchError((e) {
        AppConfig.debugPrint('⚠️ Auto session clear failed (continuing): $e');
      });

      final response = await AuthService.signIn(
        email: trimmedEmail,
        password: _password,
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw Exception(
          'Login timed out. Please check your connection and try again.',
        ),
      );

      if (response.user == null || response.session == null) {
        throw Exception('Login failed - no user session created');
      }

      AppConfig.debugPrint('✅ Login successful: ${response.user?.email}');

      // Give iOS auth state time to settle
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;

      ErrorHandlingService.showSuccess(context, 'Welcome back!');

      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false);
    } catch (e) {
      AppConfig.debugPrint('❌ Login error: $e');
      rethrow;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSignUp() async {
    if (_password != _confirmPassword) {
      throw Exception('Passwords do not match');
    }
    if (_password.length < 6) {
      throw Exception('Password should be at least 6 characters');
    }

    try {
      final trimmedEmail = _email.trim().toLowerCase();
      AppConfig.debugPrint('📝 Sign up attempt for: $trimmedEmail');

      final response = await AuthService.signUp(
        email: trimmedEmail,
        password: _password,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () =>
            throw Exception('Connection timed out. Please try again.'),
      );

      if (response.user == null) {
        throw Exception('Sign up failed. Please try again.');
      }

      AppConfig.debugPrint('✅ Sign up successful: ${response.user?.email}');
      if (_rememberMe) await _saveCredentials();
      if (!mounted) return;

      if (response.session == null) {
        // Email confirmation required
        ErrorHandlingService.showSuccess(
          context,
          'Account created! Please check your email to confirm your account.',
        );
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          setState(() {
            _isLogin = true;
            _isLoading = false;
          });
        }
      } else {
        // Immediate session — no email confirmation required
        ErrorHandlingService.showSuccess(
          context,
          'Welcome to bari Food Scanner!',
        );
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Sign up error: $e');
      rethrow;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _forceResetSession() async {
    try {
      setState(() => _isLoading = true);
      await AuthService.forceResetSession();
      if (mounted) {
        ErrorHandlingService.showSuccess(
          context,
          'Session cleared! Please try logging in again.',
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'Failed to clear session: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendPasswordResetEmail() async {
    String resetEmail = _emailController.text.trim().toLowerCase();
    if (resetEmail.isEmpty) {
      resetEmail = await _showEmailInputDialog() ?? '';
    }
    if (resetEmail.isEmpty) {
      ErrorHandlingService.showSimpleError(
          // ignore: use_build_context_synchronously
          context, 'Please enter your email address');
      return;
    }
    if (!_isValidEmail(resetEmail)) {
      ErrorHandlingService.showSimpleError(
          // ignore: use_build_context_synchronously
          context, 'Please enter a valid email address');
      return;
    }

    try {
      await AuthService.resetPassword(resetEmail).timeout(
        const Duration(seconds: 10),
        onTimeout: () =>
            throw Exception('Request timed out. Please try again.'),
      );
      if (mounted) {
        ErrorHandlingService.showSuccess(
          context,
          'Password reset link sent! Check your email and spam folder.',
        );
      }
    } catch (e) {
      if (mounted) {
        // ✅ FIXED: Use unknownError not authError.
        // A failed password reset email is NOT an auth error — using
        // authError caused "Hmm, who are you?" to appear here.
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.unknownError,
          showSnackBar: true,
          showDialog: false,
          customMessage:
              'Unable to send password reset email. Please try again.',
          onRetry: _sendPasswordResetEmail,
        );
      }
    }
  }

  Future<String?> _showEmailInputDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.lock_reset, color: Colors.blue),
            SizedBox(width: 12),
            Text('Reset Password'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your email address to receive a password reset link:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Email Address',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.email_outlined),
              ),
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (v) => Navigator.pop(dialogContext, v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Send Link'),
          ),
        ],
      ),
    );
  }

  void _toggleMode() {
    setState(() {
      _isLogin = !_isLogin;
      _formKey.currentState?.reset();
      final savedEmail = _emailController.text;
      _emailController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();
      if (savedEmail.isNotEmpty && _isValidEmail(savedEmail)) {
        _emailController.text = savedEmail;
        _email = savedEmail;
      }
      _password = '';
      _confirmPassword = '';
    });
  }

  bool _isValidEmail(String email) =>
      RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email.trim());

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required';
    if (!_isValidEmail(value)) return 'Please enter a valid email address';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (!_isLogin && value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (!_isLogin) {
      if (value == null || value.isEmpty) return 'Please confirm your password';
      if (value != _passwordController.text) return 'Passwords do not match';
    }
    return null;
  }

  // --------------------------------------------------------
  // BUILD
  // --------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final maxWidth = isTablet ? 500.0 : screenWidth;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isLogin ? 'Sign In' : 'Create Account'),
        centerTitle: true,
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(
              ScreenUtils.getBackgroundImage(context, type: 'login'),
            ),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.1),
              BlendMode.darken,
            ),
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(
                ScreenUtils.getResponsivePadding(context),
              ),
              child: Container(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  color: Colors.white.withValues(alpha: 0.95),
                  child: Padding(
                    padding: EdgeInsets.all(
                      ScreenUtils.getResponsivePadding(context),
                    ),
                    child: AutofillGroup(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(
                              Icons.restaurant_menu,
                              size: ScreenUtils.getIconSize(context,
                                  baseSize: 64),
                              color: Colors.orange.shade600,
                            ),
                            SizedBox(height: isTablet ? 24 : 16),
                            Text(
                              _isLogin
                                  ? 'Welcome Back!'
                                  : 'Create Your Account',
                              style: TextStyle(
                                fontSize: (isTablet ? 28 : 24) *
                                    ScreenUtils.getFontSizeMultiplier(
                                        context),
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade800,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isLogin
                                  ? 'Sign in to access your recipes'
                                  : 'Join to unlock all features',
                              style: TextStyle(
                                fontSize: (isTablet ? 16 : 14) *
                                    ScreenUtils.getFontSizeMultiplier(
                                        context),
                                color: Colors.grey.shade600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: isTablet ? 40 : 32),

                            // Email field
                            TextFormField(
                              controller: _emailController,
                              decoration: InputDecoration(
                                labelText: 'Email Address',
                                prefixIcon:
                                    const Icon(Icons.email_outlined),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              validator: _validateEmail,
                              onSaved: (val) => _email = val?.trim() ?? '',
                              autocorrect: false,
                              enableSuggestions: false,
                              autofillHints: const [AutofillHints.email],
                            ),
                            const SizedBox(height: 16),

                            // Password field
                            TextFormField(
                              controller: _passwordController,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined),
                                  onPressed: () => setState(() =>
                                      _obscurePassword = !_obscurePassword),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              obscureText: _obscurePassword,
                              textInputAction: _isLogin
                                  ? TextInputAction.done
                                  : TextInputAction.next,
                              validator: _validatePassword,
                              onSaved: (val) => _password = val ?? '',
                              autocorrect: false,
                              enableSuggestions: false,
                              autofillHints: _isLogin
                                  ? const [AutofillHints.password]
                                  : const [AutofillHints.newPassword],
                              onFieldSubmitted:
                                  _isLogin ? (_) => _submitForm() : null,
                            ),

                            // Confirm password (sign up only)
                            if (!_isLogin) ...[
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _confirmPasswordController,
                                decoration: InputDecoration(
                                  labelText: 'Confirm Password',
                                  prefixIcon:
                                      const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscureConfirmPassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined),
                                    onPressed: () => setState(() =>
                                        _obscureConfirmPassword =
                                            !_obscureConfirmPassword),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                obscureText: _obscureConfirmPassword,
                                textInputAction: TextInputAction.done,
                                validator: _validateConfirmPassword,
                                onSaved: (val) =>
                                    _confirmPassword = val ?? '',
                                autocorrect: false,
                                enableSuggestions: false,
                                autofillHints: const [
                                  AutofillHints.newPassword
                                ],
                                onFieldSubmitted: (_) => _submitForm(),
                              ),
                            ],

                            // Remember me (login only)
                            if (_isLogin) ...[
                              const SizedBox(height: 16),
                              InkWell(
                                onTap: () => setState(
                                    () => _rememberMe = !_rememberMe),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 4),
                                  child: Row(
                                    children: [
                                      Checkbox(
                                        value: _rememberMe,
                                        onChanged: (value) => setState(
                                            () => _rememberMe =
                                                value ?? true),
                                        activeColor: Colors.orange.shade600,
                                      ),
                                      Expanded(
                                        child: Text(
                                          'Remember me',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey.shade800,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],

                            SizedBox(height: isTablet ? 32 : 24),

                            // Submit button
                            SizedBox(
                              height: ScreenUtils.getButtonHeight(context),
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _submitForm,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange.shade600,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      Colors.grey.shade300,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 2,
                                ),
                                child: _isLoading
                                    ? Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            _isLogin
                                                ? 'Signing In...'
                                                : 'Creating Account...',
                                            style: TextStyle(
                                              fontSize: (isTablet ? 18 : 16) *
                                                  ScreenUtils
                                                      .getFontSizeMultiplier(
                                                          context),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Text(
                                        _isLogin
                                            ? 'Sign In'
                                            : 'Create Account',
                                        style: TextStyle(
                                          fontSize: (isTablet ? 18 : 16) *
                                              ScreenUtils.getFontSizeMultiplier(
                                                  context),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),

                            // Forgot password + Clear session (login only)
                            if (_isLogin) ...[
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed:
                                    _isLoading ? null : _sendPasswordResetEmail,
                                child: Text(
                                  'Forgot your password?',
                                  style: TextStyle(
                                    color: Colors.orange.shade600,
                                    fontSize: (isTablet ? 16 : 14) *
                                        ScreenUtils.getFontSizeMultiplier(
                                            context),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed:
                                    _isLoading ? null : _forceResetSession,
                                icon: const Icon(Icons.refresh,
                                    size: 16, color: Colors.orange),
                                label: Text(
                                  'Having login issues? Clear session',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange.shade700,
                                  ),
                                ),
                              ),
                            ],

                            SizedBox(height: isTablet ? 32 : 24),

                            // OR divider
                            Row(
                              children: [
                                const Expanded(child: Divider()),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  child: Text(
                                    'OR',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                      fontSize: isTablet ? 14 : 12,
                                    ),
                                  ),
                                ),
                                const Expanded(child: Divider()),
                              ],
                            ),

                            SizedBox(height: isTablet ? 32 : 24),

                            // Toggle sign-in / sign-up
                            TextButton(
                              onPressed: _isLoading ? null : _toggleMode,
                              child: RichText(
                                textAlign: TextAlign.center,
                                text: TextSpan(
                                  style: TextStyle(
                                    fontSize: (isTablet ? 16 : 14) *
                                        ScreenUtils.getFontSizeMultiplier(
                                            context),
                                    color: Colors.grey.shade800,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: _isLogin
                                          ? "Don't have an account? "
                                          : 'Already have an account? ',
                                    ),
                                    TextSpan(
                                      text:
                                          _isLogin ? 'Create one' : 'Sign in',
                                      style: TextStyle(
                                        color: Colors.orange.shade600,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
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
          ),
        ),
      ),
    );
  }
}