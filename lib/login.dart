// lib/login.dart - DEBUG VERSION WITH COMPREHENSIVE LOGGING

import 'package:supabase_flutter/supabase_flutter.dart';
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
    _setupAuthListener();
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
        _handleAuthError(e);
      }
    }
  }

  void _handleAuthError(dynamic error) {
    String errorMessage = error.toString();
    String userFriendlyMessage;

    if (errorMessage.contains('Invalid login credentials') || 
        errorMessage.contains('Invalid email or password')) {
      userFriendlyMessage = 'Incorrect email or password. Please try again.';
    } else if (errorMessage.contains('Email not confirmed')) {
      userFriendlyMessage = 'Please verify your email first. Check your inbox for the confirmation link.';
    } else if (errorMessage.contains('User already registered')) {
      userFriendlyMessage = 'This email is already registered. Try signing in instead.';
    } else if (errorMessage.contains('Password should be at least 6 characters')) {
      userFriendlyMessage = 'Password must be at least 6 characters long.';
    } else if (errorMessage.contains('timeout') || errorMessage.contains('network')) {
      userFriendlyMessage = 'Connection timed out. Please check your internet and try again.';
    } else if (errorMessage.contains('Passwords do not match')) {
      userFriendlyMessage = 'The passwords you entered don\'t match.';
    } else if (errorMessage.contains('row-level security') || errorMessage.contains('RLS')) {
      userFriendlyMessage = 'Account setup failed. Please contact support if this continues.';
    } else if (errorMessage.contains('session') || errorMessage.contains('expired')) {
      userFriendlyMessage = 'Session error detected. Please try the "Clear Session" button below.';
    } else {
      userFriendlyMessage = 'Unable to sign in right now. Please try again.';
    }

    ErrorHandlingService.handleError(
      context: context,
      error: error,
      category: ErrorHandlingService.authError,
      showSnackBar: true,
      customMessage: userFriendlyMessage,
      onRetry: _submitForm,
    );
  }

  Future<void> _handleLogin() async {
    print('\n========================================');
    print('🟢 LOGIN PAGE: Starting login handler');
    print('========================================');
    
    try {
      final trimmedEmail = _email.trim().toLowerCase();
      
      if (trimmedEmail.isEmpty) {
        throw Exception('Please enter your email address');
      }

      print('🟢 LOGIN PAGE: Email: $trimmedEmail');
      print('🟢 LOGIN PAGE: Remember me: $_rememberMe');

      if (_rememberMe) {
        print('🟢 LOGIN PAGE: Saving credentials...');
        await _saveCredentials();
        print('🟢 LOGIN PAGE: ✅ Credentials saved');
      }

      print('🟢 LOGIN PAGE: Calling AuthService.signIn...');
      final response = await AuthService.signIn(
        email: trimmedEmail,
        password: _password,
      );

      print('🟢 LOGIN PAGE: AuthService.signIn returned');
      print('  - User ID: ${response.user?.id}');
      print('  - User Email: ${response.user?.email}');
      print('  - Session exists: ${response.session != null}');
      print('  - Access token exists: ${response.session?.accessToken != null}');

      // ✅ CRITICAL: Verify we actually got authenticated
      if (response.user == null || response.session == null) {
        print('🟢 LOGIN PAGE: ❌ CRITICAL - No user or session!');
        throw Exception('Login failed - no user session created');
      }

      print('🟢 LOGIN PAGE: ✅ Login successful!');
      print('  - User ID: ${response.user!.id}');
      
      // Wait for auth state to settle
      print('🟢 LOGIN PAGE: Waiting 800ms for auth state to settle...');
      await Future.delayed(const Duration(milliseconds: 800));
      
      if (!mounted) {
        print('🟢 LOGIN PAGE: ⚠️ Widget unmounted, aborting navigation');
        return;
      }

      print('🟢 LOGIN PAGE: Showing success message...');
      ErrorHandlingService.showSuccess(context, 'Welcome back!');
      
      await Future.delayed(const Duration(milliseconds: 300));
      
      if (!mounted) {
        print('🟢 LOGIN PAGE: ⚠️ Widget unmounted after success message');
        return;
      }

      print('🟢 LOGIN PAGE: Navigating to /home...');
      Navigator.pushNamedAndRemoveUntil(
        context, 
        '/home',
        (route) => false,
      );
      
      print('🟢 LOGIN PAGE: ✅ Navigation complete');
      print('========================================\n');

    } catch (e) {
      print('🟢 LOGIN PAGE: ❌ Login handler error: $e');
      print('🟢 LOGIN PAGE: Error type: ${e.runtimeType}');
      print('========================================\n');
      rethrow;
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleSignUp() async {
    print('\n========================================');
    print('🟢 SIGNUP PAGE: Starting signup handler');
    print('========================================');
    
    if (_password != _confirmPassword) {
      print('🟢 SIGNUP PAGE: ❌ Passwords do not match');
      throw Exception('Passwords do not match');
    }

    if (_password.length < 6) {
      print('🟢 SIGNUP PAGE: ❌ Password too short');
      throw Exception('Password should be at least 6 characters');
    }

    try {
      final trimmedEmail = _email.trim().toLowerCase();
      
      print('🟢 SIGNUP PAGE: Email: $trimmedEmail');
      print('🟢 SIGNUP PAGE: Password length: ${_password.length}');
      print('🟢 SIGNUP PAGE: Calling AuthService.signUp...');

      final startTime = DateTime.now();
      
      final response = await AuthService.signUp(
        email: trimmedEmail,
        password: _password,
      ).timeout(
        const Duration(seconds: 30), // Increased from 15s
        onTimeout: () {
          print('🟢 SIGNUP PAGE: ❌ TIMEOUT after 30 seconds');
          throw Exception('Connection timed out. Please try again.');
        },
      );

      final duration = DateTime.now().difference(startTime);
      print('🟢 SIGNUP PAGE: AuthService.signUp completed in ${duration.inSeconds}s');

      print('🟢 SIGNUP PAGE: Signup response received:');
      print('  - User ID: ${response.user?.id}');
      print('  - User Email: ${response.user?.email}');
      print('  - Session exists: ${response.session != null}');
      print('  - Access token exists: ${response.session?.accessToken != null}');

      if (response.user != null) {
        print('🟢 SIGNUP PAGE: ✅ User created successfully!');
        print('  - User ID: ${response.user!.id}');
        
        if (_rememberMe) {
          print('🟢 SIGNUP PAGE: Saving credentials...');
          await _saveCredentials();
        }

        if (mounted) {
          if (response.session == null) {
            print('🟢 SIGNUP PAGE: ⚠️ No session - email confirmation required');
            ErrorHandlingService.showSuccess(
              context,
              'Account created! Please check your email to confirm your account.'
            );
            
            await Future.delayed(const Duration(seconds: 2));
            
            if (mounted) {
              print('🟢 SIGNUP PAGE: Switching to login mode');
              setState(() {
                _isLogin = true;
                _isLoading = false;
              });
            }
          } else {
            print('🟢 SIGNUP PAGE: ✅ Session exists - auto-login successful!');
            print('  - Token preview: ${response.session!.accessToken.substring(0, 20)}...');
            
            ErrorHandlingService.showSuccess(context, 'Welcome to bari Food Scanner!');
            await Future.delayed(const Duration(milliseconds: 500));
            
            if (!mounted) {
              print('🟢 SIGNUP PAGE: ⚠️ Widget unmounted before navigation');
              return;
            }
            
            print('🟢 SIGNUP PAGE: Navigating to /home...');
            Navigator.pushReplacementNamed(context, '/home');
            print('🟢 SIGNUP PAGE: ✅ Navigation complete');
          }
        }
      } else {
        print('🟢 SIGNUP PAGE: ❌ No user in response');
        throw Exception('Sign up failed. Please try again.');
      }
      
      print('========================================\n');
    } catch (e) {
      print('🟢 SIGNUP PAGE: ❌ Signup handler error: $e');
      print('🟢 SIGNUP PAGE: Error type: ${e.runtimeType}');
      print('========================================\n');
      rethrow;
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _forceResetSession() async {
    try {
      setState(() => _isLoading = true);
      
      print('🟢 LOGIN PAGE: User requested session reset');
      await AuthService.forceResetSession();
      
      if (mounted) {
        ErrorHandlingService.showSuccess(
          context,
          'Session cleared! Please try logging in again.',
        );
      }
    } catch (e) {
      print('🟢 LOGIN PAGE: Session reset failed: $e');
      if (mounted) {
        ErrorHandlingService.showSimpleError(
          context,
          'Failed to clear session: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sendPasswordResetEmail() async {
    String resetEmail = _emailController.text.trim().toLowerCase();

    if (resetEmail.isEmpty) {
      resetEmail = await _showEmailInputDialog() ?? '';
    }

    if (resetEmail.isEmpty) {
      ErrorHandlingService.showSimpleError(context, 'Please enter your email address');
      return;
    }

    if (!_isValidEmail(resetEmail)) {
      ErrorHandlingService.showSimpleError(context, 'Please enter a valid email address');
      return;
    }

    try {
      await AuthService.resetPassword(resetEmail).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Request timed out. Please try again.');
        },
      );

      if (mounted) {
        ErrorHandlingService.showSuccess(
          context,
          'Password reset link sent! Check your email and spam folder.'
        );
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.authError,
          customMessage: 'Unable to send password reset email. Please try again.',
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.email_outlined),
              ),
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
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

  void _setupAuthListener() {
    print('🟢 LOGIN PAGE: Setting up auth state listener...');
    _authSub = AuthService.authStateChanges.listen((data) {
      final event = data.event;
      final session = data.session;

      if (!mounted) return;

      print('🟢 LOGIN PAGE: Auth state change detected');
      print('  - Event: $event');
      print('  - Session exists: ${session != null}');
      print('  - User: ${session?.user.email}');

      // ✅ CRITICAL: Only log, don't navigate from here
      switch (event) {
        case AuthChangeEvent.signedIn:
          print('🟢 LOGIN PAGE: 🔐 Auth event: User signed in');
          break;
        case AuthChangeEvent.signedOut:
          print('🟢 LOGIN PAGE: 🔓 Auth event: User signed out');
          break;
        case AuthChangeEvent.passwordRecovery:
          print('🟢 LOGIN PAGE: 🔑 Auth event: Password recovery');
          break;
        default:
          print('🟢 LOGIN PAGE: Auth event: $event');
          break;
      }
    });
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

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email.trim());
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    if (!_isValidEmail(value)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (!_isLogin && value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (!_isLogin) {
      if (value == null || value.isEmpty) {
        return 'Please confirm your password';
      }
      if (value != _passwordController.text) {
        return 'Passwords do not match';
      }
    }
    return null;
  }

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
              Colors.black.withOpacity(0.1),
              BlendMode.darken,
            ),
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(ScreenUtils.getResponsivePadding(context)),
              child: Container(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  color: Colors.white.withOpacity(0.95),
                  child: Padding(
                    padding: EdgeInsets.all(ScreenUtils.getResponsivePadding(context)),
                    child: AutofillGroup(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(
                              Icons.restaurant_menu,
                              size: ScreenUtils.getIconSize(context, baseSize: 64),
                              color: Colors.orange.shade600,
                            ),
                            SizedBox(height: isTablet ? 24 : 16),
                            Text(
                              _isLogin ? 'Welcome Back!' : 'Create Your Account',
                              style: TextStyle(
                                fontSize: (isTablet ? 28 : 24) * ScreenUtils.getFontSizeMultiplier(context),
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade800,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 8),
                            Text(
                              _isLogin 
                                  ? 'Sign in to access your recipes'
                                  : 'Join to unlock all features',
                              style: TextStyle(
                                fontSize: (isTablet ? 16 : 14) * ScreenUtils.getFontSizeMultiplier(context),
                                color: Colors.grey.shade600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: isTablet ? 40 : 32),
                            
                            // Email Field
                            TextFormField(
                              controller: _emailController,
                              decoration: InputDecoration(
                                labelText: "Email Address",
                                prefixIcon: const Icon(Icons.email_outlined),
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
                            
                            // Password Field
                            TextFormField(
                              controller: _passwordController,
                              decoration: InputDecoration(
                                labelText: "Password",
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscurePassword 
                                      ? Icons.visibility_outlined 
                                      : Icons.visibility_off_outlined
                                  ),
                                  onPressed: () => setState(() => 
                                      _obscurePassword = !_obscurePassword
                                  ),
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
                              onFieldSubmitted: _isLogin 
                                  ? (_) => _submitForm() 
                                  : null,
                            ),
                            
                            // Confirm Password (Sign Up Only)
                            if (!_isLogin) ...[
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _confirmPasswordController,
                                decoration: InputDecoration(
                                  labelText: "Confirm Password",
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscureConfirmPassword 
                                        ? Icons.visibility_outlined 
                                        : Icons.visibility_off_outlined
                                    ),
                                    onPressed: () => setState(() => 
                                        _obscureConfirmPassword = !_obscureConfirmPassword
                                    ),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                obscureText: _obscureConfirmPassword,
                                textInputAction: TextInputAction.done,
                                validator: _validateConfirmPassword,
                                onSaved: (val) => _confirmPassword = val ?? '',
                                autocorrect: false,
                                enableSuggestions: false,
                                autofillHints: const [AutofillHints.newPassword],
                                onFieldSubmitted: (_) => _submitForm(),
                              ),
                            ],
                            
                            // Remember Me (Login Only)
                            if (_isLogin) ...[
                              const SizedBox(height: 16),
                              InkWell(
                                onTap: () => setState(() => _rememberMe = !_rememberMe),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Checkbox(
                                        value: _rememberMe,
                                        onChanged: (value) => setState(() => 
                                            _rememberMe = value ?? true
                                        ),
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
                            
                            // Submit Button
                            SizedBox(
                              height: ScreenUtils.getButtonHeight(context),
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _submitForm,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange.shade600,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: Colors.grey.shade300,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 2,
                                ),
                                child: _isLoading 
                                    ? Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
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
                                            _isLogin ? 'Signing In...' : 'Creating Account...',
                                            style: TextStyle(
                                              fontSize: (isTablet ? 18 : 16) * ScreenUtils.getFontSizeMultiplier(context),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Text(
                                        _isLogin ? 'Sign In' : 'Create Account',
                                        style: TextStyle(
                                          fontSize: (isTablet ? 18 : 16) * ScreenUtils.getFontSizeMultiplier(context),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),
                            
                            // Forgot Password + Debug Session Reset (Login Only)
                            if (_isLogin) ...[
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: _isLoading ? null : _sendPasswordResetEmail,
                                child: Text(
                                  "Forgot your password?",
                                  style: TextStyle(
                                    color: Colors.orange.shade600,
                                    fontSize: (isTablet ? 16 : 14) * ScreenUtils.getFontSizeMultiplier(context),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              
                              // Debug Session Reset Button
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: _isLoading ? null : _forceResetSession,
                                icon: const Icon(Icons.refresh, size: 16, color: Colors.red),
                                label: Text(
                                  "Clear Session & Retry",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ),
                            ],
                            
                            SizedBox(height: isTablet ? 32 : 24),
                            
                            // Divider
                            Row(
                              children: [
                                const Expanded(child: Divider()),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
                            
                            // Toggle Mode Button
                            TextButton(
                              onPressed: _isLoading ? null : _toggleMode,
                              child: RichText(
                                textAlign: TextAlign.center,
                                text: TextSpan(
                                  style: TextStyle(
                                    fontSize: (isTablet ? 16 : 14) * ScreenUtils.getFontSizeMultiplier(context),
                                    color: Colors.grey.shade800,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: _isLogin 
                                          ? "Don't have an account? "
                                          : "Already have an account? ",
                                    ),
                                    TextSpan(
                                      text: _isLogin ? 'Create one' : 'Sign in',
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