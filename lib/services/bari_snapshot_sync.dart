// lib/services/bari_snapshot_sync.dart
// Thin bridge: call BariSnapshotSync.syncEntry(userId, entry) right after
// TrackerService.saveEntry() in your TrackerPage.
// This is the ONLY change needed in TrackerPage (one line added).
// No other existing files are modified.

import '../models/tracker_entry.dart';
import '../models/bari_models.dart';
import '../services/bari_features_service.dart';
import '../services/tracker_service.dart';
import '../config/app_config.dart';

class BariSnapshotSync {
  /// Call this immediately after TrackerService.saveEntry() succeeds.
  /// It converts the local TrackerEntry to a BariNutrientSnapshot and
  /// upserts it to Supabase so the dashboard always has up-to-date data.
  static Future<void> syncEntry(String userId, TrackerEntry entry) async {
    try {
      final totals =
          TrackerService.calculateNutritionTotals(entry.meals);

      // Parse water intake from string (e.g. "6 cups", "48 oz")
      double? waterCups;
      if (entry.waterIntake != null && entry.waterIntake!.isNotEmpty) {
        waterCups = _parseWaterCups(entry.waterIntake!);
      }

      final snapshot = BariNutrientSnapshot(
        userId: userId,
        snapshotDate: DateTime.parse(entry.date),
        calories: totals['calories'],
        proteinG: totals['protein'],
        fatG: totals['fat'],
        saturatedFatG: totals['saturatedFat'],
        sugarG: totals['sugar'],
        sodiumMg: totals['sodium'],
        fiberG: totals['fiber'],
        waterCups: waterCups,
        dailyScore: entry.dailyScore,
        weightKg: entry.weight,
        supplementCount: entry.supplements.length,
      );

      await BariFeaturesService.upsertDailySnapshot(snapshot);
      AppConfig.debugPrint(
          '🔄 Bari snapshot synced for ${entry.date}');
    } catch (e) {
      // Non-fatal: local tracker still saved; Supabase sync is best-effort
      AppConfig.debugPrint(
          '⚠️ Bari snapshot sync failed (non-fatal): $e');
    }
  }

  static double _parseWaterCups(String water) {
    final lower = water.toLowerCase();
    if (lower.contains('oz')) {
      final match = RegExp(r'(\d+)').firstMatch(lower);
      if (match != null) {
        final oz = int.tryParse(match.group(1)!) ?? 0;
        return oz / 8.0;
      }
    }
    if (lower.contains('l') && !lower.contains('fl')) {
      final match = RegExp(r'(\d+\.?\d*)').firstMatch(lower);
      if (match != null) {
        final liters = double.tryParse(match.group(1)!) ?? 0;
        return liters * 4.23;
      }
    }
    final match = RegExp(r'(\d+\.?\d*)').firstMatch(lower);
    if (match != null) return double.tryParse(match.group(1)!) ?? 0;
    return 0;
  }
}