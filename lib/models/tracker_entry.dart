// lib/models/tracker_entry.dart

/// Kept for backward-compatible JSON deserialization of existing stored data.
/// New code uses List<Map<String, dynamic>> with a 'notes' key instead.
class SupplementEntry {
  final String name;
  final String amount; // e.g. "500mg", "1 tablet", "2 capsules"

  SupplementEntry({required this.name, required this.amount});

  Map<String, dynamic> toJson() => {'name': name, 'amount': amount};

  factory SupplementEntry.fromJson(Map<String, dynamic> json) =>
      SupplementEntry(
        name: json['name'] as String? ?? '',
        amount: json['amount'] as String? ?? '',
      );

  SupplementEntry copyWith({String? name, String? amount}) =>
      SupplementEntry(name: name ?? this.name, amount: amount ?? this.amount);
}

class TrackerEntry {
  final String date; // YYYY-MM-DD format
  final List<Map<String, dynamic>> meals;
  final List<Map<String, dynamic>> supplements;
  final String? exercise;
  final String? waterIntake;
  final double? weight; // Weight in kg (nullable for days without weight tracking)
  final int dailyScore;

  TrackerEntry({
    required this.date,
    this.meals = const [],
    this.supplements = const [],
    this.exercise,
    this.waterIntake,
    this.weight,
    required this.dailyScore,
  });

  // Convenience getters
  int get mealCount => meals.length;
  int get supplementCount => supplements.length;

  // ========================================
  // JSON SERIALIZATION
  // ========================================

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'meals': meals,
      'supplements': supplements,
      'exercise': exercise,
      'waterIntake': waterIntake,
      'weight': weight,
      'dailyScore': dailyScore,
    };
  }

  factory TrackerEntry.fromJson(Map<String, dynamic> json) {
    return TrackerEntry(
      date: json['date'] as String,
      meals: json['meals'] != null
          ? List<Map<String, dynamic>>.from(
              (json['meals'] as List).map((m) => Map<String, dynamic>.from(m)),
            )
          : [],
      supplements: json['supplements'] != null
          ? List<Map<String, dynamic>>.from(
              (json['supplements'] as List).map((s) {
                final map = Map<String, dynamic>.from(s as Map);
                map.putIfAbsent('notes', () => '');
                return map;
              }),
            )
          : [],
      exercise: json['exercise'] as String?,
      waterIntake: json['waterIntake'] as String?,
      weight: json['weight'] != null ? (json['weight'] as num).toDouble() : null,
      dailyScore: json['dailyScore'] as int? ?? 0,
    );
  }

  // ========================================
  // COPY WITH
  // ========================================

  TrackerEntry copyWith({
    String? date,
    List<Map<String, dynamic>>? meals,
    List<Map<String, dynamic>>? supplements,
    String? exercise,
    String? waterIntake,
    double? weight,
    int? dailyScore,
  }) {
    return TrackerEntry(
      date: date ?? this.date,
      meals: meals ?? this.meals,
      supplements: supplements ?? this.supplements,
      exercise: exercise ?? this.exercise,
      waterIntake: waterIntake ?? this.waterIntake,
      weight: weight ?? this.weight,
      dailyScore: dailyScore ?? this.dailyScore,
    );
  }

  // ========================================
  // EQUALITY & HASH
  // ========================================

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TrackerEntry && other.date == date;
  }

  @override
  int get hashCode => date.hashCode;

  @override
  String toString() {
    return 'TrackerEntry(date: $date, meals: ${meals.length}, supplements: ${supplements.length}, weight: ${weight?.toStringAsFixed(1)}kg, score: $dailyScore)';
  }
}