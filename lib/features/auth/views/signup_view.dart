import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../config/app_constraints.dart';
import '../../../config/app_text_styles.dart';
import '../../../config/app_routes.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_error_banner.dart';
import '../../../core/utils/validators.dart';

class SignupView extends StatefulWidget {
  const SignupView({super.key});

  @override
  State<SignupView> createState() => _SignupViewState();
}

class _SignupViewState extends State<SignupView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  String _passwordStrength = '';
  Color _strengthColor = AppColors.danger;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_checkPasswordStrength);
  }

  @override
  void dispose() {
    _passwordController.removeListener(_checkPasswordStrength);
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _checkPasswordStrength() {
    final pwd = _passwordController.text;
    if (pwd.isEmpty) {
      setState(() {
        _passwordStrength = '';
      });
      return;
    }

    int score = 0;
    if (pwd.length >= 8) score++;
    if (pwd.contains(RegExp(r'[A-Z]'))) score++;
    if (pwd.contains(RegExp(r'[a-z]'))) score++;
    if (pwd.contains(RegExp(r'[0-9]'))) score++;
    if (pwd.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) score++;

    setState(() {
      if (score <= 2) {
        _passwordStrength = 'Weak';
        _strengthColor = AppColors.danger;
      } else if (score == 3) {
        _passwordStrength = 'Fair';
        _strengthColor = AppColors.warning;
      } else if (score == 4) {
        _passwordStrength = 'Good';
        _strengthColor = AppColors.info;
      } else {
        _passwordStrength = 'Strong';
        _strengthColor = AppColors.success;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match.')),
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    final success = await auth.register(
      _emailController.text,
      _passwordController.text,
      _nameController.text,
    );

    if (success && mounted) {
      Navigator.pushReplacementNamed(context, AppRoutes.verifyEmail);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

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
                  Center(
                    child: Text(
                      'Create Account',
                      style: AppTextStyles.displayMedium(context),
                    ),
                  ),
                  AppGap.xs(context),
                  Center(
                    child: Text(
                      'Join FreshTrack and start conserving food',
                      style: AppTextStyles.bodyMedium(context),
                      textAlign: TextAlign.center,
                    ),
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
                    controller: _nameController,
                    label: 'Full Name',
                    hint: 'e.g. John Doe',
                    validator: Validators.validateName,
                  ),
                  AppGap.sm(context),
                  AppTextField(
                    controller: _emailController,
                    label: 'Email Address',
                    hint: 'e.g. name@email.com',
                    keyboardType: TextInputType.emailAddress,
                    validator: Validators.validateEmail,
                  ),
                  AppGap.sm(context),
                  AppTextField(
                    controller: _passwordController,
                    label: 'Password',
                    hint: 'Min 8 characters',
                    isPassword: true,
                    validator: Validators.validatePassword,
                  ),
                  
                  // Password Strength Indicator
                  if (_passwordStrength.isNotEmpty) ...[
                    AppGap.xs(context),
                    Row(
                      children: [
                        Text(
                          'Strength: ',
                          style: AppTextStyles.caption(context).copyWith(color: AppColors.textSecondary),
                        ),
                        Text(
                          _passwordStrength,
                          style: AppTextStyles.caption(context).copyWith(color: _strengthColor, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4.0),
                    Row(
                      children: List.generate(4, (index) {
                        bool active = false;
                        if (_passwordStrength == 'Weak' && index == 0) active = true;
                        if (_passwordStrength == 'Fair' && index <= 1) active = true;
                        if (_passwordStrength == 'Good' && index <= 2) active = true;
                        if (_passwordStrength == 'Strong') active = true;
                        
                        return Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2.0),
                            height: 4.0,
                            decoration: BoxDecoration(
                              color: active ? _strengthColor : AppColors.cardBorder,
                              borderRadius: BorderRadius.circular(2.0),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                  AppGap.sm(context),
                  AppTextField(
                    controller: _confirmPasswordController,
                    label: 'Confirm Password',
                    hint: 'Re-enter your password',
                    isPassword: true,
                    textInputAction: TextInputAction.done,
                    validator: (val) {
                      if (val == null || val.isEmpty) {
                        return 'Please confirm your password';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  AppGap.md(context),
                  
                  AppButton(
                    text: 'Create Account',
                    isLoading: auth.isLoading,
                    onPressed: auth.isLoading ? null : _submit,
                  ),
                  
                  AppGap.sm(context),
                  Center(
                    child: Text(
                      'By signing up, you agree to our Terms & Privacy Policy.',
                      style: AppTextStyles.caption(context),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  AppGap.lg(context),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Already have an account? ', style: AppTextStyles.bodyMedium(context)),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushNamed(context, AppRoutes.login);
                        },
                        child: Text(
                          'Sign In',
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
