// main.dart
// ✅ FIXED: Password reset deep links now handled reliably via a post-frame
//           callback that waits for the navigator to be fully ready before
//           pushing /reset-password.
// ✅ FIXED: Recursive main() call on retry replaced with safe runApp restart
// ✅ FIXED: _isReady guard on initialRoute prevents routing before init completes
// ✅ FIXED: signedIn + recoverySentAt check catches recovery links that fire
//           signedIn instead of passwordRecovery (common on iOS cold-start)
// ✅ iOS/iPad-compatible Firebase initialization + Android 15 Edge-to-Edge

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'config/app_config.dart';
import 'pages/badge_debug_page.dart';
import 'pages/tracker_page.dart';
import 'pages/onboarding_page.dart';

// 🔥 Firebase imports
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// 🔔 Stream controller for profile refresh events
import 'services/profile_events.dart';

// Screens and Pages
import 'login.dart';
import 'pages/premium_page.dart';
import 'pages/grocery_list.dart';
import 'pages/submit_recipe.dart';
import 'pages/messages_page.dart';
import 'pages/search_users_page.dart';
import 'pages/profile_screen.dart';
import 'pages/favorite_recipes_page.dart';
import 'contact_screen.dart';
import 'home_screen.dart';
import 'pages/reset_password_page.dart';
import 'package:bari_wise/pages/manual_barcode_entry_screen.dart';
import 'package:bari_wise/pages/nutrition_search_screen.dart';
import 'package:bari_wise/pages/saved_ingredients_screen.dart';
import './pages/submission_status_page.dart';
import './pages/my_cookbook_page.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import './pages/saved_posts_page.dart';
import 'pages/lora_dataset_page.dart';

// ── Bariatric health features ──────────────────────────────────────────────
import 'pages/bari_hub_page.dart';
import 'pages/bari_dashboard_page.dart';
import 'pages/hydration_log_page.dart';
import 'pages/supplement_schedule_page.dart';
import 'pages/symptom_log_page.dart';
import 'pages/alcohol_log_page.dart';
import 'pages/recipe_generator_page.dart';
import 'pages/meal_planner_page.dart';
import 'pages/list_generator_page.dart';
import 'pages/extended_tracker_page.dart';
import 'services/bari_notification_service.dart';
import 'pages/account_preferences_page.dart';

// ── Settings ──────────────────────────────────────────────────────────────
import 'pages/settings_page.dart';
import 'widgets/admin_guard.dart';

/// 🔥 Background FCM handler (Android only - required for messages when app
/// is terminated)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!kIsWeb && Platform.isAndroid) {
    await Firebase.initializeApp();
  }
  debugPrint("🔥 Background message received: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Configure system UI for edge-to-edge display on Android 15+
  if (!kIsWeb && Platform.isAndroid) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // ✅ Only initialize MobileAds on Android/iOS
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    MobileAds.instance.initialize();
  }

  try {
    await dotenv.load(fileName: ".env");
    AppConfig.validateConfig();

    // 🔥 Platform-specific Firebase initialization
    try {
      if (!kIsWeb && Platform.isAndroid) {
        await Firebase.initializeApp();
        if (AppConfig.enableDebugPrints) {
          AppConfig.debugPrint('✅ Firebase initialized (Android)');
        }

        FirebaseMessaging.onBackgroundMessage(
            _firebaseMessagingBackgroundHandler);

        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          AppConfig.debugPrint("🔔 FCM onMessage: ${message.data}");
          if (message.data['type'] == 'refresh_profile') {
            AppConfig.debugPrint(
                "🔄 Refresh profile triggered (FOREGROUND)");
            profileUpdateStreamController.add(null);
          }
        });

        final messaging = FirebaseMessaging.instance;
        final settings = await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );

        if (AppConfig.enableDebugPrints) {
          AppConfig.debugPrint(
              '📱 Notification permission: ${settings.authorizationStatus}');
          final token = await messaging.getToken();
          if (token != null) {
            AppConfig.debugPrint(
                '🔑 FCM Token: ${token.substring(0, 20)}...');
          }
        }
      } else if (!kIsWeb && Platform.isIOS) {
        if (AppConfig.enableDebugPrints) {
          AppConfig.debugPrint('✅ Firebase auto-initialized (iOS/iPadOS)');
          AppConfig.debugPrint(
              'ℹ️  FCM disabled on iOS to prevent conflicts during review');
        }
      }
    } catch (fcmError) {
      if (AppConfig.enableDebugPrints) {
        AppConfig.debugPrint('⚠️ Firebase/FCM setup failed: $fcmError');
        AppConfig.debugPrint('App will continue without push notifications');
      }
    }

    if (AppConfig.enableDebugPrints) {
      AppConfig.debugPrint('🔄 Initializing Supabase...');
      AppConfig.debugPrint('Supabase URL: ${AppConfig.supabaseUrl}');
    }

    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    ).timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        throw Exception(
            'Supabase connection timeout. Please check your internet.');
      },
    );

    if (AppConfig.enableDebugPrints) {
      AppConfig.debugPrint('✅ Supabase initialized successfully');
      AppConfig.debugPrint('App Name: ${AppConfig.appName}');
      if (!kIsWeb) {
        AppConfig.debugPrint(
            'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
      }
    }

    // Initialize bariatric notification service
    await BariNotificationService.initialize();
    if (AppConfig.enableDebugPrints) {
      AppConfig.debugPrint('✅ BariNotificationService initialized');
    }

    runApp(const MyApp());
  } catch (e) {
    if (AppConfig.enableDebugPrints) {

    }
    runApp(_buildErrorApp(e));
  }
}

Widget _buildErrorApp(dynamic error) {
  final errorString = error.toString().toLowerCase();

  String title = 'Unable to Start App';
  String message = 'Please check your internet connection and try again.';
  IconData icon = Icons.cloud_off_rounded;
  Color iconColor = Colors.orange;

  if (errorString.contains('timeout') || errorString.contains('network')) {
    title = 'Connection Problem';
    message = 'Please check your internet connection and try again.';
    icon = Icons.wifi_off_rounded;
  } else if (errorString.contains('configuration') ||
      errorString.contains('url')) {
    title = 'Configuration Issue';
    message = 'The app needs to be updated. Please contact support.';
    icon = Icons.settings_rounded;
    iconColor = Colors.blue;
  } else {
    title = 'Startup Failed';
    message = 'Unable to start the app. Please try restarting.';
    icon = Icons.refresh_rounded;
    iconColor = Colors.red;
  }

  return MaterialApp(
    debugShowCheckedModeBanner: false,
    title: AppConfig.appName,
    home: Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 80, color: iconColor),
                ),

                const SizedBox(height: 32),

                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 12),

                Text(
                  message,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade700,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 40),

                // ✅ FIXED: Safe retry
                SizedBox(
                  width: 200,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await dotenv.load(fileName: ".env");
                        await Supabase.initialize(
                          url: AppConfig.supabaseUrl,
                          anonKey: AppConfig.supabaseAnonKey,
                        ).timeout(const Duration(seconds: 15));
                      } catch (_) {}
                      runApp(const MyApp());
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text(
                      'Try Again',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        color: Colors.blue.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'If the problem continues, try closing and reopening the app.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (AppConfig.enableDebugPrints)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      'Debug: $error',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // ignore: unused_field — tracks premium for UI, used in _checkPremiumStatus
  bool _isPremium = false;
  bool _isReady = false;
  bool _showOnboarding = false;
  late final AppLinks _appLinks;

  final GlobalKey<NavigatorState> _navigatorKey =
      GlobalKey<NavigatorState>();

  bool _resetNavigationHandled = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _checkPremiumStatus();
    await _checkOnboarding();

    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      AppConfig.debugPrint('🔐 Auth event: $event');

      if (event == AuthChangeEvent.passwordRecovery && session != null) {
        AppConfig.debugPrint('🔑 Password recovery event received');
        _handleRecoverySession(session);
        return;
      }

      if (event == AuthChangeEvent.signedIn && session != null) {
        final recoverySentAtStr = session.user.recoverySentAt;
        if (recoverySentAtStr != null) {
          try {
            final recoverySentAt =
                DateTime.parse(recoverySentAtStr).toUtc();
            final minutesAgo = DateTime.now()
                .toUtc()
                .difference(recoverySentAt)
                .inMinutes;
            if (minutesAgo < 30) {
              AppConfig.debugPrint(
                  '🔑 signedIn via recovery link (recoverySentAt: $recoverySentAtStr)');
              _handleRecoverySession(session);
            }
          } catch (e) {
            AppConfig.debugPrint(
                '⚠️ Could not parse recoverySentAt: $e');
          }
        }
      }
    });

    _initAppLinks();

    if (mounted) {
      setState(() => _isReady = true);
    }
  }

  void _handleRecoverySession(Session session) {
    if (_resetNavigationHandled) {
      AppConfig.debugPrint(
          '⚠️ Reset navigation already handled, skipping');
      return;
    }
    _resetNavigationHandled = true;
    _navigateToReset(session);

    Future.delayed(const Duration(seconds: 5), () {
      _resetNavigationHandled = false;
    });
  }

  void _navigateToReset(Session session) {
    AppConfig.debugPrint(
        '🔀 Scheduling navigation to /reset-password...');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = _navigatorKey.currentState;
      if (nav != null) {
        AppConfig.debugPrint('✅ Pushing /reset-password');
        nav.pushNamedAndRemoveUntil(
          '/reset-password',
          (route) => false,
          arguments: session,
        );
      } else {
        AppConfig.debugPrint(
            '⚠️ Navigator still null — retrying in 300ms');
        Future.delayed(const Duration(milliseconds: 300), () {
          _navigatorKey.currentState?.pushNamedAndRemoveUntil(
            '/reset-password',
            (route) => false,
            arguments: session,
          );
        });
      }
    });
  }

  Future<void> _checkOnboarding() async {
    final completed = await OnboardingPage.hasCompletedOnboarding();
    final user = Supabase.instance.client.auth.currentUser;
    if (!completed && user != null) {
      _showOnboarding = true;
    }
  }

  Future<void> _initAppLinks() async {
    try {
      _appLinks = AppLinks();

      _appLinks.uriLinkStream.listen((Uri? uri) async {
        if (uri != null) {
          AppConfig.debugPrint('🔗 Deep link received: $uri');
          await _handleDeepLink(uri);
        }
      });

      try {
        final initialUri = await _appLinks.getInitialLink();
        if (initialUri != null) {
          AppConfig.debugPrint('🔗 Initial deep link: $initialUri');
          await _handleDeepLink(initialUri);
        }
      } catch (e) {
        if (AppConfig.enableDebugPrints) {
          AppConfig.debugPrint('Failed to handle initial deep link: $e');
        }
      }
    } catch (e) {
      if (AppConfig.enableDebugPrints) {
        AppConfig.debugPrint('Failed to initialize app links: $e');
      }
    }
  }

  Future<void> _handleDeepLink(Uri uri) async {
    final uriStr = uri.toString();

    if (uriStr.contains('reset-password') ||
        uriStr.contains('type=recovery') ||
        uriStr.contains('recovery')) {
      AppConfig.debugPrint(
          '🔑 Reset-password deep link — parsing session...');

      try {
        final response = await Supabase.instance.client.auth
            .getSessionFromUrl(uri)
            .timeout(const Duration(seconds: 10));

        AppConfig.debugPrint(
            '✅ Session parsed from URL (fallback path)');
        _handleRecoverySession(response.session);
            } catch (e) {
        AppConfig.debugPrint('⚠️ getSessionFromUrl failed: $e');
      }
    }
  }

  Future<void> _checkPremiumStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = Supabase.instance.client.auth.currentUser?.id;

      if (AppConfig.enableDebugPrints && userId != null) {
        AppConfig.debugPrint('Current user ID: $userId');
      }

      if (mounted) {
        setState(() {
          _isPremium = prefs.getBool('isPremiumUser') ?? false;
        });
      }
    } catch (e) {
      if (AppConfig.enableDebugPrints) {
        AppConfig.debugPrint('Error checking premium status: $e');
      }
      if (mounted) {
        setState(() {
          _isPremium = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: AppConfig.appName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 16),
          bodyMedium: TextStyle(fontSize: 14),
        ),
      ),
      initialRoute: _isReady ? _getInitialRoute(supabase) : '/login',
      routes: {
        '/login':                (context) => const LoginPage(),
        '/home':                 (context) => const HomePage(),
        '/onboarding':           (context) => const OnboardingPage(),
        '/profile':              (context) => ProfileScreen(favoriteRecipes: const []),
        '/purchase':             (context) => const PremiumPage(),
        '/grocery-list':         (context) => const GroceryListPage(),
        '/submit-recipe':        (context) => const SubmitRecipePage(),
        '/messages':             (context) => MessagesPage(),
        '/search-users':         (context) => const SearchUsersPage(),
        '/favorite-recipes':     (context) => FavoriteRecipesPage(favoriteRecipes: const []),
        '/contact':              (context) => const ContactScreen(),
        '/manual-barcode-entry': (context) => const ManualBarcodeEntryScreen(),
        '/nutrition-search':     (context) => const NutritionSearchScreen(),
        '/saved-ingredients':    (context) => const SavedIngredientsScreen(),
        '/badge-debug':          (context) => BadgeDebugPage(),
        '/submission-status':    (context) => const SubmissionStatusPage(),
        '/tracker':              (context) => const TrackerPage(),
        '/my-cookbook':          (context) => const MyCookbookPage(),
        '/saved-posts':          (context) => const SavedPostsPage(),
        '/settings':             (context) => const SettingsPage(),
        // ── Bariatric health features ────────────────────────────────
        '/bari-hub':             (context) => const BariHubPage(),
        '/bari-dashboard':       (context) => const BariDashboardPage(),
        '/hydration-log':        (context) => const HydrationLogPage(),
        '/supplement-schedule':  (context) => const SupplementSchedulePage(),
        '/symptom-log':          (context) => const SymptomLogPage(),
        '/alcohol-log':          (context) => const AlcoholLogPage(),
        '/recipe-generator':     (context) => const RecipeGeneratorPage(),
        '/meal-planner':         (context) => const MealPlannerPage(),
        '/list-generator':       (context) => const ListGeneratorPage(),
        '/extended-tracker':     (context) => const ExtendedTrackerPage(),
        '/lora-dataset':         (context) => const AdminGuard(child: LoraDatasetPage()),
        '/account-preferences':  (context) => const AccountPreferencesPage(),
        '/reset-password':       (context) {
          final session =
              ModalRoute.of(context)?.settings.arguments as Session?;
          return ResetPasswordPage(session: session);
        },
      },
      onUnknownRoute: (settings) {
        if (AppConfig.enableDebugPrints) {
          AppConfig.debugPrint(
              'Unknown route requested: ${settings.name}');
        }

        return MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: const Text('Page Not Found'),
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.search_off_rounded,
                        size: 64,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Page Not Found',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'The page you\'re looking for doesn\'t exist or has been moved.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: 200,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (Navigator.canPop(context)) {
                            Navigator.pop(context);
                          } else {
                            Navigator.pushReplacementNamed(
                                context, '/home');
                          }
                        },
                        icon: const Icon(Icons.home_rounded),
                        label: const Text(
                          'Go Home',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _getInitialRoute(SupabaseClient supabase) {
    try {
      final user = supabase.auth.currentUser;

      if (user != null) {
        if (AppConfig.enableDebugPrints) {
          AppConfig.debugPrint('✅ User authenticated: ${user.email}');
        }
        if (_showOnboarding) {
          return '/onboarding';
        }
        return '/home';
      } else {
        if (AppConfig.enableDebugPrints) {
          AppConfig.debugPrint(
              'ℹ️ No authenticated user, showing login');
        }
        return '/login';
      }
    } catch (e) {
      if (AppConfig.enableDebugPrints) {
        AppConfig.debugPrint(
            '⚠️ Error determining initial route: $e');
      }
      return '/login';
    }
  }
}