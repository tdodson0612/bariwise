// lib/pages/manual_barcode_entry_screen.dart

import 'package:flutter/material.dart';
import 'package:bari_wise/services/nutrition_api_service.dart';
import 'package:bari_wise/models/nutrition_info.dart';
import 'package:bari_wise/widgets/nutrition_display.dart';
import 'package:bari_wise/services/error_handling_service.dart';
import '../services/recipe_nutrition_service.dart';
import '../barihealthbar.dart';

class ManualBarcodeEntryScreen extends StatefulWidget {
  const ManualBarcodeEntryScreen({super.key});

  @override
  State<ManualBarcodeEntryScreen> createState() =>
      _ManualBarcodeEntryScreenState();
}

class _ManualBarcodeEntryScreenState extends State<ManualBarcodeEntryScreen> {
  final TextEditingController _barcodeController = TextEditingController();
  bool _isLoading = false;
  NutritionInfo? _nutrition;

  static const String disclaimer =
      "These are average nutritional values and may vary depending on brand or source. "
      "For more accurate details, try scanning the barcode.";

  @override
  void initState() {
    super.initState();

    // Autofocus barcode input when screen loads
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) FocusScope.of(context).requestFocus(FocusNode());
    });
  }

  Future<void> _lookupBarcode() async {
    final barcode = _barcodeController.text.trim();

    if (barcode.isEmpty) {
      ErrorHandlingService.showSimpleError(context, "Enter a barcode first.");
      return;
    }

    // Validate numeric-only
    if (!RegExp(r'^[0-9]+$').hasMatch(barcode)) {
      ErrorHandlingService.showSimpleError(
        context,
        "Barcodes must contain digits only.",
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _nutrition = null;
    });

    try {
      final result = await NutritionApiService.fetchByBarcode(barcode);

      if (result == null) {
        ErrorHandlingService.showSimpleError(
          context,
          "Product not found in database.",
        );
      } else {
        setState(() => _nutrition = result);
      }
    } catch (e) {
      ErrorHandlingService.handleError(
        context: context,
        error: e,
        customMessage: "Error fetching product information.",
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Manual Barcode Entry"),
        backgroundColor: Colors.orange,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(), // Dismiss keyboard
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const SizedBox(height: 12),

              // INPUT FIELD
              TextField(
                controller: _barcodeController,
                decoration: InputDecoration(
                  labelText: "Enter Barcode Number",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.numbers),
                ),
                keyboardType: TextInputType.number,
                onSubmitted: (_) => _lookupBarcode(),
              ),

              const SizedBox(height: 16),

              // LOOKUP BUTTON
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _lookupBarcode,
                  icon: const Icon(Icons.search),
                  label: Text(
                    _isLoading ? "Searching..." : "Look Up Product",
                    style: const TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // LOADING INDICATOR
              if (_isLoading)
                const Center(child: CircularProgressIndicator()),

              // RESULT
              if (_nutrition != null)
                NutritionDisplay(
                  nutrition: _nutrition!,
                  bariScore: BariHealthCalculator.calculate(
                    fat: _nutrition!.fat,
                    sodium: _nutrition!.sodium,
                    sugar: _nutrition!.sugar,
                    calories: _nutrition!.calories,
                  ),
                  disclaimer: disclaimer,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
