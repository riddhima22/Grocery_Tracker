import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'firebase_options.dart';

import 'config/app_routes.dart';
import 'config/app_pages.dart';
import 'config/app_theme.dart';
import 'config/app_navigation.dart';

import 'features/auth/providers/auth_provider.dart';
import 'features/onboarding/providers/onboarding_provider.dart';
import 'features/kitchen/providers/kitchen_provider.dart';
import 'features/scan/providers/scan_provider.dart';
import 'features/recipes/providers/recipe_provider.dart';
import 'features/grocery_list/providers/grocery_list_provider.dart';
import 'features/meals/providers/meal_provider.dart';
import 'core/services/offline_sync_service.dart';
import 'core/services/notification_service.dart';
import 'core/api/api_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  OfflineSyncService().initialize();
  ApiClient().warmUp(); // Non-blocking pre-warm of backend container

  // Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Pass all uncaught errors from the framework to Crashlytics if not running on Web.
    if (!kIsWeb) {
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;
    }
    // Initialize push and local notifications
    await NotificationService().initialize();
  } catch (e) {
    debugPrint('Firebase/Notification initialization failed: $e');
  }

  // Enforce vertical portrait orientation only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => OnboardingProvider()),
        ChangeNotifierProvider(create: (_) => KitchenProvider()),
        ChangeNotifierProvider(create: (_) => ScanProvider()),
        ChangeNotifierProvider(create: (_) => RecipeProvider()),
        ChangeNotifierProvider(create: (_) => GroceryListProvider()),
        ChangeNotifierProvider(create: (_) => MealProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FreshTrack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      navigatorKey: AppNavigation.navigatorKey,
      initialRoute: AppRoutes.splash,
      routes: AppPages.routes,
      // Localization defaults
      locale: const Locale('en', 'IN'),
    );
  }
}
