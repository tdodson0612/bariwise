// lib/models/alcohol_entry.dart
// Data models for bariatric alcohol tracking.
// Includes AlcoholEntry, DrinkPreset, kDrinkPresets, and AlcoholRiskLevel.

class AlcoholEntry {
  final String? id;
  final String drinkName;
  final double totalVolumeOz;
  final double abvPercent;
  final double pureAlcoholOz;
  final double standardDrinks;
  final DateTime loggedAt;
  final String? notes;

  AlcoholEntry({
    this.id,
    required this.drinkName,
    required this.totalVolumeOz,
    required this.abvPercent,
    required this.loggedAt,
    this.notes,
  })  : pureAlcoholOz = totalVolumeOz * abvPercent / 100,
        standardDrinks = (totalVolumeOz * abvPercent / 100) / 0.6;

  factory AlcoholEntry.fromMap(Map<String, dynamic> map) {
    return AlcoholEntry(
      id: map['id'] as String?,
      drinkName: map['drink_name'] as String,
      totalVolumeOz: (map['total_volume_oz'] as num).toDouble(),
      abvPercent: (map['abv_percent'] as num).toDouble(),
      loggedAt: DateTime.parse(map['logged_at'] as String).toLocal(),
      notes: map['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'drink_name': drinkName,
        'total_volume_oz': totalVolumeOz,
        'abv_percent': abvPercent,
        'pure_alcohol_oz': pureAlcoholOz,
        'standard_drinks': standardDrinks,
        'logged_at': loggedAt.toUtc().toIso8601String(),
        if (notes != null) 'notes': notes,
      };
}

// ---------------------------------------------------------------------------

class DrinkPreset {
  final String name;
  final double volumeOz;
  final double abvPercent;
  final String emoji;

  const DrinkPreset({
    required this.name,
    required this.volumeOz,
    required this.abvPercent,
    required this.emoji,
  });

  double get pureAlcoholOz => volumeOz * abvPercent / 100;
}

const List<DrinkPreset> kDrinkPresets = [
  DrinkPreset(name: 'Regular Beer',       volumeOz: 12.0, abvPercent: 5.0,  emoji: '🍺'),
  DrinkPreset(name: 'Light Beer',         volumeOz: 12.0, abvPercent: 4.2,  emoji: '🍺'),
  DrinkPreset(name: 'Craft IPA',          volumeOz: 12.0, abvPercent: 7.0,  emoji: '🍺'),
  DrinkPreset(name: 'White Wine',         volumeOz: 5.0,  abvPercent: 12.0, emoji: '🥂'),
  DrinkPreset(name: 'Red Wine',           volumeOz: 5.0,  abvPercent: 14.0, emoji: '🍷'),
  DrinkPreset(name: 'Champagne',          volumeOz: 4.0,  abvPercent: 12.0, emoji: '🥂'),
  DrinkPreset(name: 'Shot (Vodka/Whiskey)', volumeOz: 1.5, abvPercent: 40.0, emoji: '🥃'),
  DrinkPreset(name: 'Gin & Tonic',        volumeOz: 8.0,  abvPercent: 10.0, emoji: '🍹'),
  DrinkPreset(name: 'Margarita',          volumeOz: 6.0,  abvPercent: 15.0, emoji: '🍹'),
  DrinkPreset(name: 'Hard Seltzer',       volumeOz: 12.0, abvPercent: 5.0,  emoji: '🫧'),
  DrinkPreset(name: 'Hard Cider',         volumeOz: 12.0, abvPercent: 5.0,  emoji: '🍎'),
  DrinkPreset(name: 'Rum & Cola',         volumeOz: 8.0,  abvPercent: 10.0, emoji: '🥤'),
];

// ---------------------------------------------------------------------------

enum AlcoholRiskLevel {
  none,
  low,
  moderate,
  high;

  String get emoji => switch (this) {
        AlcoholRiskLevel.none     => '✅',
        AlcoholRiskLevel.low      => '🟡',
        AlcoholRiskLevel.moderate => '🟠',
        AlcoholRiskLevel.high     => '🔴',
      };

  String get label => switch (this) {
        AlcoholRiskLevel.none     => 'None',
        AlcoholRiskLevel.low      => 'Low Risk',
        AlcoholRiskLevel.moderate => 'Moderate Risk',
        AlcoholRiskLevel.high     => 'High Risk',
      };

  int get colorValue => switch (this) {
        AlcoholRiskLevel.none     => 0xFF4CAF50, // green
        AlcoholRiskLevel.low      => 0xFFFFC107, // amber
        AlcoholRiskLevel.moderate => 0xFFFF9800, // orange
        AlcoholRiskLevel.high     => 0xFFF44336, // red
      };
}