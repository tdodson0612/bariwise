// lib/models/ingredient_matrix_entry.dart
// Formalized ingredient matrix for LoRA training dataset.
// Replaces / extends the hardcoded _knownFoodWords / _knownNonFoodWords sets
// in FoodClassifierService with structured, bariatric-aware metadata.
//
// LORA_INTEGRATION_POINT: This matrix is the ground-truth source for
// Model C (food classifier) training data AND informs Model A (recipe
// generator) about which ingredients to prefer / avoid per surgery type.

class IngredientMatrixEntry {
  final String name;
  final List<String> aliases;
  final IngredientCategory category;
  final BariImpact bariImpact;
  final List<String> bariFlags;
  final List<String> typicalMeasurements;
  final List<String> avoidFor;    // surgery type strings
  final List<String> preferredFor;
  final double? sodiumMgPer100g;
  final double? sugarGPer100g;
  final double? fatGPer100g;

  const IngredientMatrixEntry({
    required this.name,
    this.aliases = const [],
    required this.category,
    required this.bariImpact,
    this.bariFlags = const [],
    this.typicalMeasurements = const ['cup', 'oz', 'g'],
    this.avoidFor = const [],
    this.preferredFor = const [],
    this.sodiumMgPer100g,
    this.sugarGPer100g,
    this.fatGPer100g,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'aliases': aliases,
        'category': category.name,
        'bari_impact': bariImpact.name,
        'bari_flags': bariFlags,
        'typical_measurements': typicalMeasurements,
        'avoid_for': avoidFor,
        'preferred_for': preferredFor,
        if (sodiumMgPer100g != null) 'sodium_mg_per_100g': sodiumMgPer100g,
        if (sugarGPer100g != null) 'sugar_g_per_100g': sugarGPer100g,
        if (fatGPer100g != null) 'fat_g_per_100g': fatGPer100g,
      };

  factory IngredientMatrixEntry.fromJson(Map<String, dynamic> json) =>
      IngredientMatrixEntry(
        name: json['name'] as String,
        aliases: (json['aliases'] as List?)?.cast<String>() ?? [],
        category:
            IngredientCategory.values.byName(json['category'] as String),
        bariImpact:
            BariImpact.values.byName(json['bari_impact'] as String),
        bariFlags: (json['bari_flags'] as List?)?.cast<String>() ?? [],
        typicalMeasurements:
            (json['typical_measurements'] as List?)?.cast<String>() ??
                ['cup', 'oz', 'g'],
        avoidFor: (json['avoid_for'] as List?)?.cast<String>() ?? [],
        preferredFor:
            (json['preferred_for'] as List?)?.cast<String>() ?? [],
        sodiumMgPer100g:
            (json['sodium_mg_per_100g'] as num?)?.toDouble(),
        sugarGPer100g: (json['sugar_g_per_100g'] as num?)?.toDouble(),
        fatGPer100g: (json['fat_g_per_100g'] as num?)?.toDouble(),
      );
}

enum IngredientCategory {
  protein,
  vegetable,
  fruit,
  grain,
  dairy,
  legume,
  fat,
  spice,
  liquid,
  condiment,
  other,
}

/// How an ingredient affects bariatric surgery recovery and outcomes.
enum BariImpact {
  beneficial, // supports weight loss, healing, and nutrient absorption
  neutral,    // safe, no special bariatric benefit
  caution,    // safe in moderation; watch portion size or texture
  avoid,      // may trigger dumping syndrome, stall weight loss, or cause obstruction
}

// ─────────────────────────────────────────────
// MASTER INGREDIENT MATRIX
// Surgery type strings used in preferredFor / avoidFor:
//   "gastric_bypass"  — Roux-en-Y gastric bypass (RYGB)
//   "sleeve"          — Sleeve gastrectomy
//   "lap_band"        — Adjustable gastric band
//   "revision"        — Revision bariatric surgery
// ─────────────────────────────────────────────
class IngredientMatrix {
  static const List<IngredientMatrixEntry> entries = [

    // ── PROTEINS ──────────────────────────────
    IngredientMatrixEntry(
      name: 'salmon',
      aliases: ['salmon fillet', 'fresh salmon', 'wild salmon'],
      category: IngredientCategory.protein,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['high_protein', 'high_omega3', 'anti_inflammatory', 'soft_texture'],
      typicalMeasurements: ['oz', 'g', 'lb'],
      preferredFor: ['gastric_bypass', 'sleeve', 'lap_band', 'revision'],
      fatGPer100g: 13.0,
      sodiumMgPer100g: 59.0,
    ),
    IngredientMatrixEntry(
      name: 'chicken breast',
      aliases: ['chicken', 'boneless chicken', 'skinless chicken breast'],
      category: IngredientCategory.protein,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['high_protein', 'low_fat', 'lean', 'post_op_staple'],
      typicalMeasurements: ['oz', 'g', 'lb', 'piece'],
      preferredFor: ['gastric_bypass', 'sleeve', 'lap_band', 'revision'],
      fatGPer100g: 3.6,
      sodiumMgPer100g: 74.0,
    ),
    IngredientMatrixEntry(
      name: 'tuna',
      aliases: ['canned tuna', 'tuna fillet'],
      category: IngredientCategory.protein,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['high_protein', 'high_omega3', 'low_calorie'],
      typicalMeasurements: ['oz', 'g', 'can'],
      preferredFor: ['gastric_bypass', 'sleeve'],
      sodiumMgPer100g: 300.0,
    ),
    IngredientMatrixEntry(
      name: 'beef',
      aliases: ['beef strips', 'ground beef', 'lean beef'],
      category: IngredientCategory.protein,
      bariImpact: BariImpact.caution,
      bariFlags: ['high_protein', 'high_saturated_fat', 'dense_texture'],
      typicalMeasurements: ['oz', 'g', 'lb'],
      avoidFor: ['lap_band'],   // dense meat can cause obstruction with band
      fatGPer100g: 20.0,
    ),
    IngredientMatrixEntry(
      name: 'pork',
      aliases: ['pork loin', 'pork chop'],
      category: IngredientCategory.protein,
      bariImpact: BariImpact.caution,
      bariFlags: ['high_protein', 'moderate_fat', 'dense_texture'],
      typicalMeasurements: ['oz', 'g', 'lb'],
      avoidFor: ['lap_band'],
    ),
    IngredientMatrixEntry(
      name: 'eggs',
      aliases: ['egg', 'large egg', 'whole egg'],
      category: IngredientCategory.protein,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['high_protein', 'soft_texture', 'post_op_staple', 'contains_choline'],
      typicalMeasurements: ['piece', 'pieces'],
      preferredFor: ['gastric_bypass', 'sleeve', 'lap_band', 'revision'],
      sodiumMgPer100g: 142.0,
    ),
    IngredientMatrixEntry(
      name: 'shrimp',
      aliases: ['prawns'],
      category: IngredientCategory.protein,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['high_protein', 'low_fat', 'low_calorie', 'soft_texture'],
      typicalMeasurements: ['oz', 'g', 'pieces'],
      preferredFor: ['gastric_bypass', 'sleeve'],
    ),
    IngredientMatrixEntry(
      name: 'tofu',
      aliases: ['firm tofu', 'silken tofu'],
      category: IngredientCategory.protein,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['plant_protein', 'low_saturated_fat', 'soft_texture'],
      typicalMeasurements: ['oz', 'g', 'cup'],
      preferredFor: ['gastric_bypass', 'sleeve', 'lap_band', 'revision'],
    ),
    IngredientMatrixEntry(
      name: 'cottage cheese',
      aliases: ['low-fat cottage cheese'],
      category: IngredientCategory.dairy,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['high_protein', 'soft_texture', 'post_op_staple', 'easy_to_tolerate'],
      typicalMeasurements: ['cup', 'oz'],
      preferredFor: ['gastric_bypass', 'sleeve', 'lap_band', 'revision'],
      sodiumMgPer100g: 372.0,
    ),
    IngredientMatrixEntry(
      name: 'protein powder',
      aliases: ['whey protein', 'protein shake', 'whey isolate'],
      category: IngredientCategory.protein,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['high_protein', 'post_op_staple', 'supplement_support'],
      typicalMeasurements: ['scoop', 'tbsp', 'oz'],
      preferredFor: ['gastric_bypass', 'sleeve', 'lap_band', 'revision'],
    ),

    // ── VEGETABLES ────────────────────────────
    IngredientMatrixEntry(
      name: 'broccoli',
      aliases: ['broccoli florets'],
      category: IngredientCategory.vegetable,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['high_fiber', 'antioxidant', 'low_calorie', 'nutrient_dense'],
      typicalMeasurements: ['cup', 'cups', 'g', 'oz'],
      preferredFor: ['gastric_bypass', 'sleeve', 'revision'],
      // lap_band: raw broccoli can be difficult; cooked is fine
      sodiumMgPer100g: 33.0,
    ),
    IngredientMatrixEntry(
      name: 'spinach',
      aliases: ['fresh spinach', 'baby spinach'],
      category: IngredientCategory.vegetable,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['high_iron', 'antioxidant', 'folate', 'low_calorie', 'soft_cooked'],
      typicalMeasurements: ['cup', 'cups', 'oz'],
      preferredFor: ['gastric_bypass', 'sleeve', 'lap_band', 'revision'],
    ),
    IngredientMatrixEntry(
      name: 'carrot',
      aliases: ['carrots', 'baby carrots'],
      category: IngredientCategory.vegetable,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['beta_carotene', 'high_fiber', 'antioxidant'],
      typicalMeasurements: ['cup', 'cups', 'piece', 'pieces', 'oz'],
      preferredFor: ['gastric_bypass', 'sleeve'],
    ),
    IngredientMatrixEntry(
      name: 'celery',
      aliases: ['celery stalks'],
      category: IngredientCategory.vegetable,
      bariImpact: BariImpact.caution,
      bariFlags: ['high_fiber', 'stringy_texture'],
      typicalMeasurements: ['cup', 'piece', 'pieces'],
      avoidFor: ['lap_band'],  // stringy texture problematic with band
    ),
    IngredientMatrixEntry(
      name: 'onion',
      aliases: ['onions', 'yellow onion', 'white onion', 'red onion'],
      category: IngredientCategory.vegetable,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['antioxidant', 'anti_inflammatory', 'low_calorie'],
      typicalMeasurements: ['cup', 'cups', 'piece', 'pieces'],
    ),
    IngredientMatrixEntry(
      name: 'garlic',
      aliases: ['garlic cloves', 'minced garlic', 'fresh garlic'],
      category: IngredientCategory.vegetable,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['anti_inflammatory', 'flavor_enhancer', 'low_calorie'],
      typicalMeasurements: ['tsp', 'tbsp', 'piece', 'pieces'],
      preferredFor: ['gastric_bypass', 'sleeve', 'lap_band', 'revision'],
    ),
    IngredientMatrixEntry(
      name: 'sweet potato',
      aliases: ['sweet potatoes', 'yam'],
      category: IngredientCategory.vegetable,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['beta_carotene', 'high_fiber', 'complex_carbs', 'soft_cooked'],
      typicalMeasurements: ['cup', 'piece', 'pieces', 'oz'],
      preferredFor: ['gastric_bypass', 'sleeve'],
    ),
    IngredientMatrixEntry(
      name: 'zucchini',
      aliases: ['courgette'],
      category: IngredientCategory.vegetable,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['low_calorie', 'high_water', 'soft_cooked', 'easy_to_tolerate'],
      typicalMeasurements: ['cup', 'piece', 'pieces'],
      preferredFor: ['gastric_bypass', 'sleeve', 'lap_band', 'revision'],
    ),
    IngredientMatrixEntry(
      name: 'bell pepper',
      aliases: ['peppers', 'red pepper', 'green pepper', 'yellow pepper'],
      category: IngredientCategory.vegetable,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['vitamin_c', 'antioxidant', 'low_calorie'],
      typicalMeasurements: ['cup', 'piece', 'pieces'],
    ),
    IngredientMatrixEntry(
      name: 'lettuce',
      aliases: ['romaine', 'mixed greens', 'salad greens'],
      category: IngredientCategory.vegetable,
      bariImpact: BariImpact.caution,
      bariFlags: ['low_calorie', 'high_water', 'low_protein'],
      typicalMeasurements: ['cup', 'cups', 'oz'],
      // caution: fills pouch with very low nutrition; protein first
    ),
    IngredientMatrixEntry(
      name: 'tomato',
      aliases: ['tomatoes', 'cherry tomatoes', 'roma tomatoes'],
      category: IngredientCategory.vegetable,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['lycopene', 'antioxidant', 'low_calorie'],
      typicalMeasurements: ['cup', 'piece', 'pieces', 'oz'],
    ),
    IngredientMatrixEntry(
      name: 'ginger',
      aliases: ['fresh ginger', 'ginger root'],
      category: IngredientCategory.spice,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['anti_nausea', 'anti_inflammatory', 'digestive_support'],
      typicalMeasurements: ['tsp', 'tbsp', 'piece'],
      preferredFor: ['gastric_bypass', 'sleeve', 'revision'],
    ),

    // ── GRAINS ────────────────────────────────
    IngredientMatrixEntry(
      name: 'brown rice',
      aliases: ['whole grain rice'],
      category: IngredientCategory.grain,
      bariImpact: BariImpact.caution,
      bariFlags: ['complex_carbs', 'high_fiber', 'protein_last'],
      typicalMeasurements: ['cup', 'cups'],
      // caution: eat protein first; grains fill small pouch quickly
    ),
    IngredientMatrixEntry(
      name: 'oats',
      aliases: ['oatmeal', 'rolled oats', 'steel cut oats'],
      category: IngredientCategory.grain,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['beta_glucan', 'high_fiber', 'soft_texture', 'easy_to_tolerate'],
      typicalMeasurements: ['cup', 'cups'],
      preferredFor: ['gastric_bypass', 'sleeve', 'lap_band', 'revision'],
    ),
    IngredientMatrixEntry(
      name: 'quinoa',
      aliases: ['cooked quinoa'],
      category: IngredientCategory.grain,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['complete_protein', 'high_fiber', 'low_glycemic'],
      typicalMeasurements: ['cup', 'cups'],
      preferredFor: ['gastric_bypass', 'sleeve'],
    ),
    IngredientMatrixEntry(
      name: 'white rice',
      aliases: ['cooked rice'],
      category: IngredientCategory.grain,
      bariImpact: BariImpact.caution,
      bariFlags: ['refined_carbs', 'high_glycemic', 'low_protein', 'fills_pouch'],
      typicalMeasurements: ['cup', 'cups'],
      avoidFor: ['gastric_bypass'],
    ),
    IngredientMatrixEntry(
      name: 'flour',
      aliases: ['all-purpose flour', 'wheat flour'],
      category: IngredientCategory.grain,
      bariImpact: BariImpact.caution,
      bariFlags: ['refined_carbs', 'low_protein'],
      typicalMeasurements: ['cup', 'cups', 'tbsp'],
    ),
    IngredientMatrixEntry(
      name: 'bread',
      aliases: ['white bread', 'whole wheat bread', 'toast'],
      category: IngredientCategory.grain,
      bariImpact: BariImpact.avoid,
      bariFlags: ['doughy_texture', 'forms_ball_in_pouch', 'obstruction_risk'],
      typicalMeasurements: ['slice', 'piece'],
      avoidFor: ['gastric_bypass', 'sleeve', 'lap_band', 'revision'],
    ),

    // ── LEGUMES ───────────────────────────────
    IngredientMatrixEntry(
      name: 'lentils',
      aliases: ['red lentils', 'green lentils', 'brown lentils'],
      category: IngredientCategory.legume,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['high_fiber', 'plant_protein', 'low_fat', 'soft_cooked'],
      typicalMeasurements: ['cup', 'cups'],
      preferredFor: ['gastric_bypass', 'sleeve', 'revision'],
    ),
    IngredientMatrixEntry(
      name: 'chickpeas',
      aliases: ['garbanzo beans', 'canned chickpeas'],
      category: IngredientCategory.legume,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['high_fiber', 'plant_protein', 'low_glycemic'],
      typicalMeasurements: ['cup', 'cups', 'oz'],
      preferredFor: ['gastric_bypass', 'sleeve'],
    ),
    IngredientMatrixEntry(
      name: 'beans',
      aliases: ['black beans', 'kidney beans', 'navy beans', 'peas'],
      category: IngredientCategory.legume,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['high_fiber', 'plant_protein'],
      typicalMeasurements: ['cup', 'cups', 'oz'],
      preferredFor: ['gastric_bypass', 'sleeve'],
    ),

    // ── DAIRY ─────────────────────────────────
    IngredientMatrixEntry(
      name: 'greek yogurt',
      aliases: ['plain greek yogurt', 'low-fat greek yogurt'],
      category: IngredientCategory.dairy,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['high_protein', 'probiotics', 'soft_texture', 'post_op_staple'],
      typicalMeasurements: ['cup', 'tbsp', 'oz'],
      preferredFor: ['gastric_bypass', 'sleeve', 'lap_band', 'revision'],
    ),
    IngredientMatrixEntry(
      name: 'milk',
      aliases: ['skim milk', 'low-fat milk', 'whole milk'],
      category: IngredientCategory.dairy,
      bariImpact: BariImpact.neutral,
      bariFlags: ['calcium', 'vitamin_d', 'liquid_calories'],
      typicalMeasurements: ['cup', 'cups', 'ml'],
    ),
    IngredientMatrixEntry(
      name: 'butter',
      aliases: ['unsalted butter'],
      category: IngredientCategory.dairy,
      bariImpact: BariImpact.caution,
      bariFlags: ['high_saturated_fat', 'high_calorie_density'],
      typicalMeasurements: ['tbsp', 'tsp', 'oz'],
      avoidFor: ['gastric_bypass', 'sleeve'],
    ),
    IngredientMatrixEntry(
      name: 'cheese',
      aliases: ['cheddar', 'mozzarella', 'parmesan'],
      category: IngredientCategory.dairy,
      bariImpact: BariImpact.caution,
      bariFlags: ['high_saturated_fat', 'high_sodium', 'moderate_protein'],
      typicalMeasurements: ['oz', 'cup', 'tbsp'],
      sodiumMgPer100g: 600.0,
    ),

    // ── FATS & OILS ───────────────────────────
    IngredientMatrixEntry(
      name: 'olive oil',
      aliases: ['extra virgin olive oil', 'evoo'],
      category: IngredientCategory.fat,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['monounsaturated_fat', 'anti_inflammatory', 'heart_healthy'],
      typicalMeasurements: ['tbsp', 'tsp', 'ml'],
      preferredFor: ['gastric_bypass', 'sleeve', 'lap_band', 'revision'],
    ),
    IngredientMatrixEntry(
      name: 'avocado',
      aliases: ['avocados'],
      category: IngredientCategory.fat,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['monounsaturated_fat', 'high_fiber', 'nutrient_dense', 'soft_texture'],
      typicalMeasurements: ['piece', 'cup', 'tbsp'],
      preferredFor: ['gastric_bypass', 'sleeve'],
    ),

    // ── FRUITS ────────────────────────────────
    IngredientMatrixEntry(
      name: 'apple',
      aliases: ['apples', 'green apple', 'red apple'],
      category: IngredientCategory.fruit,
      bariImpact: BariImpact.caution,
      bariFlags: ['high_fiber', 'antioxidant', 'moderate_sugar', 'eat_after_protein'],
      typicalMeasurements: ['piece', 'cup', 'cups'],
      sugarGPer100g: 10.0,
    ),
    IngredientMatrixEntry(
      name: 'lemon',
      aliases: ['lemon juice', 'lemon zest'],
      category: IngredientCategory.fruit,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['vitamin_c', 'flavor_enhancer', 'low_sugar', 'low_calorie'],
      typicalMeasurements: ['piece', 'tbsp', 'tsp'],
      preferredFor: ['gastric_bypass', 'sleeve', 'lap_band', 'revision'],
    ),
    IngredientMatrixEntry(
      name: 'blueberries',
      aliases: ['blueberry', 'mixed berries'],
      category: IngredientCategory.fruit,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['anthocyanins', 'antioxidant', 'low_sugar', 'anti_inflammatory'],
      typicalMeasurements: ['cup', 'cups', 'oz'],
      preferredFor: ['gastric_bypass', 'sleeve'],
    ),
    IngredientMatrixEntry(
      name: 'banana',
      aliases: ['bananas'],
      category: IngredientCategory.fruit,
      bariImpact: BariImpact.caution,
      bariFlags: ['high_potassium', 'moderate_sugar', 'soft_texture'],
      typicalMeasurements: ['piece', 'cup'],
      sugarGPer100g: 12.0,
    ),

    // ── SPICES / SEASONINGS ───────────────────
    IngredientMatrixEntry(
      name: 'turmeric',
      aliases: ['ground turmeric', 'turmeric powder'],
      category: IngredientCategory.spice,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['curcumin', 'anti_inflammatory', 'digestive_support'],
      typicalMeasurements: ['tsp', 'pinch'],
      preferredFor: ['gastric_bypass', 'sleeve', 'revision'],
    ),
    IngredientMatrixEntry(
      name: 'salt',
      aliases: ['sea salt', 'table salt'],
      category: IngredientCategory.spice,
      bariImpact: BariImpact.caution,
      bariFlags: ['high_sodium', 'fluid_retention'],
      typicalMeasurements: ['tsp', 'pinch', 'to taste'],
      avoidFor: ['revision'],
      sodiumMgPer100g: 38758.0,
    ),
    IngredientMatrixEntry(
      name: 'soy sauce',
      aliases: ['low-sodium soy sauce', 'tamari'],
      category: IngredientCategory.condiment,
      bariImpact: BariImpact.caution,
      bariFlags: ['very_high_sodium'],
      typicalMeasurements: ['tbsp', 'tsp'],
      avoidFor: ['gastric_bypass', 'revision'],
      sodiumMgPer100g: 5720.0,
    ),

    // ── LIQUIDS ───────────────────────────────
    IngredientMatrixEntry(
      name: 'water',
      aliases: ['filtered water'],
      category: IngredientCategory.liquid,
      bariImpact: BariImpact.beneficial,
      bariFlags: ['hydration', 'sip_dont_gulp', 'post_op_essential'],
      typicalMeasurements: ['cup', 'cups', 'ml', 'l'],
      preferredFor: ['gastric_bypass', 'sleeve', 'lap_band', 'revision'],
    ),
    IngredientMatrixEntry(
      name: 'vegetable broth',
      aliases: ['low-sodium vegetable broth', 'chicken broth'],
      category: IngredientCategory.liquid,
      bariImpact: BariImpact.neutral,
      bariFlags: ['moderate_sodium', 'low_calorie'],
      typicalMeasurements: ['cup', 'cups', 'ml'],
      sodiumMgPer100g: 200.0,
    ),

    // ── SUGARS / SWEETENERS ───────────────────
    IngredientMatrixEntry(
      name: 'sugar',
      aliases: ['white sugar', 'granulated sugar'],
      category: IngredientCategory.condiment,
      bariImpact: BariImpact.avoid,
      bariFlags: ['dumping_syndrome_trigger', 'high_sugar', 'stalls_weight_loss'],
      typicalMeasurements: ['cup', 'tbsp', 'tsp'],
      avoidFor: ['gastric_bypass', 'sleeve', 'lap_band', 'revision'],
      sugarGPer100g: 100.0,
    ),
    IngredientMatrixEntry(
      name: 'brown sugar',
      aliases: ['dark brown sugar'],
      category: IngredientCategory.condiment,
      bariImpact: BariImpact.avoid,
      bariFlags: ['dumping_syndrome_trigger', 'high_sugar'],
      typicalMeasurements: ['tbsp', 'tsp'],
      avoidFor: ['gastric_bypass', 'sleeve'],
    ),
    IngredientMatrixEntry(
      name: 'honey',
      aliases: ['raw honey'],
      category: IngredientCategory.condiment,
      bariImpact: BariImpact.avoid,
      bariFlags: ['dumping_syndrome_trigger', 'high_sugar', 'fructose'],
      typicalMeasurements: ['tbsp', 'tsp'],
      avoidFor: ['gastric_bypass', 'sleeve'],
    ),
  ];

  /// Get all entries for a given category
  static List<IngredientMatrixEntry> byCategory(IngredientCategory cat) =>
      entries.where((e) => e.category == cat).toList();

  /// Get all entries preferred for a surgery type
  static List<IngredientMatrixEntry> preferredForDisease(String surgeryType) =>
      entries.where((e) => e.preferredFor.contains(surgeryType)).toList();

  /// Get all entries to avoid for a surgery type
  static List<IngredientMatrixEntry> avoidForDisease(String surgeryType) =>
      entries.where((e) => e.avoidFor.contains(surgeryType)).toList();

  /// Look up an entry by name or alias (case-insensitive)
  static IngredientMatrixEntry? lookup(String term) {
    final lower = term.toLowerCase().trim();
    for (final entry in entries) {
      if (entry.name == lower) return entry;
      if (entry.aliases.any((a) => a.toLowerCase() == lower)) return entry;
    }
    return null;
  }

  /// Check if a term is a known food
  static bool isKnownFood(String term) => lookup(term) != null;

  /// Get beneficial ingredients count
  static int get beneficialCount =>
      entries.where((e) => e.bariImpact == BariImpact.beneficial).length;
}