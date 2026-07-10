// lib/services/alcohol_service.dart
// Supabase-backed service for bariatric alcohol tracking.
// All methods are static. Table: bari_alcohol_log

import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../models/alcohol_entry.dart';

class AlcoholService {
  static final _db = Supabase.instance.client;

  static String get _uid {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw Exception('Please sign in to continue');
    return uid;
  }

  // ── Log a drink ───────────────────────────────────────────────────────────

  static Future<AlcoholEntry> logDrink({
    required String drinkName,
    required double totalVolumeOz,
    required double abvPercent,
    String? notes,
    DateTime? at,
  }) async {
    final uid = _uid;
    final entry = AlcoholEntry(
      drinkName: drinkName,
      totalVolumeOz: totalVolumeOz,
      abvPercent: abvPercent,
      loggedAt: at ?? DateTime.now(),
      notes: notes,
    );

    final result = await _db
        .from('bari_alcohol_log')
        .insert({
          ...entry.toMap(),
          'user_id': uid,
        })
        .select()
        .single();

    AppConfig.debugPrint(
      '🍺 Drink logged: $drinkName '
      '${totalVolumeOz}oz @ $abvPercent% = '
      '${entry.pureAlcoholOz.toStringAsFixed(2)}oz pure alcohol',
    );

    return AlcoholEntry.fromMap(result);
  }

  // ── Fetch entries ─────────────────────────────────────────────────────────

  /// Fetch entries within an optional date range (defaults to last 30 days).
  static Future<List<AlcoholEntry>> getLog({
    DateTime? from,
    DateTime? to,
  }) async {
    final uid = _uid;
    final fromDate = from ?? DateTime.now().subtract(const Duration(days: 30));
    final toDate = to ?? DateTime.now().add(const Duration(days: 1));

    final results = await _db
        .from('bari_alcohol_log')
        .select()
        .eq('user_id', uid)
        .gte('logged_at', fromDate.toIso8601String())
        .lte('logged_at', toDate.toIso8601String())
        .order('logged_at', ascending: false);

    return (results as List)
        .map((r) => AlcoholEntry.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Returns all entries logged today (local time).
  static Future<List<AlcoholEntry>> getTodayLog() async {
    final today = DateTime.now();
    return getLog(
      from: DateTime(today.year, today.month, today.day),
      to: DateTime(today.year, today.month, today.day + 1),
    );
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  static Future<void> deleteEntry(String id) async {
    await _db
        .from('bari_alcohol_log')
        .delete()
        .eq('id', id)
        .eq('user_id', _uid);
    AppConfig.debugPrint('🗑️ Alcohol entry deleted: $id');
  }

  // ── Weekly analytics ──────────────────────────────────────────────────────

  /// Returns a map of date-string (yyyy-MM-dd) → total pure alcohol oz for
  /// each of the last 7 days. Days with no entries appear with value 0.
  static Future<Map<String, double>> getWeeklyPureAlcoholOz() async {
    final now = DateTime.now();
    final sevenDaysAgo =
        DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6)).toUtc();

    final response = await _db
        .from('bari_alcohol_log')
        .select('logged_at, pure_alcohol_oz')
        .eq('user_id', _uid)
        .gte('logged_at', sevenDaysAgo.toIso8601String())
        .order('logged_at', ascending: true);

    final Map<String, double> result = {};

    // Pre-fill all 7 days with 0.0 so days with no entries still appear
    for (int i = 6; i >= 0; i--) {
      final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      result[_dateKey(d)] = 0.0;
    }

    for (final row in (response as List)) {
      final logged = DateTime.parse(row['logged_at'] as String).toLocal();
      final key = _dateKey(logged);
      final oz = (row['pure_alcohol_oz'] as num).toDouble();
      if (result.containsKey(key)) {
        result[key] = (result[key] ?? 0.0) + oz;
      }
    }

    return result;
  }

  /// Total pure alcohol oz consumed in the last 7 days.
  static Future<double> getWeeklyTotalOz() async {
    final map = await getWeeklyPureAlcoholOz();
    return map.values.fold<double>(0.0, (a, b) => a + b);
  }

  /// Average pure alcohol oz per day over the last 7 days.
  static Future<double> getWeeklyAverageDailyOz() async {
    final total = await getWeeklyTotalOz();
    return total / 7;
  }

  /// Total standard drinks in the last 7 days.
  static Future<double> getWeeklyStandardDrinks() async {
    final now = DateTime.now();
    final sevenDaysAgo =
        DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6)).toUtc();

    final response = await _db
        .from('bari_alcohol_log')
        .select('standard_drinks')
        .eq('user_id', _uid)
        .gte('logged_at', sevenDaysAgo.toIso8601String());

    double total = 0.0;
    for (final row in (response as List)) {
      total += (row['standard_drinks'] as num).toDouble();
    }
    return total;
  }

  // ── Risk classification ───────────────────────────────────────────────────

  /// NIAAA guidelines adjusted for post-bariatric absorption.
  /// Post-bariatric patients absorb alcohol 2–3x faster than the general
  /// population, so thresholds are intentionally conservative.
  static AlcoholRiskLevel weeklyRiskLevel(double weeklyStandardDrinks) {
    if (weeklyStandardDrinks == 0) return AlcoholRiskLevel.none;
    if (weeklyStandardDrinks <= 7) return AlcoholRiskLevel.low;
    if (weeklyStandardDrinks <= 14) return AlcoholRiskLevel.moderate;
    return AlcoholRiskLevel.high;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}