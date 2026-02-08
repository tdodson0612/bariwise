// lib/pages/tracker_page.dart
// Updated with unit dropdowns, improved height handling with preferences, debugging, and ingredient auto-fill
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
  String _heightUnitPreference = 'metric'; // 'metric' or 'imperial'
  bool _weightVisible = false;
  bool _weightLossVisible = false;
  int _currentStreak = 0;

  bool _isLoading = true;
  bool _isSaving = false;

  final TextEditingController _exerciseController = TextEditingController();
  final TextEditingController _waterController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();

  // Unit selections - consistent defaults
  String _weightUnit = 'kg';
  String _exerciseUnit = 'minutes';
  String _waterUnit = 'cups';

  // SharedPreferences keys for unit persistence
  static const String _PREF_WEIGHT_UNIT = 'tracker_weight_unit_';
  static const String _PREF_EXERCISE_UNIT = 'tracker_exercise_unit_';
  static const String _PREF_WATER_UNIT = 'tracker_water_unit_';

  List<Map<String, dynamic>> _meals = [];

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
            const Text('Important Disclaimer'),
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
                    Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'If you experience medical symptoms, seek immediate professional care.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
        _exerciseUnit = prefs.getString('$_PREF_EXERCISE_UNIT$userId') ?? 'minutes';
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
      if (userId == null) {
        throw Exception('User not logged in');
      }
      AppConfig.debugPrint('   User ID: $userId');

      // Load profile data
      AppConfig.debugPrint('🔍 Loading surgery type...');
      final diseaseType = await ProfileService.getSurgeryType(userId);
      AppConfig.debugPrint('   Surgery type: ${diseaseType ?? 'none'}');
      
      AppConfig.debugPrint('🔍 Loading height...');
      final height = await ProfileService.getHeight(userId);
      AppConfig.debugPrint('   Height: ${height?.toStringAsFixed(0) ?? 'none'} cm');
      
      AppConfig.debugPrint('🔍 Loading height unit preference...');
      final heightUnitPref = await ProfileService.getHeightUnitPreference(userId);
      AppConfig.debugPrint('   Height unit preference: $heightUnitPref');
      
      AppConfig.debugPrint('🔍 Loading privacy settings...');
      final weightVisible = await ProfileService.getWeightVisibility(userId);
      final weightLossVisible = await ProfileService.getWeightLossVisibility(userId);
      AppConfig.debugPrint('   Weight visible: $weightVisible');
      AppConfig.debugPrint('   Weight loss visible: $weightLossVisible');
      
      AppConfig.debugPrint('🔍 Loading weight streak...');
      final streak = await TrackerService.getWeightStreak(userId);
      AppConfig.debugPrint('   Current streak: $streak days');

      AppConfig.debugPrint('🔍 Auto-filling missing weights...');
      await TrackerService.autoFillMissingWeights(userId);

      AppConfig.debugPrint('🔍 Loading entry for ${_selectedDate.toString().split(' ')[0]}...');
      final dateString = _selectedDate.toString().split(' ')[0];
      final entry = await TrackerService.getEntryForDate(userId, dateString);
      
      if (entry != null) {
        AppConfig.debugPrint('✅ Entry found:');
        AppConfig.debugPrint('   Meals: ${entry.meals.length}');
        AppConfig.debugPrint('   Exercise: ${entry.exercise ?? 'none'}');
        AppConfig.debugPrint('   Water: ${entry.waterIntake ?? 'none'}');
        AppConfig.debugPrint('   Weight: ${entry.weight?.toStringAsFixed(1) ?? 'none'} kg');
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
      ErrorHandlingService.showSimpleError(context, 'You must be logged in to save entries');
      return;
    }

    setState(() => _isSaving = true);

    try {
      AppConfig.debugPrint('💾 Starting save operation...');
      AppConfig.debugPrint('   User ID: $userId');
      AppConfig.debugPrint('   Date: ${_selectedDate.toString().split(' ')[0]}');
      
      // Convert exercise to standard format (minutes)
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

      // Convert water to standard format (cups)
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

      // Calculate score
      final score = TrackerService.calculateDailyScore(
        meals: _meals,
        surgeryType: _diseaseType,
        exercise: exerciseText,
        waterIntake: waterText,
      );
      AppConfig.debugPrint('   Calculated score: $score');

      // Convert weight to kg if needed
      double? weight;
      if (_weightController.text.trim().isNotEmpty) {
        final value = double.tryParse(_weightController.text.trim());
        if (value != null) {
          weight = _weightUnit == 'lbs' ? value * 0.453592 : value;
          AppConfig.debugPrint('   Weight: ${weight.toStringAsFixed(1)} kg (from $_weightUnit)');
        }
      } else {
        AppConfig.debugPrint('   Weight: none entered');
      }

      // Create entry
      final entry = TrackerEntry(
        date: _selectedDate.toString().split(' ')[0],
        meals: _meals,
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
        userId, 
        _selectedDate.toString().split(' ')[0]
      );
      
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
        AppConfig.debugPrint('🎉 User reached day 7! Popup will show on home screen.');
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
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
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
    } else {
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    }
  }

  Future<void> _addMeal() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _MealDialog(),
    );

    if (result != null && mounted) {
      setState(() {
        _meals.add(result);
      });
    }
  }

  void _removeMeal(int index) {
    setState(() {
      _meals.removeAt(index);
    });
  }

  Future<void> _toggleWeightVisibility() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return;

    try {
      final newValue = !_weightVisible;
      await ProfileService.updateWeightVisibility(userId, newValue);

      if (mounted) {
        setState(() {
          _weightVisible = newValue;
        });
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
        setState(() {
          _weightLossVisible = newValue;
        });
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

    // Load existing height and preference
    final existingHeight = await ProfileService.getHeight(userId);
    final existingPreference = await ProfileService.getHeightUnitPreference(userId);

    final feetController = TextEditingController();
    final inchesController = TextEditingController();
    final cmController = TextEditingController();
    String heightSystem = existingPreference; // Use saved preference

    // Pre-fill if height exists
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
      barrierDismissible: existingHeight != null, // Allow dismiss if height already set
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.height, color: Colors.blue),
              SizedBox(width: 8),
              Text(existingHeight != null ? 'Update Your Height' : 'Set Your Height'),
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
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 16),
                
                // Unit System Selector
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButton<String>(
                    value: heightSystem,
                    isExpanded: true,
                    underline: SizedBox(),
                    items: [
                      DropdownMenuItem(
                        value: 'metric',
                        child: Row(
                          children: [
                            Icon(Icons.straighten, size: 18, color: Colors.blue),
                            SizedBox(width: 8),
                            Text('Metric (cm)'),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'imperial',
                        child: Row(
                          children: [
                            Icon(Icons.straighten, size: 18, color: Colors.orange),
                            SizedBox(width: 8),
                            Text('Imperial (ft/in)'),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() {
                          heightSystem = value;
                          
                          // Convert existing values when switching
                          if (value == 'imperial' && cmController.text.isNotEmpty) {
                            final cm = double.tryParse(cmController.text);
                            if (cm != null) {
                              final converted = HeightUtils.cmToFeetInches(cm);
                              feetController.text = converted['feet'].toString();
                              inchesController.text = converted['inches'].toString();
                            }
                          } else if (value == 'metric' && feetController.text.isNotEmpty) {
                            final feet = int.tryParse(feetController.text) ?? 0;
                            final inches = int.tryParse(inchesController.text) ?? 0;
                            final cm = HeightUtils.feetInchesToCm(feet, inches);
                            cmController.text = cm.toStringAsFixed(0);
                          }
                        });
                      }
                    },
                  ),
                ),
                
                SizedBox(height: 16),
                
                // Conditional Height Input Fields
                if (heightSystem == 'imperial') ...[
                  // Feet and Inches Input
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: feetController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            labelText: 'Feet',
                            hintText: 'e.g., 5',
                            border: OutlineInputBorder(),
                            suffixText: 'ft',
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: inchesController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            labelText: 'Inches',
                            hintText: 'e.g., 8',
                            border: OutlineInputBorder(),
                            suffixText: 'in',
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Common: 4\'10" - 6\'6"',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ] else ...[
                  // Centimeters Input
                  TextField(
                    controller: cmController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}'))
                    ],
                    decoration: InputDecoration(
                      labelText: 'Height',
                      hintText: 'e.g., 170',
                      border: OutlineInputBorder(),
                      suffixText: 'cm',
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Common: 147cm - 198cm',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (existingHeight != null)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel'),
              ),
            ElevatedButton(
              onPressed: () async {
                double? heightInCm;
                
                if (heightSystem == 'imperial') {
                  // Parse feet and inches
                  final feet = int.tryParse(feetController.text.trim());
                  final inches = int.tryParse(inchesController.text.trim());
                  
                  if (feet == null || feet < 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Please enter valid feet')),
                    );
                    return;
                  }
                  
                  if (inches == null || inches < 0 || inches >= 12) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Please enter valid inches (0-11)')),
                    );
                    return;
                  }
                  
                  heightInCm = HeightUtils.feetInchesToCm(feet, inches);
                  
                } else {
                  // Parse centimeters
                  heightInCm = double.tryParse(cmController.text.trim());
                  
                  if (heightInCm == null || heightInCm <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Please enter a valid height in cm')),
                    );
                    return;
                  }
                }

                // Validate height range
                if (!HeightUtils.isValidHeight(heightInCm)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Height must be between 50cm and 250cm'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                try {
                  final userId = AuthService.currentUserId;
                  if (userId != null) {
                    AppConfig.debugPrint('📏 Saving height: $heightInCm cm');
                    AppConfig.debugPrint('📏 Saving preference: $heightSystem');
                    
                    // Save both height and preference
                    await ProfileService.updateHeight(userId, heightInCm);
                    await ProfileService.updateHeightUnitPreference(userId, heightSystem);
                    
                    // Verify it was saved
                    final savedHeight = await ProfileService.getHeight(userId);
                    final savedPreference = await ProfileService.getHeightUnitPreference(userId);
                    
                    if (savedHeight == null || (savedHeight - heightInCm).abs() > 0.1) {
                      throw Exception('Height verification failed after save');
                    }
                    
                    if (savedPreference != heightSystem) {
                      throw Exception('Preference verification failed after save');
                    }
                    
                    if (mounted) {
                      setState(() {
                        _userHeight = heightInCm;
                        _heightUnitPreference = heightSystem;
                      });
                      
                      AppConfig.debugPrint('✅ Height and preference saved: $heightInCm cm ($heightSystem)');
                      ErrorHandlingService.showSuccess(
                        context, 
                        'Height saved: ${HeightUtils.formatHeight(heightInCm, heightSystem)}'
                      );
                    }
                  }
                  
                  Navigator.pop(context);
                } catch (e) {
                  AppConfig.debugPrint('❌ Error saving height: $e');
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to save height: ${e.toString()}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

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
              icon: Icon(Icons.height),
              tooltip: 'Height: ${HeightUtils.formatHeight(_userHeight!, _heightUnitPreference)}',
              onPressed: _showHeightSetupDialog,
            ),
          // 🔥 DEBUG BUTTON (Remove in production)
          if (AppConfig.enableDebugPrints)
            IconButton(
              icon: Icon(Icons.bug_report),
              tooltip: 'Debug Storage',
              onPressed: () async {
                final userId = AuthService.currentUserId;
                if (userId != null) {
                  await TrackerService.debugStorageState(userId);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Check debug logs for storage state')),
                  );
                }
              },
            ),
        ],
      ),
      body: PremiumGate(
        feature: PremiumFeature.healthTracker,
        featureName: 'Health Tracker',
        featureDescription: 'Track your meals, exercise, water intake, and weight with disease-aware scoring.',
        child: _buildTrackerContent(),
      ),
    );
  }

  Widget _buildTrackerContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_userHeight == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showHeightSetupDialog();
      });
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
    final canGoForward = _selectedDate.isBefore(
      DateTime.now().subtract(const Duration(days: -1)),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              onPressed: () => _changeDate(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              _formatDate(_selectedDate),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              onPressed: canGoForward ? () => _changeDate(1) : null,
              icon: const Icon(Icons.chevron_right),
            ),
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
                const Text(
                  'Weight',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Spacer(),
                if (_userHeight != null)
                  InkWell(
                    onTap: _showHeightSetupDialog,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.height, size: 14, color: Colors.blue.shade700),
                          SizedBox(width: 4),
                          Text(
                            HeightUtils.formatHeight(_userHeight!, _heightUnitPreference),
                            style: TextStyle(
                              fontSize: 12, 
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w600,
                            ),
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
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}'))
                    ],
                    decoration: InputDecoration(
                      labelText: 'Weight',
                      hintText: _weightUnit == 'kg' ? 'e.g., 70.5' : 'e.g., 155.5',
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
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
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
                    Icon(Icons.local_fire_department, color: Colors.orange.shade700, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '$_currentStreak day${_currentStreak == 1 ? '' : 's'} streak!',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
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
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Weight average visible on profile',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                Switch(
                  value: _weightVisible,
                  onChanged: (_) => _toggleWeightVisibility(),
                  activeThumbColor: Colors.orange,
                ),
              ],
            ),
            
            if (_currentStreak >= 14) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    _weightLossVisible ? Icons.visibility : Icons.visibility_off,
                    size: 20,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Weight loss visible on profile',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  Switch(
                    value: _weightLossVisible,
                    onChanged: (_) => _toggleWeightLossVisibility(),
                    activeThumbColor: Colors.orange,
                  ),
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
                    const Icon(Icons.restaurant, color: Colors.orange, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Meals (${_meals.length})',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: _addMeal,
                  icon: const Icon(Icons.add_circle, color: Colors.orange),
                  tooltip: 'Add Meal',
                ),
              ],
            ),
            if (_meals.isEmpty) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'No meals added yet. Tap + to add a meal.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
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
                        onPressed: () => _removeMeal(index),
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
            Row(
              children: [
                const Icon(Icons.fitness_center, color: Colors.purple, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Exercise',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
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
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}'))
                    ],
                    decoration: InputDecoration(
                      labelText: 'Duration',
                      hintText: _exerciseUnit == 'minutes' ? 'e.g., 30' : 'e.g., 1',
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
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'minutes', child: Text('min')),
                      DropdownMenuItem(value: 'hours', child: Text('hrs')),
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
            Row(
              children: [
                const Icon(Icons.water_drop, color: Colors.cyan, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Water Intake',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
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
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}'))
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
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'cups', child: Text('cups')),
                      DropdownMenuItem(value: 'oz', child: Text('oz')),
                      DropdownMenuItem(value: 'liters', child: Text('L')),
                      DropdownMenuItem(value: 'pints', child: Text('pints')),
                      DropdownMenuItem(value: 'quarts', child: Text('qts')),
                      DropdownMenuItem(value: 'gallons', child: Text('gal')),
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
            Row(
              children: [
                const Icon(Icons.favorite, color: Colors.red, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Today\'s Health Score',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_meals.isEmpty) ...[
              Text(
                'Add meals to see your health score',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ] else ...[
              BariHealthBar(healthScore: score),
              const SizedBox(height: 8),
              Text(
                'Based on ${_meals.length} meal${_meals.length == 1 ? '' : 's'}${_exerciseController.text.isNotEmpty ? ', exercise' : ''}${_waterController.text.isNotEmpty ? ', and water intake' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
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
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            )
          : const Icon(Icons.save),
        label: Text(
          _isSaving ? 'Saving...' : 'Save Entry',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

// 🔥 UPDATED: Meal Dialog with Saved Ingredients auto-fill
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
      final ingredients = await SavedIngredientsService.loadSavedIngredients();
      if (mounted) {
        setState(() {
          _savedIngredients = ingredients;
          _isLoadingIngredients = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingIngredients = false;
        });
      }
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Auto-filled from "${ingredient.productName}"'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _saveMeal() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a meal name')),
      );
      return;
    }

    final meal = {
      'name': _nameController.text.trim(),
      'calories': double.tryParse(_caloriesController.text) ?? 0.0,
      'fat': double.tryParse(_fatController.text) ?? 0.0,
      'sodium': double.tryParse(_sodiumController.text) ?? 0.0,
      'sugar': double.tryParse(_sugarController.text) ?? 0.0,
      'protein': double.tryParse(_proteinController.text),
      'fiber': double.tryParse(_fiberController.text),
      'saturatedFat': double.tryParse(_saturatedFatController.text),
    };

    Navigator.pop(context, meal);
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
            // 🔥 NEW: Saved Ingredients Section
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
                        Icon(Icons.bookmark, color: Colors.blue.shade700, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Quick Fill from Saved Ingredients:',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
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
                              onTap: () => _autofillFromIngredient(ingredient),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 140,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.blue.shade300),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      ingredient.productName,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${ingredient.calories.toStringAsFixed(0)} cal',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Icon(Icons.touch_app, size: 12, color: Colors.blue.shade700),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Tap to fill',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: Colors.blue.shade700,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
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
              Center(
                child: Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey.shade400)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'OR ENTER MANUALLY',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.grey.shade400)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ] else if (_isLoadingIngredients) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Loading saved ingredients...',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Manual Entry Fields
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Meal Name *',
                hintText: 'e.g., Grilled Chicken Salad',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _caloriesController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}'))],
              decoration: const InputDecoration(
                labelText: 'Calories *',
                suffixText: 'cal',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fatController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}'))],
              decoration: const InputDecoration(
                labelText: 'Fat *',
                suffixText: 'g',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sodiumController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}'))],
              decoration: const InputDecoration(
                labelText: 'Sodium *',
                suffixText: 'mg',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sugarController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}'))],
              decoration: const InputDecoration(
                labelText: 'Sugar *',
                suffixText: 'g',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _proteinController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}'))],
              decoration: const InputDecoration(
                labelText: 'Protein (optional)',
                suffixText: 'g',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fiberController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}'))],
              decoration: const InputDecoration(
                labelText: 'Fiber (optional)',
                suffixText: 'g',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _saturatedFatController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}'))],
              decoration: const InputDecoration(
                labelText: 'Saturated Fat (optional)',
                suffixText: 'g',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveMeal,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}