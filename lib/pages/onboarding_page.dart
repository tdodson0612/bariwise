// lib/pages/onboarding_page.dart
// Extended with full bariatric intake flow (Section 6 — User Intake Workspace).
// Slides 1–4: existing marketing intro (unchanged).
// Slides 5–10: intake — surgery type, surgery date, height, weight, restrictions +
// supplements, and a final Review Selections slide.
// All intake data saved to Supabase profiles table via ProfileService / workerQuery,
// except dietary restrictions + supplement baseline which are UI/UX-only phase and saved
// to SharedPreferences only.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/profile_service.dart';
import '../services/auth_service.dart';
import '../services/database_service_core.dart';
import '../config/app_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────────────────────────

class _MarketingSlide {
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final String title;
  final String subtitle;
  final String body;

  const _MarketingSlide({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.title,
    required this.subtitle,
    required this.body,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  static const String _onboardingKey = 'onboarding_completed';

  static Future<bool> hasCompletedOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingKey) ?? false;
  }

  static Future<void> markOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingKey, true);
  }

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isSaving = false;

  // ── Marketing slides (unchanged) ──────────────────────────────────────────
  final List<_MarketingSlide> _marketing = const [
    _MarketingSlide(
      icon: Icons.favorite_rounded,
      iconColor: Color(0xFFE65100),
      backgroundColor: Color(0xFFFFF3E0),
      title: 'Welcome to BariWise',
      subtitle: 'Your personal bariatric health companion',
      body:
          'BariWise helps you make smarter food choices and track your daily health — all designed around the specific needs of life after bariatric surgery.',
    ),
    _MarketingSlide(
      icon: Icons.qr_code_scanner_rounded,
      iconColor: Color(0xFF1565C0),
      backgroundColor: Color(0xFFE3F2FD),
      title: 'Scan Any Food Label',
      subtitle: 'Know what\'s really in your food',
      body:
          'Point your camera at any barcode to instantly see nutrition facts. BariWise scores each product for bariatric compatibility and suggests surgery-friendly recipes based on what you scan.',
    ),
    _MarketingSlide(
      icon: Icons.bar_chart_rounded,
      iconColor: Color(0xFF6A1B9A),
      backgroundColor: Color(0xFFF3E5F5),
      title: 'Track Your Day',
      subtitle: 'Log meals, supplements, water & exercise',
      body:
          'Log everything you eat and drink each day. See your daily nutrition totals and find out exactly what your body needs more of — or less of — for successful long-term bariatric health.',
    ),
    _MarketingSlide(
      icon: Icons.people_rounded,
      iconColor: Color(0xFF2E7D32),
      backgroundColor: Color(0xFFF1F8E9),
      title: 'A Community That Understands',
      subtitle: 'Share recipes and connect with others',
      body:
          'You\'re not alone. Share bariatric-friendly recipes, post your progress, and connect with others who are on the same journey toward a healthier life after surgery.',
    ),
  ];

  // Total slides = 4 marketing + 6 intake (5 data-entry + 1 review)
  int get _totalSlides => _marketing.length + 6;
  bool get _isIntakeSlide => _currentPage >= _marketing.length;
  int get _intakeIndex => _currentPage - _marketing.length;

  // ── Intake state ──────────────────────────────────────────────────────────

  // Slide 5 — Surgery type
  String? _surgeryType;
  final List<String> _surgeryTypes = [
    'Gastric Bypass (RYGB)',
    'Gastric Sleeve (VSG)',
    'Adjustable Gastric Band',
    'Duodenal Switch (BPD/DS)',
    'SADI-S / Loop DS',
    'Gastric Balloon',
    'Revision Surgery',
    'Pre-op / Not yet had surgery',
    'Other',
  ];

  // Slide 6 — Surgery date
  DateTime? _surgeryDate;

  // Slide 7 — Height
  String _heightUnit = 'imperial';
  final TextEditingController _feetCtrl = TextEditingController();
  final TextEditingController _inchesCtrl = TextEditingController();
  final TextEditingController _cmCtrl = TextEditingController();

  // Slide 8 — Weight
  String _weightUnit = 'lbs';
  final TextEditingController _startWeightCtrl = TextEditingController();
  final TextEditingController _currentWeightCtrl = TextEditingController();

  // Slide 9 — Dietary restrictions + supplement baseline
  final Set<String> _dietaryRestrictions = {};
  final Set<String> _supplements = {};

  final List<String> _restrictionOptions = [
    'Lactose intolerant',
    'Gluten-free',
    'Nut allergy',
    'Shellfish allergy',
    'Soy allergy',
    'Egg allergy',
    'Vegetarian',
    'Vegan',
    'Diabetic-friendly only',
    'Low-sodium',
    'Low-sugar',
    'None',
  ];

  final List<String> _supplementOptions = [
    'Multivitamin',
    'Calcium Citrate',
    'Vitamin D3',
    'Vitamin B12',
    'Iron',
    'Folate / Folic Acid',
    'Zinc',
    'Magnesium',
    'Vitamin B1 (Thiamine)',
    'Omega-3 Fish Oil',
    'Biotin',
    'Protein Powder',
    'Probiotics',
    'CoQ10',
    'None yet',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _feetCtrl.dispose();
    _inchesCtrl.dispose();
    _cmCtrl.dispose();
    _startWeightCtrl.dispose();
    _currentWeightCtrl.dispose();
    super.dispose();
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _nextPage() {
    if (_currentPage < _totalSlides - 1) {
      // Validate current intake slide before advancing
      if (_isIntakeSlide) {
        final error = _validateCurrentIntakeSlide();
        if (error != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error),
            backgroundColor: Colors.orange.shade700,
          ));
          return;
        }
      }
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  String? _validateCurrentIntakeSlide() {
    switch (_intakeIndex) {
      case 0: // Surgery type
        if (_surgeryType == null) return 'Please select your surgery type.';
        return null;
      case 1: // Surgery date — optional, skip allowed
        return null;
      case 2: // Height
        if (_heightUnit == 'imperial') {
          final feet = int.tryParse(_feetCtrl.text.trim());
          final inches = int.tryParse(_inchesCtrl.text.trim());
          if (feet == null || feet < 3 || feet > 8) {
            return 'Please enter a valid height (feet).';
          }
          if (inches == null || inches < 0 || inches > 11) {
            return 'Please enter valid inches (0–11).';
          }
        } else {
          final cm = double.tryParse(_cmCtrl.text.trim());
          if (cm == null || cm < 100 || cm > 250) {
            return 'Please enter a valid height in cm (100–250).';
          }
        }
        return null;
      case 3: // Weight — current weight required, starting optional
        final current = double.tryParse(_currentWeightCtrl.text.trim());
        if (current == null || current <= 0) {
          return 'Please enter your current weight.';
        }
        return null;
      case 4: // Restrictions + supplements — both optional
        return null;
      case 5: // Review — nothing to validate, just confirm
        return null;
      default:
        return null;
    }
  }

  Future<void> _finish() async {
    setState(() => _isSaving = true);
    try {
      await _saveIntakeData();
      await OnboardingPage.markOnboardingComplete();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (e) {
      AppConfig.debugPrint('❌ Error finishing onboarding: $e');
      if (mounted) {
        // Non-fatal — still let them into the app
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              'Some profile data could not be saved. You can update it in Settings.'),
          backgroundColor: Colors.orange.shade700,
          duration: const Duration(seconds: 4),
        ));
        await OnboardingPage.markOnboardingComplete();
        Navigator.pushReplacementNamed(context, '/home');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveIntakeData() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return;

    // 1. Surgery type
    if (_surgeryType != null) {
      await ProfileService.updateSurgeryType(userId, _surgeryType!);
    }

    // 2. Surgery date
    if (_surgeryDate != null) {
      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'profiles',
        filters: {'id': userId},
        data: {
          'surgery_date': _surgeryDate!.toIso8601String().split('T').first,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );
      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');
    }

    // 3. Height
    double? heightCm;
    if (_heightUnit == 'imperial') {
      final feet = int.tryParse(_feetCtrl.text.trim()) ?? 0;
      final inches = int.tryParse(_inchesCtrl.text.trim()) ?? 0;
      heightCm = (feet * 30.48) + (inches * 2.54);
    } else {
      heightCm = double.tryParse(_cmCtrl.text.trim());
    }
    if (heightCm != null && heightCm > 0) {
      await ProfileService.updateHeight(userId, heightCm);
      await ProfileService.updateHeightUnitPreference(userId, _heightUnit);
    }

    // 4. Weight — save starting weight and current weight to profiles table
    final startWeight = double.tryParse(_startWeightCtrl.text.trim());
    final currentWeight = double.tryParse(_currentWeightCtrl.text.trim());

    double? startKg = startWeight;
    double? currentKg = currentWeight;
    if (_weightUnit == 'lbs') {
      if (startKg != null) startKg = startKg * 0.453592;
      if (currentKg != null) currentKg = currentKg * 0.453592;
    }

    if (startKg != null || currentKg != null) {
      final weightData = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (startKg != null) weightData['starting_weight_kg'] = startKg;
      if (currentKg != null) weightData['current_weight_kg'] = currentKg;

      await DatabaseServiceCore.workerQuery(
        action: 'update',
        table: 'profiles',
        filters: {'id': userId},
        data: weightData,
      );
      await DatabaseServiceCore.clearCache('cache_user_profile_$userId');
      await DatabaseServiceCore.clearCache('cache_profile_timestamp_$userId');
    }

    // 5. Dietary restrictions + supplement baseline — SharedPreferences
    // (UI/UX-only phase: no DB table for these yet)
    final prefs = await SharedPreferences.getInstance();
    if (_dietaryRestrictions.isNotEmpty) {
      await prefs.setStringList(
          'intake_dietary_restrictions_$userId',
          _dietaryRestrictions.toList());
    }
    if (_supplements.isNotEmpty) {
      await prefs.setStringList(
          'intake_supplement_baseline_$userId',
          _supplements.toList());
    }

    AppConfig.debugPrint('✅ Intake data saved successfully');
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: skip (marketing) or back/step indicator (intake)
            _buildTopBar(),

            // Page content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _totalSlides,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  if (index < _marketing.length) {
                    return _buildMarketingSlide(_marketing[index]);
                  } else {
                    return _buildIntakeSlide(index - _marketing.length);
                  }
                },
              ),
            ),

            // Bottom: dots + action button
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    if (!_isIntakeSlide) {
      // Marketing slides: skip button
      return Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 12, right: 16),
          child: TextButton(
            onPressed: _finish,
            child: Text(
              'Skip',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 15,
              ),
            ),
          ),
        ),
      );
    } else {
      // Intake slides: back button + step indicator
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
              onPressed: _prevPage,
              color: Colors.orange.shade700,
            ),
            Expanded(
              child: Center(
                child: Text(
                  'Step ${_intakeIndex + 1} of 6',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ),
            // Placeholder to balance the row
            const SizedBox(width: 48),
          ],
        ),
      );
    }
  }

  Widget _buildBottomBar() {
    final isLast = _currentPage == _totalSlides - 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        children: [
          // Page dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_totalSlides, (index) {
              final isMarketing = index < _marketing.length;
              final isSelected = _currentPage == index;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: isSelected ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.orange.shade700
                      : isMarketing
                          ? Colors.grey.shade300
                          : Colors.orange.shade200,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),

          const SizedBox(height: 24),

          // Next / Get Started / Finish button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _nextPage,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      isLast
                          ? 'Get Started'
                          : _isIntakeSlide
                              ? 'Continue'
                              : 'Next',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),

          // Skip intake link (only on intake slides, not the last one)
          if (_isIntakeSlide && !isLast) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                // Skip to next intake slide without validating
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeInOut,
                );
              },
              child: Text(
                'Skip this step',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Marketing slide (existing design, unchanged) ───────────────────────────

  Widget _buildMarketingSlide(_MarketingSlide slide) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: slide.backgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(slide.icon, size: 60, color: slide.iconColor),
          ),
          const SizedBox(height: 40),
          Text(
            slide.title,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            slide.subtitle,
            style: TextStyle(
              fontSize: 16,
              color: Colors.orange.shade700,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text(
            slide.body,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey.shade700,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Intake slides ─────────────────────────────────────────────────────────

  Widget _buildIntakeSlide(int index) {
    switch (index) {
      case 0: return _buildSurgeryTypeSlide();
      case 1: return _buildSurgeryDateSlide();
      case 2: return _buildHeightSlide();
      case 3: return _buildWeightSlide();
      case 4: return _buildRestrictionsSlide();
      case 5: return _buildReviewSlide();
      default: return const SizedBox.shrink();
    }
  }

  // ── Intake Slide 1: Surgery Type ──────────────────────────────────────────

  Widget _buildSurgeryTypeSlide() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _intakeHeader(
            icon: Icons.local_hospital_rounded,
            iconColor: Colors.red.shade600,
            title: 'Your Surgery Type',
            subtitle: 'This helps us tailor nutrition advice to your specific procedure.',
          ),
          const SizedBox(height: 20),
          ...(_surgeryTypes.map((type) {
            final selected = _surgeryType == type;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                onTap: () => setState(() => _surgeryType = type),
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.orange.shade50
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? Colors.orange.shade600
                          : Colors.grey.shade300,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: selected
                            ? Colors.orange.shade600
                            : Colors.grey.shade400,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          type,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: selected
                                ? Colors.orange.shade900
                                : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          })),
        ],
      ),
    );
  }

  // ── Intake Slide 2: Surgery Date ──────────────────────────────────────────

  Widget _buildSurgeryDateSlide() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _intakeHeader(
            icon: Icons.calendar_today_rounded,
            iconColor: Colors.blue.shade700,
            title: 'Surgery Date',
            subtitle:
                'Knowing how long ago your surgery was helps us give you stage-appropriate advice.',
          ),
          const SizedBox(height: 32),

          // Date display card
          InkWell(
            onTap: _pickSurgeryDate,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _surgeryDate != null
                    ? Colors.blue.shade50
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _surgeryDate != null
                      ? Colors.blue.shade400
                      : Colors.grey.shade300,
                  width: _surgeryDate != null ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.calendar_month_rounded,
                    size: 48,
                    color: _surgeryDate != null
                        ? Colors.blue.shade600
                        : Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _surgeryDate != null
                        ? '${_surgeryDate!.month}/${_surgeryDate!.day}/${_surgeryDate!.year}'
                        : 'Tap to select date',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: _surgeryDate != null
                          ? Colors.blue.shade800
                          : Colors.grey.shade500,
                    ),
                  ),
                  if (_surgeryDate != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _surgeryDateDescription(_surgeryDate!),
                      style: TextStyle(
                          fontSize: 13, color: Colors.blue.shade600),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Future surgery option
          InkWell(
            onTap: () {
              setState(() {
                // Set a future date to indicate pre-op
                _surgeryDate = DateTime.now().add(const Duration(days: 30));
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'My surgery is upcoming / not scheduled yet',
                    style: TextStyle(
                        fontSize: 14, color: Colors.orange.shade900),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This step is optional. You can update it anytime in Settings.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickSurgeryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _surgeryDate ?? now,
      firstDate: DateTime(2000),
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: Colors.orange.shade700,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _surgeryDate = picked);
    }
  }

  String _surgeryDateDescription(DateTime date) {
    final now = DateTime.now();
    if (date.isAfter(now)) return 'Upcoming surgery';
    final diff = now.difference(date);
    if (diff.inDays < 30) return '${diff.inDays} days post-op';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} months post-op';
    return '${(diff.inDays / 365).floor()} year${(diff.inDays / 365).floor() == 1 ? '' : 's'} post-op';
  }

  // ── Intake Slide 3: Height ────────────────────────────────────────────────

  Widget _buildHeightSlide() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _intakeHeader(
            icon: Icons.height_rounded,
            iconColor: Colors.purple.shade700,
            title: 'Your Height',
            subtitle: 'Used to calculate your BMI and personalize your nutrition targets.',
          ),
          const SizedBox(height: 24),

          // Unit toggle
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _unitToggleButton('Imperial (ft/in)', 'imperial',
                    _heightUnit == 'imperial'),
                _unitToggleButton('Metric (cm)', 'metric',
                    _heightUnit == 'metric'),
              ],
            ),
          ),

          const SizedBox(height: 24),

          if (_heightUnit == 'imperial') ...[
            Row(
              children: [
                Expanded(
                  child: _intakeTextField(
                    controller: _feetCtrl,
                    label: 'Feet',
                    hint: '5',
                    suffix: 'ft',
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _intakeTextField(
                    controller: _inchesCtrl,
                    label: 'Inches',
                    hint: '7',
                    suffix: 'in',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Common range: 4\'10" – 6\'6"',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ] else ...[
            _intakeTextField(
              controller: _cmCtrl,
              label: 'Height',
              hint: '170',
              suffix: 'cm',
            ),
            const SizedBox(height: 8),
            Text(
              'Common range: 147 – 198 cm',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }

  Widget _unitToggleButton(String label, String value, bool selected) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          if (value == 'imperial') {
            _heightUnit = 'imperial';
          } else {
            _heightUnit = 'metric';
          }
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? Colors.orange.shade700 : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.grey.shade600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Intake Slide 4: Weight ─────────────────────────────────────────────────

  Widget _buildWeightSlide() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _intakeHeader(
            icon: Icons.monitor_weight_rounded,
            iconColor: Colors.teal.shade700,
            title: 'Your Weight',
            subtitle:
                'Tracking your starting and current weight helps measure your progress.',
          ),
          const SizedBox(height: 24),

          // Weight unit toggle
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _weightUnitButton('lbs', _weightUnit == 'lbs'),
                _weightUnitButton('kg', _weightUnit == 'kg'),
              ],
            ),
          ),

          const SizedBox(height: 24),

          _intakeTextField(
            controller: _startWeightCtrl,
            label: 'Starting Weight (before surgery)',
            hint: _weightUnit == 'lbs' ? '280' : '127',
            suffix: _weightUnit,
            optional: true,
          ),

          const SizedBox(height: 16),

          _intakeTextField(
            controller: _currentWeightCtrl,
            label: 'Current Weight *',
            hint: _weightUnit == 'lbs' ? '210' : '95',
            suffix: _weightUnit,
          ),

          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.teal.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline,
                    size: 16, color: Colors.teal.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your weight data is private by default. You control what appears on your profile.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.teal.shade800),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _weightUnitButton(String unit, bool selected) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _weightUnit = unit),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? Colors.orange.shade700 : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              unit,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.grey.shade600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Intake Slide 5: Dietary Restrictions + Supplements ────────────────────

  Widget _buildRestrictionsSlide() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _intakeHeader(
            icon: Icons.checklist_rounded,
            iconColor: Colors.green.shade700,
            title: 'Dietary & Supplements',
            subtitle:
                'Select any restrictions and the supplements you\'re currently taking.',
          ),
          const SizedBox(height: 20),

          // Dietary restrictions
          _sectionLabel('Dietary Restrictions', Icons.no_food_rounded,
              Colors.red.shade600),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _restrictionOptions.map((option) {
              final selected = _dietaryRestrictions.contains(option);
              return FilterChip(
                label: Text(option),
                selected: selected,
                selectedColor: Colors.red.shade100,
                checkmarkColor: Colors.red.shade700,
                labelStyle: TextStyle(
                  fontSize: 13,
                  color: selected ? Colors.red.shade900 : Colors.black87,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal,
                ),
                side: BorderSide(
                  color: selected
                      ? Colors.red.shade400
                      : Colors.grey.shade300,
                ),
                onSelected: (val) {
                  setState(() {
                    if (option == 'None') {
                      _dietaryRestrictions.clear();
                      if (val) _dietaryRestrictions.add('None');
                    } else {
                      _dietaryRestrictions.remove('None');
                      if (val) {
                        _dietaryRestrictions.add(option);
                      } else {
                        _dietaryRestrictions.remove(option);
                      }
                    }
                  });
                },
              );
            }).toList(),
          ),

          const SizedBox(height: 28),

          // Supplement baseline
          _sectionLabel('Current Supplements', Icons.medication_rounded,
              Colors.blue.shade700),
          const SizedBox(height: 4),
          Text(
            'Select everything you\'re already taking:',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _supplementOptions.map((option) {
              final selected = _supplements.contains(option);
              return FilterChip(
                label: Text(option),
                selected: selected,
                selectedColor: Colors.blue.shade100,
                checkmarkColor: Colors.blue.shade700,
                labelStyle: TextStyle(
                  fontSize: 13,
                  color: selected ? Colors.blue.shade900 : Colors.black87,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal,
                ),
                side: BorderSide(
                  color: selected
                      ? Colors.blue.shade400
                      : Colors.grey.shade300,
                ),
                onSelected: (val) {
                  setState(() {
                    if (option == 'None yet') {
                      _supplements.clear();
                      if (val) _supplements.add('None yet');
                    } else {
                      _supplements.remove('None yet');
                      if (val) {
                        _supplements.add(option);
                      } else {
                        _supplements.remove(option);
                      }
                    }
                  });
                },
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 16, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You can update these anytime in Settings. This helps us send smarter supplement reminders.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Intake Slide 6: Review Selections ─────────────────────────────────────

  Widget _buildReviewSlide() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _intakeHeader(
            icon: Icons.fact_check_rounded,
            iconColor: Colors.orange.shade700,
            title: 'Review Your Info',
            subtitle:
                'Double-check everything looks right before we get started.',
          ),
          const SizedBox(height: 20),
          _reviewRow(
            label: 'Surgery Type',
            value: _surgeryType ?? 'Not set',
            onEdit: () => _jumpToIntakeSlide(0),
          ),
          _reviewRow(
            label: 'Surgery Date',
            value: _surgeryDate != null
                ? '${_surgeryDate!.month}/${_surgeryDate!.day}/${_surgeryDate!.year}'
                : 'Not set',
            onEdit: () => _jumpToIntakeSlide(1),
          ),
          _reviewRow(
            label: 'Height',
            value: _heightSummary(),
            onEdit: () => _jumpToIntakeSlide(2),
          ),
          _reviewRow(
            label: 'Weight',
            value: _weightSummary(),
            onEdit: () => _jumpToIntakeSlide(3),
          ),
          _reviewRow(
            label: 'Dietary Restrictions',
            value: _dietaryRestrictions.isEmpty
                ? 'None selected'
                : _dietaryRestrictions.join(', '),
            onEdit: () => _jumpToIntakeSlide(4),
          ),
          _reviewRow(
            label: 'Supplements',
            value: _supplements.isEmpty
                ? 'None selected'
                : _supplements.join(', '),
            onEdit: () => _jumpToIntakeSlide(4),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tap any section to make changes. Everything here can also be updated later in Settings.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewRow({
    required String label,
    required String value,
    required VoidCallback onEdit,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600)),
                const SizedBox(height: 4),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14, color: Colors.black87)),
              ],
            ),
          ),
          TextButton(
            onPressed: onEdit,
            style: TextButton.styleFrom(
                padding: EdgeInsets.zero, minimumSize: const Size(40, 32)),
            child: Text('Edit',
                style: TextStyle(
                    color: Colors.orange.shade700,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  String _heightSummary() {
    if (_heightUnit == 'imperial') {
      final feet = _feetCtrl.text.trim();
      final inches = _inchesCtrl.text.trim();
      if (feet.isEmpty && inches.isEmpty) return 'Not set';
      return '$feet\' $inches"';
    } else {
      final cm = _cmCtrl.text.trim();
      return cm.isEmpty ? 'Not set' : '$cm cm';
    }
  }

  String _weightSummary() {
    final current = _currentWeightCtrl.text.trim();
    final start = _startWeightCtrl.text.trim();
    if (current.isEmpty && start.isEmpty) return 'Not set';
    final parts = <String>[];
    if (start.isNotEmpty) parts.add('Starting: $start $_weightUnit');
    if (current.isNotEmpty) parts.add('Current: $current $_weightUnit');
    return parts.join(' · ');
  }

  void _jumpToIntakeSlide(int index) {
    _pageController.animateToPage(
      _marketing.length + index,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  // ── Shared intake widgets ─────────────────────────────────────────────────

  Widget _intakeHeader({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _intakeTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required String suffix,
    bool optional = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label${optional ? ' (optional)' : ''}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}'))
          ],
          decoration: InputDecoration(
            hintText: hint,
            suffixText: suffix,
            isDense: true,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  BorderSide(color: Colors.orange.shade700, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String label, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}