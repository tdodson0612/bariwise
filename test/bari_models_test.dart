// test/bari_models_test.dart
//
// Round-trip tests for the four model classes added to bari_models.dart
// this session (ToleranceEntry, AllergyEntry, Glp1Entry, WellnessEntry).
// These are pure Dart classes with no Supabase/network dependency, so they
// can be tested directly: build one, serialize it with toMap(), rebuild it
// with fromMap(), and confirm every field survived the round trip. This is
// exactly the kind of test that would have caught a typo'd JSON key (e.g.
// 'food_name' vs 'foodname') before it ever reached a real device.

import 'package:flutter_test/flutter_test.dart';
import 'package:bari_wise/models/bari_models.dart';

void main() {
  group('ToleranceEntry', () {
    test('Round-trips through toMap/fromMap with all fields set', () {
      final original = ToleranceEntry(
        id: 'abc-123',
        userId: 'user-1',
        foodName: 'Scrambled eggs',
        toleranceScore: 4,
        symptoms: 'Mild bloating',
        notes: 'Ate slowly, was fine',
        loggedAt: DateTime.parse('2026-01-15T08:30:00.000'),
      );

      final rebuilt = ToleranceEntry.fromMap(original.toMap());

      expect(rebuilt.id, original.id);
      expect(rebuilt.userId, original.userId);
      expect(rebuilt.foodName, original.foodName);
      expect(rebuilt.toleranceScore, original.toleranceScore);
      expect(rebuilt.symptoms, original.symptoms);
      expect(rebuilt.notes, original.notes);
      expect(rebuilt.loggedAt, original.loggedAt);
    });

    test('Round-trips correctly when optional fields are null', () {
      final original = ToleranceEntry(
        userId: 'user-1',
        foodName: 'Rice',
        toleranceScore: 5,
        loggedAt: DateTime.parse('2026-02-01T12:00:00.000'),
      );

      final map = original.toMap();
      // Optional null fields should be omitted from the map entirely
      // (toMap uses `if (x != null)`), not present as explicit nulls.
      expect(map.containsKey('id'), isFalse);
      expect(map.containsKey('symptoms'), isFalse);
      expect(map.containsKey('notes'), isFalse);

      final rebuilt = ToleranceEntry.fromMap(map);
      expect(rebuilt.id, isNull);
      expect(rebuilt.symptoms, isNull);
      expect(rebuilt.notes, isNull);
      expect(rebuilt.foodName, 'Rice');
      expect(rebuilt.toleranceScore, 5);
    });

    test('fromMap converts a numeric id to a String', () {
      // Supabase can return integer-typed IDs depending on column config;
      // the model explicitly calls .toString() to normalize this.
      final map = {
        'id': 42,
        'user_id': 'user-1',
        'food_name': 'Toast',
        'tolerance_score': 3,
        'logged_at': '2026-01-01T00:00:00.000',
      };
      final entry = ToleranceEntry.fromMap(map);
      expect(entry.id, '42');
      expect(entry.id, isA<String>());
    });
  });

  group('AllergyEntry', () {
    test('Round-trips through toMap/fromMap with all fields set', () {
      final original = AllergyEntry(
        id: 'a-1',
        userId: 'user-1',
        triggerFood: 'Shellfish',
        severity: 'severe',
        symptoms: ['Hives', 'Swelling', 'Difficulty breathing'],
        notes: 'Went to ER',
        loggedAt: DateTime.parse('2026-03-10T18:00:00.000'),
      );

      final rebuilt = AllergyEntry.fromMap(original.toMap());

      expect(rebuilt.id, original.id);
      expect(rebuilt.triggerFood, original.triggerFood);
      expect(rebuilt.severity, original.severity);
      expect(rebuilt.symptoms, original.symptoms);
      expect(rebuilt.notes, original.notes);
      expect(rebuilt.loggedAt, original.loggedAt);
    });

    test('Defaults severity to "mild" when missing from the map', () {
      final map = {
        'user_id': 'user-1',
        'trigger_food': 'Peanuts',
        'logged_at': '2026-01-01T00:00:00.000',
      };
      final entry = AllergyEntry.fromMap(map);
      expect(entry.severity, 'mild');
      expect(entry.symptoms, isEmpty);
    });

    test('An empty symptoms list round-trips as an empty list, not null', () {
      final original = AllergyEntry(
        userId: 'user-1',
        triggerFood: 'Dairy',
        severity: 'mild',
        symptoms: const [],
        loggedAt: DateTime.parse('2026-01-01T00:00:00.000'),
      );
      final rebuilt = AllergyEntry.fromMap(original.toMap());
      expect(rebuilt.symptoms, isEmpty);
      expect(rebuilt.symptoms, isA<List<String>>());
    });
  });

  group('Glp1Entry', () {
    test('Round-trips through toMap/fromMap with all fields set', () {
      final original = Glp1Entry(
        id: 'g-1',
        userId: 'user-1',
        medication: 'Semaglutide (Ozempic/Wegovy)',
        doseMg: 0.5,
        sideEffects: ['Nausea', 'Fatigue'],
        notes: 'First dose',
        loggedAt: DateTime.parse('2026-04-01T09:00:00.000'),
      );

      final rebuilt = Glp1Entry.fromMap(original.toMap());

      expect(rebuilt.id, original.id);
      expect(rebuilt.medication, original.medication);
      expect(rebuilt.doseMg, original.doseMg);
      expect(rebuilt.sideEffects, original.sideEffects);
      expect(rebuilt.notes, original.notes);
      expect(rebuilt.loggedAt, original.loggedAt);
    });

    test('fromMap converts an integer dose_mg to a double', () {
      // Supabase's numeric column can come back as an int (e.g. "1")
      // rather than a double (e.g. "1.0") depending on the stored value.
      final map = {
        'user_id': 'user-1',
        'medication': 'Tirzepatide (Mounjaro/Zepbound)',
        'dose_mg': 5, // int, not 5.0
        'side_effects': <String>[],
        'logged_at': '2026-01-01T00:00:00.000',
      };
      final entry = Glp1Entry.fromMap(map);
      expect(entry.doseMg, 5.0);
      expect(entry.doseMg, isA<double>());
    });
  });

  group('WellnessEntry', () {
    test('Round-trips through toMap/fromMap with all fields set', () {
      final original = WellnessEntry(
        id: 'w-1',
        userId: 'user-1',
        checkinDate: DateTime(2026, 5, 20),
        mood: 4,
        energy: 3,
        sleepHours: 7,
        pain: 1,
        notes: 'Feeling good today',
        loggedAt: DateTime.parse('2026-05-20T21:00:00.000'),
      );

      final rebuilt = WellnessEntry.fromMap(original.toMap());

      expect(rebuilt.id, original.id);
      expect(rebuilt.checkinDate, original.checkinDate);
      expect(rebuilt.mood, original.mood);
      expect(rebuilt.energy, original.energy);
      expect(rebuilt.sleepHours, original.sleepHours);
      expect(rebuilt.pain, original.pain);
      expect(rebuilt.notes, original.notes);
      expect(rebuilt.loggedAt, original.loggedAt);
    });

    test('toMap truncates checkinDate to a date-only string (no time component)', () {
      // Wellness is one-check-in-per-day, upserted on (user_id, checkin_date).
      // If a time component leaked into the stored value, two check-ins on
      // the same calendar day but different times would incorrectly be
      // treated as different days.
      final entry = WellnessEntry(
        userId: 'user-1',
        checkinDate: DateTime(2026, 6, 1, 23, 59, 59),
        mood: 3,
        energy: 3,
        sleepHours: 8,
        pain: 0,
        loggedAt: DateTime.parse('2026-06-01T23:59:59.000'),
      );
      final map = entry.toMap();
      expect(map['checkin_date'], '2026-06-01');
      expect(map['checkin_date'], isNot(contains('T')));
    });
  });
}