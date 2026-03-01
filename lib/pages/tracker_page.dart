// lib/pages/tracker_page.dart
// Updated with supplement tracker, unit dropdowns, improved height handling with preferences,
// nutrition summary section, bariatric supplement chips, and debugging
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/tracker_service.dart';
import '../services/profile_service.dart';
import '../services/auth_service.dart';
import '../services/error_handling_service.dart';
import '../services/saved_ingredients_service.dart';
import '../models/tracker_entry.dart';
import '../models/nutrition_info.dart';
import '../barihealthbar.dart';
import '../config/app_config.dart';
import '../widgets/premium_gate.dart';
import '../controllers/premium_gate_controller.dart';
import '../utils/height_utils.dart';

class TrackerPage extends StatefulWidget {
  const TrackerPage({super.key});

  @override
  State<TrackerPage> createState() => _TrackerPageState();
}

class _TrackerPageState extends State<TrackerPage> {
  late final PremiumGateController _premiumController;
  bool _isPremium = false;

  DateTime _selectedDate = DateTime.now();
  TrackerEntry? _currentEntry;
  String? _diseaseType;
  double? _userHeight;
  String _heightUnitPreference = 'metric';
  bool _weightVisible = false;
  bool _weightLossVisible = false;
  int _currentStreak = 0;

  bool _isLoading = true;
  bool _isSaving = false;

  final TextEditingController _exerciseController = TextEditingController();
  final TextEditingController _waterController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();

  String _weightUnit = 'kg';
  String _exerciseUnit = 'minutes';
  String _waterUnit = 'cups';

  static const String _PREF_WEIGHT_UNIT = 'tracker_weight_unit_';
  static const String _PREF_EXERCISE_UNIT = 'tracker_exercise_unit_';
  static const String _PREF_WATER_UNIT = 'tracker_water_unit_';

  List<Map<String, dynamic>> _meals = [];
  List<Map<String, dynamic>> _supplements = [];

  @override
  void initState() {
    super.initState();
    _initializePremiumController();
    _checkDisclaimerAndLoad();
  }

  @override
  void dispose() {
    _premiumController.removeListener(_updatePremiumState);
    _exerciseController.dispose();
    _waterController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  void _initializePremiumController() {
    _premiumController = PremiumGateController();
    _premiumController.addListener(_updatePremiumState);
    _updatePremiumState();
  }

  void _updatePremiumState() {
    if (mounted) {
      setState(() {
        _isPremium = _premiumController.isPremium;
      });
    }
  }

  Future<void> _checkDisclaimerAndLoad() async {
    final accepted = await TrackerService.hasAcceptedDisclaimer();
    if (!accepted && mounted) {
      await _showDisclaimer();
    }
    if (mounted) {
      await _loadData();
    }
  }

  Future<void> _showDisclaimer() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.medical_information, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Important Disclaimer'),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This health tracker is for educational and informational purposes only.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                '• This is NOT a substitute for professional medical advice\n'
                '• Always consult your physician before making health decisions\n'
                '• Scores are estimates based on general nutrition guidelines\n'
                '• Your doctor\'s recommendations take priority\n'
                '• All data is stored locally on your device',
                style: TextStyle(height: 1.5),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber,
                        color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'If you experience medical symptoms, seek immediate professional care.',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Decline'),
          ),
          ElevatedButton(
            onPressed: () async {
              await TrackerService.acceptDisclaimer();
              if (mounted) {
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('I Understand'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadUnitPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = AuthService.currentUserId ?? '';

      setState(() {
        _weightUnit = prefs.getString('$_PREF_WEIGHT_UNIT$userId') ?? 'kg';
        _exerciseUnit =
            prefs.getString('$_PREF_EXERCISE_UNIT$userId') ?? 'minutes';
        _waterUnit = prefs.getString('$_PREF_WATER_UNIT$userId') ?? 'cups';
      });

      AppConfig.debugPrint('📋 Loaded unit preferences:');
      AppConfig.debugPrint('   Weight: $_weightUnit');
      AppConfig.debugPrint('   Exercise: $_exerciseUnit');
      AppConfig.debugPrint('   Water: $_waterUnit');
    } catch (e) {
      AppConfig.debugPrint('Error loading unit preferences: $e');
    }
  }

  Future<void> _saveUnitPreference(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = AuthService.currentUserId ?? '';
      await prefs.setString('$key$userId', value);
      AppConfig.debugPrint('✅ Saved unit preference: $key = $value');
    } catch (e) {
      AppConfig.debugPrint('Error saving unit preference: $e');
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      AppConfig.debugPrint('📂 Loading tracker data...');

      await _loadUnitPreferences();

      final userId = AuthService.currentUserId;
      if (userId == null) throw Exception('User not logged in');
      AppConfig.debugPrint('   User ID: $userId');

      AppConfig.debugPrint('🔍 Loading surgery type...');
      final diseaseType = await ProfileService.getSurgeryType(userId);
      AppConfig.debugPrint('   Surgery type: ${diseaseType ?? 'none'}');

      AppConfig.debugPrint('🔍 Loading height...');
      final height = await ProfileService.getHeight(userId);
      AppConfig.debugPrint(
          '   Height: ${height?.toStringAsFixed(0) ?? 'none'} cm');

      AppConfig.debugPrint('🔍 Loading height unit preference...');
      final heightUnitPref =
          await ProfileService.getHeightUnitPreference(userId);
      AppConfig.debugPrint('   Height unit preference: $heightUnitPref');

      AppConfig.debugPrint('🔍 Loading privacy settings...');
      final weightVisible = await ProfileService.getWeightVisibility(userId);
      final weightLossVisible =
          await ProfileService.getWeightLossVisibility(userId);
      AppConfig.debugPrint('   Weight visible: $weightVisible');
      AppConfig.debugPrint('   Weight loss visible: $weightLossVisible');

      AppConfig.debugPrint('🔍 Loading weight streak...');
      final streak = await TrackerService.getWeightStreak(userId);
      AppConfig.debugPrint('   Current streak: $streak days');

      AppConfig.debugPrint('🔍 Auto-filling missing weights...');
      await TrackerService.autoFillMissingWeights(userId);

      AppConfig.debugPrint(
          '🔍 Loading entry for ${_selectedDate.toString().split(' ')[0]}...');
      final dateString = _selectedDate.toString().split(' ')[0];
      final entry = await TrackerService.getEntryForDate(userId, dateString);

      if (entry != null) {
        AppConfig.debugPrint('✅ Entry found:');
        AppConfig.debugPrint('   Meals: ${entry.meals.length}');
        AppConfig.debugPrint('   Exercise: ${entry.exercise ?? 'none'}');
        AppConfig.debugPrint('   Water: ${entry.waterIntake ?? 'none'}');
        AppConfig.debugPrint(
            '   Weight: ${entry.weight?.toStringAsFixed(1) ?? 'none'} kg');
        AppConfig.debugPrint('   Score: ${entry.dailyScore}');
      } else {
        AppConfig.debugPrint('ℹ️ No entry found for this date');
      }

      if (mounted) {
        setState(() {
          _diseaseType = diseaseType ?? 'Other (default scoring)';
          _userHeight = height;
          _heightUnitPreference = heightUnitPref;
          _weightVisible = weightVisible;
          _weightLossVisible = weightLossVisible;
          _currentStreak = streak;
          _currentEntry = entry;
          _meals = entry?.meals ?? [];
          _supplements = entry?.supplements ?? [];
          _exerciseController.text = entry?.exercise ?? '';
          _waterController.text = entry?.waterIntake ?? '';
          _weightController.text = entry?.weight?.toStringAsFixed(1) ?? '';
          _isLoading = false;
        });
        AppConfig.debugPrint('✅ Data loaded successfully');
      }
    } catch (e, stackTrace) {
      AppConfig.debugPrint('❌ Error loading tracker data: $e');
      AppConfig.debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        setState(() => _isLoading = false);
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Failed to load tracker data: ${e.toString()}',
          onRetry: _loadData,
        );
      }
    }
  }

  Future<void> _saveEntry() async {
    final userId = AuthService.currentUserId;
    if (userId == null) {
      AppConfig.debugPrint('❌ Cannot save: No user ID');
      ErrorHandlingService.showSimpleError(
          context, 'You must be logged in to save entries');
      return;
    }

    setState(() => _isSaving = true);

    try {
      AppConfig.debugPrint('💾 Starting save operation...');
      AppConfig.debugPrint('   User ID: $userId');
      AppConfig.debugPrint(
          '   Date: ${_selectedDate.toString().split(' ')[0]}');

      String? exerciseText;
      if (_exerciseController.text.trim().isNotEmpty) {
        final value = double.tryParse(_exerciseController.text.trim());
        if (value != null) {
          if (_exerciseUnit == 'hours') {
            exerciseText = '${(value * 60).round()} minutes';
          } else {
            exerciseText = '${value.round()} minutes';
          }
          AppConfig.debugPrint('   Exercise: $exerciseText');
        }
      }

      String? waterText;
      if (_waterController.text.trim().isNotEmpty) {
        final value = double.tryParse(_waterController.text.trim());
        if (value != null) {
          double cups = value;
          switch (_waterUnit) {
            case 'liters':
              cups = value * 4.227;
              break;
            case 'oz':
              cups = value / 8;
              break;
            case 'pints':
              cups = value * 2;
              break;
            case 'quarts':
              cups = value * 4;
              break;
            case 'gallons':
              cups = value * 16;
              break;
          }
          waterText = '${cups.toStringAsFixed(1)} cups';
          AppConfig.debugPrint('   Water: $waterText');
        }
      }

      final score = TrackerService.calculateDailyScore(
        meals: _meals,
        surgeryType: _diseaseType,
        exercise: exerciseText,
        waterIntake: waterText,
      );
      AppConfig.debugPrint('   Calculated score: $score');

      double? weight;
      if (_weightController.text.trim().isNotEmpty) {
        final value = double.tryParse(_weightController.text.trim());
        if (value != null) {
          weight = _weightUnit == 'lbs' ? value * 0.453592 : value;
          AppConfig.debugPrint(
              '   Weight: ${weight.toStringAsFixed(1)} kg (from $_weightUnit)');
        }
      } else {
        AppConfig.debugPrint('   Weight: none entered');
      }

      final entry = TrackerEntry(
        date: _selectedDate.toString().split(' ')[0],
        meals: _meals,
        supplements: _supplements,
        exercise: exerciseText,
        waterIntake: waterText,
        weight: weight,
        dailyScore: score,
      );

      AppConfig.debugPrint('📝 Saving entry...');
      await TrackerService.saveEntry(userId, entry);

      AppConfig.debugPrint('🔄 Auto-filling missing weights...');
      await TrackerService.autoFillMissingWeights(userId);

      AppConfig.debugPrint('🔍 Verifying save...');
      final savedEntry = await TrackerService.getEntryForDate(
          userId, _selectedDate.toString().split(' ')[0]);

      if (savedEntry == null) {
        throw Exception('Save verification failed - entry not found after save');
      }
      if (weight != null && savedEntry.weight == null) {
        throw Exception('Weight was not saved correctly');
      }
      if (_meals.isNotEmpty && savedEntry.meals.isEmpty) {
        throw Exception('Meals were not saved correctly');
      }

      final newStreak = await TrackerService.getWeightStreak(userId);
      final hasReachedDay7 = await TrackerService.hasReachedDay7Streak(userId);
      final hasShownPopup = await TrackerService.hasShownDay7Popup(userId);

      if (hasReachedDay7 && !hasShownPopup) {
        await TrackerService.markDay7PopupShown(userId);
        AppConfig.debugPrint(
            '🎉 User reached day 7! Popup will show on home screen.');
      }

      if (mounted) {
        setState(() {
          _currentEntry = savedEntry;
          _currentStreak = newStreak;
          _isSaving = false;
        });
        AppConfig.debugPrint('✅ Save completed successfully!');
        AppConfig.debugPrint('   New streak: $newStreak days');
        ErrorHandlingService.showSuccess(context, 'Entry saved successfully!');
      }
    } catch (e, stackTrace) {
      AppConfig.debugPrint('❌ Error saving entry: $e');
      AppConfig.debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        setState(() => _isSaving = false);
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Failed to save entry: ${e.toString()}',
          onRetry: _saveEntry,
        );
      }
    }
  }

  void _changeDate(int days) {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: days)));
    _loadData();
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return 'Today';
    } else if (date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day) {
      return 'Yesterday';
    }
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  // ── Supplements ───────────────────────────────────────────────

  Future<void> _addSupplement() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _SupplementDialog(),
    );
    if (result != null && mounted) {
      setState(() => _supplements.add(result));
    }
  }

  void _removeSupplement(int index) {
    setState(() => _supplements.removeAt(index));
  }

  // ── Meals ─────────────────────────────────────────────────────

  Future<void> _addMeal() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _MealDialog(),
    );
    if (result != null && mounted) {
      setState(() => _meals.add(result));
    }
  }

  void _removeMeal(int index) {
    setState(() => _meals.removeAt(index));
  }

  Future<void> _toggleWeightVisibility() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return;
    try {
      final newValue = !_weightVisible;
      await ProfileService.updateWeightVisibility(userId, newValue);
      if (mounted) {
        setState(() => _weightVisible = newValue);
        ErrorHandlingService.showSuccess(
          context,
          newValue
              ? 'Weight stats will appear on your profile'
              : 'Weight stats hidden from profile',
        );
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Failed to update privacy setting',
        );
      }
    }
  }

  Future<void> _toggleWeightLossVisibility() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return;
    try {
      final newValue = !_weightLossVisible;
      await ProfileService.updateWeightLossVisibility(userId, newValue);
      if (mounted) {
        setState(() => _weightLossVisible = newValue);
        ErrorHandlingService.showSuccess(
          context,
          newValue
              ? 'Weight loss stats will appear on your profile'
              : 'Weight loss stats hidden from profile',
        );
      }
    } catch (e) {
      if (mounted) {
        await ErrorHandlingService.handleError(
          context: context,
          error: e,
          category: ErrorHandlingService.databaseError,
          customMessage: 'Failed to update privacy setting',
        );
      }
    }
  }

  Future<void> _showHeightSetupDialog() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return;

    final existingHeight = await ProfileService.getHeight(userId);
    final existingPreference =
        await ProfileService.getHeightUnitPreference(userId);

    final feetController = TextEditingController();
    final inchesController = TextEditingController();
    final cmController = TextEditingController();
    String heightSystem = existingPreference;

    if (existingHeight != null) {
      if (existingPreference == 'imperial') {
        final converted = HeightUtils.cmToFeetInches(existingHeight);
        feetController.text = converted['feet'].toString();
        inchesController.text = converted['inches'].toString();
      } else {
        cmController.text = existingHeight.toStringAsFixed(0);
      }
    }

    return showDialog(
      context: context,
      barrierDismissible: existingHeight != null,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.height, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(existingHeight != null
                    ? 'Update Your Height'
                    : 'Set Your Height'),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  existingHeight != null
                      ? 'Update your height below.'
                      : 'Please enter your height. This helps with BMI calculations.',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButton<String>(
                    value: heightSystem,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: [
                      DropdownMenuItem(
                        value: 'metric',
                        child: Row(children: [
                          Icon(Icons.straighten,
                              size: 18, color: Colors.blue),
                          const SizedBox(width: 8),
                          const Text('Metric (cm)'),
                        ]),
                      ),
                      DropdownMenuItem(
                        value: 'imperial',
                        child: Row(children: [
                          Icon(Icons.straighten,
                              size: 18, color: Colors.orange),
                          const SizedBox(width: 8),
                          const Text('Imperial (ft/in)'),
                        ]),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() {
                          heightSystem = value;
                          if (value == 'imperial' &&
                              cmController.text.isNotEmpty) {
                            final cm = double.tryParse(cmController.text);
                            if (cm != null) {
                              final c = HeightUtils.cmToFeetInches(cm);
                              feetController.text =
                                  c['feet'].toString();
                              inchesController.text =
                                  c['inches'].toString();
                            }
                          } else if (value == 'metric' &&
                              feetController.text.isNotEmpty) {
                            final feet =
                                int.tryParse(feetController.text) ?? 0;
                            final inches =
                                int.tryParse(inchesController.text) ?? 0;
                            cmController.text =
                                HeightUtils.feetInchesToCm(feet, inches)
                                    .toStringAsFixed(0);
                          }
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
                if (heightSystem == 'imperial') ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: feetController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Feet',
                            hintText: 'e.g., 5',
                            border: OutlineInputBorder(),
                            suffixText: 'ft',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: inchesController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Inches',
                            hintText: 'e.g., 8',
                            border: OutlineInputBorder(),
                            suffixText: 'in',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    HeightUtils.getCommonHeightRange('imperial'),
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ] else ...[
                  TextField(
                    controller: cmController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,1}'))
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Height',
                      hintText: 'e.g., 170',
                      border: OutlineInputBorder(),
                      suffixText: 'cm',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    HeightUtils.getCommonHeightRange('metric'),
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (existingHeight != null)
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                double? heightInCm;
                if (heightSystem == 'imperial') {
                  final feet = int.tryParse(feetController.text.trim());
                  final inches =
                      int.tryParse(inchesController.text.trim());
                  if (feet == null || feet < 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Please enter valid feet')));
                    return;
                  }
                  if (inches == null || inches < 0 || inches >= 12) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Please enter valid inches (0-11)')));
                    return;
                  }
                  heightInCm = HeightUtils.feetInchesToCm(feet, inches);
                } else {
                  heightInCm =
                      double.tryParse(cmController.text.trim());
                  if (heightInCm == null || heightInCm <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('Please enter a valid height in cm')));
                    return;
                  }
                }
                if (!HeightUtils.isValidHeight(heightInCm)) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text(
                        'Height must be between 50cm and 250cm'),
                    backgroundColor: Colors.orange,
                  ));
                  return;
                }
                try {
                  final uid = AuthService.currentUserId;
                  if (uid != null) {
                    AppConfig.debugPrint(
                        '📏 Saving height: $heightInCm cm');
                    AppConfig.debugPrint(
                        '📏 Saving preference: $heightSystem');

                    await ProfileService.updateHeight(uid, heightInCm);
                    await ProfileService.updateHeightUnitPreference(
                        uid, heightSystem);

                    // Verify it was saved
                    final savedHeight =
                        await ProfileService.getHeight(uid);
                    final savedPreference =
                        await ProfileService.getHeightUnitPreference(uid);

                    if (savedHeight == null ||
                        (savedHeight - heightInCm).abs() > 0.1) {
                      throw Exception(
                          'Height verification failed after save');
                    }
                    if (savedPreference != heightSystem) {
                      throw Exception(
                          'Preference verification failed after save');
                    }

                    if (mounted) {
                      setState(() {
                        _userHeight = heightInCm;
                        _heightUnitPreference = heightSystem;
                      });
                      AppConfig.debugPrint(
                          '✅ Height and preference saved: $heightInCm cm ($heightSystem)');
                      ErrorHandlingService.showSuccess(
                          context,
                          'Height saved: ${HeightUtils.formatHeight(heightInCm!, heightSystem)}');
                    }
                  }
                  Navigator.pop(context);
                } catch (e) {
                  AppConfig.debugPrint('❌ Error saving height: $e');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          'Failed to save height: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ));
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Tracker'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          if (_userHeight != null)
            IconButton(
              icon: const Icon(Icons.height),
              tooltip:
                  'Height: ${HeightUtils.formatHeight(_userHeight!, _heightUnitPreference)}',
              onPressed: _showHeightSetupDialog,
            ),
          if (AppConfig.enableDebugPrints)
            IconButton(
              icon: const Icon(Icons.bug_report),
              tooltip: 'Debug Storage',
              onPressed: () async {
                final userId = AuthService.currentUserId;
                if (userId != null) {
                  await TrackerService.debugStorageState(userId);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content:
                          Text('Check debug logs for storage state')));
                }
              },
            ),
        ],
      ),
      body: PremiumGate(
        feature: PremiumFeature.healthTracker,
        featureName: 'Health Tracker',
        featureDescription:
            'Track your meals, exercise, water intake, and weight with disease-aware scoring.',
        child: _buildTrackerContent(),
      ),
    );
  }

  Widget _buildTrackerContent() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_userHeight == null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _showHeightSetupDialog());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDateSelector(),
          const SizedBox(height: 20),
          _buildWeightSection(),
          const SizedBox(height: 20),
          _buildMealsSection(),
          const SizedBox(height: 20),
          if (_meals.isNotEmpty) ...[
            _buildNutritionSummarySection(),
            const SizedBox(height: 20),
          ],
          _buildSupplementsSection(),
          const SizedBox(height: 20),
          _buildExerciseSection(),
          const SizedBox(height: 20),
          _buildWaterSection(),
          const SizedBox(height: 20),
          _buildScoreSection(),
          const SizedBox(height: 20),
          _buildSaveButton(),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    final canGoForward = _selectedDate
        .isBefore(DateTime.now().subtract(const Duration(days: -1)));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
                onPressed: () => _changeDate(-1),
                icon: const Icon(Icons.chevron_left)),
            Text(_formatDate(_selectedDate),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            IconButton(
                onPressed: canGoForward ? () => _changeDate(1) : null,
                icon: const Icon(Icons.chevron_right)),
          ],
        ),
      ),
    );
  }

  Widget _buildWeightSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.monitor_weight, color: Colors.blue, size: 24),
                const SizedBox(width: 8),
                const Text('Weight',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_userHeight != null)
                  InkWell(
                    onTap: _showHeightSetupDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.height,
                              size: 14, color: Colors.blue.shade700),
                          const SizedBox(width: 4),
                          Text(
                            HeightUtils.formatHeight(
                                _userHeight!, _heightUnitPreference),
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _weightController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,1}'))
                    ],
                    decoration: InputDecoration(
                      labelText: 'Weight',
                      hintText: _weightUnit == 'kg'
                          ? 'e.g., 70.5'
                          : 'e.g., 155.5',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.monitor_weight),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: DropdownButtonFormField<String>(
                    value: _weightUnit,
                    decoration:
                        const InputDecoration(border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'kg', child: Text('kg')),
                      DropdownMenuItem(value: 'lbs', child: Text('lbs')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _weightUnit = value);
                        _saveUnitPreference(_PREF_WEIGHT_UNIT, value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_currentStreak > 0) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_fire_department,
                        color: Colors.orange.shade700, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '$_currentStreak day${_currentStreak == 1 ? '' : 's'} streak!',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Icon(
                    _weightVisible ? Icons.visibility : Icons.visibility_off,
                    size: 20,
                    color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Weight average visible on profile',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade700)),
                ),
                Switch(
                    value: _weightVisible,
                    onChanged: (_) => _toggleWeightVisibility(),
                    activeThumbColor: Colors.orange),
              ],
            ),
            if (_currentStreak >= 14) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                      _weightLossVisible
                          ? Icons.visibility
                          : Icons.visibility_off,
                      size: 20,
                      color: Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Weight loss visible on profile',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade700)),
                  ),
                  Switch(
                      value: _weightLossVisible,
                      onChanged: (_) => _toggleWeightLossVisibility(),
                      activeThumbColor: Colors.orange),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMealsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.restaurant,
                        color: Colors.orange, size: 24),
                    const SizedBox(width: 8),
                    Text('Meals (${_meals.length})',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(
                    onPressed: _addMeal,
                    icon: const Icon(Icons.add_circle, color: Colors.orange),
                    tooltip: 'Add Meal'),
              ],
            ),
            if (_meals.isEmpty) ...[
              const SizedBox(height: 12),
              Center(
                  child: Text('No meals added yet. Tap + to add a meal.',
                      style: TextStyle(color: Colors.grey.shade600))),
            ] else ...[
              const SizedBox(height: 12),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _meals.length,
                itemBuilder: (context, index) {
                  final meal = _meals[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(meal['name'] ?? 'Meal ${index + 1}'),
                      subtitle: Text(
                        '${meal['calories']?.toStringAsFixed(0) ?? '0'} cal • '
                        '${meal['fat']?.toStringAsFixed(1) ?? '0'}g fat • '
                        '${meal['sodium']?.toStringAsFixed(0) ?? '0'}mg sodium',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _removeMeal(index)),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Nutrition Summary ─────────────────────────────────────────

  Widget _buildNutritionSummarySection() {
    final totals = TrackerService.calculateNutritionTotals(_meals);
    final status = TrackerService.getNutritionStatus(_meals);
    final targets = TrackerService.dailyTargets;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bar_chart, color: Colors.teal, size: 24),
                const SizedBox(width: 8),
                const Text('Daily Nutrition Summary',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Based on bariatric post-surgery daily targets',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            _buildNutrientRow(
              label: 'Calories',
              current: totals['calories'] ?? 0,
              target: targets['calories']!,
              unit: 'kcal',
              status: status['calories'] ?? 'low',
              isUpperLimit: false,
            ),
            _buildNutrientRow(
              label: 'Protein',
              current: totals['protein'] ?? 0,
              target: targets['protein']!,
              unit: 'g',
              status: status['protein'] ?? 'low',
              isUpperLimit: false,
            ),
            _buildNutrientRow(
              label: 'Fiber',
              current: totals['fiber'] ?? 0,
              target: targets['fiber']!,
              unit: 'g',
              status: status['fiber'] ?? 'low',
              isUpperLimit: false,
            ),
            const Divider(height: 20),
            Text(
              'Keep these under the daily limit:',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 8),
            _buildNutrientRow(
              label: 'Fat',
              current: totals['fat'] ?? 0,
              target: targets['fat']!,
              unit: 'g',
              status: status['fat'] ?? 'good',
              isUpperLimit: true,
            ),
            _buildNutrientRow(
              label: 'Saturated Fat',
              current: totals['saturatedFat'] ?? 0,
              target: targets['saturatedFat']!,
              unit: 'g',
              status: status['saturatedFat'] ?? 'good',
              isUpperLimit: true,
            ),
            _buildNutrientRow(
              label: 'Sodium',
              current: totals['sodium'] ?? 0,
              target: targets['sodium']!,
              unit: 'mg',
              status: status['sodium'] ?? 'good',
              isUpperLimit: true,
            ),
            _buildNutrientRow(
              label: 'Sugar',
              current: totals['sugar'] ?? 0,
              target: targets['sugar']!,
              unit: 'g',
              status: status['sugar'] ?? 'good',
              isUpperLimit: true,
            ),
            const SizedBox(height: 12),
            _buildNutritionLegend(),
          ],
        ),
      ),
    );
  }

  Widget _buildNutrientRow({
    required String label,
    required double current,
    required double target,
    required String unit,
    required String status,
    required bool isUpperLimit,
  }) {
    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case 'over':
        statusColor = Colors.red.shade600;
        statusIcon = Icons.arrow_upward;
        break;
      case 'low':
        statusColor = Colors.orange.shade700;
        statusIcon = Icons.arrow_downward;
        break;
      case 'good':
      default:
        statusColor = Colors.green.shade600;
        statusIcon = Icons.check_circle_outline;
        break;
    }

    final progress = (current / target).clamp(0.0, 1.5);
    final displayProgress = progress.clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              Text(
                '${current.toStringAsFixed(current >= 10 ? 0 : 1)}$unit',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: statusColor),
              ),
              const SizedBox(width: 4),
              Text(
                '/ ${target.toStringAsFixed(0)}$unit',
                style:
                    TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              const SizedBox(width: 6),
              Icon(statusIcon, size: 14, color: statusColor),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: displayProgress,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                progress > 1.0 ? Colors.red.shade400 : statusColor,
              ),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNutritionLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _legendItem(Colors.green.shade600, 'On track'),
        _legendItem(Colors.orange.shade700, 'Need more'),
        _legendItem(Colors.red.shade600, 'Over limit'),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
      ],
    );
  }

  // ── Supplement Section ────────────────────────────────────────

  Widget _buildSupplementsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.medication, color: Colors.teal, size: 24),
                    const SizedBox(width: 8),
                    Text('Supplements (${_supplements.length})',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(
                  onPressed: _addSupplement,
                  icon: const Icon(Icons.add_circle, color: Colors.teal),
                  tooltip: 'Add Supplement',
                ),
              ],
            ),
            if (_supplements.isEmpty) ...[
              const SizedBox(height: 12),
              Center(
                  child: Text(
                'No supplements logged yet. Tap + to add one.',
                style: TextStyle(color: Colors.grey.shade600),
              )),
            ] else ...[
              const SizedBox(height: 12),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _supplements.length,
                itemBuilder: (context, index) {
                  final supplement = _supplements[index];
                  final name = supplement['name'] as String? ??
                      'Supplement ${index + 1}';
                  final amount = supplement['amount'] as String? ?? '';
                  final notes = supplement['notes'] as String? ?? '';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: Colors.teal.shade200),
                        ),
                        child: Icon(Icons.medication_liquid,
                            color: Colors.teal.shade700, size: 20),
                      ),
                      title: Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (amount.isNotEmpty)
                            Text('Amount: $amount',
                                style: const TextStyle(fontSize: 12)),
                          if (notes.isNotEmpty)
                            Text(notes,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600)),
                        ],
                      ),
                      isThreeLine: notes.isNotEmpty,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeSupplement(index),
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExerciseSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.fitness_center, color: Colors.purple, size: 24),
                SizedBox(width: 8),
                Text('Exercise',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _exerciseController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,1}'))
                    ],
                    decoration: InputDecoration(
                      labelText: 'Duration',
                      hintText: _exerciseUnit == 'minutes'
                          ? 'e.g., 30'
                          : 'e.g., 1',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.directions_run),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: DropdownButtonFormField<String>(
                    value: _exerciseUnit,
                    decoration:
                        const InputDecoration(border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(
                          value: 'minutes', child: Text('min')),
                      DropdownMenuItem(
                          value: 'hours', child: Text('hrs')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _exerciseUnit = value);
                        _saveUnitPreference(_PREF_EXERCISE_UNIT, value);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaterSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.water_drop, color: Colors.cyan, size: 24),
                SizedBox(width: 8),
                Text('Water Intake',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _waterController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,1}'))
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      hintText: 'e.g., 8',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.local_drink),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  child: DropdownButtonFormField<String>(
                    value: _waterUnit,
                    decoration:
                        const InputDecoration(border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'cups', child: Text('cups')),
                      DropdownMenuItem(value: 'oz', child: Text('oz')),
                      DropdownMenuItem(value: 'liters', child: Text('L')),
                      DropdownMenuItem(
                          value: 'pints', child: Text('pints')),
                      DropdownMenuItem(
                          value: 'quarts', child: Text('qts')),
                      DropdownMenuItem(
                          value: 'gallons', child: Text('gal')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _waterUnit = value);
                        _saveUnitPreference(_PREF_WATER_UNIT, value);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreSection() {
    final score = _currentEntry?.dailyScore ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.favorite, color: Colors.red, size: 24),
                SizedBox(width: 8),
                Text("Today's Health Score",
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            if (_meals.isEmpty) ...[
              Text('Add meals to see your health score',
                  style: TextStyle(color: Colors.grey.shade600)),
            ] else ...[
              BariHealthBar(healthScore: score),
              const SizedBox(height: 8),
              Text(
                'Based on ${_meals.length} meal${_meals.length == 1 ? '' : 's'}'
                '${_exerciseController.text.isNotEmpty ? ', exercise' : ''}'
                '${_waterController.text.isNotEmpty ? ', and water intake' : ''}',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _saveEntry,
        icon: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white)))
            : const Icon(Icons.save),
        label: Text(
          _isSaving ? 'Saving...' : 'Save Entry',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Supplement Dialog
// ════════════════════════════════════════════════════════════════

class _SupplementDialog extends StatefulWidget {
  const _SupplementDialog();

  @override
  State<_SupplementDialog> createState() => _SupplementDialogState();
}

class _SupplementDialogState extends State<_SupplementDialog> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  String _selectedUnit = 'mg';
  static const List<String> _units = [
    'mg', 'mcg', 'g', 'IU', 'ml', 'capsule(s)', 'tablet(s)', 'tsp', 'tbsp',
  ];

  // Common bariatric post-surgery supplements for quick fill
  final List<String> _commonSupplements = [
    'Multivitamin',
    'Calcium Citrate',
    'Vitamin D3',
    'Vitamin B12',
    'Iron',
    'Folate',
    'Zinc',
    'Vitamin B1 (Thiamine)',
    'Magnesium',
    'Omega-3 Fish Oil',
    'Biotin',
    'Vitamin C',
    'Copper',
    'Vitamin A',
    'Vitamin K',
    'Probiotics',
    'Protein Powder',
    'Vitamin E',
    'Selenium',
    'CoQ10',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _save() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a supplement name')));
      return;
    }

    final rawAmount = _amountController.text.trim();
    final amountString =
        rawAmount.isNotEmpty ? '$rawAmount $_selectedUnit' : '';

    Navigator.pop(context, {
      'name': _nameController.text.trim(),
      'amount': amountString,
      'notes': _notesController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.medication, color: Colors.teal),
          SizedBox(width: 8),
          Text('Add Supplement'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick-fill chips
            Text(
              'Common bariatric supplements:',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _commonSupplements.take(10).map((name) {
                final isSelected = _nameController.text == name;
                return GestureDetector(
                  onTap: () {
                    setState(() => _nameController.text = name);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.teal.shade100
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? Colors.teal
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Text(name,
                        style: const TextStyle(fontSize: 12)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Name field
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Supplement Name *',
                hintText: 'e.g., Calcium Citrate, B12',
                prefixIcon: Icon(Icons.medication_liquid),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            // Amount + unit row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}'))
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      hintText: 'e.g., 500',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    value: _selectedUnit,
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      border: OutlineInputBorder(),
                    ),
                    items: _units
                        .map((u) =>
                            DropdownMenuItem(value: u, child: Text(u)))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedUnit = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Notes field
            TextField(
              controller: _notesController,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'e.g., Take with food',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal, foregroundColor: Colors.white),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Meal Dialog
// ════════════════════════════════════════════════════════════════

class _MealDialog extends StatefulWidget {
  @override
  State<_MealDialog> createState() => _MealDialogState();
}

class _MealDialogState extends State<_MealDialog> {
  final _nameController = TextEditingController();
  final _caloriesController = TextEditingController();
  final _fatController = TextEditingController();
  final _sodiumController = TextEditingController();
  final _sugarController = TextEditingController();
  final _proteinController = TextEditingController();
  final _fiberController = TextEditingController();
  final _saturatedFatController = TextEditingController();

  List<NutritionInfo> _savedIngredients = [];
  bool _isLoadingIngredients = true;

  @override
  void initState() {
    super.initState();
    _loadSavedIngredients();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _caloriesController.dispose();
    _fatController.dispose();
    _sodiumController.dispose();
    _sugarController.dispose();
    _proteinController.dispose();
    _fiberController.dispose();
    _saturatedFatController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedIngredients() async {
    try {
      final ingredients =
          await SavedIngredientsService.loadSavedIngredients();
      if (mounted) {
        setState(() {
          _savedIngredients = ingredients;
          _isLoadingIngredients = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingIngredients = false);
      AppConfig.debugPrint('Error loading saved ingredients: $e');
    }
  }

  void _autofillFromIngredient(NutritionInfo ingredient) {
    setState(() {
      _nameController.text = ingredient.productName;
      _caloriesController.text = ingredient.calories.toStringAsFixed(0);
      _fatController.text = ingredient.fat.toStringAsFixed(1);
      _sodiumController.text = ingredient.sodium.toStringAsFixed(0);
      _sugarController.text = ingredient.sugar.toStringAsFixed(1);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Auto-filled from "${ingredient.productName}"'),
      backgroundColor: Colors.orange,
      duration: const Duration(seconds: 2),
    ));
  }

  void _saveMeal() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a meal name')));
      return;
    }
    Navigator.pop(context, {
      'name': _nameController.text.trim(),
      'calories': double.tryParse(_caloriesController.text) ?? 0.0,
      'fat': double.tryParse(_fatController.text) ?? 0.0,
      'sodium': double.tryParse(_sodiumController.text) ?? 0.0,
      'sugar': double.tryParse(_sugarController.text) ?? 0.0,
      'protein': double.tryParse(_proteinController.text),
      'fiber': double.tryParse(_fiberController.text),
      'saturatedFat': double.tryParse(_saturatedFatController.text),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Meal'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_savedIngredients.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.bookmark,
                            color: Colors.blue.shade700, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Quick Fill from Saved Ingredients:',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _savedIngredients.length,
                        itemBuilder: (context, index) {
                          final ingredient = _savedIngredients[index];
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: InkWell(
                              onTap: () =>
                                  _autofillFromIngredient(ingredient),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 140,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: Colors.blue.shade300),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Text(ingredient.productName,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 4),
                                    Text(
                                        '${ingredient.calories.toStringAsFixed(0)} cal',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade600)),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Icon(Icons.touch_app,
                                            size: 12,
                                            color: Colors.blue.shade700),
                                        const SizedBox(width: 4),
                                        Text('Tap to fill',
                                            style: TextStyle(
                                                fontSize: 9,
                                                color: Colors.blue.shade700,
                                                fontWeight:
                                                    FontWeight.w600)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade400)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('OR ENTER MANUALLY',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600)),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade400)),
                ],
              ),
              const SizedBox(height: 12),
            ] else if (_isLoadingIngredients) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 12),
                      Text('Loading saved ingredients...',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                  labelText: 'Meal Name *',
                  hintText: 'e.g., Grilled Chicken Salad'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            _numField(_caloriesController, 'Calories *', 'cal'),
            const SizedBox(height: 12),
            _numField(_fatController, 'Fat *', 'g'),
            const SizedBox(height: 12),
            _numField(_sodiumController, 'Sodium *', 'mg'),
            const SizedBox(height: 12),
            _numField(_sugarController, 'Sugar *', 'g'),
            const SizedBox(height: 12),
            _numField(_proteinController, 'Protein (optional)', 'g'),
            const SizedBox(height: 12),
            _numField(_fiberController, 'Fiber (optional)', 'g'),
            const SizedBox(height: 12),
            _numField(_saturatedFatController, 'Saturated Fat (optional)', 'g'),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saveMeal,
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange, foregroundColor: Colors.white),
          child: const Text('Add'),
        ),
      ],
    );
  }

  Widget _numField(
      TextEditingController ctrl, String label, String suffix) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}'))
      ],
      decoration: InputDecoration(labelText: label, suffixText: suffix),
    );
  }
}