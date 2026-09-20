import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:google_sign_in/google_sign_in.dart';
import '../providers/auth_provider.dart';
import '../../onboarding/providers/onboarding_provider.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../config/app_radius.dart';
import '../../../config/app_icon_sizes.dart';
import '../../../config/app_constraints.dart';
import '../../../config/app_text_styles.dart';
import '../../../config/app_routes.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_error_banner.dart';
import '../../../core/utils/validators.dart';
import '../../../core/extensions/responsive_context_extension.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final success = await auth.login(
      _emailController.text,
      _passwordController.text,
    );

    if (success && mounted) {
      final onboarding = context.read<OnboardingProvider>();
      if (!onboarding.onboardingComplete) {
        Navigator.pushReplacementNamed(context, AppRoutes.onboarding);
      } else {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      }
    } else if (auth.state == AuthState.unverified && mounted) {
      Navigator.pushReplacementNamed(context, AppRoutes.verifyEmail);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
      );
      final GoogleSignInAccount? account = await googleSignIn.signIn();
      if (account != null) {
        final GoogleSignInAuthentication authDetails =
            await account.authentication;
        final token =
            authDetails.idToken ??
            authDetails.accessToken ??
            'mock_google_token';

        // Synchronize with Firebase Auth
        try {
          final fb_auth.OAuthCredential credential =
              fb_auth.GoogleAuthProvider.credential(
            accessToken: authDetails.accessToken,
            idToken: authDetails.idToken,
          );
          await fb_auth.FirebaseAuth.instance.signInWithCredential(credential);
        } catch (fbError) {
          debugPrint('Firebase sign in sync note: $fbError');
        }

        if (!mounted) return;
        final authProvider = context.read<AuthProvider>();
        final success = await authProvider.loginWithGoogle(
          token: token,
          email: account.email,
          name: account.displayName,
        );

        if (success && mounted) {
          final onboarding = context.read<OnboardingProvider>();
          if (!onboarding.onboardingComplete) {
            Navigator.pushReplacementNamed(context, AppRoutes.onboarding);
          } else {
            Navigator.pushReplacementNamed(context, AppRoutes.home);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Google Sign-In failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final double logoBoxSize = context.scaleWidth(64.0);

    return AppScaffold(
      isLoading: auth.isLoading,
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: BoxConstraints(maxWidth: AppConstraints.formMaxWidth),
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.pageHorizontal(context),
              vertical: AppSpacing.pageVertical(context),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mini Logo
                  Center(
                    child: Container(
                      width: logoBoxSize,
                      height: logoBoxSize,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(
                          AppRadius.card(context),
                        ),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.eco_rounded,
                          size: AppIconSizes.lg(context),
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  AppGap.md(context),
                  Center(
                    child: Text(
                      'Welcome back',
                      style: AppTextStyles.displayMedium(context),
                    ),
                  ),
                  AppGap.xs(context),
                  Center(
                    child: Text(
                      'Sign in to manage your smart grocery intelligence',
                      style: AppTextStyles.bodyMedium(context),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  AppGap.lg(context),

                  // Error banner
                  AppErrorBanner(
                    errorMessage: auth.errorMessage,
                    onClose: () {
                      auth.clearErrors();
                    },
                  ),
                  AppGap.sm(context),

                  // Inputs
                  AppTextField(
                    controller: _emailController,
                    label: 'Email Address',
                    hint: 'e.g. name@email.com',
                    keyboardType: TextInputType.emailAddress,
                    validator: Validators.validateEmail,
                  ),
                  AppGap.md(context),
                  AppTextField(
                    controller: _passwordController,
                    label: 'Password',
                    hint: 'Enter your password',
                    isPassword: true,
                    validator: Validators.validatePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                  ),

                  // Forgot Password link
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        Navigator.pushNamed(context, AppRoutes.forgotPassword);
                      },
                      child: Text(
                        'Forgot Password?',
                        style: AppTextStyles.labelMedium(
                          context,
                        ).copyWith(color: AppColors.primary),
                      ),
                    ),
                  ),
                  AppGap.sm(context),

                  // Sign In Button
                  AppButton(
                    text: 'Sign In',
                    isLoading: auth.isLoading,
                    onPressed: auth.isLoading ? null : _submit,
                  ),
                  AppGap.md(context),

                  // Divider
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.md(context),
                        ),
                        child: Text(
                          'OR',
                          style: AppTextStyles.caption(context),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  AppGap.sm(context),

                  // Third-party buttons
                  AppButton(
                    text: 'Continue with Google',
                    isLoading: auth.isLoading,
                    onPressed: auth.isLoading ? null : _handleGoogleSignIn,
                    style: AppButtonStyle.secondary,
                    icon: Icons.g_mobiledata_rounded,
                  ),
                  AppGap.xl(context),


                  // Sign Up link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Don\'t have an account? ',
                        style: AppTextStyles.bodyMedium(context),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushNamed(context, AppRoutes.signup);
                        },
                        child: Text(
                          'Sign Up',
                          style: AppTextStyles.labelMedium(context).copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
