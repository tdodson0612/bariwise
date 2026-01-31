//search history service
// lib/services/search_history_service.dart
// Manages saving, loading, and clearing nutrition search history
import 'package:shared_preferences/shared_preferences.dart';

class SearchHistoryService {
  static const String _key = 'nutrition_search_history';
  static const int _maxHistory = 10;

  /// Load search history (most recent first)
  static Future<List<String>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  /// Add a search term
  static Future<void> addToHistory(String term) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList(_key) ?? [];

    term = term.trim();
    if (term.isEmpty) return;

    // Remove duplicates
    history.remove(term);

    // Add new term at the top
    history.insert(0, term);

    // Cap history length
    if (history.length > _maxHistory) {
      history = history.sublist(0, _maxHistory);
    }

    await prefs.setStringList(_key, history);
  }

  /// Clear all search history
  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
