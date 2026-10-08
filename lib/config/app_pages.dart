import 'package:flutter/material.dart';
import 'app_routes.dart';
import '../features/auth/views/splash_view.dart';
import '../features/onboarding/views/onboarding_view.dart';
import '../features/auth/views/login_view.dart';
import '../features/auth/views/signup_view.dart';
import '../features/auth/views/forgot_password_view.dart';
import '../features/auth/views/verify_email_view.dart';
import '../features/home/views/home_shell.dart';
import '../features/scan/views/scan_view.dart';
import '../features/scan/views/manual_add_view.dart';
import '../features/scan/views/barcode_scanner_view.dart';
import '../features/recipes/views/recipe_detail_view.dart';
import '../features/recipes/views/recipes_view.dart';
import '../features/kitchen/views/kitchen_item_detail_view.dart';
import '../data/models/recipe_model.dart';
import '../data/models/grocery_model.dart';

class AppPages {
  static Map<String, WidgetBuilder> get routes => {
    AppRoutes.splash: (context) => const SplashView(),
    AppRoutes.onboarding: (context) => const OnboardingView(),
    AppRoutes.login: (context) => const LoginView(),
    AppRoutes.signup: (context) => const SignupView(),
    AppRoutes.forgotPassword: (context) => const ForgotPasswordView(),
    AppRoutes.verifyEmail: (context) => const VerifyEmailView(),
    AppRoutes.home: (context) => const HomeShell(),
    AppRoutes.scan: (context) => const ScanView(),
    AppRoutes.barcodeScan: (context) => const BarcodeScannerView(),
    
    // Dynamic/Parameterized route builders
    AppRoutes.manualAdd: (context) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        return ManualAddView(initialData: args);
      } else if (args is String) {
        return ManualAddView(initialZone: args);
      }
      return const ManualAddView();
    },
    AppRoutes.recipeDetail: (context) {
      final recipe = ModalRoute.of(context)!.settings.arguments as RecipeModel;
      return RecipeDetailView(recipe: recipe);
    },
    AppRoutes.itemDetail: (context) {
      final args = ModalRoute.of(context)!.settings.arguments;
      if (args is GroceryModel) {
        return KitchenItemDetailView(item: args);
      }
      throw ArgumentError('Expected GroceryModel for itemDetail route, got: $args');
    },
    AppRoutes.recipes: (context) {
      final args = ModalRoute.of(context)?.settings.arguments;
      final expiringOnly = (args is Map<String, dynamic>) ? (args['expiring_only'] == true) : false;
      return RecipesView(initialExpiringOnly: expiringOnly);
    },
  };
}
