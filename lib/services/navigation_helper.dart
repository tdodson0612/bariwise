import 'package:flutter/material.dart';

class NavigationHelper {
  /// Opens the submit-recipe page with prefilled ingredient details.
  static void openSubmitRecipeWithIngredient(
    BuildContext context,
    String ingredientName,
  ) {
    final recipeDraft = {
      'initialIngredients': ingredientName,
      'initialTitle': "$ingredientName Recipe",
      'initialDescription': "A recipe featuring $ingredientName.",
    };

    Navigator.pushNamed(
      context,
      '/submit-recipe',
      arguments: recipeDraft,
    );
  }
}
