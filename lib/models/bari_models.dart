// lib/models/bari_models.dart
// Bariatric health data models.
// Covers hydration, supplement scheduling, symptom tracking,
// nutrient snapshots, and weekly goal management for post-bariatric patients.
// Ported from liverwise liver_models.dart — all terminology updated to bariatric context.

// ============================================================
// HYDRATION
// ============================================================

/// A single water-intake log entry for a bariatric patient.
/// Post-surgery patients must sip fluids constantly to avoid dehydration.
class HydrationEntry {
  final String? id;
  final String userId;
  final double cups;
  final DateTime loggedAt;

  const HydrationEntry({
    this.id,
    required this.userId,
    required this.cups,
    required this.loggedAt,
  });

  factory HydrationEntry.fromMap(Map<String, dynamic> map) {
    return HydrationEntry(
      id: map['id']?.toString(),
      userId: map['user_id'] as String,
      cups: (map['cups'] as num).toDouble(),
      loggedAt: DateTime.parse(map['logged_at'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'cups': cups,
        'logged_at': loggedAt.toIso8601String(),
      };
}

// ============================================================
// SUPPLEMENT SCHEDULING
// ============================================================

/// A recurring supplement reminder for a bariatric patient.
/// Post-op patients require lifelong supplementation: iron, B12, calcium citrate,
/// vitamin D3, multivitamin, zinc, etc.
class SupplementSchedule {
  final String? id;
  final String userId;
  final String name;
  final String dose;
  final String timeOfDay; // 'HH:mm' or label like 'morning'
  final bool isActive;

  const SupplementSchedule({
    this.id,
    required this.userId,
    required this.name,
    required this.dose,
    required this.timeOfDay,
    this.isActive = true,
  });

  factory SupplementSchedule.fromMap(Map<String, dynamic> map) {
    return SupplementSchedule(
      id: map['id']?.toString(),
      userId: map['user_id'] as String,
      name: map['name'] as String,
      dose: map['dose'] as String,
      timeOfDay: map['time_of_day'] as String,
      isActive: map['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'name': name,
        'dose': dose,
        'time_of_day': timeOfDay,
        'is_active': isActive,
      };

  SupplementSchedule copyWith({
    String? id,
    String? userId,
    String? name,
    String? dose,
    String? timeOfDay,
    bool? isActive,
  }) {
    return SupplementSchedule(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      dose: dose ?? this.dose,
      timeOfDay: timeOfDay ?? this.timeOfDay,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// A record that a scheduled supplement was actually taken on a given day.
class SupplementTakenEntry {
  final String? id;
  final String userId;
  final String name;
  final String dose;
  final String? scheduleId;
  final DateTime takenAt;

  const SupplementTakenEntry({
    this.id,
    required this.userId,
    required this.name,
    required this.dose,
    this.scheduleId,
    required this.takenAt,
  });

  factory SupplementTakenEntry.fromMap(Map<String, dynamic> map) {
    return SupplementTakenEntry(
      id: map['id']?.toString(),
      userId: map['user_id'] as String,
      name: map['name'] as String,
      dose: map['dose'] as String,
      scheduleId: map['schedule_id']?.toString(),
      takenAt: DateTime.parse(map['taken_at'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'name': name,
        'dose': dose,
        if (scheduleId != null) 'schedule_id': scheduleId,
        'taken_at': takenAt.toIso8601String(),
      };
}

// ============================================================
// SYMPTOM TRACKING
// ============================================================

/// Symptom types relevant after bariatric surgery.
/// Patients experience unique post-op symptoms: dumping syndrome, nausea,
/// fatigue from nutrient deficiency, reflux, food intolerances, etc.
enum SymptomType {
  fatigue,
  nausea,
  abdominalPain,
  dumpingSyndrome,
  reflux,
  diarrhea,
  constipation,
  hairLoss,
  headache,
  dizziness,
  foodIntolerance,
  other;

  String get displayName => switch (this) {
        SymptomType.fatigue         => 'Fatigue',
        SymptomType.nausea          => 'Nausea',
        SymptomType.abdominalPain   => 'Abdominal Pain',
        SymptomType.dumpingSyndrome => 'Dumping Syndrome',
        SymptomType.reflux          => 'Acid Reflux',
        SymptomType.diarrhea        => 'Diarrhea',
        SymptomType.constipation    => 'Constipation',
        SymptomType.hairLoss        => 'Hair Loss',
        SymptomType.headache        => 'Headache',
        SymptomType.dizziness       => 'Dizziness',
        SymptomType.foodIntolerance => 'Food Intolerance',
        SymptomType.other           => 'Other',
      };

  String get emoji => switch (this) {
        SymptomType.fatigue         => '😴',
        SymptomType.nausea          => '🤢',
        SymptomType.abdominalPain   => '🫁',
        SymptomType.dumpingSyndrome => '⚡',
        SymptomType.reflux          => '🔥',
        SymptomType.diarrhea        => '🚽',
        SymptomType.constipation    => '😣',
        SymptomType.hairLoss        => '💇',
        SymptomType.headache        => '🤕',
        SymptomType.dizziness       => '💫',
        SymptomType.foodIntolerance => '🚫',
        SymptomType.other           => '📋',
      };

  String get dbValue => name;

  static SymptomType fromDb(String value) {
    return SymptomType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SymptomType.other,
    );
  }
}

/// A single logged symptom occurrence for a bariatric patient.
class SymptomEntry {
  final String? id;
  final String userId;
  final SymptomType symptomType;
  final int severity; // 1–5
  final String? notes;
  final DateTime loggedAt;

  const SymptomEntry({
    this.id,
    required this.userId,
    required this.symptomType,
    required this.severity,
    this.notes,
    required this.loggedAt,
  });

  factory SymptomEntry.fromMap(Map<String, dynamic> map) {
    return SymptomEntry(
      id: map['id']?.toString(),
      userId: map['user_id'] as String,
      symptomType: SymptomType.fromDb(map['symptom_type'] as String),
      severity: map['severity'] as int,
      notes: map['notes'] as String?,
      loggedAt: DateTime.parse(map['logged_at'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'symptom_type': symptomType.dbValue,
        'severity': severity,
        if (notes != null) 'notes': notes,
        'logged_at': loggedAt.toIso8601String(),
      };
}

// ============================================================
// NUTRIENT SNAPSHOTS (daily nutrition summary)
// ============================================================

/// A daily nutrition snapshot for trend analysis on the Bari Dashboard.
/// Used to track macros, micronutrients, and daily health score over time.
/// Back-filled from TrackerService when Supabase entries are sparse.
class BariNutrientSnapshot {
  final String? id;
  final String userId;
  final DateTime snapshotDate;
  final double? calories;
  final double? proteinG;
  final double? fatG;
  final double? saturatedFatG;
  final double? sugarG;
  final double? sodiumMg;
  final double? fiberG;
  final double? waterCups;
  final int? dailyScore;
  final double? weightKg;
  final int? supplementCount;

  const BariNutrientSnapshot({
    this.id,
    required this.userId,
    required this.snapshotDate,
    this.calories,
    this.proteinG,
    this.fatG,
    this.saturatedFatG,
    this.sugarG,
    this.sodiumMg,
    this.fiberG,
    this.waterCups,
    this.dailyScore,
    this.weightKg,
    this.supplementCount,
  });

  factory BariNutrientSnapshot.fromMap(Map<String, dynamic> map) {
    return BariNutrientSnapshot(
      id: map['id']?.toString(),
      userId: map['user_id'] as String,
      snapshotDate: DateTime.parse(map['snapshot_date'] as String),
      calories: (map['calories'] as num?)?.toDouble(),
      proteinG: (map['protein_g'] as num?)?.toDouble(),
      fatG: (map['fat_g'] as num?)?.toDouble(),
      saturatedFatG: (map['saturated_fat_g'] as num?)?.toDouble(),
      sugarG: (map['sugar_g'] as num?)?.toDouble(),
      sodiumMg: (map['sodium_mg'] as num?)?.toDouble(),
      fiberG: (map['fiber_g'] as num?)?.toDouble(),
      waterCups: (map['water_cups'] as num?)?.toDouble(),
      dailyScore: map['daily_score'] as int?,
      weightKg: (map['weight_kg'] as num?)?.toDouble(),
      supplementCount: map['supplement_count'] as int?,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'snapshot_date': snapshotDate.toIso8601String().split('T').first,
        if (calories != null) 'calories': calories,
        if (proteinG != null) 'protein_g': proteinG,
        if (fatG != null) 'fat_g': fatG,
        if (saturatedFatG != null) 'saturated_fat_g': saturatedFatG,
        if (sugarG != null) 'sugar_g': sugarG,
        if (sodiumMg != null) 'sodium_mg': sodiumMg,
        if (fiberG != null) 'fiber_g': fiberG,
        if (waterCups != null) 'water_cups': waterCups,
        if (dailyScore != null) 'daily_score': dailyScore,
        if (weightKg != null) 'weight_kg': weightKg,
        if (supplementCount != null) 'supplement_count': supplementCount,
      };
}

// ============================================================
// WEEKLY GOALS
// ============================================================

/// User-defined weekly nutrition goals for bariatric health management.
/// Post-op patients have specific macro targets: high protein, low sugar,
/// low fat, adequate fiber, and sufficient hydration.
class BariWeeklyGoal {
  final String? id;
  final String userId;
  final DateTime weekStartDate;
  final double? goalProteinG;
  final double? goalSodiumMg;
  final double? goalSugarG;
  final double? goalFatG;
  final double? goalFiberG;
  final double? goalWaterCups;

  const BariWeeklyGoal({
    this.id,
    required this.userId,
    required this.weekStartDate,
    this.goalProteinG,
    this.goalSodiumMg,
    this.goalSugarG,
    this.goalFatG,
    this.goalFiberG,
    this.goalWaterCups,
  });

  factory BariWeeklyGoal.fromMap(Map<String, dynamic> map) {
    return BariWeeklyGoal(
      id: map['id']?.toString(),
      userId: map['user_id'] as String,
      weekStartDate: DateTime.parse(map['week_start_date'] as String),
      goalProteinG: (map['goal_protein_g'] as num?)?.toDouble(),
      goalSodiumMg: (map['goal_sodium_mg'] as num?)?.toDouble(),
      goalSugarG: (map['goal_sugar_g'] as num?)?.toDouble(),
      goalFatG: (map['goal_fat_g'] as num?)?.toDouble(),
      goalFiberG: (map['goal_fiber_g'] as num?)?.toDouble(),
      goalWaterCups: (map['goal_water_cups'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'week_start_date':
            weekStartDate.toIso8601String().split('T').first,
        if (goalProteinG != null) 'goal_protein_g': goalProteinG,
        if (goalSodiumMg != null) 'goal_sodium_mg': goalSodiumMg,
        if (goalSugarG != null) 'goal_sugar_g': goalSugarG,
        if (goalFatG != null) 'goal_fat_g': goalFatG,
        if (goalFiberG != null) 'goal_fiber_g': goalFiberG,
        if (goalWaterCups != null) 'goal_water_cups': goalWaterCups,
      };

  BariWeeklyGoal copyWith({
    String? id,
    String? userId,
    DateTime? weekStartDate,
    double? goalProteinG,
    double? goalSodiumMg,
    double? goalSugarG,
    double? goalFatG,
    double? goalFiberG,
    double? goalWaterCups,
  }) {
    return BariWeeklyGoal(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      weekStartDate: weekStartDate ?? this.weekStartDate,
      goalProteinG: goalProteinG ?? this.goalProteinG,
      goalSodiumMg: goalSodiumMg ?? this.goalSodiumMg,
      goalSugarG: goalSugarG ?? this.goalSugarG,
      goalFatG: goalFatG ?? this.goalFatG,
      goalFiberG: goalFiberG ?? this.goalFiberG,
      goalWaterCups: goalWaterCups ?? this.goalWaterCups,
    );
  }
}