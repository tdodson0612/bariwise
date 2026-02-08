// lib/utils/height_utils.dart
// Utility class for height conversions and formatting

class HeightUtils {
  /// Convert cm to feet and inches
  /// Returns a map with 'feet' and 'inches' keys
  static Map<String, int> cmToFeetInches(double cm) {
    final totalInches = cm / 2.54;
    final feet = totalInches ~/ 12;
    final inches = (totalInches % 12).round();
    
    return {'feet': feet, 'inches': inches};
  }
  
  /// Convert feet and inches to cm
  static double feetInchesToCm(int feet, int inches) {
    final totalInches = (feet * 12) + inches;
    return totalInches * 2.54;
  }
  
  /// Format height for display based on unit preference
  /// - 'metric' returns "170 cm"
  /// - 'imperial' returns "5'7""
  static String formatHeight(double heightCm, String unitPreference) {
    if (unitPreference == 'imperial') {
      final converted = cmToFeetInches(heightCm);
      return '${converted['feet']}\'${converted['inches']}"';
    } else {
      return '${heightCm.toStringAsFixed(0)} cm';
    }
  }
  
  /// Validate height input (reasonable human height range)
  /// Returns true if height is between 50cm (1'8") and 250cm (8'2")
  static bool isValidHeight(double heightCm) {
    return heightCm >= 50 && heightCm <= 250;
  }
  
  /// Get common height range text for display
  static String getCommonHeightRange(String unitPreference) {
    if (unitPreference == 'imperial') {
      return 'Common: 4\'10" - 6\'6"';
    } else {
      return 'Common: 147cm - 198cm';
    }
  }
  
  /// Convert height from any unit to cm (handles validation)
  /// Throws FormatException if invalid
  static double parseHeightToCm({
    String? cmText,
    String? feetText,
    String? inchesText,
    required String unitPreference,
  }) {
    if (unitPreference == 'imperial') {
      // Parse imperial
      if (feetText == null || feetText.trim().isEmpty) {
        throw const FormatException('Please enter feet');
      }
      if (inchesText == null || inchesText.trim().isEmpty) {
        throw const FormatException('Please enter inches');
      }
      
      final feet = int.tryParse(feetText.trim());
      final inches = int.tryParse(inchesText.trim());
      
      if (feet == null || feet < 0) {
        throw const FormatException('Invalid feet value');
      }
      if (inches == null || inches < 0 || inches >= 12) {
        throw const FormatException('Inches must be between 0-11');
      }
      
      return feetInchesToCm(feet, inches);
    } else {
      // Parse metric
      if (cmText == null || cmText.trim().isEmpty) {
        throw const FormatException('Please enter height in cm');
      }
      
      final cm = double.tryParse(cmText.trim());
      if (cm == null || cm <= 0) {
        throw const FormatException('Invalid height value');
      }
      
      return cm;
    }
  }
}