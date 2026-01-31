// lib/models/tracker_entry.dart

class TrackerEntry {
  final String date; // YYYY-MM-DD format
  final List<Map<String, dynamic>> meals;
  final String? exercise;
  final String? waterIntake;
  final double? weight; // Weight in kg (nullable for days without weight tracking)
  final int dailyScore;

  TrackerEntry({
    required this.date,
    this.meals = const [],
    this.exercise,
    this.waterIntake,
    this.weight,
    required this.dailyScore,
  });

  // Convenience getter for meal count
  int get mealCount => meals.length;

  // ========================================
  // JSON SERIALIZATION
  // ========================================

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'meals': meals,
      'exercise': exercise,
      'waterIntake': waterIntake,
      'weight': weight,
      'dailyScore': dailyScore,
    };
  }

  /// Create from JSON
  factory TrackerEntry.fromJson(Map<String, dynamic> json) {
    return TrackerEntry(
      date: json['date'] as String,
      meals: json['meals'] != null 
          ? List<Map<String, dynamic>>.from(
              (json['meals'] as List).map((m) => Map<String, dynamic>.from(m))
            )
          : [],
      exercise: json['exercise'] as String?,
      waterIntake: json['waterIntake'] as String?,
      weight: json['weight'] != null ? (json['weight'] as num).toDouble() : null,
      dailyScore: json['dailyScore'] as int? ?? 0,
    );
  }

  // ========================================
  // COPY WITH (for updates)
  // ========================================

  TrackerEntry copyWith({
    String? date,
    List<Map<String, dynamic>>? meals,
    String? exercise,
    String? waterIntake,
    double? weight,
    int? dailyScore,
  }) {
    return TrackerEntry(
      date: date ?? this.date,
      meals: meals ?? this.meals,
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
    return 'TrackerEntry(date: $date, meals: ${meals.length}, weight: ${weight?.toStringAsFixed(1)}kg, score: $dailyScore)';
  }
}