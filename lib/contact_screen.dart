// lib/contact_screen.dart - IMPROVED: Real-time validation & character count
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

  // 🔥 NEW: Real-time validation states
  String? _emailError;
  int _messageLength = 0;
  bool _isEmailValid = false;

  @override
  void initState() {
    super.initState();
    
    // 🔥 NEW: Add listeners for real-time updates
    _emailController.addListener(_validateEmail);
    _messageController.addListener(_updateMessageLength);
  }

  // 🔥 NEW: Real-time email validation
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

  // 🔥 NEW: Real-time message length counter
  void _updateMessageLength() {
    setState(() {
      _messageLength = _messageController.text.length;
    });
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      try {
        // Show loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sending message...')),
        );

        await ContactService.submitContactMessage(
          name: _nameController.text,
          email: _emailController.text,
          message: _messageController.text,
        );

        // Success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Thank you for your message! We\'ll get back to you soon.'),
              backgroundColor: Colors.orange,
            ),
          );

          // Clear form
          _nameController.clear();
          _emailController.clear();
          _messageController.clear();
        }

      } catch (error) {
        // Error handling
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to send message. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
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
      drawer: AppDrawer(currentPage: 'contact'),
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Image.asset(
              'assets/backgrounds/background.jpeg',
              fit: BoxFit.cover,
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
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
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
                    color: Colors.white.withValues(alpha: 1.0),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
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
                          validator: (value) {
                            if (value == null || value.isEmpty) {
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
                                    color: _emailError != null 
                                        ? Colors.red 
                                        : Colors.blue,
                                    width: 2,
                                  ),
                                ),
                                errorBorder: const OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.red, width: 2),
                                ),
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your email';
                                }
                                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                                  return 'Please enter a valid email';
                                }
                                return null;
                              },
                            ),
                            
                            // 🔥 NEW: Real-time error message
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
                            
                            // 🔥 NEW: Success indicator
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
                              decoration: InputDecoration(
                                labelText: 'Message',
                                prefixIcon: const Icon(Icons.message),
                                border: const OutlineInputBorder(),
                                focusedBorder: const OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.blue, width: 2),
                                ),
                                alignLabelWithHint: true,
                                // 🔥 NEW: Character counter in hint
                                helperText: '', // Reserve space for helper
                              ),
                              maxLines: 5,
                              maxLength: 500, // Add max length
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your message';
                                }
                                if (value.length < 10) {
                                  return 'Message must be at least 10 characters long';
                                }
                                return null;
                              },
                            ),
                            
                            // 🔥 NEW: Character count indicator
                            Padding(
                              padding: const EdgeInsets.only(left: 12, top: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.text_fields,
                                    size: 14,
                                    color: _messageLength < 10 
                                        ? Colors.orange 
                                        : Colors.orange,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    '$_messageLength/500 characters',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _messageLength < 10 
                                          ? Colors.orange 
                                          : Colors.orange,
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
                            
                            // 🔥 NEW: Progress bar
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
                          onPressed: _submitForm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 3,
                          ),
                          child: const Text(
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

                // Contact Details
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
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
                      _buildContactRow(Icons.email, 'baridiseasescanner@gmail.com'),                     
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // FAQ Section
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
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