// lib/contact_screen.dart - IMPROVED: Real-time validation, character count, and fixed email
import 'package:flutter/material.dart';
import 'package:bari_wise/services/contact_service.dart';
import 'widgets/app_drawer.dart';

class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // 🔥 Real-time validation states
  String? _emailError;
  int _messageLength = 0;
  bool _isEmailValid = false;
  bool _isSending = false;  // 🔥 NEW: Track sending state

  @override
  void initState() {
    super.initState();
    // 🔥 Add listeners for real-time updates
    _emailController.addListener(_validateEmail);
    _messageController.addListener(_updateMessageLength);
  }

  // 🔥 Real-time email validation
  void _validateEmail() {
    final email = _emailController.text.trim();
    setState(() {
      if (email.isEmpty) {
        _emailError = null;
        _isEmailValid = false;
      } else if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
        _emailError = 'Please enter a valid email address';
        _isEmailValid = false;
      } else {
        _emailError = null;
        _isEmailValid = true;
      }
    });
  }

  // 🔥 Real-time message length counter
  void _updateMessageLength() {
    setState(() {
      _messageLength = _messageController.text.length;
    });
  }

  // 🔥 IMPROVED: Better error handling and validation
  Future<void> _submitForm() async {
    // Validate form
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fix the errors before submitting'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check if already sending
    if (_isSending) return;

    setState(() {
      _isSending = true;
    });

    try {
      print('📤 Submitting contact form...');
      print('Name: ${_nameController.text}');
      print('Email: ${_emailController.text}');
      print('Message length: ${_messageController.text.length}');

      // Show loading snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Sending message...'),
            ],
          ),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 30),
        ),
      );

      // Submit the form
      await ContactService.submitContactMessage(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        message: _messageController.text.trim(),
      );

      print('✅ Contact form submitted successfully');

      if (!mounted) return;

      // Clear the loading snackbar
      ScaffoldMessenger.of(context).clearSnackBars();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text('Thank you for your message! We\'ll get back to you soon.'),
              ),
            ],
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );

      // Clear form
      _nameController.clear();
      _emailController.clear();
      _messageController.clear();

      // Reset validation states
      setState(() {
        _emailError = null;
        _isEmailValid = false;
        _messageLength = 0;
      });
    } catch (error, stackTrace) {
      print('❌ Error submitting contact form: $error');
      print('Stack trace: $stackTrace');

      if (!mounted) return;

      // Clear the loading snackbar
      ScaffoldMessenger.of(context).clearSnackBars();

      // Determine error message
      String errorMessage = 'Failed to send message. Please try again.';
      
      final errorString = error.toString().toLowerCase();
      if (errorString.contains('network') || errorString.contains('socket')) {
        errorMessage = 'Network error. Please check your connection and try again.';
      } else if (errorString.contains('timeout')) {
        errorMessage = 'Request timed out. Please try again.';
      } else if (errorString.contains('authentication') || errorString.contains('401')) {
        errorMessage = 'Authentication error. Please sign out and back in.';
      }

      // Show error message with retry option
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(errorMessage)),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: _submitForm,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.removeListener(_validateEmail);
    _messageController.removeListener(_updateMessageLength);
    _nameController.dispose();
    _emailController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact Us'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      drawer: const AppDrawer(currentPage: 'contact'),
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Image.asset(
              'assets/backgrounds/background.jpeg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(color: Colors.grey[100]);
              },
            ),
          ),
          // Content
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Contact Info Section
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha((0.95 * 255).toInt()),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha((0.1 * 255).toInt()),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Column(
                    children: [
                      Icon(
                        Icons.contact_mail,
                        size: 50,
                        color: Colors.blue,
                      ),
                      SizedBox(height: 15),
                      Text(
                        'Get in Touch',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'We\'d love to hear from you! Send us a message and we\'ll respond as soon as possible.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Contact Form
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha((0.1 * 255).toInt()),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Send us a Message',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),

                        // Name Field
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Name',
                            prefixIcon: Icon(Icons.person),
                            border: OutlineInputBorder(),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.blue, width: 2),
                            ),
                          ),
                          enabled: !_isSending,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 15),

                        // 🔥 IMPROVED: Email Field with real-time validation
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: _emailController,
                              decoration: InputDecoration(
                                labelText: 'Email',
                                prefixIcon: const Icon(Icons.email),
                                suffixIcon: _emailController.text.isNotEmpty
                                    ? Icon(
                                        _isEmailValid ? Icons.check_circle : Icons.error,
                                        color: _isEmailValid ? Colors.orange : Colors.red,
                                      )
                                    : null,
                                border: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: _emailError != null ? Colors.red : Colors.grey,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: _emailError != null ? Colors.red : Colors.blue,
                                    width: 2,
                                  ),
                                ),
                                errorBorder: const OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.red, width: 2),
                                ),
                              ),
                              keyboardType: TextInputType.emailAddress,
                              enabled: !_isSending,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your email';
                                }
                                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                                  return 'Please enter a valid email';
                                }
                                return null;
                              },
                            ),
                            // 🔥 Real-time error message
                            if (_emailError != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 12, top: 6),
                                child: Text(
                                  _emailError!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            // 🔥 Success indicator
                            if (_isEmailValid && _emailError == null)
                              Padding(
                                padding: const EdgeInsets.only(left: 12, top: 6),
                                child: Row(
                                  children: [
                                    Icon(Icons.check_circle, size: 16, color: Colors.orange),
                                    SizedBox(width: 4),
                                    Text(
                                      'Valid email address',
                                      style: TextStyle(
                                        color: Colors.orange,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 15),

                        // 🔥 IMPROVED: Message Field with character counter
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: _messageController,
                              decoration: const InputDecoration(
                                labelText: 'Message',
                                prefixIcon: Icon(Icons.message),
                                border: OutlineInputBorder(),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.blue, width: 2),
                                ),
                                alignLabelWithHint: true,
                                helperText: '', // Reserve space for helper
                              ),
                              maxLines: 5,
                              maxLength: 500,
                              enabled: !_isSending,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your message';
                                }
                                if (value.trim().length < 10) {
                                  return 'Message must be at least 10 characters long';
                                }
                                return null;
                              },
                            ),
                            // 🔥 Character count indicator
                            Padding(
                              padding: const EdgeInsets.only(left: 12, top: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.text_fields,
                                    size: 14,
                                    color: _messageLength < 10 ? Colors.orange : Colors.orange,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$_messageLength/500 characters',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _messageLength < 10 ? Colors.orange : Colors.orange,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (_messageLength < 10)
                                    Text(
                                      ' (${10 - _messageLength} more needed)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // 🔥 Progress bar
                            Padding(
                              padding: const EdgeInsets.only(left: 12, top: 8, right: 12),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: (_messageLength / 500).clamp(0.0, 1.0),
                                  backgroundColor: Colors.grey.shade200,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _messageLength < 10
                                        ? Colors.orange
                                        : _messageLength > 450
                                            ? Colors.red
                                            : Colors.orange,
                                  ),
                                  minHeight: 6,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Submit Button
                        ElevatedButton(
                          onPressed: _isSending ? null : _submitForm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 3,
                            disabledBackgroundColor: Colors.grey,
                          ),
                          child: _isSending
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text(
                                  'Send Message',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Contact Details - 🔥 FIXED: Correct email address
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha((0.95 * 255).toInt()),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha((0.1 * 255).toInt()),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Other Ways to Reach Us',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // 🔥 FIXED: Changed from baridiseasescanner@gmail.com to bbrc2021bbc1298.442@icloud.com
                      _buildContactRow(Icons.email, 'bbrc2021bbc1298.442@icloud.com'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // FAQ Section
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.blue.withAlpha((0.1 * 255).toInt()),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.blue.withAlpha((0.3 * 255).toInt())),
                  ),
                  child: const Column(
                    children: [
                      Icon(
                        Icons.help_outline,
                        size: 40,
                        color: Colors.blue,
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Quick Help',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'For technical support or app-related questions, please include your device model and app version in your message.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: Colors.blue, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }
}