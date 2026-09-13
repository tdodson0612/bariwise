// test/grocery_service_test.dart
//
// Unit tests for GroceryService.autoAssignCategory — a pure, static,
// keyword-matching function with no Supabase or network dependency, making
// it directly and cheaply testable. Covers the basic per-category matches,
// case-insensitivity, the "Other" fallback, and the specific first-match
// ordering behavior (since some real grocery items match keywords from more
// than one category, e.g. "chicken broth" matches both "chicken" under
// Meat & Seafood and "broth" under Pantry — Meat & Seafood wins because it
// appears first in the category map).

import 'package:flutter_test/flutter_test.dart';
import 'package:bari_wise/services/grocery_service.dart';

void main() {
  group('GroceryService.autoAssignCategory', () {
    test('Matches a simple Produce item', () {
      expect(GroceryService.autoAssignCategory('Apple'), 'Produce');
      expect(GroceryService.autoAssignCategory('bananas'), 'Produce');
    });

    test('Matches a simple Dairy & Eggs item', () {
      expect(GroceryService.autoAssignCategory('Whole milk'), 'Dairy & Eggs');
      expect(GroceryService.autoAssignCategory('large eggs'), 'Dairy & Eggs');
    });

    test('Matches a simple Meat & Seafood item', () {
      expect(GroceryService.autoAssignCategory('Chicken breast'), 'Meat & Seafood');
      expect(GroceryService.autoAssignCategory('Ground turkey'), 'Meat & Seafood');
    });

    test('Matches a simple Snacks item', () {
      expect(GroceryService.autoAssignCategory('Chips'), 'Snacks');
    });

    test('Matches a simple Household item', () {
      expect(GroceryService.autoAssignCategory('Paper towels'), 'Household');
    });

    test('Is case-insensitive', () {
      expect(GroceryService.autoAssignCategory('CHICKEN BREAST'), 'Meat & Seafood');
      expect(GroceryService.autoAssignCategory('ChIcKeN'), 'Meat & Seafood');
    });

    test('Falls back to "Other" for an unrecognized item', () {
      expect(GroceryService.autoAssignCategory('Xyzzy widget'), 'Other');
      expect(GroceryService.autoAssignCategory(''), 'Other');
    });

    test('First matching category wins when an item matches multiple keywords', () {
      // "chicken broth" matches "chicken" (Meat & Seafood) and "broth"
      // (Pantry). Meat & Seafood is declared earlier in the category map,
      // so it should win. This test locks in that ordering behavior so a
      // future edit to the keyword map doesn't silently change it.
      expect(GroceryService.autoAssignCategory('Chicken broth'), 'Meat & Seafood');
    });

    test('Matches a substring keyword inside a longer phrase', () {
      // "ground beef" is itself a listed keyword under Meat & Seafood,
      // distinct from the separate "beef"-less entries.
      expect(GroceryService.autoAssignCategory('1 lb ground beef'), 'Meat & Seafood');
    });

    test('categories list contains "Other" as the final fallback option', () {
      expect(GroceryService.categories, contains('Other'));
      expect(GroceryService.categories.last, 'Other');
    });
  });
}