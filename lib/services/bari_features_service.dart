// lib/services/bari_features_service.dart
// Supabase data layer for all bariatric health tracking features:
//   • Hydration logging
//   • Supplement scheduling and taken-log
//   • Symptom logging
//   • Daily nutrient snapshots
//   • Weekly goal management
//
// Ported from liverwise liver_features_service.dart.
// All table names, column names, and terminology are bariatric-specific.
// Assumes the following Supabase tables exist (see database_service.txt for schema):
//   bari_hydration_log
//   bari_supplement_schedules
//   bari_supplement_taken_log
//   bari_symptom_log
//   bari_nutrient_snapshots
//   bari_weekly_goals

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bari_models.dart';
import '../config/app_config.dart';

class BariFeaturesService {
  static SupabaseClient get _db => Supabase.instance.client;

  static String? get _uid =>
      _db.auth.currentUser?.id;

  // ================================================================
  // HYDRATION
  // ================================================================

  /// Log a water intake entry for the current user.
  static Future<void> logHydration({required double cups}) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');

    await _db.from('bari_hydration_log').insert({
      'user_id': uid,
      'cups': cups,
      'logged_at': DateTime.now().toIso8601String(),
    });

    AppConfig.debugPrint(
        '💧 Hydration logged: $cups cups for user $uid');
  }

  /// Fetch hydration entries for the current user within a date range.
  static Future<List<HydrationEntry>> getHydrationLog({
    required DateTime from,
    required DateTime to,
  }) async {
    final uid = _uid;
    if (uid == null) return [];

    final data = await _db
        .from('bari_hydration_log')
        .select()
        .eq('user_id', uid)
        .gte('logged_at', from.toIso8601String())
        .lt('logged_at', to.toIso8601String())
        .order('logged_at', ascending: true);

    return (data as List)
        .map((row) => HydrationEntry.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Return total cups logged today as a single double.
  static Future<double> getTodayCups(String todayDateStr) async {
    final uid = _uid;
    if (uid == null) return 0;

    final from = DateTime.parse(todayDateStr);
    final to = from.add(const Duration(days: 1));

    final entries = await getHydrationLog(from: from, to: to);
    return entries.fold<double>(0, (sum, e) => sum + e.cups);
  }

  /// Delete a specific hydration entry by ID.
  static Future<void> deleteHydrationEntry(String entryId) async {
    await _db
        .from('bari_hydration_log')
        .delete()
        .eq('id', entryId);

    AppConfig.debugPrint('🗑️ Hydration entry deleted: $entryId');
  }

  // ================================================================
  // SUPPLEMENT SCHEDULES
  // ================================================================

  /// Fetch all active supplement schedules for the current user.
  static Future<List<SupplementSchedule>> getSupplementSchedules() async {
    final uid = _uid;
    if (uid == null) return [];

    final data = await _db
        .from('bari_supplement_schedules')
        .select()
        .eq('user_id', uid)
        .eq('is_active', true)
        .order('time_of_day', ascending: true);

    return (data as List)
        .map((row) =>
            SupplementSchedule.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Create a new supplement schedule entry.
  static Future<SupplementSchedule> createSupplementSchedule(
      SupplementSchedule schedule) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');

    final inserted = await _db
        .from('bari_supplement_schedules')
        .insert(schedule.toMap()..['user_id'] = uid)
        .select()
        .single();

    AppConfig.debugPrint(
        '💊 Supplement schedule created: ${schedule.name}');
    return SupplementSchedule.fromMap(
        inserted as Map<String, dynamic>);
  }

  /// Soft-delete a supplement schedule by marking it inactive.
  static Future<void> deactivateSupplementSchedule(
      String scheduleId) async {
    await _db
        .from('bari_supplement_schedules')
        .update({'is_active': false})
        .eq('id', scheduleId);

    AppConfig.debugPrint(
        '🔕 Supplement schedule deactivated: $scheduleId');
  }

  // ================================================================
  // SUPPLEMENT TAKEN LOG
  // ================================================================

  /// Log that a supplement was taken now.
  static Future<void> logSupplementTaken({
    required String name,
    required String dose,
    String? scheduleId,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');

    await _db.from('bari_supplement_taken_log').insert({
      'user_id': uid,
      'name': name,
      'dose': dose,
      if (scheduleId != null) 'schedule_id': scheduleId,
      'taken_at': DateTime.now().toIso8601String(),
    });

    AppConfig.debugPrint('✅ Supplement taken: $name ($dose)');
  }

  /// Fetch supplement taken entries within a date range.
  static Future<List<SupplementTakenEntry>> getSupplementTakenLog({
    required DateTime from,
    required DateTime to,
  }) async {
    final uid = _uid;
    if (uid == null) return [];

    final data = await _db
        .from('bari_supplement_taken_log')
        .select()
        .eq('user_id', uid)
        .gte('taken_at', from.toIso8601String())
        .lt('taken_at', to.toIso8601String())
        .order('taken_at', ascending: true);

    return (data as List)
        .map((row) =>
            SupplementTakenEntry.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  // ================================================================
  // SYMPTOM LOG
  // ================================================================

  /// Log a symptom occurrence for the current user.
  static Future<void> logSymptom({
    required SymptomType symptomType,
    required int severity,
    String? notes,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');

    await _db.from('bari_symptom_log').insert({
      'user_id': uid,
      'symptom_type': symptomType.dbValue,
      'severity': severity,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'logged_at': DateTime.now().toIso8601String(),
    });

    AppConfig.debugPrint(
        '📋 Symptom logged: ${symptomType.displayName} (severity $severity)');
  }

  /// Fetch symptom entries from a given date onward.
  static Future<List<SymptomEntry>> getSymptomLog({
    required DateTime from,
  }) async {
    final uid = _uid;
    if (uid == null) return [];

    final data = await _db
        .from('bari_symptom_log')
        .select()
        .eq('user_id', uid)
        .gte('logged_at', from.toIso8601String())
        .order('logged_at', ascending: false);

    return (data as List)
        .map((row) =>
            SymptomEntry.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Delete a specific symptom log entry.
  static Future<void> deleteSymptomEntry(String entryId) async {
    await _db
        .from('bari_symptom_log')
        .delete()
        .eq('id', entryId);

    AppConfig.debugPrint('🗑️ Symptom entry deleted: $entryId');
  }

  // ================================================================
  // NUTRIENT SNAPSHOTS
  // ================================================================

  /// Fetch daily nutrient snapshots for the current user.
  /// Used by the Bari Dashboard to render trend charts.
  static Future<List<BariNutrientSnapshot>> getDailySnapshots({
    int days = 30,
  }) async {
    final uid = _uid;
    if (uid == null) return [];

    final since = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String()
        .split('T')
        .first;

    final data = await _db
        .from('bari_nutrient_snapshots')
        .select()
        .eq('user_id', uid)
        .gte('snapshot_date', since)
        .order('snapshot_date', ascending: true);

    return (data as List)
        .map((row) =>
            BariNutrientSnapshot.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Upsert a daily nutrient snapshot (insert or update by date).
  static Future<void> upsertDailySnapshot(
      BariNutrientSnapshot snapshot) async {
    await _db
        .from('bari_nutrient_snapshots')
        .upsert(snapshot.toMap(), onConflict: 'user_id,snapshot_date');

    AppConfig.debugPrint(
        '📊 Bari snapshot upserted for ${snapshot.snapshotDate}');
  }

  // ================================================================
  // WEEKLY GOALS
  // ================================================================

  /// Fetch the current week's nutrition goal for the authenticated user.
  static Future<BariWeeklyGoal?> getCurrentWeekGoal() async {
    final uid = _uid;
    if (uid == null) return null;

    final monday = _getMondayOfCurrentWeek()
        .toIso8601String()
        .split('T')
        .first;

    final data = await _db
        .from('bari_weekly_goals')
        .select()
        .eq('user_id', uid)
        .eq('week_start_date', monday)
        .maybeSingle();

    if (data == null) return null;
    return BariWeeklyGoal.fromMap(data as Map<String, dynamic>);
  }

  /// Insert or update the current week's nutrition goal.
  static Future<BariWeeklyGoal> saveWeeklyGoal(
      BariWeeklyGoal goal) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');

    final map = goal.toMap()..['user_id'] = uid;

    final result = await _db
        .from('bari_weekly_goals')
        .upsert(map, onConflict: 'user_id,week_start_date')
        .select()
        .single();

    AppConfig.debugPrint('🎯 Bariatric weekly goals saved');
    return BariWeeklyGoal.fromMap(result as Map<String, dynamic>);
  }

  // ================================================================
  // HELPERS
  // ================================================================

  static DateTime _getMondayOfCurrentWeek() {
    final now = DateTime.now();
    return now.subtract(Duration(days: now.weekday - 1));
  }
} 