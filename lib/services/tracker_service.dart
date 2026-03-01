// lib/services/tracker_service.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tracker_entry.dart';
import '../barihealthbar.dart';
import '../config/app_config.dart';

class TrackerService {
  static const String _STORAGE_KEY_PREFIX = 'tracker_entries_';
  static const String _DISCLAIMER_KEY = 'tracker_disclaimer_accepted';

  // ========================================
  // DAILY NUTRITION TARGETS (bariatric-diet based)
  // ========================================

  static const Map<String, double> dailyTargets = {
    'calories': 1200,     // grams — bariatric patients eat much less
    'fat': 40,            // grams — keep fat low post-surgery
    'sodium': 1500,       // mg — low sodium for blood pressure
    'sugar': 25,          // grams — very low sugar (dumping syndrome risk)
    'protein': 80,        // grams — high protein priority post-surgery
    'fiber': 25,          // grams — fiber for digestive health
    'saturatedFat': 10,   // grams — limit saturated fat
  };

  // Upper limits — nutrients where exceeding is bad
  static const Set<String> _upperLimitNutrients = {
    'fat', 'sodium', 'sugar', 'saturatedFat'
  };

  // Lower targets — nutrients where getting enough is good
  static const Set<String> _lowerTargetNutrients = {
    'calories', 'protein', 'fiber'
  };

  // ========================================
  // DISCLAIMER MANAGEMENT
  // ========================================

  /// Check if user has accepted the tracker disclaimer
  static Future<bool> hasAcceptedDisclaimer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_DISCLAIMER_KEY) ?? false;
    } catch (e) {
      AppConfig.debugPrint('Error checking disclaimer: $e');
      return false;
    }
  }

  /// Mark disclaimer as accepted
  static Future<void> acceptDisclaimer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_DISCLAIMER_KEY, true);
      AppConfig.debugPrint('✅ Tracker disclaimer accepted');
    } catch (e) {
      AppConfig.debugPrint('❌ Error accepting disclaimer: $e');
      throw Exception('Failed to save disclaimer acceptance');
    }
  }

  // ========================================
  // STORAGE KEY MANAGEMENT
  // ========================================

  static String _getStorageKey(String userId) {
    return '$_STORAGE_KEY_PREFIX$userId';
  }

  // ========================================
  // ENTRY MANAGEMENT
  // ========================================

  /// Get all tracker entries for current user
  static Future<List<TrackerEntry>> getEntries(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getStorageKey(userId);
      final jsonString = prefs.getString(key);

      if (jsonString == null) {
        return [];
      }

      final List<dynamic> jsonList = json.decode(jsonString);
      final entries = jsonList
          .map((json) => TrackerEntry.fromJson(json))
          .toList();

      // Sort by date descending (newest first)
      entries.sort((a, b) => b.date.compareTo(a.date));

      AppConfig.debugPrint('📋 Loaded ${entries.length} tracker entries');
      return entries;
    } catch (e) {
      AppConfig.debugPrint('❌ Error loading entries: $e');
      return [];
    }
  }

  /// Save a tracker entry with verification
  static Future<void> saveEntry(String userId, TrackerEntry entry) async {
    try {
      AppConfig.debugPrint('💾 Saving tracker entry for ${entry.date}');

      final entries = await getEntries(userId);

      // Remove existing entry for this date if it exists
      entries.removeWhere((e) => e.date == entry.date);

      // Add new entry
      entries.add(entry);

      // Save back to storage
      final prefs = await SharedPreferences.getInstance();
      final key = _getStorageKey(userId);
      final jsonString = json.encode(entries.map((e) => e.toJson()).toList());

      // ✅ VERIFY SAVE OPERATION
      final saveSuccess = await prefs.setString(key, jsonString);

      if (!saveSuccess) {
        throw Exception('Failed to save entry to SharedPreferences');
      }

      // ✅ VERIFY DATA WAS ACTUALLY SAVED
      final savedData = prefs.getString(key);
      if (savedData == null || savedData != jsonString) {
        throw Exception('Data verification failed - saved data does not match');
      }

      AppConfig.debugPrint('✅ Saved and verified tracker entry for ${entry.date}');
      AppConfig.debugPrint('   Weight: ${entry.weight?.toStringAsFixed(1) ?? 'none'} kg');
      AppConfig.debugPrint('   Meals: ${entry.meals.length}');
      AppConfig.debugPrint('   Supplements: ${entry.supplements.length}');
      AppConfig.debugPrint('   Exercise: ${entry.exercise ?? 'none'}');
      AppConfig.debugPrint('   Water: ${entry.waterIntake ?? 'none'}');
      AppConfig.debugPrint('   Score: ${entry.dailyScore}');
    } catch (e) {
      AppConfig.debugPrint('❌ Error saving entry: $e');
      throw Exception('Failed to save tracker entry: $e');
    }
  }

  /// Delete a tracker entry
  static Future<void> deleteEntry(String userId, String date) async {
    try {
      final entries = await getEntries(userId);
      entries.removeWhere((e) => e.date == date);

      final prefs = await SharedPreferences.getInstance();
      final key = _getStorageKey(userId);
      final jsonString = json.encode(entries.map((e) => e.toJson()).toList());
      await prefs.setString(key, jsonString);

      AppConfig.debugPrint('✅ Deleted tracker entry for $date');
    } catch (e) {
      AppConfig.debugPrint('❌ Error deleting entry: $e');
      throw Exception('Failed to delete tracker entry');
    }
  }

  /// Get entry for a specific date with detailed logging (returns null if not found)
  static Future<TrackerEntry?> getEntryForDate(String userId, String date) async {
    try {
      final entries = await getEntries(userId);

      AppConfig.debugPrint('📋 Looking for entry on $date');
      AppConfig.debugPrint('   Total entries in storage: ${entries.length}');

      try {
        final entry = entries.firstWhere((e) => e.date == date);

        AppConfig.debugPrint('✅ Found entry for $date:');
        AppConfig.debugPrint('   Weight: ${entry.weight?.toStringAsFixed(1) ?? 'none'} kg');
        AppConfig.debugPrint('   Meals: ${entry.meals.length}');
        AppConfig.debugPrint('   Supplements: ${entry.supplements.length}');
        AppConfig.debugPrint('   Exercise: ${entry.exercise ?? 'none'}');
        AppConfig.debugPrint('   Water: ${entry.waterIntake ?? 'none'}');
        AppConfig.debugPrint('   Score: ${entry.dailyScore}');

        return entry;
      } catch (e) {
        AppConfig.debugPrint('ℹ️ No entry found for $date');
        return null;
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting entry for date: $e');
      return null;
    }
  }

  // ========================================
  // NUTRITION TOTALS & GAPS
  // ========================================

  /// Calculate total nutrients from a list of meals
  static Map<String, double> calculateNutritionTotals(
      List<Map<String, dynamic>> meals) {
    final totals = <String, double>{
      'calories': 0,
      'fat': 0,
      'sodium': 0,
      'sugar': 0,
      'protein': 0,
      'fiber': 0,
      'saturatedFat': 0,
    };

    for (final meal in meals) {
      totals['calories'] =
          totals['calories']! + ((meal['calories'] as num?)?.toDouble() ?? 0);
      totals['fat'] =
          totals['fat']! + ((meal['fat'] as num?)?.toDouble() ?? 0);
      totals['sodium'] =
          totals['sodium']! + ((meal['sodium'] as num?)?.toDouble() ?? 0);
      totals['sugar'] =
          totals['sugar']! + ((meal['sugar'] as num?)?.toDouble() ?? 0);
      totals['protein'] =
          totals['protein']! + ((meal['protein'] as num?)?.toDouble() ?? 0);
      totals['fiber'] =
          totals['fiber']! + ((meal['fiber'] as num?)?.toDouble() ?? 0);
      totals['saturatedFat'] = totals['saturatedFat']! +
          ((meal['saturatedFat'] as num?)?.toDouble() ?? 0);
    }

    return totals;
  }

  /// Returns gap analysis: positive = need more, negative = over limit
  static Map<String, double> calculateNutritionGaps(
      List<Map<String, dynamic>> meals) {
    final totals = calculateNutritionTotals(meals);
    final gaps = <String, double>{};

    for (final nutrient in dailyTargets.keys) {
      final target = dailyTargets[nutrient]!;
      final actual = totals[nutrient] ?? 0;
      gaps[nutrient] = target - actual;
    }

    return gaps;
  }

  /// Get a status for each nutrient: 'good', 'low', 'over'
  static Map<String, String> getNutritionStatus(
      List<Map<String, dynamic>> meals) {
    final totals = calculateNutritionTotals(meals);
    final status = <String, String>{};

    for (final nutrient in dailyTargets.keys) {
      final target = dailyTargets[nutrient]!;
      final actual = totals[nutrient] ?? 0;
      final ratio = actual / target;

      if (_upperLimitNutrients.contains(nutrient)) {
        if (ratio > 1.1) {
          status[nutrient] = 'over';
        } else if (ratio >= 0.7) {
          status[nutrient] = 'good';
        } else {
          status[nutrient] = 'low';
        }
      } else {
        // Lower target nutrients
        if (ratio < 0.5) {
          status[nutrient] = 'low';
        } else if (ratio <= 1.1) {
          status[nutrient] = 'good';
        } else {
          status[nutrient] = 'over';
        }
      }
    }

    return status;
  }

  // ========================================
  // SCORE CALCULATION
  // ========================================

  /// Get today's score (returns null if no entry exists)
  static Future<int?> getTodayScore(String userId) async {
    try {
      final today = DateTime.now().toString().split(' ')[0]; // YYYY-MM-DD
      final entry = await getEntryForDate(userId, today);
      if (entry == null) return null;
      return entry.dailyScore;
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting today score: $e');
      return null;
    }
  }

  /// Get weekly average score (last 7 days, returns null if no entries)
  static Future<int?> getWeeklyScore(String userId) async {
    try {
      final entries = await getEntries(userId);
      if (entries.isEmpty) return null;

      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7));

      final recentEntries = entries.where((entry) {
        try {
          final entryDate = DateTime.parse(entry.date);
          return entryDate.isAfter(sevenDaysAgo) &&
              entryDate.isBefore(now.add(const Duration(days: 1)));
        } catch (e) {
          return false;
        }
      }).toList();

      if (recentEntries.isEmpty) return null;

      final totalScore = recentEntries.fold<int>(
          0, (sum, entry) => sum + entry.dailyScore);
      final average = (totalScore / recentEntries.length).round();

      AppConfig.debugPrint(
          '📊 Weekly average: $average (from ${recentEntries.length} days)');
      return average;
    } catch (e) {
      AppConfig.debugPrint('❌ Error calculating weekly score: $e');
      return null;
    }
  }

  /// Get weekly average weight (last 7 days, returns null if no entries with weight)
  static Future<double?> getWeeklyWeightAverage(String userId) async {
    try {
      final entries = await getEntries(userId);
      if (entries.isEmpty) return null;

      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7));

      final recentEntriesWithWeight = entries.where((entry) {
        if (entry.weight == null) return false;
        try {
          final entryDate = DateTime.parse(entry.date);
          return entryDate.isAfter(sevenDaysAgo) &&
              entryDate.isBefore(now.add(const Duration(days: 1)));
        } catch (e) {
          return false;
        }
      }).toList();

      if (recentEntriesWithWeight.isEmpty) return null;

      final totalWeight = recentEntriesWithWeight.fold<double>(
          0.0, (sum, entry) => sum + entry.weight!);
      final average = totalWeight / recentEntriesWithWeight.length;

      AppConfig.debugPrint(
          '⚖️ Weekly weight average: ${average.toStringAsFixed(1)}kg (from ${recentEntriesWithWeight.length} days)');
      return average;
    } catch (e) {
      AppConfig.debugPrint('❌ Error calculating weekly weight: $e');
      return null;
    }
  }

  /// Get last recorded weight
  static Future<double?> getLastWeight(String userId) async {
    try {
      final entries = await getEntries(userId);
      // Entries are already sorted by date descending
      for (final entry in entries) {
        if (entry.weight != null) return entry.weight;
      }
      return null;
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting last weight: $e');
      return null;
    }
  }

  // ========================================
  // AUTO-FILL MISSING WEIGHT ENTRIES
  // ========================================

  /// Auto-fill missing weight days with previous weight to maintain streak
  static Future<void> autoFillMissingWeights(String userId) async {
    try {
      final entries = await getEntries(userId);

      final entriesWithWeight = entries
          .where((e) => e.weight != null)
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));

      if (entriesWithWeight.isEmpty) {
        AppConfig.debugPrint('ℹ️ No weight entries to auto-fill from');
        return;
      }

      final firstDate = DateTime.parse(entriesWithWeight.first.date);
      final lastDate = DateTime.parse(entriesWithWeight.last.date);
      final daysToCheck = lastDate.difference(firstDate).inDays;
      double? lastKnownWeight = entriesWithWeight.first.weight;
      int filledCount = 0;

      for (int i = 0; i <= daysToCheck; i++) {
        final checkDate = firstDate.add(Duration(days: i));
        final dateString = checkDate.toString().split(' ')[0];

        final existingEntry = entries.firstWhere(
          (e) => e.date == dateString,
          orElse: () => TrackerEntry(date: dateString, dailyScore: 0),
        );

        if (existingEntry.date == dateString && existingEntry.weight != null) {
          lastKnownWeight = existingEntry.weight;
        } else if (existingEntry.date == dateString &&
            existingEntry.weight == null) {
          if (lastKnownWeight != null) {
            final updatedEntry =
                existingEntry.copyWith(weight: lastKnownWeight);
            await saveEntry(userId, updatedEntry);
            filledCount++;
            AppConfig.debugPrint(
                '✅ Auto-filled weight for $dateString: ${lastKnownWeight}kg');
          }
        } else if (lastKnownWeight != null) {
          final newEntry = TrackerEntry(
            date: dateString,
            meals: [],
            weight: lastKnownWeight,
            dailyScore: 0,
          );
          await saveEntry(userId, newEntry);
          filledCount++;
          AppConfig.debugPrint(
              '✅ Created entry with auto-filled weight for $dateString: ${lastKnownWeight}kg');
        }
      }

      if (filledCount > 0) {
        AppConfig.debugPrint(
            '🎉 Auto-filled $filledCount missing weight entries');
      } else {
        AppConfig.debugPrint('ℹ️ No missing weight entries to fill');
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Error auto-filling weights: $e');
      throw Exception('Failed to auto-fill weights: $e');
    }
  }

  /// Check if user has consecutive weight entries (for streak tracking)
  static Future<int> getWeightStreak(String userId) async {
    try {
      final entries = await getEntries(userId);

      final entriesWithWeight = entries
          .where((e) => e.weight != null)
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      if (entriesWithWeight.isEmpty) return 0;

      final today = DateTime.now();
      int streak = 0;

      for (int i = 0; i < 30; i++) {
        final checkDate = today.subtract(Duration(days: i));
        final dateString = checkDate.toString().split(' ')[0];
        final hasWeight = entriesWithWeight.any((e) => e.date == dateString);
        if (hasWeight) {
          streak++;
        } else {
          break;
        }
      }

      AppConfig.debugPrint('📊 Current weight streak: $streak days');
      return streak;
    } catch (e) {
      AppConfig.debugPrint('❌ Error calculating weight streak: $e');
      return 0;
    }
  }

  // ========================================
  // DAY 7 ACHIEVEMENT TRACKING
  // ========================================

  static const String _DAY7_POPUP_KEY = 'day7_popup_shown_';

  /// Check if user has reached 7-day weight streak
  static Future<bool> hasReachedDay7Streak(String userId) async {
    try {
      final streak = await getWeightStreak(userId);
      return streak >= 7;
    } catch (e) {
      AppConfig.debugPrint('❌ Error checking day 7 streak: $e');
      return false;
    }
  }

  /// Check if day 7 popup has been shown
  static Future<bool> hasShownDay7Popup(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('$_DAY7_POPUP_KEY$userId') ?? false;
    } catch (e) {
      AppConfig.debugPrint('❌ Error checking day 7 popup status: $e');
      return false;
    }
  }

  /// Mark day 7 popup as shown
  static Future<void> markDay7PopupShown(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_DAY7_POPUP_KEY$userId', true);
      AppConfig.debugPrint('✅ Day 7 popup marked as shown');
    } catch (e) {
      AppConfig.debugPrint('❌ Error marking day 7 popup: $e');
    }
  }

  // ========================================
  // WEEK-OVER-WEEK WEIGHT LOSS (DAY 14+)
  // ========================================

  /// Calculate weight loss from week 1 avg to week 2 avg
  /// Returns null if user hasn't completed 14 days
  /// Returns positive number for weight loss, negative for weight gain
  static Future<double?> getWeekOverWeekWeightLoss(String userId) async {
    try {
      final entries = await getEntries(userId);

      final entriesWithWeight = entries
          .where((e) => e.weight != null)
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));

      if (entriesWithWeight.length < 14) {
        AppConfig.debugPrint(
            'ℹ️ Not enough data for week-over-week (need 14 days, have ${entriesWithWeight.length})');
        return null;
      }

      final week1Entries = entriesWithWeight.take(7).toList();
      final week2Entries = entriesWithWeight.skip(7).take(7).toList();

      if (week1Entries.length < 7 || week2Entries.length < 7) return null;

      final week1Avg = week1Entries
              .map((e) => e.weight!)
              .reduce((a, b) => a + b) /
          week1Entries.length;
      final week2Avg = week2Entries
              .map((e) => e.weight!)
              .reduce((a, b) => a + b) /
          week2Entries.length;

      final difference = week1Avg - week2Avg;

      AppConfig.debugPrint('📊 Week 1 avg: ${week1Avg.toStringAsFixed(1)}kg');
      AppConfig.debugPrint('📊 Week 2 avg: ${week2Avg.toStringAsFixed(1)}kg');
      AppConfig.debugPrint(
          '📊 Weight change: ${difference.toStringAsFixed(1)}kg');

      return difference;
    } catch (e) {
      AppConfig.debugPrint('❌ Error calculating week-over-week: $e');
      return null;
    }
  }

  /// Calculate daily score from meals with surgery-aware logic
  static int calculateDailyScore({
    required List<Map<String, dynamic>> meals,
    String? surgeryType,
    String? exercise,
    String? waterIntake,
  }) {
    if (meals.isEmpty) {
      return 0; // No meals tracked = 0 score
    }

    final mealScores = meals.map((meal) {
      return BariHealthBar.calculateScore(
        fat: (meal['fat'] as num?)?.toDouble() ?? 0.0,
        sodium: (meal['sodium'] as num?)?.toDouble() ?? 0.0,
        sugar: (meal['sugar'] as num?)?.toDouble() ?? 0.0,
        calories: (meal['calories'] as num?)?.toDouble() ?? 0.0,
        surgeryType: surgeryType,
        protein: (meal['protein'] as num?)?.toDouble(),
        fiber: (meal['fiber'] as num?)?.toDouble(),
        saturatedFat: (meal['saturatedFat'] as num?)?.toDouble(),
      );
    }).toList();

    final avgMealScore = mealScores.isEmpty
        ? 0
        : (mealScores.reduce((a, b) => a + b) / mealScores.length).round();

    int finalScore = avgMealScore;

    // Exercise bonus: +5 per 30 minutes, max +10
    if (exercise != null && exercise.isNotEmpty) {
      final exerciseMinutes = _parseExerciseMinutes(exercise);
      final exerciseBonus = ((exerciseMinutes / 30) * 5).clamp(0, 10).round();
      finalScore += exerciseBonus;
    }

    // Water bonus: +2 per 4 cups, max +5
    if (waterIntake != null && waterIntake.isNotEmpty) {
      final waterCups = _parseWaterCups(waterIntake);
      final waterBonus = ((waterCups / 4) * 2).clamp(0, 5).round();
      finalScore += waterBonus;
    }

    return finalScore.clamp(0, 100);
  }

  // ========================================
  // HELPER PARSERS
  // ========================================

  static int _parseExerciseMinutes(String exercise) {
    final lower = exercise.toLowerCase();
    if (lower.contains('hour')) {
      final match = RegExp(r'(\d+\.?\d*)').firstMatch(lower);
      if (match != null) {
        final hours = double.tryParse(match.group(1)!) ?? 0;
        return (hours * 60).round();
      }
    }
    final match = RegExp(r'(\d+)').firstMatch(lower);
    if (match != null) return int.tryParse(match.group(1)!) ?? 0;
    return 0;
  }

  static int _parseWaterCups(String water) {
    final lower = water.toLowerCase();
    if (lower.contains('oz')) {
      final match = RegExp(r'(\d+)').firstMatch(lower);
      if (match != null) {
        final oz = int.tryParse(match.group(1)!) ?? 0;
        return (oz / 8).round();
      }
    }
    final match = RegExp(r'(\d+)').firstMatch(lower);
    if (match != null) return int.tryParse(match.group(1)!) ?? 0;
    return 0;
  }

  // ========================================
  // DATA MANAGEMENT
  // ========================================

  /// Get last 7 days of entries for graph
  static Future<List<TrackerEntry>> getLastSevenDays(String userId) async {
    try {
      final entries = await getEntries(userId);
      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7));

      return entries.where((entry) {
        try {
          final entryDate = DateTime.parse(entry.date);
          return entryDate.isAfter(sevenDaysAgo);
        } catch (e) {
          return false;
        }
      }).toList();
    } catch (e) {
      AppConfig.debugPrint('❌ Error getting last 7 days: $e');
      return [];
    }
  }

  /// Clear all tracker data (for reset/logout)
  static Future<void> clearAllData(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_getStorageKey(userId));
      AppConfig.debugPrint('✅ Cleared all tracker data');
    } catch (e) {
      AppConfig.debugPrint('❌ Error clearing tracker data: $e');
    }
  }

  // ========================================
  // DEBUG HELPER
  // ========================================

  /// Debug method to check storage state
  static Future<void> debugStorageState(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getStorageKey(userId);
      final jsonString = prefs.getString(key);

      if (jsonString == null) {
        AppConfig.debugPrint('🔍 DEBUG: No data in storage for user $userId');
        return;
      }

      final List<dynamic> jsonList = json.decode(jsonString);
      final entries = jsonList
          .map((json) => TrackerEntry.fromJson(json))
          .toList();

      AppConfig.debugPrint('🔍 DEBUG: Storage state for user $userId');
      AppConfig.debugPrint('   Total entries: ${entries.length}');

      for (final entry in entries.take(5)) {
        AppConfig.debugPrint(
            '   - ${entry.date}: ${entry.weight?.toStringAsFixed(1) ?? 'no weight'} kg, ${entry.meals.length} meals, score ${entry.dailyScore}');
      }

      if (entries.length > 5) {
        AppConfig.debugPrint('   ... and ${entries.length - 5} more entries');
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Error checking storage state: $e');
    }
  }
}