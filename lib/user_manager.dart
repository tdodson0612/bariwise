//lib/user_manager.dart

class UserManager {
  static bool _hasPurchased = false;
  static bool _isMonetized = false;

  static bool get showAds => _isMonetized && !_hasPurchased;

  static void setPurchased(bool value) {
    _hasPurchased = value;
  }

  static void setMonetized(bool value) {
    _isMonetized = value;
  }

  static bool get isMonetized => _isMonetized;
  static bool get hasPurchased => _hasPurchased;
}
