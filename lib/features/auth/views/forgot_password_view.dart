import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
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

class ForgotPasswordView extends StatefulWidget {
  const ForgotPasswordView({super.key});

  @override
  State<ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<ForgotPasswordView> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _sentSuccessfully = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    final auth = context.read<AuthProvider>();
    final success = await auth.requestPasswordReset(_emailController.text);
    if (success) {
      setState(() {
        _sentSuccessfully = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return AppScaffold(
      isLoading: auth.isLoading,
      body: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: AppConstraints.formMaxWidth),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.pageHorizontal(context),
            vertical: AppSpacing.pageVertical(context),
          ),
          child: _sentSuccessfully ? _buildSuccessState() : _buildFormState(auth),
        ),
      ),
    );
  }

  Widget _buildFormState(AuthProvider auth) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppGap.md(context),
          Text(
            'Reset Password',
            style: AppTextStyles.displayMedium(context),
          ),
          AppGap.sm(context),
          Text(
            'Enter the email address associated with your account and we\'ll send you a password reset link.',
            style: AppTextStyles.bodyLarge(context).copyWith(color: AppColors.textSecondary),
          ),
          AppGap.lg(context),
          
          AppErrorBanner(
            errorMessage: auth.errorMessage,
            onClose: () {
              auth.clearErrors();
            },
          ),
          AppGap.sm(context),
          
          AppTextField(
            controller: _emailController,
            label: 'Email Address',
            hint: 'e.g. name@email.com',
            keyboardType: TextInputType.emailAddress,
            validator: Validators.validateEmail,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
          ),
          AppGap.lg(context),
          
          AppButton(
            text: 'Send Reset Link',
            onPressed: _submit,
          ),
          const Spacer(),
          
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text(
                'Back to Sign In',
                style: AppTextStyles.labelMedium(context).copyWith(color: AppColors.primary),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSuccessState() {
    final double iconBoxSize = context.scaleWidth(80.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Spacer(),
        // Animated check indicator container
        Container(
          width: iconBoxSize,
          height: iconBoxSize,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.success.withValues(alpha: 0.3), width: 1.5),
          ),
          child: Center(
            child: Icon(
              Icons.mark_email_read_outlined,
              size: AppIconSizes.lg(context) * 1.25,
              color: AppColors.success,
            ),
          ),
        ),
        AppGap.md(context),
        Text(
          'Email Sent!',
          style: AppTextStyles.displayMedium(context),
        ),
        AppGap.sm(context),
        Text(
          'We have sent a secure password reset link to your email address: ${_emailController.text}. Please check your spam folder if you do not receive it shortly.',
          style: AppTextStyles.bodyLarge(context),
          textAlign: TextAlign.center,
        ),
        const Spacer(),
        AppButton(
          text: 'Back to Login',
          onPressed: () {
            Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (route) => false);
          },
        ),
      ],
    );
  }
}
