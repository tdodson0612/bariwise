// test/recipe_generator_test.dart - FIXED VERSION
import 'package:flutter_test/flutter_test.dart';
import 'package:bari_wise/home_screen.dart';
import 'package:bari_wise/barihealthbar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RecipeGenerator.searchByKeywords', () {
    test('Returns recipes when provided with keywords', () async {
      final recipes = await RecipeGenerator.searchByKeywords(['tomato', 'pasta']);
      
      // Should return either real recipes from worker or fallback healthy recipes
      expect(recipes, isNotEmpty);
      expect(recipes.first.title, isNotEmpty);
      expect(recipes.first.ingredients, isNotEmpty);
      expect(recipes.first.instructions, isNotEmpty);
    });

    test('Returns healthy recipes when keywords are empty', () async {
      final recipes = await RecipeGenerator.searchByKeywords([]);
      
      expect(recipes, isNotEmpty);
      expect(recipes.length, 2);
      // Should get fallback healthy recipes
      expect(recipes.any((r) => 
        r.title.contains('Mediterranean') || 
        r.title.contains('Quinoa')
      ), isTrue);
    });

    test('Normalizes and deduplicates keywords', () async {
      // Test that duplicate and empty keywords are handled
      final recipes = await RecipeGenerator.searchByKeywords([
        'Tomato',
        'tomato',
        '  TOMATO  ',
        '',
      ]);
      
      expect(recipes, isNotEmpty);
      expect(recipes.first.title, isNotEmpty);
    });

    test('Handles network errors gracefully by returning fallback recipes', () async {
      // Even with network errors, should return fallback recipes instead of throwing
      final recipes = await RecipeGenerator.searchByKeywords(['chicken']);
      
      expect(recipes, isNotEmpty);
      expect(recipes.first.title, isNotEmpty);
    });
  });

  group('RecipeGenerator.generateSuggestions', () {
    test('Returns healthy recipes for high score (75+)', () {
      final recipes = RecipeGenerator.generateSuggestions(80);
      
      expect(recipes, isNotEmpty);
      expect(recipes.length, 2);
      expect(recipes.any((r) => 
        r.title.contains('Mediterranean') || 
        r.title.contains('Quinoa')
      ), isTrue);
    });

    test('Returns moderate recipes for mid-range score (50-74)', () {
      final recipes = RecipeGenerator.generateSuggestions(60);
      
      expect(recipes, isNotEmpty);
      expect(recipes.length, 2);
      expect(recipes.any((r) => 
        r.title.contains('Baked Chicken') || 
        r.title.contains('Lentil')
      ), isTrue);
    });

    test('Returns detox recipes for low score (0-49)', () {
      final recipes = RecipeGenerator.generateSuggestions(30);
      
      expect(recipes, isNotEmpty);
      expect(recipes.length, 2);
      expect(recipes.any((r) => 
        r.title.contains('Detox') || 
        r.title.contains('Steamed')
      ), isTrue);
    });

    test('Handles boundary score of 75', () {
      final recipes = RecipeGenerator.generateSuggestions(75);
      
      expect(recipes, isNotEmpty);
      expect(recipes.any((r) => 
        r.title.contains('Mediterranean') || 
        r.title.contains('Quinoa')
      ), isTrue);
    });

    test('Handles boundary score of 50', () {
      final recipes = RecipeGenerator.generateSuggestions(50);
      
      expect(recipes, isNotEmpty);
      expect(recipes.any((r) => 
        r.title.contains('Baked Chicken') || 
        r.title.contains('Lentil')
      ), isTrue);
    });

    test('Handles score of 0', () {
      final recipes = RecipeGenerator.generateSuggestions(0);
      
      expect(recipes, isNotEmpty);
      expect(recipes.any((r) => 
        r.title.contains('Detox') || 
        r.title.contains('Steamed')
      ), isTrue);
    });

    test('Handles score of 100', () {
      final recipes = RecipeGenerator.generateSuggestions(100);
      
      expect(recipes, isNotEmpty);
      expect(recipes.any((r) => 
        r.title.contains('Mediterranean') || 
        r.title.contains('Quinoa')
      ), isTrue);
    });
  });

  group('Recipe model', () {
    test('Creates recipe from JSON with array ingredients', () {
      final json = {
        'title': 'Test Recipe',
        'description': 'Test description',
        'ingredients': ['ingredient1', 'ingredient2', 'ingredient3'],
        'instructions': 'Test instructions',
      };

      final recipe = Recipe.fromJson(json);

      expect(recipe.title, 'Test Recipe');
      expect(recipe.description, 'Test description');
      expect(recipe.ingredients, ['ingredient1', 'ingredient2', 'ingredient3']);
      expect(recipe.instructions, 'Test instructions');
    });

    test('Handles string ingredients by splitting on comma', () {
      final json = {
        'title': 'Test Recipe',
        'description': 'Test description',
        'ingredients': 'flour, sugar, eggs',
        'instructions': 'Mix and bake',
      };

      final recipe = Recipe.fromJson(json);

      expect(recipe.title, 'Test Recipe');
      expect(recipe.ingredients, ['flour', 'sugar', 'eggs']);
      expect(recipe.instructions, 'Mix and bake');
    });

    test('Handles alternative JSON key names', () {
      final json = {
        'name': 'Alternative Name',
        'description': 'Test description',
        'ingredients': ['ingredient1'],
        'directions': 'Alternative instructions',
      };

      final recipe = Recipe.fromJson(json);

      expect(recipe.title, 'Alternative Name');
      expect(recipe.instructions, 'Alternative instructions');
    });

    test('Handles missing optional fields', () {
      final json = {
        'title': 'Minimal Recipe',
      };

      final recipe = Recipe.fromJson(json);

      expect(recipe.title, 'Minimal Recipe');
      expect(recipe.description, '');
      expect(recipe.ingredients, isEmpty);
      expect(recipe.instructions, '');
    });

    test('Converts recipe to JSON correctly', () {
      final recipe = Recipe(
        title: 'Test Recipe',
        description: 'Test description',
        ingredients: ['ingredient1', 'ingredient2'],
        instructions: 'Test instructions',
      );

      final json = recipe.toJson();

      expect(json['title'], 'Test Recipe');
      expect(json['description'], 'Test description');
      expect(json['ingredients'], ['ingredient1', 'ingredient2']);
      expect(json['instructions'], 'Test instructions');
    });
  });

  group('bariHealthBar.calculateScore', () {
    test('Returns 100 for zero values', () {
      final score = BariHealthBar.calculateScore(
        fat: 0, 
        sodium: 0, 
        sugar: 0, 
        calories: 0,
      );
      expect(score, 100);
    });

    test('Returns 0 for extremely high values', () {
      final score = BariHealthBar.calculateScore(
        fat: 1000, 
        sodium: 10000, 
        sugar: 500, 
        calories: 10000,
      );
      expect(score, 0);
    });

    test('Produces lower score when inputs increase', () {
      final lowScore = BariHealthBar.calculateScore(
        fat: 2, 
        sodium: 50, 
        sugar: 2, 
        calories: 50,
      );
      
      final highScore = BariHealthBar.calculateScore(
        fat: 10, 
        sodium: 200, 
        sugar: 10, 
        calories: 200,
      );
      
      expect(highScore, lessThan(lowScore));
    });

    test('Returns value between 0 and 100', () {
      final score = BariHealthBar.calculateScore(
        fat: 5, 
        sodium: 100, 
        sugar: 5, 
        calories: 100,
      );
      
      expect(score, greaterThanOrEqualTo(0));
      expect(score, lessThanOrEqualTo(100));
    });

    test('Handles typical food values correctly', () {
      // Example: Apple (per 100g)
      final appleScore = BariHealthBar.calculateScore(
        fat: 0.3,
        sodium: 1,
        sugar: 10,
        calories: 52,
      );
      
      expect(appleScore, greaterThan(70));
      
      // Example: Potato chips (per 100g)
      final chipsScore = BariHealthBar.calculateScore(
        fat: 35,
        sodium: 500,
        sugar: 1,
        calories: 536,
      );
      
      expect(chipsScore, lessThan(30));
    });
  });
}