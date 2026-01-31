// lib/pages/edit_recipe_page.dart - WITH CACHE INVALIDATION
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/submitted_recipe.dart';
import '../services/submitted_recipes_service.dart';
import '../services/error_handling_service.dart';

class EditRecipePage extends StatefulWidget {
  final SubmittedRecipe recipe;

  const EditRecipePage({
    super.key,
    required this.recipe,
  });

  @override
  State<EditRecipePage> createState() => _EditRecipePageState();
}

class _EditRecipePageState extends State<EditRecipePage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _ingredientsController;
  late TextEditingController _directionsController;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.recipe.recipeName);
    _ingredientsController = TextEditingController(text: widget.recipe.ingredients);
    _directionsController = TextEditingController(text: widget.recipe.directions);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ingredientsController.dispose();
    _directionsController.dispose();
    super.dispose();
  }

  // Invalidate cached recipes after update
  Future<void> _invalidateRecipeCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Clear submitted recipes cache (list)
      await prefs.remove('submitted_recipes_${widget.recipe.userId}');
      
      // Clear individual recipe cache if it exists
      await prefs.remove('submitted_recipe_${widget.recipe.id}');
      
      print('Recipe cache invalidated after update');
    } catch (e) {
      print('Error invalidating recipe cache: $e');
      // Don't throw - cache invalidation failure shouldn't break the update
    }
  }

  Future<void> _saveRecipe() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Check if recipe ID is valid
    if (widget.recipe.id == null) {
      ErrorHandlingService.showSimpleError(
        context,
        'Invalid recipe ID',
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await SubmittedRecipesService.updateRecipe(
        recipeId: widget.recipe.id!,
        recipeName: _nameController.text.trim(),
        ingredients: _ingredientsController.text.trim(),
        directions: _directionsController.text.trim(),
      );

      // Invalidate cache so next fetch gets fresh data
      await _invalidateRecipeCache();

      if (mounted) {
        ErrorHandlingService.showSuccess(
          context,
          'Recipe updated successfully!',
        );
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });

        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Unable to update recipe',
          onRetry: _saveRecipe,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Recipe'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          if (_isSubmitting)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          // Background
          Positioned.fill(
            child: Image.asset(
              'assets/background.jpeg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.orange.shade50,
                );
              },
            ),
          ),
          
          // Content
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Info Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Update your recipe details below',
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Recipe Name
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha((0.95 * 255).toInt()),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.restaurant, color: Colors.orange.shade700),
                            const SizedBox(width: 8),
                            const Text(
                              'Recipe Name',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            hintText: 'e.g., Chocolate Chip Cookies',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter a recipe name';
                            }
                            return null;
                          },
                          enabled: !_isSubmitting,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Ingredients
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha((0.95 * 255).toInt()),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.list_alt, color: Colors.orange.shade700),
                            const SizedBox(width: 8),
                            const Text(
                              'Ingredients',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'List each ingredient on a new line',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _ingredientsController,
                          decoration: InputDecoration(
                            hintText: '2 cups flour\n1 cup sugar\n1/2 cup butter',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          maxLines: 10,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter ingredients';
                            }
                            return null;
                          },
                          enabled: !_isSubmitting,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Directions
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha((0.95 * 255).toInt()),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.format_list_numbered, color: Colors.orange.shade700),
                            const SizedBox(width: 8),
                            const Text(
                              'Directions',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Describe the cooking steps',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _directionsController,
                          decoration: InputDecoration(
                            hintText: '1. Preheat oven to 350°F\n2. Mix ingredients\n3. Bake for 12 minutes',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          maxLines: 10,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter directions';
                            }
                            return null;
                          },
                          enabled: !_isSubmitting,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSubmitting
                              ? null
                              : () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(color: Colors.grey.shade400),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _saveRecipe,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade400,
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.save),
                                    SizedBox(width: 8),
                                    Text(
                                      'Save Changes',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
