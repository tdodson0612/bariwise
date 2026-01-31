// lib/pages/submit_recipe.dart - COMPLETE WITH TABBED NUTRITION
import 'package:flutter/material.dart';
import 'package:bari_wise/services/submitted_recipes_service.dart';
import 'package:bari_wise/services/grocery_service.dart';
import '../services/database_service_core.dart';
import '../services/auth_service.dart';
import '../services/error_handling_service.dart';
import 'package:bari_wise/services/local_draft_service.dart';
import 'package:bari_wise/widgets/recipe_nutrition_display.dart';
import 'package:bari_wise/services/recipe_nutrition_service.dart';
import 'package:bari_wise/services/saved_ingredients_service.dart';
import 'package:bari_wise/models/nutrition_info.dart';
import 'package:bari_wise/widgets/nutrition_facts_label.dart'; // 🔥 ADDED
import 'dart:convert';
import '../services/draft_recipes_service.dart';
import '../models/draft_recipe.dart';

class IngredientRow {
  String quantity;
  String measurement;
  String name;
  String? customMeasurement;

  IngredientRow({
    this.quantity = '',
    this.measurement = 'cup',
    this.name = '',
    this.customMeasurement,
  });

  Map<String, dynamic> toJson() => {
    'quantity': quantity,
    'measurement': measurement,
    'name': name,
    if (customMeasurement != null) 'customMeasurement': customMeasurement,
  };

  factory IngredientRow.fromJson(Map<String, dynamic> json) => IngredientRow(
    quantity: json['quantity'] ?? '',
    measurement: json['measurement'] ?? 'cup',
    name: json['name'] ?? '',
    customMeasurement: json['customMeasurement'],
  );

  bool get isEmpty => quantity.isEmpty && name.isEmpty;
  bool get isValid => quantity.isNotEmpty && name.isNotEmpty;
  
  String get displayMeasurement => 
    measurement == 'other' && customMeasurement != null 
      ? customMeasurement! 
      : measurement;
}

class SubmitRecipePage extends StatefulWidget {
  final String? initialIngredients;
  final String? productName;

  const SubmitRecipePage({
    super.key,
    this.initialIngredients,
    this.productName,
  });

  @override
  _SubmitRecipePageState createState() => _SubmitRecipePageState();
}

class _SubmitRecipePageState extends State<SubmitRecipePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _directionsController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  List<IngredientRow> _ingredients = [IngredientRow()];
  final List<String> _measurements = [
    'cup', 'cups', 'tbsp', 'tsp', 'oz', 'lb', 'g', 'kg',
    'ml', 'l', 'piece', 'pieces', 'pinch', 'dash', 'to taste',
    'other',
  ];

  bool isSubmitting = false;
  bool isLoading = true;
  bool _isSaved = false;

  int _tabIndex = 0;
  Map<String, dynamic> _drafts = {};
  String? _loadedDraftName;

  List<NutritionInfo> _matchedNutritionIngredients = [];
  RecipeNutrition? _recipeNutrition;
  bool _isAnalyzingNutrition = false;

  List<Map<String, dynamic>> _submittedRecipes = [];
  bool _isLoadingSubmitted = false;

  String _ingredientsToPlainText() {
    return _ingredients
        .where((i) => i.isValid)
        .map((i) => '${i.quantity} ${i.measurement} ${i.name}')
        .join('\n');
  }

  // 🔥 NEW: Convert RecipeNutrition to NutritionInfo for FDA label
  NutritionInfo _convertRecipeNutritionToInfo(RecipeNutrition recipeNutr) {
    return recipeNutr.toNutritionInfo(
      productName: _nameController.text.isNotEmpty 
        ? _nameController.text 
        : 'Recipe Nutrition',
    );
  }

  // 🔥 NEW: Build dietary badge
  Widget _buildBadge(String label, Color color) {
    // Determine text color based on badge background color
    final textColor = _getBadgeTextColor(color);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }

  // Helper to get appropriate text color for badges
  Color _getBadgeTextColor(Color badgeColor) {
    if (badgeColor == Colors.blue) return Colors.blue.shade900;
    if (badgeColor == Colors.orange) return Colors.orange.shade900;
    if (badgeColor == Colors.purple) return Colors.purple.shade900;
    if (badgeColor == Colors.orange) return Colors.orange.shade900;
    if (badgeColor == Colors.red) return Colors.red.shade900;
    return Colors.black87; // Default fallback
  }

  @override
  void initState() {
    super.initState();
    _initializeUser();
    _loadDrafts();
    _loadSubmittedRecipes();

    if (widget.initialIngredients != null) {
      _parseInitialIngredients(widget.initialIngredients!);
    }
    if (widget.productName != null) {
      _nameController.text = '${widget.productName} Recipe';
    }
  }

  void _parseInitialIngredients(String ingredients) {
    try {
      final List<dynamic> parsed = jsonDecode(ingredients);
      _ingredients = parsed.map((e) => IngredientRow.fromJson(e)).toList();
    } catch (e) {
      final lines = ingredients.split('\n').where((l) => l.trim().isNotEmpty).toList();
      _ingredients = lines.map((line) => IngredientRow(name: line.trim())).toList();
    }
    
    if (_ingredients.isEmpty) {
      _ingredients = [IngredientRow()];
    }
  }

  String _serializeIngredients() {
    final validIngredients = _ingredients.where((i) => i.isValid).toList();
    return jsonEncode(validIngredients.map((i) => i.toJson()).toList());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _directionsController.dispose();
    super.dispose();
  }

  Future<void> _initializeUser() async {
    try {
      DatabaseServiceCore.ensureUserAuthenticated();
      setState(() => isLoading = false);
    } catch (e) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> _loadDrafts() async {
    final d = await LocalDraftService.getDrafts();
    setState(() => _drafts = d);
  }

  Future<void> _loadSubmittedRecipes() async {
    setState(() => _isLoadingSubmitted = true);
    
    try {
      final userId = AuthService.currentUserId;
      if (userId == null) {
        if (mounted) {
          setState(() {
            _submittedRecipes = [];
            _isLoadingSubmitted = false;
          });
        }
        return;
      }

      final submissions = await SubmittedRecipesService.getUserSubmissions(userId);
      
      if (mounted) {
        setState(() {
          _submittedRecipes = submissions.map((submission) => {
            'id': submission.id,
            'title': submission.draftRecipeId,
            'status': submission.status,
            'submitted_at': submission.submittedAt,
            'approved_at': submission.reviewedAt,
            'views': 0,
            'rejection_reason': submission.rejectionReason,
          }).toList();
          _isLoadingSubmitted = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSubmitted = false);
      }
      print('Error loading submitted recipes: $e');
    }
  }

  void _addIngredientRow() {
    setState(() => _ingredients.add(IngredientRow()));
  }

  void _removeIngredientRow(int index) {
    if (_ingredients.length > 1) {
      setState(() => _ingredients.removeAt(index));
    }
  }

  Future<void> _saveRecipe() async {
    if (!_formKey.currentState!.validate()) return;

    final validIngredients = _ingredients.where((i) => i.isValid).toList();
    
    if (validIngredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one valid ingredient'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => isSubmitting = true);

    try {
      final name = _nameController.text.trim();
      final description = _descriptionController.text.trim();
      final ing = _serializeIngredients();
      final dir = _directionsController.text.trim();

      await LocalDraftService.saveDraft(
        name: name,
        description: description.isNotEmpty ? description : null,
        ingredients: ing,
        directions: dir,
      );

      _loadedDraftName = name;
      _isSaved = true;
      await _loadDrafts();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Draft saved!',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Saved "$name" with ${validIngredients.length} ingredient${validIngredients.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'VIEW DRAFTS',
              textColor: Colors.white,
              onPressed: () {
                setState(() => _tabIndex = 1);
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving draft: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isSubmitting = false);
      }
    }
  }

  Future<void> _updateDraft() async {
    if (!_formKey.currentState!.validate()) return;

    final validIngredients = _ingredients.where((i) => i.isValid).toList();
    
    if (validIngredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one valid ingredient'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_loadedDraftName == null) {
      _saveRecipe();
      return;
    }

    setState(() => isSubmitting = true);

    try {
      final name = _nameController.text.trim();
      final description = _descriptionController.text.trim();
      final ing = _serializeIngredients();
      final dir = _directionsController.text.trim();

      if (_loadedDraftName != name) {
        await LocalDraftService.deleteDraft(_loadedDraftName!);
      }

      await LocalDraftService.saveDraft(
        name: name,
        description: description.isNotEmpty ? description : null,
        ingredients: ing,
        directions: dir,
      );

      _loadedDraftName = name;
      _isSaved = true;
      await _loadDrafts();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Draft "$name" updated!',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating draft: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isSubmitting = false);
      }
    }
  }

  Future<void> _addToGroceryList() async {
    final validIngredients = _ingredients.where((i) => i.isValid).toList();
    
    if (validIngredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add ingredients first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      int addedCount = 0;
      for (var ingredient in validIngredients) {
        final itemText = '${ingredient.quantity} ${ingredient.measurement} ${ingredient.name}'.trim();
        await GroceryService.addToGroceryList(itemText);
        addedCount++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added $addedCount ingredients to grocery list!'),
            backgroundColor: Colors.orange,
            action: SnackBarAction(
              label: 'VIEW',
              textColor: Colors.white,
              onPressed: () {
                Navigator.pushNamed(context, '/grocery-list');
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Failed to add ingredients to grocery list',
        );
      }
    }
  }

  Future<void> _submitRecipe() async {
    if (!_formKey.currentState!.validate()) return;

    final validIngredients = _ingredients.where((i) => i.isValid).toList();
    if (validIngredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one valid ingredient'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final submissionType = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit Recipe'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recipe: ${_nameController.text.trim()}'),
            const SizedBox(height: 8),
            Text('Ingredients: ${validIngredients.length}'),
            const SizedBox(height: 16),
            
            const Text(
              'Choose submission type:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.save, color: Colors.blue),
              title: const Text('Save as Draft'),
              subtitle: const Text('Keep private, edit anytime'),
              onTap: () => Navigator.pop(context, 'draft'),
            ),
            
            const Divider(),
            
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.send, color: Colors.orange),
              title: const Text('Submit for Community'),
              subtitle: const Text('Goes through compliance review'),
              onTap: () => Navigator.pop(context, 'community'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (submissionType == null) return;

    setState(() => isSubmitting = true);

    try {
      DatabaseServiceCore.ensureUserAuthenticated();

      if (submissionType == 'draft') {
        await _saveDraftRecipe();
      } else if (submissionType == 'community') {
        await _submitForCommunityReview();
      }

      if (_loadedDraftName != null) {
        await LocalDraftService.deleteDraft(_loadedDraftName!);
        await _loadDrafts();
        _loadedDraftName = null;
      }

      await _loadSubmittedRecipes();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    submissionType == 'draft'
                        ? 'Recipe saved to your cookbook!'
                        : 'Recipe submitted for review!',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
            action: submissionType == 'community' ? SnackBarAction(
              label: 'View Status',
              textColor: Colors.white,
              onPressed: () {
                setState(() => _tabIndex = 2);
              },
            ) : null,
          ),
        );

        _nameController.clear();
        _directionsController.clear();
        _descriptionController.clear();
        setState(() {
          _ingredients = [IngredientRow()];
          _isSaved = false;
          _loadedDraftName = null;
        });
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Failed to submit recipe',
          onRetry: _submitRecipe,
        );
      }
    } finally {
      if (mounted) {
        setState(() => isSubmitting = false);
      }
    }
  }

  Future<void> _saveDraftRecipe() async {
    try {
      final recipeIngredients = _ingredients
          .where((i) => i.isValid)
          .map((ing) => RecipeIngredient(
                productName: ing.name,
                quantity: double.tryParse(ing.quantity) ?? 1.0,
                unit: ing.measurement,
              ))
          .toList();

      final draftRecipe = DraftRecipe(
        userId: AuthService.currentUserId!,
        title: _nameController.text.trim(),
        description: _descriptionController.text.trim().isNotEmpty 
          ? _descriptionController.text.trim() 
          : null,
        ingredients: recipeIngredients,
        instructions: _directionsController.text.trim(),
        servings: 1,
      );

      await DraftRecipesService.createDraftRecipe(draftRecipe);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _submitForCommunityReview() async {
    try {
      final recipeIngredients = _ingredients
          .where((i) => i.isValid)
          .map((ing) => RecipeIngredient(
                productName: ing.name,
                quantity: double.tryParse(ing.quantity) ?? 1.0,
                unit: ing.measurement,
              ))
          .toList();

      final draftRecipe = DraftRecipe(
        userId: AuthService.currentUserId!,
        title: _nameController.text.trim(),
        description: _descriptionController.text.trim().isNotEmpty 
            ? _descriptionController.text.trim() 
            : null,
        ingredients: recipeIngredients,
        instructions: _directionsController.text.trim(),
        servings: 1,
      );

      final draftRecipeId = await DraftRecipesService.createDraftRecipe(draftRecipe);
      await SubmittedRecipesService.submitRecipeForReview(draftRecipeId);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _analyzeRecipeNutrition() async {
    final validIngredients = _ingredients.where((i) => i.isValid).toList();
    
    if (validIngredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add ingredients first to analyze nutrition.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isAnalyzingNutrition = true;
      _matchedNutritionIngredients = [];
      _recipeNutrition = null;
    });

    try {
      final saved = await SavedIngredientsService.loadSavedIngredients();
      
      if (saved.isEmpty) {
        if (mounted) {
          setState(() => _isAnalyzingNutrition = false);
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: const [
                  Icon(Icons.info_outline, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('No Saved Ingredients'),
                ],
              ),
              content: const Text(
                'You don\'t have any saved ingredients yet.\n\n'
                'To analyze recipe nutrition:\n'
                '1. Go to Home screen\n'
                '2. Scan a product barcode\n'
                '3. Click "Save Ingredient"\n'
                '4. Come back and analyze\n\n'
                'Saved ingredients help us calculate accurate nutrition for your recipes!'
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/');
                  },
                  icon: const Icon(Icons.home),
                  label: const Text('Go to Home'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          );
        }
        return;
      }

      final List<NutritionInfo> matches = [];
      for (var ingredient in validIngredients) {
        final name = ingredient.name.trim().toLowerCase();
        if (name.length < 3) continue;
        
        final found = saved.where((item) {
          final itemName = item.productName.toLowerCase();
          final nameWords = name.split(' ');
          final itemWords = itemName.split(' ');
          
          if (itemName.contains(name) || name.contains(itemName)) {
            return true;
          }
          
          for (var word in nameWords) {
            if (word.length >= 3 && itemWords.any((iw) => iw.contains(word))) {
              return true;
            }
          }
          
          return false;
        }).toList();
        
        for (var item in found) {
          if (!matches.any((m) => m.productName.toLowerCase() == item.productName.toLowerCase())) {
            matches.add(item);
          }
        }
      }

      if (matches.isEmpty) {
        if (mounted) {
          setState(() => _isAnalyzingNutrition = false);
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.search_off, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('No Matches Found'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('We couldn\'t match your recipe ingredients to saved items.\n'),
                  SizedBox(height: 12),
                  Text('Recipe ingredients:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...validIngredients.take(5).map((ing) => 
                    Padding(
                      padding: EdgeInsets.only(left: 8, top: 4),
                      child: Text('• ${ing.name}'),
                    )
                  ),
                  if (validIngredients.length > 5)
                    Padding(
                      padding: EdgeInsets.only(left: 8, top: 4),
                      child: Text('... and ${validIngredients.length - 5} more'),
                    ),
                  SizedBox(height: 12),
                  Text('You have ${saved.length} saved ingredient${saved.length == 1 ? '' : 's'}:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...saved.take(3).map((item) => 
                    Padding(
                      padding: EdgeInsets.only(left: 8, top: 4),
                      child: Text('• ${item.productName}'),
                    )
                  ),
                  if (saved.length > 3)
                    Padding(
                      padding: EdgeInsets.only(left: 8, top: 4),
                      child: Text('... and ${saved.length - 3} more'),
                    ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text('OK')),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/saved-ingredients');
                  },
                  icon: Icon(Icons.bookmark),
                  label: Text('View Saved'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          );
        }
        return;
      }

      final totals = RecipeNutritionService.calculateTotals(matches);

      if (mounted) {
        setState(() {
          _matchedNutritionIngredients = matches;
          _recipeNutrition = totals;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Matched ${matches.length} ingredient${matches.length == 1 ? '' : 's'}!'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(context: context, error: e, customMessage: 'Error analyzing nutrition');
      }
    } finally {
      if (mounted) setState(() => _isAnalyzingNutrition = false);
    }
  }

  void _loadDraftForEditing(String name, Map<String, dynamic> draft) {
    setState(() {
      _nameController.text = draft["name"] ?? '';
      _directionsController.text = draft["directions"] ?? '';
      _descriptionController.text = draft["description"] ?? '';
      
      try {
        final List<dynamic> parsed = jsonDecode(draft["ingredients"]);
        _ingredients = parsed.map((e) => IngredientRow.fromJson(e)).toList();
      } catch (e) {
        _ingredients = [IngredientRow(name: draft["ingredients"] ?? '')];
      }
      
      if (_ingredients.isEmpty) {
        _ingredients = [IngredientRow()];
      }
      
      _loadedDraftName = name;
      _isSaved = true;
      _tabIndex = 0;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Loaded "$name" for editing'), backgroundColor: Colors.blue, duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _confirmDeleteDraft(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Draft'),
        content: Text('Are you sure you want to delete "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await LocalDraftService.deleteDraft(name);
      await _loadDrafts();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "$name"'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  String _formatDateTime(dynamic timestamp) {
    try {
      if (timestamp == null) return 'Unknown';
      
      DateTime date;
      if (timestamp is String) {
        date = DateTime.parse(timestamp);
      } else if (timestamp is DateTime) {
        date = timestamp;
      } else {
        return 'Unknown';
      }
      
      final now = DateTime.now();
      final diff = now.difference(date);
      
      if (diff.inDays == 0) {
        if (diff.inHours == 0) return '${diff.inMinutes} min ago';
        return '${diff.inHours} hr ago';
      } else if (diff.inDays < 7) {
        return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
      } else {
        return '${date.month}/${date.day}/${date.year}';
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  void _showSubmittedRecipeDetails(Map<String, dynamic> recipe) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(recipe['title'] ?? 'Recipe Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Status', recipe['status'] ?? 'pending'),
              _buildDetailRow('Submitted', _formatDateTime(recipe['submitted_at'])),
              if (recipe['approved_at'] != null)
                _buildDetailRow('Approved', _formatDateTime(recipe['approved_at'])),
              if (recipe['views'] != null)
                _buildDetailRow('Views', recipe['views'].toString()),
              if (recipe['rejection_reason'] != null) ...[
                const SizedBox(height: 12),
                const Text('Rejection Reason:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                const SizedBox(height: 4),
                Text(recipe['rejection_reason'], style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved': return Colors.orange;
      case 'rejected': return Colors.red;
      default: return Colors.orange;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved': return Icons.check_circle;
      case 'rejected': return Icons.cancel;
      default: return Icons.pending;
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildTabButton(String title, int index) {
    final selected = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          color: selected ? Colors.orange : Colors.grey.shade300,
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                color: selected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDraftList() {
    if (_drafts.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(230),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bookmark_border, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text("No drafts saved yet", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                "Save your recipes as drafts to edit them later",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(10),
      children: _drafts.keys.map((name) {
        final draft = _drafts[name];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.receipt_long, color: Colors.orange.shade700),
            ),
            title: Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  "Last updated: ${_formatDateTime(draft["updated_at"])}",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Text(
                    'DRAFT',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade700),
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  tooltip: 'Edit Draft',
                  onPressed: () => _loadDraftForEditing(name, draft),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  tooltip: 'Delete Draft',
                  onPressed: () => _confirmDeleteDraft(name),
                ),
              ],
            ),
            onTap: () => _loadDraftForEditing(name, draft),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSubmittedList() {
    if (_isLoadingSubmitted) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_submittedRecipes.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(230),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.send_outlined, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                "No submitted recipes yet",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Submit a recipe to see it here",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(10),
      children: _submittedRecipes.map((recipe) {
        final status = recipe['status'] ?? 'pending';
        final statusColor = _getStatusColor(status);
        final statusIcon = _getStatusIcon(status);
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(statusIcon, color: statusColor),
            ),
            title: Text(
              recipe['title'] ?? 'Untitled',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  "Submitted: ${_formatDateTime(recipe['submitted_at'])}",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: statusColor),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (recipe['views'] != null) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.visibility, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        '${recipe['views']}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showSubmittedRecipeDetails(recipe),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildIngredientRow(int index) {
    final ingredient = _ingredients[index];
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: ingredient.quantity,
              decoration: InputDecoration(
                labelText: 'Qty',
                hintText: '1',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (value) => ingredient.quantity = value,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: ingredient.measurement == 'other'
                ? TextFormField(
                    initialValue: ingredient.customMeasurement ?? '',
                    decoration: InputDecoration(
                      labelText: 'Custom Unit',
                      hintText: 'e.g., handful',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          setState(() {
                            ingredient.measurement = 'cup';
                            ingredient.customMeasurement = null;
                          });
                        },
                        tooltip: 'Back to dropdown',
                      ),
                    ),
                    onChanged: (value) {
                      setState(() => ingredient.customMeasurement = value);
                    },
                  )
                : DropdownButtonFormField<String>(
                    value: ingredient.measurement,
                    decoration: InputDecoration(
                      labelText: 'Unit',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                    ),
                    items: _measurements.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                    onChanged: (value) {
                      setState(() {
                        ingredient.measurement = value!;
                        if (value != 'other') {
                          ingredient.customMeasurement = null;
                        }
                      });
                    },
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: TextFormField(
              initialValue: ingredient.name,
              decoration: InputDecoration(
                labelText: 'Ingredient',
                hintText: 'flour',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              onChanged: (value) => ingredient.name = value,
              validator: (value) {
                if (ingredient.quantity.isNotEmpty && (value == null || value.trim().isEmpty)) {
                  return 'Required';
                }
                return null;
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.remove_circle, color: Colors.red),
            onPressed: _ingredients.length > 1 ? () => _removeIngredientRow(index) : null,
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    required String? Function(String?) validator,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(230),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_getIconForField(label), color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade600),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.orange, width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.red, width: 2),
              ),
              contentPadding: const EdgeInsets.all(12),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            validator: validator,
          ),
        ],
      ),
    );
  }

  IconData _getIconForField(String label) {
    switch (label) {
      case 'Recipe Name': return Icons.restaurant;
      case 'Ingredients': return Icons.list_alt;
      case 'Directions': return Icons.description;
      default: return Icons.edit;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Your Recipe'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(child: Image.asset('assets/background.jpeg', fit: BoxFit.cover)),
          Column(
            children: [
              Container(
                color: Colors.white.withOpacity(0.9),
                child: Row(
                  children: [
                    _buildTabButton("Submit Recipe", 0),
                    _buildTabButton("Saved Drafts", 1),
                    _buildTabButton("Submitted", 2),
                  ],
                ),
              ),
              Expanded(
                child: _tabIndex == 0
                    ? _buildSubmitForm()
                    : _tabIndex == 1
                        ? _buildDraftList()
                        : _buildSubmittedList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(230),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Icon(Icons.add_circle_outline, size: 48, color: Colors.orange),
                  const SizedBox(height: 12),
                  const Text(
                    'Share Your Recipe',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            _buildTextField(
              controller: _nameController,
              label: 'Recipe Name',
              hint: 'Enter the name of your recipe',
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a recipe name';
                }
                if (value.trim().length < 3) {
                  return 'Recipe name must be at least 3 characters';
                }
                return null;
              },
            ),

            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(230),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.description, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Description (Optional)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Tell us about this recipe... When did you develop it? What makes it special?',
                      hintStyle: TextStyle(color: Colors.grey.shade600),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.orange, width: 2),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Share the story behind this recipe or any special notes',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Structured Ingredients Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(230),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.list_alt, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Ingredients',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Ingredient rows
                  ..._ingredients.asMap().entries.map((entry) {
                    return _buildIngredientRow(entry.key);
                  }),
                  
                  // Add ingredient button
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _addIngredientRow,
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Add Ingredient'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.orange),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            _buildTextField(
              controller: _directionsController,
              label: 'Directions',
              hint: 'Provide step-by-step instructions',
              maxLines: 10,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter the directions';
                }
                if (value.trim().length < 20) {
                  return 'Please provide more detailed directions';
                }
                return null;
              },
            ),

            const SizedBox(height: 20),

            // 🔥 NEW: Recipe Nutrition Section with TABBED VIEW
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(230),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.analytics, color: Colors.orange, size: 22),
                      const SizedBox(width: 8),
                      const Text(
                        'Recipe Nutrition (Saved Ingredients)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),
                  const Text(
                    'We will try to match saved ingredients to your list and estimate total nutrition.',
                    style: TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                  const SizedBox(height: 12),

                  // Analyze button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isAnalyzingNutrition ? null : _analyzeRecipeNutrition,
                      icon: _isAnalyzingNutrition
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.calculate),
                      label: Text(
                        _isAnalyzingNutrition ? 'Analyzing...' : 'Analyze Recipe Nutrition',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Matched ingredient list
                  if (_matchedNutritionIngredients.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.check_circle, size: 16, color: Colors.orange.shade700),
                              const SizedBox(width: 6),
                              Text(
                                'Matched ${_matchedNutritionIngredients.length} ingredient${_matchedNutritionIngredients.length == 1 ? '' : 's'}:',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ..._matchedNutritionIngredients.map(
                            (n) => Padding(
                              padding: const EdgeInsets.only(left: 8, top: 2),
                              child: Text(
                                '• ${n.productName}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 🔥 NEW: Tabbed Nutrition Display
                  if (_recipeNutrition != null) ...[
                    DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          // Tab Bar
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: TabBar(
                              labelColor: Colors.orange,
                              unselectedLabelColor: Colors.grey.shade600,
                              indicatorColor: Colors.orange,
                              indicatorWeight: 3,
                              tabs: [
                                Tab(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.summarize, size: 16),
                                      SizedBox(width: 6),
                                      Text('Summary', style: TextStyle(fontSize: 13)),
                                    ],
                                  ),
                                ),
                                Tab(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.restaurant_menu, size: 16),
                                      SizedBox(width: 6),
                                      Text('Full Label', style: TextStyle(fontSize: 13)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 12),
                          
                          // Tab Views
                          SizedBox(
                            height: 450,
                            child: TabBarView(
                              children: [
                                // Tab 1: Summary (existing display)
                                SingleChildScrollView(
                                  child: RecipeNutritionDisplay(nutrition: _recipeNutrition!),
                                ),
                                
                                // Tab 2: Full FDA Label with Insights
                                SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      NutritionFactsLabel(
                                        nutrition: _convertRecipeNutritionToInfo(_recipeNutrition!),
                                        showbariScore: true,
                                      ),
                                      
                                      const SizedBox(height: 12),
                                      
                                      // Nutrition quality indicators
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.blue.shade200),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(Icons.eco, size: 16, color: Colors.blue.shade700),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Recipe Profile',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.blue.shade900,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            
                                            // Dietary labels
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: [
                                                if (RecipeNutritionService.isHighProtein(_recipeNutrition!))
                                                  _buildBadge('High Protein', Colors.blue),
                                                if (RecipeNutritionService.isLowCarb(_recipeNutrition!))
                                                  _buildBadge('Low Carb', Colors.orange),
                                                if (RecipeNutritionService.isLowFat(_recipeNutrition!))
                                                  _buildBadge('Low Fat', Colors.purple),
                                                if (RecipeNutritionService.isLowSugar(_recipeNutrition!))
                                                  _buildBadge('Low Sugar', Colors.green),
                                                if (RecipeNutritionService.isBariatricFriendly(_recipeNutrition!))
                                                  _buildBadge('Bariatric Friendly', Colors.red),
                                              ],
                                            ),

                                            // Health warnings
                                            if (RecipeNutritionService.getBariatricWarnings(_recipeNutrition!).isNotEmpty) ...[
                                              const SizedBox(height: 12),
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange.shade50,
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: Colors.orange.shade200),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Icon(Icons.warning_amber, size: 14, color: Colors.orange.shade700),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          'Health Notes:',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.bold,
                                                            color: Colors.orange.shade900,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    ...RecipeNutritionService.getBariatricWarnings(_recipeNutrition!).map(
                                                      (warning) => Padding(
                                                        padding: const EdgeInsets.only(left: 8, top: 2),
                                                        child: Text(
                                                          '• $warning',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: Colors.orange.shade800,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                            
                                            // Health benefits
                                            if (RecipeNutritionService.getHealthBenefits(_recipeNutrition!).isNotEmpty) ...[
                                              const SizedBox(height: 12),
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange.shade50,
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: Colors.orange.shade200),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Icon(Icons.thumb_up, size: 14, color: Colors.orange.shade700),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          'Benefits:',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.bold,
                                                            color: Colors.orange.shade900,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    ...RecipeNutritionService.getHealthBenefits(_recipeNutrition!).map(
                                                      (benefit) => Padding(
                                                        padding: const EdgeInsets.only(left: 8, top: 2),
                                                        child: Text(
                                                          '• $benefit',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: Colors.orange.shade800,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                  ],
                  
                  // Disclaimer
                  if (_recipeNutrition != null)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, size: 14, color: Colors.grey.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "🛈 This is an estimate based on your saved ingredients. "
                              "Accuracy depends on the items you have saved.",
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // BUTTONS SECTION
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(230),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  // Show which draft is being edited
                  if (_loadedDraftName != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.edit_note, color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Editing Draft',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  _loadedDraftName!,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: ElevatedButton.icon(
                            onPressed: isSubmitting ? null : (_loadedDraftName != null ? _updateDraft : _saveRecipe),
                            icon: Icon(_isSaved ? Icons.check_circle : Icons.save, size: 20),
                            label: Text(
                              _isSaved 
                                  ? 'Saved!' 
                                  : (_loadedDraftName != null ? 'Update Draft' : 'Save Draft'),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isSaved ? Colors.orange.shade700 : Colors.blue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: ElevatedButton.icon(
                            onPressed: isSubmitting ? null : _addToGroceryList,
                            icon: const Icon(Icons.add_shopping_cart, size: 20),
                            label: const Text(
                              'Grocery List',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: isSubmitting ? null : _submitRecipe,
                      icon: isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.send, size: 20),
                      label: Text(
                        isSubmitting ? 'Submitting...' : 'Submit to Community',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: TextButton.icon(
                      onPressed: isSubmitting
                          ? null
                          : () {
                              if (_nameController.text.isNotEmpty ||
                                  _ingredients.any((i) => i.isValid) ||
                                  _directionsController.text.isNotEmpty) {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Discard Changes?'),
                                    content: const Text(
                                      'You have unsaved changes. Are you sure you want to discard them?'
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Keep Editing'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          Navigator.pop(context);
                                        },
                                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                                        child: const Text('Discard'),
                                      ),
                                    ],
                                  ),
                                );
                              } else {
                                Navigator.pop(context);
                              }
                            },
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancel'),
                      style: TextButton.styleFrom(foregroundColor: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}