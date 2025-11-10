// lib/pages/profile_screen.dart - UPDATED: Added Recipe Management with Ratings
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/app_drawer.dart';
import '../widgets/premium_gate.dart';
import '../widgets/recipe_card.dart';
import '../controllers/premium_gate_controller.dart';
import '../models/submitted_recipe.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../services/error_handling_service.dart';
import '../pages/user_profile_page.dart';
import '../pages/edit_recipe_page.dart';

class ProfileScreen extends StatefulWidget {
  final List<String> favoriteRecipes;

  const ProfileScreen({super.key, required this.favoriteRecipes});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with AutomaticKeepAliveClientMixin {
  File? _profileImage;
  File? _backgroundImage;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  bool _isEditingName = false;
  bool _isEditingEmail = false;
  String _userName = 'User';
  String _userEmail = '';
  bool _isLoading = false;
  
  List<Map<String, dynamic>> _friends = [];
  bool _friendsListVisible = true;
  bool _isLoadingFriends = false;

  // Pictures management
  List<String> _pictures = [];
  bool _isLoadingPictures = false;
  static const int _maxPictures = 20;

  // NEW: Submitted recipes
  List<SubmittedRecipe> _submittedRecipes = [];
  bool _isLoadingRecipes = false;

  late final PremiumGateController _premiumController;
  bool _isPremium = false;
  int _totalScansUsed = 0;
  bool _hasUsedAllFreeScans = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializePremiumController();
    _loadProfile();
    _loadFriends();
    _loadPictures();
    _loadSubmittedRecipes(); // NEW
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _premiumController.removeListener(_updatePremiumState);
    super.dispose();
  }

  void _initializePremiumController() {
    _premiumController = PremiumGateController();
    _premiumController.addListener(_updatePremiumState);
    _updatePremiumState();
  }
  
  void _updatePremiumState() {
    if (mounted) {
      setState(() {
        _isPremium = _premiumController.isPremium;
        _totalScansUsed = _premiumController.totalScansUsed;
        _hasUsedAllFreeScans = _premiumController.hasUsedAllFreeScans;
      });
    }
  }

  Widget _sectionContainer({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha((0.9 * 255).toInt()),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }

  // NEW: Load submitted recipes
  Future<void> _loadSubmittedRecipes() async {
    if (!mounted) return;
    
    setState(() {
      _isLoadingRecipes = true;
    });

    try {
      final recipes = await DatabaseService.getSubmittedRecipes();
      
      if (mounted) {
        setState(() {
          _submittedRecipes = recipes;
          _isLoadingRecipes = false;
        });
      }
    } catch (e) {
      print('Error loading recipes: $e');
      if (mounted) {
        setState(() {
          _submittedRecipes = [];
          _isLoadingRecipes = false;
        });
      }
    }
  }

  // NEW: Delete recipe
  Future<void> _deleteRecipe(int recipeId) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await DatabaseService.deleteSubmittedRecipe(recipeId);
      
      if (mounted) {
        await _loadSubmittedRecipes();
        ErrorHandlingService.showSuccess(context, 'Recipe deleted successfully');
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to delete recipe',
          onRetry: () => _deleteRecipe(recipeId),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // NEW: Edit recipe
  Future<void> _editRecipe(SubmittedRecipe recipe) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EditRecipePage(recipe: recipe),
      ),
    );

    if (result == true) {
      await _loadSubmittedRecipes();
    }
  }

  // Load pictures from database
  Future<void> _loadPictures() async {
    if (!mounted) return;
    
    setState(() {
      _isLoadingPictures = true;
    });

    try {
      final pictures = await DatabaseService.getCurrentUserPictures();
      
      if (mounted) {
        setState(() {
          _pictures = pictures;
          _isLoadingPictures = false;
        });
      }
    } catch (e) {
      print('Error loading pictures: $e');
      if (mounted) {
        setState(() {
          _pictures = [];
          _isLoadingPictures = false;
        });
      }
    }
  }

  // Upload a picture
  Future<void> _uploadPicture(ImageSource source) async {
    if (_pictures.length >= _maxPictures) {
      ErrorHandlingService.showSimpleError(
        context, 
        'Maximum $_maxPictures pictures allowed. Please delete some first.'
      );
      return;
    }

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile != null && mounted) {
        setState(() {
          _isLoadingPictures = true;
        });

        final imageFile = File(pickedFile.path);
        await DatabaseService.uploadPicture(imageFile);
        
        await _loadPictures();
        
        if (mounted) {
          ErrorHandlingService.showSuccess(context, 'Picture uploaded successfully!');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingPictures = false;
        });
        
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.imageError,
          customMessage: 'Unable to upload picture',
          onRetry: () => _uploadPicture(source),
        );
      }
    }
  }

  // Delete a picture
  Future<void> _deletePicture(String pictureUrl) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Picture'),
          content: const Text('Are you sure you want to delete this picture?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm == true && mounted) {
      setState(() {
        _isLoadingPictures = true;
      });

      try {
        await DatabaseService.deletePicture(pictureUrl);
        await _loadPictures();
        
        if (mounted) {
          ErrorHandlingService.showSuccess(context, 'Picture deleted successfully');
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoadingPictures = false;
          });
          
          await ErrorHandlingService.handleError(
            context: context,
            error: e,
            category: ErrorHandlingService.databaseError,
            customMessage: 'Unable to delete picture',
            onRetry: () => _deletePicture(pictureUrl),
          );
        }
      }
    }
  }

  // Show picture options dialog
  void _showPictureOptionsDialog(String pictureUrl) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Picture Options'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.account_circle, color: Colors.blue),
                title: const Text('Set as Profile Picture'),
                onTap: () {
                  Navigator.pop(context);
                  _setAsProfilePicture(pictureUrl);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete Picture'),
                onTap: () {
                  Navigator.pop(context);
                  _deletePicture(pictureUrl);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // Set picture as profile picture
  Future<void> _setAsProfilePicture(String pictureUrl) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await DatabaseService.setPictureAsProfilePicture(pictureUrl);
      
      if (mounted) {
        ErrorHandlingService.showSuccess(context, 'Profile picture updated!');
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to set profile picture',
          onRetry: () => _setAsProfilePicture(pictureUrl),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Show full-screen picture viewer
  void _showFullScreenImage(String imageUrl, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text('Picture ${index + 1} of ${_pictures.length}'),
            actions: [
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () {
                  Navigator.pop(context);
                  _showPictureOptionsDialog(imageUrl);
                },
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error, size: 50, color: Colors.red),
                        SizedBox(height: 10),
                        Text(
                          'Failed to load image',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Show picture upload dialog
  void _showPictureUploadDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add Picture'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.blue),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _uploadPicture(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.blue),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _uploadPicture(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _loadFriends() async {
    if (!mounted) return;
    
    setState(() {
      _isLoadingFriends = true;
    });

    try {
      final currentUserId = AuthService.currentUserId;
      if (currentUserId == null) {
        if (mounted) {
          setState(() {
            _friends = [];
            _isLoadingFriends = false;
          });
        }
        return;
      }

      final friends = await DatabaseService.getUserFriends(currentUserId);
      final visibility = await DatabaseService.getFriendsListVisibility();
      
      if (mounted) {
        setState(() {
          _friends = friends;
          _friendsListVisible = visibility;
          _isLoadingFriends = false;
        });
      }
    } catch (e) {
      print('Error loading friends: $e');
      if (mounted) {
        setState(() {
          _friends = [];
          _isLoadingFriends = false;
        });
      }
    }
  }

  Future<void> _toggleFriendsVisibility(bool isVisible) async {
    try {
      await DatabaseService.updateFriendsListVisibility(isVisible);
      if (mounted) {
        setState(() {
          _friendsListVisible = isVisible;
        });
        
        ErrorHandlingService.showSuccess(
          context,
          isVisible 
              ? 'Friends list is now visible to others' 
              : 'Friends list is now hidden from others'
        );
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to update privacy setting',
          onRetry: () => _toggleFriendsVisibility(isVisible),
        );
      }
    }
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final imagePath = prefs.getString('profile_image_path');
      final backgroundPath = prefs.getString('profile_background_path');
      final savedName = prefs.getString('user_name') ?? 'User';
      final savedEmail = prefs.getString('user_email') ?? '';
      
      if (mounted) {
        setState(() {
          _userName = savedName;
          _userEmail = savedEmail;
          _nameController.text = savedName;
          _emailController.text = savedEmail;
          if (imagePath != null && imagePath.isNotEmpty) {
            _profileImage = File(imagePath);
          }
          if (backgroundPath != null && backgroundPath.isNotEmpty) {
            _backgroundImage = File(backgroundPath);
          }
        });
      }

      final profile = await DatabaseService.getCurrentUserProfile();
      if (profile != null && mounted) {
        final userName = profile['username'] ?? savedName;
        final userEmail = profile['email'] ?? savedEmail;
        
        await prefs.setString('user_name', userName);
        await prefs.setString('user_email', userEmail);
        
        setState(() {
          _userName = userName;
          _userEmail = userEmail;
          _nameController.text = userName;
          _emailController.text = userEmail;
        });
      }
    } catch (e) {
      print('Error loading profile: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: source);

      if (pickedFile != null && mounted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('profile_image_path', pickedFile.path);
        
        setState(() {
          _profileImage = File(pickedFile.path);
        });

        ErrorHandlingService.showSuccess(context, 'Profile picture updated!');
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.imageError,
          onRetry: () => _pickImage(source),
        );
      }
    }
  }

  Future<void> _pickBackgroundImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile != null && mounted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('profile_background_path', pickedFile.path);
        
        setState(() {
          _backgroundImage = File(pickedFile.path);
        });

        ErrorHandlingService.showSuccess(context, 'Background updated!');
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.imageError,
          customMessage: 'Unable to update background',
          onRetry: () => _pickBackgroundImage(source),
        );
      }
    }
  }

  Future<void> _removeBackgroundImage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('profile_background_path');
      
      if (mounted) {
        setState(() {
          _backgroundImage = null;
        });
        
        ErrorHandlingService.showSuccess(context, 'Background reset to default');
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to reset background',
        );
      }
    }
  }

  Future<void> _saveUserName() async {
    if (_nameController.text.trim().isEmpty) {
      ErrorHandlingService.showSimpleError(context, 'Name cannot be empty');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await DatabaseService.updateProfile(username: _nameController.text.trim());
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', _nameController.text.trim());
      
      if (mounted) {
        setState(() {
          _userName = _nameController.text.trim();
          _isEditingName = false;
        });
        
        ErrorHandlingService.showSuccess(context, 'Name updated successfully!');
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to update name',
          onRetry: _saveUserName,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveUserEmail() async {
    if (_emailController.text.trim().isEmpty) {
      ErrorHandlingService.showSimpleError(context, 'Email cannot be empty');
      return;
    }

    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(_emailController.text.trim())) {
      ErrorHandlingService.showSimpleError(context, 'Please enter a valid email address');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await DatabaseService.updateProfile(email: _emailController.text.trim());
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_email', _emailController.text.trim());
      
      if (mounted) {
        setState(() {
          _userEmail = _emailController.text.trim();
          _isEditingEmail = false;
        });
        
        ErrorHandlingService.showSuccess(context, 'Email updated successfully!');
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to update email',
          onRetry: _saveUserEmail,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _toggleEditName() {
    setState(() {
      _isEditingName = !_isEditingName;
      if (_isEditingName) {
        _nameController.text = _userName;
      }
    });
  }

  void _toggleEditEmail() {
    setState(() {
      _isEditingEmail = !_isEditingEmail;
      if (_isEditingEmail) {
        _emailController.text = _userEmail;
      }
    });
  }

  void _cancelEditName() {
    setState(() {
      _isEditingName = false;
      _nameController.text = _userName;
    });
  }

  void _cancelEditEmail() {
    setState(() {
      _isEditingEmail = false;
      _emailController.text = _userEmail;
    });
  }

  void _showImagePickerDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Profile Picture'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showBackgroundPickerDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Background'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.blue),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickBackgroundImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.blue),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickBackgroundImage(ImageSource.gallery);
                },
              ),
              if (_backgroundImage != null) ...[
                Divider(),
                ListTile(
                  leading: const Icon(Icons.restore, color: Colors.orange),
                  title: const Text('Reset to Default'),
                  onTap: () {
                    Navigator.pop(context);
                    _removeBackgroundImage();
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _navigateToUserProfile(String userId) {
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserProfilePage(userId: userId),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to open profile')),
        );
      }
    }
  }

  void _navigateToSearchUsers() {
    try {
      Navigator.pushNamed(context, '/search-users');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search page unavailable')),
        );
      }
    }
  }

  void _showFullFriendsList() {
    try {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.people, color: Colors.blue),
                SizedBox(width: 8),
                Text('All Friends'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('You have ${_friends.length} friends:'),
                SizedBox(height: 12),
                Container(
                  constraints: BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Column(
                      children: _friends.map((friend) => ListTile(
                        leading: CircleAvatar(
                          backgroundImage: friend['avatar_url'] != null
                              ? NetworkImage(friend['avatar_url'])
                              : null,
                          child: friend['avatar_url'] == null
                              ? Text((friend['username'] ?? 'U')[0].toUpperCase())
                              : null,
                        ),
                        title: Text(
                          friend['first_name'] != null && friend['last_name'] != null
                              ? '${friend['first_name']} ${friend['last_name']}'
                              : friend['username'] ?? 'Unknown',
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _navigateToUserProfile(friend['id']);
                        },
                      )).toList(),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Close'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      print('Error showing friends dialog: $e');
    }
  }

  Widget _buildPremiumStatusSection() {
    return _sectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isPremium) ...[
            Row(
              children: [
                Icon(Icons.star, color: Colors.amber, size: 24),
                SizedBox(width: 8),
                Text(
                  'Premium Account Active',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade700,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              'You have access to all premium features!',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ] else ...[
            Row(
              children: [
                Icon(Icons.person, color: Colors.grey, size: 24),
                SizedBox(width: 8),
                Text(
                  'Free Account',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              'Daily scans used: $_totalScansUsed/3',
              style: TextStyle(
                color: _hasUsedAllFreeScans 
                    ? Colors.red.shade600 
                    : Colors.grey.shade600,
                fontWeight: _hasUsedAllFreeScans 
                    ? FontWeight.w600 
                    : FontWeight.normal,
              ),
            ),
            SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  try {
                    Navigator.pushNamed(context, '/purchase');
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Premium page unavailable')),
                    );
                  }
                },
                icon: Icon(Icons.star),
                label: Text('Upgrade to Premium'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Build pictures gallery section
  Widget _buildPicturesSection() {
    return _sectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Pictures (${_pictures.length}/$_maxPictures)',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_pictures.length < _maxPictures)
                IconButton(
                  icon: Icon(Icons.add_photo_alternate, color: Colors.blue),
                  onPressed: _showPictureUploadDialog,
                  tooltip: 'Add Picture',
                ),
            ],
          ),
          SizedBox(height: 12),
          
          if (_isLoadingPictures) ...[
            Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            ),
          ] else if (_pictures.isEmpty) ...[
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.photo_library,
                    size: 50,
                    color: Colors.grey.shade400,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'No pictures yet',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _showPictureUploadDialog,
                    icon: Icon(Icons.add_photo_alternate),
                    label: Text('Add Your First Picture'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            GridView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: _pictures.length,
              itemBuilder: (context, index) {
                final pictureUrl = _pictures[index];
                return GestureDetector(
                  onTap: () => _showFullScreenImage(pictureUrl, index),
                  onLongPress: () => _showPictureOptionsDialog(pictureUrl),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        pictureUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Icon(
                              Icons.broken_image,
                              color: Colors.grey.shade400,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  // NEW: Build submitted recipes section
  Widget _buildSubmittedRecipesSection() {
    return _sectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'My Submitted Recipes (${_submittedRecipes.length})',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: Icon(Icons.add_circle, color: Colors.green),
                onPressed: () async {
                  try {
                    final result = await Navigator.pushNamed(context, '/submit-recipe');
                    if (result == true) {
                      await _loadSubmittedRecipes();
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Recipe page unavailable')),
                    );
                  }
                },
                tooltip: 'Submit New Recipe',
              ),
            ],
          ),
          SizedBox(height: 12),
          
          if (_isLoadingRecipes) ...[
            Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            ),
          ] else if (_submittedRecipes.isEmpty) ...[
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.restaurant_menu,
                    size: 50,
                    color: Colors.grey.shade400,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'No recipes submitted yet',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Share your favorite recipes with the community!',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        final result = await Navigator.pushNamed(context, '/submit-recipe');
                        if (result == true) {
                          await _loadSubmittedRecipes();
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Recipe page unavailable')),
                        );
                      }
                    },
                    icon: Icon(Icons.add),
                    label: Text('Submit Your First Recipe'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: _submittedRecipes.length,
              itemBuilder: (context, index) {
                final recipe = _submittedRecipes[index];
                
                // Skip recipes with null IDs
                if (recipe.id == null) {
                  return SizedBox.shrink();
                }
                
                return RecipeCard(
                  recipe: recipe,
                  onDelete: () => _deleteRecipe(recipe.id!),
                  onEdit: () => _editRecipe(recipe),
                  onRatingChanged: () => _loadSubmittedRecipes(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.wallpaper),
            tooltip: 'Change Background',
            onPressed: _showBackgroundPickerDialog,
          ),
          if (_isLoading)
            Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
        ],
      ),
      drawer: AppDrawer(currentPage: 'profile'),
      body: Stack(
        children: [
          Positioned.fill(
            child: _backgroundImage != null
                ? Image.file(
                    _backgroundImage!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Image.asset(
                        'assets/bari.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.green.shade50,
                          );
                        },
                      );
                    },
                  )
                : Image.asset(
                    'assets/bari.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.green.shade50,
                        child: Center(
                          child: Icon(
                            Icons.image_not_supported,
                            size: 50,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 80,
                        backgroundColor: Colors.grey[300],
                        backgroundImage: _profileImage != null
                            ? FileImage(_profileImage!)
                            : null,
                        child: _profileImage == null
                            ? const Icon(
                                Icons.person,
                                size: 80,
                                color: Colors.grey,
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _showImagePickerDialog,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                _sectionContainer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Username:',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (!_isEditingName)
                            TextButton.icon(
                              onPressed: _toggleEditName,
                              icon: const Icon(Icons.edit, size: 16),
                              label: const Text('Edit'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.blue,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_isEditingName) ...[
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'Enter your username',
                          ),
                          autofocus: true,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            ElevatedButton(
                              onPressed: _isLoading ? null : _saveUserName,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                              child: _isLoading
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : const Text('Save'),
                            ),
                            const SizedBox(width: 10),
                            TextButton(
                              onPressed: _cancelEditName,
                              child: const Text('Cancel'),
                            ),
                          ],
                        ),
                      ] else ...[
                        Text(
                          _userName.isEmpty ? 'No username set' : _userName,
                          style: const TextStyle(
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                _sectionContainer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Email:',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (!_isEditingEmail)
                            TextButton.icon(
                              onPressed: _toggleEditEmail,
                              icon: const Icon(Icons.edit, size: 16),
                              label: const Text('Edit'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.blue,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_isEditingEmail) ...[
                        TextField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'Enter your email',
                          ),
                          keyboardType: TextInputType.emailAddress,
                          autofocus: true,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            ElevatedButton(
                              onPressed: _isLoading ? null : _saveUserEmail,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                              child: _isLoading
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : const Text('Save'),
                            ),
                            const SizedBox(width: 10),
                            TextButton(
                              onPressed: _cancelEditEmail,
                              child: const Text('Cancel'),
                            ),
                          ],
                        ),
                      ] else ...[
                        Text(
                          _userEmail.isEmpty ? 'No email set' : _userEmail,
                          style: const TextStyle(
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                _buildPicturesSection(),

                const SizedBox(height: 20),

                _sectionContainer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Friends (${_friends.length})',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert, size: 20),
                            onSelected: (value) {
                              if (value == 'toggle_visibility') {
                                _toggleFriendsVisibility(!_friendsListVisible);
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'toggle_visibility',
                                child: Row(
                                  children: [
                                    Icon(
                                      _friendsListVisible ? Icons.visibility_off : Icons.visibility,
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(_friendsListVisible 
                                        ? 'Hide from Others' 
                                        : 'Make Visible'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            _friendsListVisible ? Icons.visibility : Icons.visibility_off,
                            size: 16,
                            color: Colors.grey.shade600,
                          ),
                          SizedBox(width: 4),
                          Text(
                            _friendsListVisible ? 'Visible to others' : 'Hidden from others',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      
                      if (_isLoadingFriends) ...[
                        Center(child: CircularProgressIndicator()),
                      ] else if (_friends.isEmpty) ...[
                        Text(
                          'No friends yet. Start by finding and adding friends!',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _navigateToSearchUsers,
                          icon: Icon(Icons.person_search),
                          label: Text('Find Friends'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ] else ...[
                        GridView.builder(
                          shrinkWrap: true,
                          physics: NeverScrollableScrollPhysics(),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.8,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: _friends.length > 6 ? 6 : _friends.length,
                          itemBuilder: (context, index) {
                            if (index == 5 && _friends.length > 6) {
                              return GestureDetector(
                                onTap: _showFullFriendsList,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.more_horiz, size: 30, color: Colors.grey.shade600),
                                      SizedBox(height: 4),
                                      Text(
                                        'View All\n${_friends.length} friends',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                            
                            final friend = _friends[index];
                            return GestureDetector(
                              onTap: () => _navigateToUserProfile(friend['id']),
                              child: Column(
                                children: [
                                  CircleAvatar(
                                    radius: 25,
                                    backgroundImage: friend['avatar_url'] != null
                                        ? NetworkImage(friend['avatar_url'])
                                        : null,
                                    child: friend['avatar_url'] == null
                                        ? Text(
                                            (friend['username'] ?? friend['first_name'] ?? friend['email'] ?? 'U')[0].toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          )
                                        : null,
                                  ),
                                  SizedBox(height: 4),
                                  Expanded(
                                    child: Text(
                                      friend['first_name'] != null && friend['last_name'] != null
                                          ? '${friend['first_name']} ${friend['last_name']}'
                                          : friend['username'] ?? 'Unknown',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        
                        if (_friends.length > 6) ...[
                          SizedBox(height: 12),
                          TextButton(
                            onPressed: _showFullFriendsList,
                            child: Text('View All ${_friends.length} Friends'),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                _buildPremiumStatusSection(),

                const SizedBox(height: 20),

                // NEW: Submitted Recipes Section (with Premium Gate)
                PremiumGate(
                  feature: PremiumFeature.submitRecipes,
                  featureName: 'Recipe Submission',
                  featureDescription: 'Share your favorite recipes with the community.',
                  child: _buildSubmittedRecipesSection(),
                ),

                const SizedBox(height: 20),

                PremiumGate(
                  feature: PremiumFeature.favoriteRecipes,
                  featureName: 'Favorite Recipes',
                  featureDescription: 'Save and organize your favorite recipes.',
                  showSoftPreview: true,
                  child: _sectionContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Favorite Recipes',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          widget.favoriteRecipes.isEmpty
                              ? 'No favorite recipes yet. Start scanning to discover new recipes!'
                              : '${widget.favoriteRecipes.length} favorite recipes saved',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        if (widget.favoriteRecipes.isNotEmpty) ...[
                          SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                try {
                                  Navigator.pushNamed(context, '/favorite-recipes');
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Favorites page unavailable')),
                                  );
                                }
                              },
                              icon: Icon(Icons.favorite),
                              label: Text('View Favorite Recipes'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 100),
              ],
            ),
          ), 
        ],
      ),
    );
  }
}