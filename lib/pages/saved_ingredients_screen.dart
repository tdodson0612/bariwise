// lib/pages/saved_ingredients_screen.dart
import 'package:flutter/material.dart';
import 'package:bari_wise/services/saved_ingredients_service.dart';
import 'package:bari_wise/widgets/nutrition_display.dart';
import 'package:bari_wise/models/nutrition_info.dart';
import 'package:bari_wise/services/error_handling_service.dart';
import '../barihealthbar.dart';

class SavedIngredientsScreen extends StatefulWidget {
  const SavedIngredientsScreen({super.key});

  @override
  State<SavedIngredientsScreen> createState() => _SavedIngredientsScreenState();
}

class _SavedIngredientsScreenState extends State<SavedIngredientsScreen> {
  List<NutritionInfo> _ingredients = [];
  List<NutritionInfo> _filteredIngredients = [];
  NutritionInfo? _selectedIngredient;

  final TextEditingController _searchController = TextEditingController();

  static const String disclaimer =
      "These are average nutritional values and may vary. "
      "For more accurate details, try scanning the barcode.";

  @override
  void initState() {
    super.initState();
    _loadSavedIngredients();
  }

  Future<void> _loadSavedIngredients() async {
    final items = await SavedIngredientsService.loadSavedIngredients();
    setState(() {
      _ingredients = items;
      _filteredIngredients = items;
    });
  }

  void _filterList(String query) {
    query = query.trim().toLowerCase();

    if (query.isEmpty) {
      setState(() => _filteredIngredients = _ingredients);
      return;
    }

    setState(() {
      _filteredIngredients = _ingredients
          .where((item) => item.productName.toLowerCase().contains(query))
          .toList();
    });
  }

  Future<void> _removeIngredient(NutritionInfo item) async {
    await SavedIngredientsService.removeIngredient(item.productName);

    setState(() {
      _ingredients.removeWhere((i) => i.productName == item.productName);
      _filteredIngredients
          .removeWhere((i) => i.productName == item.productName);

      if (_selectedIngredient?.productName == item.productName) {
        _selectedIngredient = null;
      }
    });

    ErrorHandlingService.showSuccess(context, "Removed ingredient.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Saved Ingredients"),
        backgroundColor: Colors.orange,
      ),
      body: Row(
        children: [
          // LEFT SIDE — LIST
          Expanded(
            flex: 1,
            child: Column(
              children: [
                // SEARCH BOX
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _filterList,
                    decoration: InputDecoration(
                      hintText: "Search saved ingredients...",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.search),
                    ),
                  ),
                ),

                // INGREDIENT LIST
                Expanded(
                  child: _filteredIngredients.isEmpty
                      ? const Center(
                          child: Text(
                            "No saved ingredients.",
                            style: TextStyle(fontSize: 16),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredIngredients.length,
                          itemBuilder: (context, index) {
                            final item = _filteredIngredients[index];

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                title: Text(item.productName),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () => _removeIngredient(item),
                                ),
                                onTap: () {
                                  setState(() => _selectedIngredient = item);
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          // RIGHT SIDE — DETAILS PANEL
          Expanded(
            flex: 1,
            child: _selectedIngredient == null
                ? const Center(
                    child: Text(
                      "Select an ingredient to view details",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: NutritionDisplay(
                      nutrition: _selectedIngredient!,
                      bariScore: BariHealthCalculator.calculate(
                        fat: _selectedIngredient!.fat,
                        sodium: _selectedIngredient!.sodium,
                        sugar: _selectedIngredient!.sugar,
                        calories: _selectedIngredient!.calories,
                      ),
                      disclaimer: disclaimer,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
