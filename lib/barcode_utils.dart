//lib/barcode_utils.dart
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

Future<String> decodeBarcodeAndLookup(String imagePath) async {
  final inputImage = InputImage.fromFilePath(imagePath);
  final barcodeScanner = BarcodeScanner();

  try {
    final barcodes = await barcodeScanner.processImage(inputImage);
    await barcodeScanner.close();

    if (barcodes.isEmpty) {
      return "No barcode found. Please retake.";
    }

    final barcode = barcodes.first;
    final barcodeData = barcode.rawValue ?? 'Unknown';

    final lookupResult = await fetchNutritionInfo(barcodeData);
    return lookupResult;
  } catch (e) {
    return "Error decoding barcode: $e";
  }
}

Future<String> fetchNutritionInfo(String barcode) async {
  final url =
      "https://world.openfoodfacts.org/api/v0/product/$barcode.json";

  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['status'] == 1) {
        final product = data['product'];
        final productName = product['product_name'] ?? 'Unknown product';
        final nutriments = product['nutriments'] ?? {};
        final energy = nutriments['energy-kcal_100g'] ?? 'N/A';
        final fat = nutriments['fat_100g'] ?? 'N/A';
        final sugars = nutriments['sugars_100g'] ?? 'N/A';

        return 'Product: $productName\nEnergy: $energy kcal/100g\nFat: $fat g/100g\nSugars: $sugars g/100g';
      } else {
        return "Product not found in database.";
      }
    } else {
      return "Failed to fetch product info.";
    }
  } catch (e) {
    return "Error fetching nutrition info: $e";
  }
}

int calculatebariHealthScore({
  required double fat,
  required double sodium,
  required double sugar,
  required double calories,
}) {
  // Define max safe thresholds (you can tweak these)
  const fatMax = 20.0;       // grams
  const sodiumMax = 500.0;   // mg
  const sugarMax = 20.0;     // grams
  const calMax = 400.0;      // kcal

  // Normalize each component to a score from 0 (bad) to 1 (good)
  double fatScore = 1 - (fat / fatMax).clamp(0, 1);
  double sodiumScore = 1 - (sodium / sodiumMax).clamp(0, 1);
  double sugarScore = 1 - (sugar / sugarMax).clamp(0, 1);
  double calScore = 1 - (calories / calMax).clamp(0, 1);

  // Weighted average (tweak weights based on medical importance)
  double finalScore = (fatScore * 0.3) +
                      (sodiumScore * 0.25) +
                      (sugarScore * 0.25) +
                      (calScore * 0.2);

  return (finalScore * 100).round();  // Convert to 0–100
}

