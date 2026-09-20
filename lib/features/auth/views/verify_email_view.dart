import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../providers/auth_provider.dart';
import '../../onboarding/providers/onboarding_provider.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../config/app_icon_sizes.dart';
import '../../../config/app_constraints.dart';
import '../../../config/app_text_styles.dart';
import '../../../config/app_routes.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/extensions/responsive_context_extension.dart';

class VerifyEmailView extends StatefulWidget {
  const VerifyEmailView({super.key});

  @override
  State<VerifyEmailView> createState() => _VerifyEmailViewState();
}

class _VerifyEmailViewState extends State<VerifyEmailView> {
  int _countdown = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdown = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown == 0) {
        setState(() {
          _timer?.cancel();
        });
      } else {
        setState(() {
          _countdown--;
        });
      }
    });
  }

  Future<void> _resend() async {
    if (_countdown > 0) return;
    final auth = context.read<AuthProvider>();
    await auth.resendVerification();
    _startCountdown();
  }

  Future<void> _checkStatus() async {
    final auth = context.read<AuthProvider>();
    final verified = await auth.verifyEmail();
    if (verified && mounted) {
      final onboarding = context.read<OnboardingProvider>();
      if (!onboarding.onboardingComplete) {
        Navigator.pushReplacementNamed(context, AppRoutes.onboarding);
      } else {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final email = auth.user?.email ?? 'your email';
    final double iconBoxSize = context.scaleWidth(80.0);

    return AppScaffold(
      isLoading: auth.isLoading,
      body: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: AppConstraints.formMaxWidth),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.pageHorizontal(context),
            vertical: AppSpacing.pageVertical(context),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              Container(
                width: iconBoxSize,
                height: iconBoxSize,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
                ),
                child: Center(
                  child: Icon(
                    Icons.email_outlined,
                    size: AppIconSizes.lg(context) * 1.25,
                    color: AppColors.primary,
                  ),
                ),
              ),
              AppGap.md(context),
              Text(
                'Verify Email',
                style: AppTextStyles.displayMedium(context),
              ),
              AppGap.xs(context),
              Text(
                'We have sent a verification code link to:',
                style: AppTextStyles.bodyMedium(context),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4.0),
              Text(
                email,
                style: AppTextStyles.labelLarge(context).copyWith(color: AppColors.primary),
                textAlign: TextAlign.center,
              ),
              AppGap.md(context),
              Text(
                'Please verify your email address to unlock FreshTrack features.',
                style: AppTextStyles.bodyMedium(context).copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              
              AppButton(
                text: 'I have verified my email',
                onPressed: _checkStatus,
              ),
              AppGap.xs(context),
              
              TextButton(
                onPressed: _countdown > 0 ? null : _resend,
                child: Text(
                  _countdown > 0 ? 'Resend verification in ${_countdown}s' : 'Resend Verification Email',
                  style: AppTextStyles.labelMedium(context).copyWith(
                    color: _countdown > 0 ? AppColors.textHint : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 8.0),
              
              TextButton(
                onPressed: () {
                  auth.logout();
                  Navigator.pushReplacementNamed(context, AppRoutes.login);
                },
                child: Text(
                  'Use a different email address',
                  style: AppTextStyles.caption(context).copyWith(color: AppColors.danger),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
