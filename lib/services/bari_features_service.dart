// lib/services/bari_features_service.dart
// Supabase data layer for all bariatric health tracking features:
//   • Hydration logging
//   • Supplement scheduling and taken-log
//   • Symptom logging
//   • Food tolerance logging
//   • Allergy logging
//   • GLP-1 dose logging
//   • Wellness check-in logging
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
//   bari_tolerance_log     (✅ new this session)
//   bari_allergy_log       (✅ new this session)
//   bari_glp1_log          (✅ new this session)
//   bari_wellness_log      (✅ new this session)
//   bari_nutrient_snapshots
//   bari_weekly_goals
//
// ── Section 12 backend build (this session) ───────────────────────────────
// Added logTolerance/getToleranceLog/deleteToleranceEntry,
// logAllergy/getAllergyLog/deleteAllergyEntry,
// logGlp1Dose/getGlp1Log/deleteGlp1Entry, and
// upsertWellnessCheckin/getWellnessLog/deleteWellnessEntry — mirroring the
// existing logSymptom/getSymptomLog/deleteSymptomEntry pattern exactly
// (same try/authenticated-check/insert/select shape). Wellness uses upsert
// instead of insert since it's one-per-day, matching upsertDailySnapshot's
// existing pattern below. Purely additive — every existing method in this
// file is unchanged.

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
        inserted);
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
  // ✅ NEW THIS SESSION — FOOD TOLERANCE LOG
  // ================================================================

  /// Log a food-tolerance entry for the current user.
  /// [loggedAt] defaults to now; migration code (extended_tracker_page.dart)
  /// passes the original local entry's date to avoid re-dating history.
  static Future<void> logTolerance({
    required String foodName,
    required int toleranceScore,
    String? symptoms,
    String? notes,
    DateTime? loggedAt,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');

    await _db.from('bari_tolerance_log').insert({
      'user_id': uid,
      'food_name': foodName,
      'tolerance_score': toleranceScore,
      if (symptoms != null) 'symptoms': symptoms,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'logged_at': (loggedAt ?? DateTime.now()).toIso8601String(),
    });

    AppConfig.debugPrint(
        '🍽️ Tolerance logged: $foodName (score $toleranceScore)');
  }

  /// Fetch tolerance entries from a given date onward.
  static Future<List<ToleranceEntry>> getToleranceLog({
    required DateTime from,
  }) async {
    final uid = _uid;
    if (uid == null) return [];

    final data = await _db
        .from('bari_tolerance_log')
        .select()
        .eq('user_id', uid)
        .gte('logged_at', from.toIso8601String())
        .order('logged_at', ascending: false);

    return (data as List)
        .map((row) => ToleranceEntry.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Update an existing tolerance entry (used by the Tracker Detail Screen).
  static Future<void> updateToleranceEntry(
    String entryId, {
    required String foodName,
    required int toleranceScore,
    String? symptoms,
    String? notes,
  }) async {
    await _db.from('bari_tolerance_log').update({
      'food_name': foodName,
      'tolerance_score': toleranceScore,
      'symptoms': symptoms,
      'notes': notes,
    }).eq('id', entryId);

    AppConfig.debugPrint('✏️ Tolerance entry updated: $entryId');
  }

  /// Delete a specific tolerance log entry.
  static Future<void> deleteToleranceEntry(String entryId) async {
    await _db.from('bari_tolerance_log').delete().eq('id', entryId);
    AppConfig.debugPrint('🗑️ Tolerance entry deleted: $entryId');
  }

  // ================================================================
  // ✅ NEW THIS SESSION — ALLERGY LOG
  // ================================================================

  /// Log an allergic-reaction entry for the current user.
  /// [loggedAt] defaults to now; migration code passes the original date.
  static Future<void> logAllergy({
    required String triggerFood,
    required String severity,
    required List<String> symptoms,
    String? notes,
    DateTime? loggedAt,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');

    await _db.from('bari_allergy_log').insert({
      'user_id': uid,
      'trigger_food': triggerFood,
      'severity': severity,
      'symptoms': symptoms,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'logged_at': (loggedAt ?? DateTime.now()).toIso8601String(),
    });

    AppConfig.debugPrint('⚠️ Allergy logged: $triggerFood ($severity)');
  }

  /// Fetch allergy entries from a given date onward.
  static Future<List<AllergyEntry>> getAllergyLog({
    required DateTime from,
  }) async {
    final uid = _uid;
    if (uid == null) return [];

    final data = await _db
        .from('bari_allergy_log')
        .select()
        .eq('user_id', uid)
        .gte('logged_at', from.toIso8601String())
        .order('logged_at', ascending: false);

    return (data as List)
        .map((row) => AllergyEntry.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Update an existing allergy entry (used by the Tracker Detail Screen).
  static Future<void> updateAllergyEntry(
    String entryId, {
    required String triggerFood,
    required String severity,
    required List<String> symptoms,
    String? notes,
  }) async {
    await _db.from('bari_allergy_log').update({
      'trigger_food': triggerFood,
      'severity': severity,
      'symptoms': symptoms,
      'notes': notes,
    }).eq('id', entryId);

    AppConfig.debugPrint('✏️ Allergy entry updated: $entryId');
  }

  /// Delete a specific allergy log entry.
  static Future<void> deleteAllergyEntry(String entryId) async {
    await _db.from('bari_allergy_log').delete().eq('id', entryId);
    AppConfig.debugPrint('🗑️ Allergy entry deleted: $entryId');
  }

  // ================================================================
  // ✅ NEW THIS SESSION — GLP-1 DOSE LOG
  // ================================================================

  /// Log a GLP-1 medication dose for the current user.
  /// [loggedAt] defaults to now; migration code passes the original date.
  static Future<void> logGlp1Dose({
    required String medication,
    required double doseMg,
    required List<String> sideEffects,
    String? notes,
    DateTime? loggedAt,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');

    await _db.from('bari_glp1_log').insert({
      'user_id': uid,
      'medication': medication,
      'dose_mg': doseMg,
      'side_effects': sideEffects,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'logged_at': (loggedAt ?? DateTime.now()).toIso8601String(),
    });

    AppConfig.debugPrint('💉 GLP-1 dose logged: ${doseMg}mg $medication');
  }

  /// Fetch GLP-1 dose entries from a given date onward.
  static Future<List<Glp1Entry>> getGlp1Log({
    required DateTime from,
  }) async {
    final uid = _uid;
    if (uid == null) return [];

    final data = await _db
        .from('bari_glp1_log')
        .select()
        .eq('user_id', uid)
        .gte('logged_at', from.toIso8601String())
        .order('logged_at', ascending: false);

    return (data as List)
        .map((row) => Glp1Entry.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Update an existing GLP-1 dose entry (used by the Tracker Detail Screen).
  static Future<void> updateGlp1Entry(
    String entryId, {
    required String medication,
    required double doseMg,
    required List<String> sideEffects,
    String? notes,
  }) async {
    await _db.from('bari_glp1_log').update({
      'medication': medication,
      'dose_mg': doseMg,
      'side_effects': sideEffects,
      'notes': notes,
    }).eq('id', entryId);

    AppConfig.debugPrint('✏️ GLP-1 entry updated: $entryId');
  }

  /// Delete a specific GLP-1 dose log entry.
  static Future<void> deleteGlp1Entry(String entryId) async {
    await _db.from('bari_glp1_log').delete().eq('id', entryId);
    AppConfig.debugPrint('🗑️ GLP-1 entry deleted: $entryId');
  }

  // ================================================================
  // ✅ NEW THIS SESSION — WELLNESS CHECK-IN LOG
  // ================================================================

  /// Insert or update today's (or a given date's) wellness check-in.
  /// One-per-day, upserted on (user_id, checkin_date) — matching the
  /// existing upsertDailySnapshot pattern below rather than the plain
  /// insert used by the other three new log types above.
  static Future<void> upsertWellnessCheckin({
    required DateTime checkinDate,
    required int mood,
    required int energy,
    required int sleepHours,
    required int pain,
    String? notes,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');

    await _db.from('bari_wellness_log').upsert({
      'user_id': uid,
      'checkin_date': checkinDate.toIso8601String().split('T').first,
      'mood': mood,
      'energy': energy,
      'sleep_hours': sleepHours,
      'pain': pain,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'logged_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id,checkin_date');

    AppConfig.debugPrint('🧘 Wellness check-in saved for $checkinDate');
  }

  /// Fetch wellness check-ins from a given date onward.
  static Future<List<WellnessEntry>> getWellnessLog({
    required DateTime from,
  }) async {
    final uid = _uid;
    if (uid == null) return [];

    final data = await _db
        .from('bari_wellness_log')
        .select()
        .eq('user_id', uid)
        .gte('checkin_date', from.toIso8601String().split('T').first)
        .order('checkin_date', ascending: false);

    return (data as List)
        .map((row) => WellnessEntry.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Delete a specific wellness check-in.
  static Future<void> deleteWellnessEntry(String entryId) async {
    await _db.from('bari_wellness_log').delete().eq('id', entryId);
    AppConfig.debugPrint('🗑️ Wellness entry deleted: $entryId');
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
    return BariWeeklyGoal.fromMap(data);
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
    return BariWeeklyGoal.fromMap(result);
  }

  // ================================================================
  // HELPERS
  // ================================================================

  static DateTime _getMondayOfCurrentWeek() {
    final now = DateTime.now();
    return now.subtract(Duration(days: now.weekday - 1));
  }
}