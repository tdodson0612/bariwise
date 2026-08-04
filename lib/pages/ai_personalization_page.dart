// lib/pages/ai_personalization_page.dart
// Section 15 — AI Personalization Engine UI Shell
// Route: '/ai-personalization'
//
// Placeholder UI for three personalization surfaces:
//   1. Recipe Recommendations  — surgery-aware, tolerance-filtered
//   2. Supplement Suggestions  — deficiency-pattern-driven
//   3. Auto Meal Plan          — tracker-history-informed
//
// All data is mocked / rule-based in this shell.
// Backend ML integration is deferred to Phase 2/3 (see ai_personalization_plan.md).
//
// ✅ FIXED THIS SESSION: previously used "BBRS design language: navy hero,
// glass cards, gold accents" — a leftover from the LiverWise/BBRS source
// template, violating Rule 1.3 (BariWise = Colors.orange). Long-flagged
// Technical Debt, now resolved. All BBRS navy/gold tokens (_kNavy, _kNavyL,
// _kGold) renamed and re-valued to a BariWise orange palette (_kPrimary,
// _kPrimaryLight) rather than just re-valued under the old names, since a
// variable called "_kNavy" holding an orange value would be more confusing
// than the mismatch it replaces. No layout, spacing, or component
// structure changed — colors only, per Rule 13.
//
// Also verified this session: the previously-flagged unused
// grocery_service.dart import is not present in this file — that item is
// resolved (or was already inaccurate) as of the current file state.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/profile_service.dart';
import '../services/recent_activity_tracker.dart';
import '../config/app_config.dart';

// ─── BariWise Tokens ──────────────────────────────────────────────────────────
// _kPrimary/_kPrimaryLight replace the former BBRS _kNavy/_kNavyL/_kGold.
// _kPrimary: deep, rich orange (deepOrange.shade900-equivalent) — used
//   wherever the hero/dark surface previously used navy.
// _kPrimaryLight: bright BariWise orange (orange.shade500-equivalent) —
//   used wherever the former gold accent (or the lighter navy gradient
//   partner) previously appeared.
const _kPrimary      = Color(0xFFBF360C);
const _kPrimaryLight = Color(0xFFFF9800);
const _kBg    = Color(0xFFEEF2F7);
const _kBody  = Color(0xFF1A2332);
const _kMuted = Color(0xFF6B7A94);
const _kBorder = Color(0xFFDDE3EE);

// ─────────────────────────────────────────────────────────────────────────────
// PAGE
// ─────────────────────────────────────────────────────────────────────────────

class AiPersonalizationPage extends StatefulWidget {
  const AiPersonalizationPage({super.key});

  @override
  State<AiPersonalizationPage> createState() => _AiPersonalizationPageState();
}

class _AiPersonalizationPageState extends State<AiPersonalizationPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  String? _surgeryType;
  List<String> _restrictions = [];
  List<String> _supplementBaseline = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadProfile();
    RecentActivityTracker.recordScreen(
        label: 'AI Personalization', route: '/ai-personalization');
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final surgeryType = await ProfileService.getSurgeryType(userId);
      final prefs = await SharedPreferences.getInstance();
      final restrictions =
          prefs.getStringList('intake_dietary_restrictions_$userId') ?? [];
      final supplements =
          prefs.getStringList('intake_supplement_baseline_$userId') ?? [];

      if (mounted) {
        setState(() {
          _surgeryType = surgeryType;
          _restrictions = restrictions;
          _supplementBaseline = supplements;
          _loading = false;
        });
      }
    } catch (e) {
      AppConfig.debugPrint('AI personalization load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: _kPrimary,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [_kPrimary, _kPrimaryLight],
                        begin: Alignment.topLeft, end: Alignment.bottomRight)),
                child: SafeArea(child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 48, 20, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end, children: [
                    Row(children: [
                      Container(padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: _kPrimaryLight.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _kPrimaryLight.withValues(alpha: 0.4))),
                          child: const Icon(Icons.auto_awesome_rounded,
                              color: _kPrimaryLight, size: 22)),
                      const SizedBox(width: 12),
                      const Column(crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Personalized For You',
                                style: TextStyle(color: Colors.white, fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                            Text('AI-powered bariatric recommendations',
                                style: TextStyle(color: Colors.white60, fontSize: 12)),
                          ]),
                    ]),
                    const SizedBox(height: 12),
                  ]),
                )),
              ),
              title: const Text('AI Recommendations',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              titlePadding: const EdgeInsets.only(left: 56, bottom: 14),
            ),
            bottom: TabBar(
              controller: _tabs,
              indicatorColor: _kPrimaryLight,
              indicatorWeight: 3,
              labelColor: _kPrimaryLight,
              unselectedLabelColor: Colors.white54,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              tabs: const [
                Tab(icon: Icon(Icons.restaurant_rounded, size: 16), text: 'Recipes'),
                Tab(icon: Icon(Icons.medication_rounded, size: 16), text: 'Supplements'),
                Tab(icon: Icon(Icons.calendar_month_rounded, size: 16), text: 'Meal Plan'),
              ],
            ),
          ),
        ],
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: _kPrimaryLight))
            : TabBarView(
                controller: _tabs,
                children: [
                  _RecipeTab(surgeryType: _surgeryType, restrictions: _restrictions),
                  _SupplementTab(baseline: _supplementBaseline, surgeryType: _surgeryType),
                  _MealPlanTab(surgeryType: _surgeryType, restrictions: _restrictions),
                ],
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1 — RECIPE RECOMMENDATIONS
// ─────────────────────────────────────────────────────────────────────────────

class _RecipeTab extends StatelessWidget {
  final String? surgeryType;
  final List<String> restrictions;

  const _RecipeTab({required this.surgeryType, required this.restrictions});

  // Rule-based recipe suggestions by surgery type (Phase 1 shell — static data)
  List<_RecipeSuggestion> _getSuggestions() {
    final isRygb = surgeryType?.contains('Bypass') ?? false;
    final isDs = surgeryType?.contains('Switch') ?? false;

    if (isDs) {
      return const [
        _RecipeSuggestion(name: 'High-Protein Tuna Scramble',
            reason: 'Duodenal Switch requires very high protein (30g+/serving).',
            protein: 38, calories: 280, tags: ['High Protein', 'Low Carb']),
        _RecipeSuggestion(name: 'Greek Yogurt Power Bowl',
            reason: 'Fat-soluble vitamin rich — supports DS absorption needs.',
            protein: 28, calories: 320, tags: ['High Protein', 'Vitamin Rich']),
        _RecipeSuggestion(name: 'Baked Salmon with Quinoa',
            reason: 'Omega-3 rich, high protein, fat-soluble vitamins.',
            protein: 42, calories: 410, tags: ['High Protein', 'Omega-3']),
      ];
    }
    if (isRygb) {
      return const [
        _RecipeSuggestion(name: 'Cottage Cheese Egg Bake',
            reason: 'Soft texture, high protein, low sugar — ideal for bypass.',
            protein: 24, calories: 210, tags: ['Soft Food', 'High Protein']),
        _RecipeSuggestion(name: 'Turkey & Veggie Meatballs',
            reason: 'Lean protein, low fat, tolerated well post-bypass.',
            protein: 28, calories: 240, tags: ['High Protein', 'Low Fat']),
        _RecipeSuggestion(name: 'Ricotta Protein Pancakes',
            reason: 'Low sugar, high protein, soft — classic bypass-friendly breakfast.',
            protein: 20, calories: 190, tags: ['Soft Food', 'Low Sugar']),
      ];
    }
    // Default / sleeve / other
    return const [
      _RecipeSuggestion(name: 'Chicken & Avocado Salad',
          reason: 'High protein with healthy fats — balanced for sleeve patients.',
          protein: 32, calories: 340, tags: ['High Protein', 'Balanced']),
      _RecipeSuggestion(name: 'Shrimp Stir-Fry with Zucchini',
          reason: 'Lean protein, low carb, easy on your stomach.',
          protein: 26, calories: 260, tags: ['Low Carb', 'High Protein']),
      _RecipeSuggestion(name: 'Protein-Packed Smoothie Bowl',
          reason: 'Easy to eat, nutrient-dense, great for morning protein.',
          protein: 22, calories: 300, tags: ['High Protein', 'Easy Eat']),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _getSuggestions();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Context banner
        _ContextBanner(
          icon: Icons.tune_rounded,
          text: surgeryType != null
              ? 'Personalized for: $surgeryType'
              : 'Set your surgery type in Account Preferences for better recommendations.',
        ),

        const SizedBox(height: 16),
        _PhaseLabel(phase: 'Phase 1', description: 'Rule-based suggestions — AI enhancement coming in Phase 2'),
        const SizedBox(height: 12),

        ...suggestions.map((s) => _RecipeCard(suggestion: s)),

        const SizedBox(height: 8),
        _ComingSoonCard(
          icon: Icons.psychology_rounded,
          title: 'Tolerance-Aware Filtering',
          description:
              'Phase 2 will automatically exclude foods you\'ve flagged as poorly tolerated in your Food Tolerance log.',
        ),
      ]),
    );
  }
}

class _RecipeSuggestion {
  final String name;
  final String reason;
  final int protein;
  final int calories;
  final List<String> tags;
  const _RecipeSuggestion({required this.name, required this.reason,
      required this.protein, required this.calories, required this.tags});
}

class _RecipeCard extends StatelessWidget {
  final _RecipeSuggestion suggestion;
  const _RecipeCard({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: _kPrimaryLight.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.restaurant_rounded, color: _kPrimaryLight, size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Text(suggestion.name,
              style: const TextStyle(fontWeight: FontWeight.bold,
                  fontSize: 14, color: _kBody))),
        ]),
        const SizedBox(height: 8),
        Text(suggestion.reason,
            style: const TextStyle(fontSize: 12, color: _kMuted, height: 1.4)),
        const SizedBox(height: 8),
        Row(children: [
          _NutriBadge(label: '${suggestion.protein}g protein', color: const Color(0xFF4FC3F7)),
          const SizedBox(width: 6),
          _NutriBadge(label: '${suggestion.calories} cal', color: const Color(0xFFFFB74D)),
          const Spacer(),
          ...suggestion.tags.map((t) => Padding(
            padding: const EdgeInsets.only(left: 4),
            child: _TagChip(label: t),
          )),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 2 — SUPPLEMENT SUGGESTIONS
// ─────────────────────────────────────────────────────────────────────────────

class _SupplementTab extends StatelessWidget {
  final List<String> baseline;
  final String? surgeryType;

  const _SupplementTab({required this.baseline, required this.surgeryType});

  List<_SupplementSuggestion> _getSuggestions() {
    final isDs = surgeryType?.contains('Switch') ?? false;
    final isRygb = surgeryType?.contains('Bypass') ?? false;

    final all = <_SupplementSuggestion>[
      const _SupplementSuggestion(
        name: 'Vitamin B12',
        reason: 'Bariatric surgery significantly reduces B12 absorption. '
            'Deficiency causes fatigue, nerve damage, and brain fog.',
        urgency: 'Essential',
        urgencyColor: Color(0xFFEF5350),
        dosage: '500–1000mcg daily (sublingual preferred)',
      ),
      const _SupplementSuggestion(
        name: 'Calcium Citrate',
        reason: 'Reduced stomach acid post-surgery means carbonate forms '
            'aren\'t absorbed. Citrate form is critical for bone health.',
        urgency: 'Essential',
        urgencyColor: Color(0xFFEF5350),
        dosage: '1200–1500mg daily in split doses',
      ),
      const _SupplementSuggestion(
        name: 'Vitamin D3',
        reason: 'D3 deficiency is nearly universal post-bariatric surgery. '
            'Required for calcium absorption and immune function.',
        urgency: 'Essential',
        urgencyColor: Color(0xFFEF5350),
        dosage: '3000 IU daily minimum',
      ),
      const _SupplementSuggestion(
        name: 'Iron',
        reason: 'Risk especially high for menstruating patients and '
            'bypass patients due to reduced stomach acid.',
        urgency: 'High Risk',
        urgencyColor: Color(0xFFFF7043),
        dosage: '45–60mg elemental iron daily with Vitamin C',
      ),
      _SupplementSuggestion(
        name: 'Zinc',
        reason: isDs
            ? 'Duodenal Switch patients have very high zinc deficiency risk due to fat malabsorption.'
            : 'Zinc supports wound healing, immune function, and hair retention post-op.',
        urgency: isDs ? 'Essential' : 'Recommended',
        urgencyColor: isDs ? const Color(0xFFEF5350) : const Color(0xFFFFB74D),
        dosage: '8–22mg daily',
      ),
      if (isRygb || isDs)
        const _SupplementSuggestion(
          name: 'Vitamin A',
          reason: 'Fat-soluble vitamin absorption is significantly impaired '
              'after bypass and switch procedures.',
          urgency: 'High Risk',
          urgencyColor: Color(0xFFFF7043),
          dosage: '10,000 IU daily as part of bariatric multivitamin',
        ),
    ];

    // Filter out what they're already taking
    final taking = baseline.map((s) => s.toLowerCase()).toSet();
    return all.where((s) => !taking.any((t) => t.contains(s.name.toLowerCase().split(' ').first))).toList();
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _getSuggestions();
    final alreadyTaking = baseline.where((s) => s != 'None yet').toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Already taking
        if (alreadyTaking.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF66BB6A).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF66BB6A).withValues(alpha: 0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.check_circle_rounded, color: Color(0xFF66BB6A), size: 16),
                SizedBox(width: 6),
                Text('Already Taking', style: TextStyle(fontWeight: FontWeight.bold,
                    color: Color(0xFF2E7D32), fontSize: 13)),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: alreadyTaking
                  .map((s) => _TagChip(label: s, color: const Color(0xFF66BB6A)))
                  .toList()),
            ]),
          ),
          const SizedBox(height: 16),
        ],

        _ContextBanner(
          icon: Icons.info_outline_rounded,
          text: 'These are educational suggestions only. Always consult your '
              'bariatric surgeon or dietitian before adding supplements.',
        ),
        const SizedBox(height: 12),
        _PhaseLabel(phase: 'Phase 1', description: 'Surgery-type rules — symptom-pattern detection coming in Phase 2'),
        const SizedBox(height: 12),

        if (suggestions.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(14), border: Border.all(color: _kBorder)),
            child: const Row(children: [
              Icon(Icons.celebration_rounded, color: _kPrimaryLight, size: 24),
              SizedBox(width: 12),
              Expanded(child: Text('You\'re already taking all the key bariatric supplements!',
                  style: TextStyle(fontSize: 14, color: _kBody))),
            ]),
          )
        else
          ...suggestions.map((s) => _SupplementCard(suggestion: s)),

        const SizedBox(height: 8),
        _ComingSoonCard(
          icon: Icons.analytics_rounded,
          title: 'Symptom-Pattern Detection',
          description:
              'Phase 2 will analyze your symptom logs to identify potential '
              'deficiency patterns and refine these recommendations automatically.',
        ),
      ]),
    );
  }
}

class _SupplementSuggestion {
  final String name;
  final String reason;
  final String urgency;
  final Color urgencyColor;
  final String dosage;
  const _SupplementSuggestion({required this.name, required this.reason,
      required this.urgency, required this.urgencyColor, required this.dosage});
}

class _SupplementCard extends StatelessWidget {
  final _SupplementSuggestion suggestion;
  const _SupplementCard({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: const Color(0xFF4FC3F7).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.medication_rounded,
                  color: Color(0xFF4FC3F7), size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Text(suggestion.name,
              style: const TextStyle(fontWeight: FontWeight.bold,
                  fontSize: 14, color: _kBody))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: suggestion.urgencyColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: suggestion.urgencyColor.withValues(alpha: 0.3)),
            ),
            child: Text(suggestion.urgency,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                    color: suggestion.urgencyColor)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(suggestion.reason,
            style: const TextStyle(fontSize: 12, color: _kMuted, height: 1.4)),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.medical_information_outlined, size: 14, color: _kMuted),
          const SizedBox(width: 4),
          Expanded(child: Text('Typical dose: ${suggestion.dosage}',
              style: const TextStyle(fontSize: 11, color: _kMuted))),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 3 — AUTO MEAL PLAN
// ─────────────────────────────────────────────────────────────────────────────

class _MealPlanTab extends StatefulWidget {
  final String? surgeryType;
  final List<String> restrictions;

  const _MealPlanTab(
      {required this.surgeryType, required this.restrictions});

  @override
  State<_MealPlanTab> createState() => _MealPlanTabState();
}

class _MealPlanTabState extends State<_MealPlanTab> {
  bool _generating = false;
  Map<String, Map<String, String>>? _generatedPlan;

  static const _dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _mealTypes = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];

  // Static rule-based meal pools by surgery type (Phase 1 shell)
  static const Map<String, List<String>> _breakfasts = {
    'bypass': ['Cottage Cheese Egg Bake', 'Greek Yogurt with Berries', 'Protein Ricotta Pancakes'],
    'sleeve': ['Scrambled Eggs & Avocado', 'Greek Yogurt Power Bowl', 'Protein Smoothie'],
    'default': ['Greek Yogurt with Berries', 'Scrambled Eggs', 'Cottage Cheese Bowl'],
  };
  static const Map<String, List<String>> _lunches = {
    'bypass': ['Turkey Meatballs', 'Tuna Salad Lettuce Wraps', 'Chicken Broth Soup'],
    'sleeve': ['Grilled Chicken Salad', 'Shrimp & Zucchini', 'Turkey Lettuce Wraps'],
    'default': ['Chicken & Avocado Salad', 'Tuna & Cucumber', 'Turkey Roll-Ups'],
  };
  static const Map<String, List<String>> _dinners = {
    'bypass': ['Baked Cod with Steamed Veg', 'Ground Turkey Stir-Fry', 'Soft Chicken Casserole'],
    'sleeve': ['Salmon & Roasted Veg', 'Lean Beef & Broccoli', 'Chicken Zucchini Bake'],
    'default': ['Baked Salmon & Quinoa', 'Grilled Tilapia & Spinach', 'Turkey & Sweet Potato'],
  };
  static const Map<String, List<String>> _snacks = {
    'bypass': ['String Cheese', 'Soft-Boiled Egg', 'Greek Yogurt'],
    'sleeve': ['Protein Bar', 'Cottage Cheese', 'Hard-Boiled Egg'],
    'default': ['Cheese Stick', 'Cottage Cheese Cup', 'Protein Shake'],
  };

  String _poolKey() {
    if (widget.surgeryType?.contains('Bypass') ?? false) return 'bypass';
    if (widget.surgeryType?.contains('Sleeve') ?? false) return 'sleeve';
    return 'default';
  }

  Future<void> _generatePlan() async {
    setState(() => _generating = true);
    await Future.delayed(const Duration(milliseconds: 800)); // simulate processing

    final key = _poolKey();
    final breakfasts = _breakfasts[key]!;
    final lunches    = _lunches[key]!;
    final dinners    = _dinners[key]!;
    final snacks     = _snacks[key]!;

    final plan = <String, Map<String, String>>{};
    for (int i = 0; i < 7; i++) {
      plan[_dayNames[i]] = {
        'Breakfast': breakfasts[i % breakfasts.length],
        'Lunch':     lunches[i % lunches.length],
        'Dinner':    dinners[i % dinners.length],
        'Snack':     snacks[i % snacks.length],
      };
    }

    if (mounted) {
      setState(() {
      _generatedPlan = plan;
      _generating = false;
    });
    }
  }

  Future<void> _exportToMealPlanner() async {
    if (_generatedPlan == null) return;
    // Navigate to meal planner — in Phase 2 this will pre-populate the planner
    Navigator.pushNamed(context, '/meal-planner');
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _ContextBanner(
          icon: Icons.auto_awesome_rounded,
          text: widget.surgeryType != null
              ? 'Generating plan for: ${widget.surgeryType}'
              : 'Set your surgery type in Account Preferences for a personalized plan.',
        ),
        const SizedBox(height: 12),
        _PhaseLabel(phase: 'Phase 1', description: 'Rule-based plan — tracker history integration coming in Phase 2'),
        const SizedBox(height: 16),

        if (_generatedPlan == null) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kBorder),
            ),
            child: Column(children: [
              Container(padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: _kPrimaryLight.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: _kPrimaryLight.withValues(alpha: 0.3))),
                  child: const Icon(Icons.auto_awesome_rounded, color: _kPrimaryLight, size: 40)),
              const SizedBox(height: 16),
              const Text('Generate Your Week', style: TextStyle(fontSize: 18,
                  fontWeight: FontWeight.bold, color: _kBody)),
              const SizedBox(height: 8),
              Text(
                'Tap below to auto-generate a 7-day bariatric meal plan '
                'tailored to your surgery type and dietary needs.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: _kMuted, height: 1.5),
              ),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: _generating ? null : _generatePlan,
                icon: _generating
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome_rounded),
                label: Text(_generating ? 'Generating…' : 'Generate 7-Day Plan'),
                style: FilledButton.styleFrom(
                  backgroundColor: _kPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: _kPrimaryLight.withValues(alpha: 0.4))),
                ),
              )),
            ]),
          ),
        ] else ...[
          // Action buttons
          Row(children: [
            Expanded(child: FilledButton.icon(
              onPressed: _generatePlan,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Regenerate'),
              style: FilledButton.styleFrom(backgroundColor: _kPrimary,
                  side: BorderSide(color: _kPrimaryLight.withValues(alpha: 0.4))),
            )),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(
              onPressed: _exportToMealPlanner,
              icon: const Icon(Icons.calendar_month_rounded, size: 16),
              label: const Text('Open Planner'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
            )),
          ]),
          const SizedBox(height: 16),

          // Generated plan
          ..._dayNames.map((day) {
            final meals = _generatedPlan![day]!;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kBorder),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                title: Text(day, style: const TextStyle(fontWeight: FontWeight.bold,
                    fontSize: 14, color: _kBody)),
                subtitle: Text('${meals.length} meals planned',
                    style: const TextStyle(fontSize: 11, color: _kMuted)),
                children: _mealTypes.map((type) => ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  leading: Icon(_mealIcon(type), size: 16, color: _mealColor(type)),
                  title: Text(type, style: TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w600, color: _mealColor(type))),
                  subtitle: Text(meals[type] ?? '', style: const TextStyle(fontSize: 13, color: _kBody)),
                )).toList(),
              ),
            );
          }),
        ],

        const SizedBox(height: 8),
        _ComingSoonCard(
          icon: Icons.history_rounded,
          title: 'Tracker History Integration',
          description:
              'Phase 2 will analyze your logged meals and nutrition gaps '
              'to generate a plan that specifically fills what you\'re missing.',
        ),
      ]),
    );
  }

  IconData _mealIcon(String type) {
    switch (type) {
      case 'Breakfast': return Icons.wb_sunny_rounded;
      case 'Lunch':     return Icons.lunch_dining_rounded;
      case 'Dinner':    return Icons.dinner_dining_rounded;
      default:          return Icons.apple_rounded;
    }
  }

  Color _mealColor(String type) {
    switch (type) {
      case 'Breakfast': return const Color(0xFFF57C00);
      case 'Lunch':     return const Color(0xFF388E3C);
      case 'Dinner':    return const Color(0xFF1565C0);
      default:          return const Color(0xFF6A1B9A);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────

class _ContextBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ContextBanner({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _kPrimaryLight.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _kPrimaryLight.withValues(alpha: 0.3)),
    ),
    child: Row(children: [
      Icon(icon, color: _kPrimaryLight, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(text,
          style: const TextStyle(fontSize: 12, color: _kBody, height: 1.4))),
    ]),
  );
}

class _PhaseLabel extends StatelessWidget {
  final String phase;
  final String description;
  const _PhaseLabel({required this.phase, required this.description});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: _kPrimary, borderRadius: BorderRadius.circular(6)),
        child: Text(phase, style: const TextStyle(color: _kPrimaryLight,
            fontSize: 10, fontWeight: FontWeight.bold))),
    const SizedBox(width: 8),
    Expanded(child: Text(description,
        style: const TextStyle(fontSize: 11, color: _kMuted))),
  ]);
}

class _ComingSoonCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  const _ComingSoonCard(
      {required this.icon, required this.title, required this.description});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [_kPrimary.withValues(alpha: 0.05), _kPrimaryLight.withValues(alpha: 0.05)]),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _kPrimary.withValues(alpha: 0.12)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: _kPrimary.withValues(alpha: 0.4), size: 20),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
              color: _kPrimary.withValues(alpha: 0.6))),
          const SizedBox(width: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: _kPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6)),
              child: Text('Phase 2', style: TextStyle(fontSize: 9,
                  fontWeight: FontWeight.bold, color: _kPrimary.withValues(alpha: 0.5)))),
        ]),
        const SizedBox(height: 4),
        Text(description, style: TextStyle(fontSize: 11,
            color: _kMuted, height: 1.4)),
      ])),
    ]),
  );
}

class _NutriBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _NutriBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3))),
    child: Text(label, style: TextStyle(fontSize: 10,
        fontWeight: FontWeight.bold, color: color)),
  );
}

class _TagChip extends StatelessWidget {
  final String label;
  final Color color;
  const _TagChip({required this.label, this.color = _kMuted});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2))),
    child: Text(label, style: TextStyle(fontSize: 10, color: color)),
  );
}