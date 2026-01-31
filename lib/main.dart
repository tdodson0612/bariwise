// main.dart - FIXED: Platform-conditional Firebase initialization
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'config/app_config.dart';
import 'pages/badge_debug_page.dart';
import 'pages/tracker_page.dart';

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


/// 🔥 Background FCM handler (required for messages when app is terminated)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if not already initialized
  if (!kIsWeb) {
    await Firebase.initializeApp();
  }
  debugPrint("🔥 Background message received: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize();

  try {
    // Load environment variables FIRST
    await dotenv.load(fileName: ".env");
    
    // Validate configuration
    AppConfig.validateConfig();
    
    // 🔥 Firebase initialization (both iOS and Android)
    try {
      if (!kIsWeb) {
        // Initialize Firebase for both iOS and Android
        await Firebase.initializeApp();
        if (AppConfig.enableDebugPrints) {
          AppConfig.debugPrint('✅ Firebase initialized (${Platform.isIOS ? "iOS" : "Android"})');
        }
      }

      // Register background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      
      if (AppConfig.enableDebugPrints) {
        AppConfig.debugPrint('✅ Background FCM handler registered');
      }

      // 🔔 Register FOREGROUND FCM listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print("🔔 FCM onMessage: ${message.data}");

        if (message.data['type'] == 'refresh_profile') {
          print("🔄 Refresh profile triggered (FOREGROUND)");
          profileUpdateStreamController.add(null);
        }
      });
      
      if (AppConfig.enableDebugPrints) {
        AppConfig.debugPrint('✅ Foreground FCM listener registered');
      }

      // Request notification permissions
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      
      if (AppConfig.enableDebugPrints) {
        AppConfig.debugPrint('📱 Notification permission: ${settings.authorizationStatus}');
      }

      // Get FCM token for debugging
      final token = await messaging.getToken();
      if (AppConfig.enableDebugPrints && token != null) {
        AppConfig.debugPrint('🔑 FCM Token: ${token.substring(0, 20)}...');
      }
    } catch (fcmError) {
      if (AppConfig.enableDebugPrints) {
        AppConfig.debugPrint('⚠️ FCM setup failed: $fcmError');
        AppConfig.debugPrint('App will continue without push notifications');
      }
      // Continue without FCM - not critical for app function
    }

    // Initialize Supabase with timeout (critical for app function)
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw Exception('Connection timeout. Please check your internet.');
      },
    );

    if (AppConfig.enableDebugPrints) {
      AppConfig.debugPrint('✅ Supabase initialized successfully');
      AppConfig.debugPrint('Supabase URL: ${AppConfig.supabaseUrl}');
      AppConfig.debugPrint('App Name: ${AppConfig.appName}');
    }

    runApp(const MyApp());
  } catch (e) {
    if (AppConfig.enableDebugPrints) {
      print('❌ Critical app initialization failed: $e');
    }
    runApp(_buildErrorApp(e));
  }
}

/// Build user-friendly error app when initialization fails
Widget _buildErrorApp(dynamic error) {
  final errorString = error.toString().toLowerCase();

  // Determine user-friendly message
  String title = 'Unable to Start App';
  String message = 'Please check your internet connection and try again.';
  IconData icon = Icons.cloud_off_rounded;
  Color iconColor = Colors.orange;

  if (errorString.contains('timeout') || errorString.contains('network')) {
    title = 'Connection Problem';
    message = 'Please check your internet connection and try again.';
    icon = Icons.wifi_off_rounded;
  } else if (errorString.contains('configuration') || errorString.contains('url')) {
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
                // Icon
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 80,
                    color: iconColor,
                  ),
                ),

                const SizedBox(height: 32),

                // Title
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 12),

                // Message
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

                // Retry button
                SizedBox(
                  width: 200,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // Force app restart by calling main again
                      WidgetsFlutterBinding.ensureInitialized();
                      main();
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

                // Help text
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

                // Debug details
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
  bool _isPremium = false;
  late final AppLinks _appLinks;

  @override
  void initState() {
    super.initState();
    _checkPremiumStatus();
    _initAppLinks();
  }

  Future<void> _initAppLinks() async {
    try {
      _appLinks = AppLinks();

      // Handle deep links when app is already running
      _appLinks.uriLinkStream.listen((Uri? uri) async {
        if (uri != null && uri.toString().contains('reset-password')) {
          await _handleResetPasswordLink(uri);
        }
      });

      // Handle deep links when app is launched by link (cold start)
      try {
        final initialUri = await _appLinks.getInitialLink();
        if (initialUri != null && initialUri.toString().contains('reset-password')) {
          await _handleResetPasswordLink(initialUri);
        }
      } catch (e) {
        if (AppConfig.enableDebugPrints) {
          AppConfig.debugPrint('Failed to handle initial deep link: $e');
        }
        // Silent fail - not critical
      }
    } catch (e) {
      if (AppConfig.enableDebugPrints) {
        AppConfig.debugPrint('Failed to initialize app links: $e');
      }
      // Silent fail - deep links not critical for app function
    }
  }

  Future<void> _handleResetPasswordLink(Uri uri) async {
    try {
      final response = await Supabase.instance.client.auth
          .getSessionFromUrl(uri)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Password reset link expired or invalid');
            },
          );

      if (mounted) {
        Navigator.pushNamed(context, '/reset-password', arguments: response.session);
      } else {
        if (AppConfig.enableDebugPrints) {
          AppConfig.debugPrint('⚠️ No valid session found in reset-password link');
        }
      }
    } catch (e) {
      if (AppConfig.enableDebugPrints) {
        AppConfig.debugPrint('❌ Error handling reset-password link: $e');
      }
      
      // Show user-friendly error if mounted
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Password reset link is invalid or expired. Please request a new one.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        });
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
      
      // Default to free tier on error
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
      debugShowCheckedModeBanner: false,
      title: AppConfig.appName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
        // iPad-friendly defaults
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 16),
          bodyMedium: TextStyle(fontSize: 14),
        ),
      ),
      initialRoute: _getInitialRoute(supabase),
      routes: {
        '/login': (context) => const LoginPage(),
        '/home': (context) => const HomePage(),
        '/profile': (context) => ProfileScreen(favoriteRecipes: const []),
        '/purchase': (context) => const PremiumPage(),
        '/grocery-list': (context) => const GroceryListPage(),
        '/submit-recipe': (context) => const SubmitRecipePage(),
        '/messages': (context) => MessagesPage(),
        '/search-users': (context) => const SearchUsersPage(),
        '/favorite-recipes': (context) => FavoriteRecipesPage(favoriteRecipes: const []),
        '/contact': (context) => const ContactScreen(),
        '/manual-barcode-entry': (context) => const ManualBarcodeEntryScreen(),
        '/nutrition-search': (context) => const NutritionSearchScreen(),
        '/saved-ingredients': (context) => const SavedIngredientsScreen(),
        '/badge-debug': (context) => BadgeDebugPage(),
        '/submission-status': (context) => const SubmissionStatusPage(),
        '/tracker': (context) => const TrackerPage(),
        '/my-cookbook': (context) => const MyCookbookPage(),
        '/saved-posts': (context) => const SavedPostsPage(),
        '/reset-password': (context) {
          final session = ModalRoute.of(context)?.settings.arguments as Session?;
          return ResetPasswordPage(session: session);
        },
      },
      onUnknownRoute: (settings) {
        if (AppConfig.enableDebugPrints) {
          AppConfig.debugPrint('Unknown route requested: ${settings.name}');
        }
        
        // User-friendly 404 page
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
                        color: Colors.orange.withOpacity(0.1),
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
                          // Try to go back, or go home if can't go back
                          if (Navigator.canPop(context)) {
                            Navigator.pop(context);
                          } else {
                            Navigator.pushReplacementNamed(context, '/home');
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
        return '/home';
      } else {
        if (AppConfig.enableDebugPrints) {
          AppConfig.debugPrint('ℹ️ No authenticated user, showing login');
        }
        return '/login';
      }
    } catch (e) {
      if (AppConfig.enableDebugPrints) {
        AppConfig.debugPrint('⚠️ Error determining initial route: $e');
      }
      // On error, default to login (safe fallback)
      return '/login';
    }
  }
}