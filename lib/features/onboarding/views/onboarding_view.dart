import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../providers/onboarding_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/services/permission_service.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../config/app_radius.dart';
import '../../../config/app_icon_sizes.dart';
import '../../../config/app_text_styles.dart';
import '../../../config/app_routes.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/extensions/responsive_context_extension.dart';

class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key});

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  final List<Map<String, dynamic>> _pages = [
    {
      'icon': Icons.eco_rounded,
      'title': 'Never waste groceries again',
      'desc': 'Track your groceries and know what to use before it expires.',
    },
    {
      'icon': Icons.ac_unit_rounded,
      'title': 'Smart storage guidance',
      'desc':
          'Know where every grocery item belongs and help it stay fresh longer.',
    },
    {
      'icon': Icons.restaurant_rounded,
      'title': 'Recipes from what you have',
      'desc': 'Turn groceries already in your kitchen into useful meal ideas.',
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _onFinish() async {
    final onboarding = context.read<OnboardingProvider>();
    final auth = context.read<AuthProvider>();

    // Request notification permission with simple explanation
    await _showNotificationExplainer();

    await onboarding.completeOnboarding();
    if (mounted) {
      if (auth.isAuthenticated) {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      } else {
        Navigator.pushReplacementNamed(context, AppRoutes.login);
      }
    }
  }

  Future<void> _showNotificationExplainer() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card(ctx)),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        title: Text(
          'Stay Fresh Alerts',
          style: AppTextStyles.headingMedium(
            ctx,
          ).copyWith(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'FreshTrack needs push notifications permission to alert you before your groceries expire, helping you reduce food waste.',
          style: AppTextStyles.bodyMedium(
            ctx,
          ).copyWith(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
            },
            child: Text(
              'Not Now',
              style: AppTextStyles.labelMedium(
                ctx,
              ).copyWith(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await PermissionService().requestNotificationPermission();
            },
            child: Text(
              'Allow Alerts',
              style: AppTextStyles.labelMedium(
                ctx,
              ).copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double imageBoxSize = context.scaleWidth(140.0);

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.md(context)),
                child: _currentIndex == _pages.length - 1
                    ? SizedBox(height: context.scaleHeight(48.0))
                    : TextButton(
                        onPressed: _onFinish,
                        child: Text(
                          'Skip',
                          style: AppTextStyles.labelMedium(
                            context,
                          ).copyWith(color: AppColors.textSecondary),
                        ),
                      ),
              ),
            ),

            // Slider Content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  final p = _pages[index];
                  final IconData pageIcon = p['icon'] as IconData;

                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl(context),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Animated Floater Icon (replaces emoji circle)
                        Container(
                          width: imageBoxSize,
                          height: imageBoxSize,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.cardBorder),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(
                                  alpha: 0.08,
                                ),
                                blurRadius: 24,
                                spreadRadius: 8,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              pageIcon,
                              size: AppIconSizes.lg(context) * 2.0,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        AppGap.xl(context),
                        Text(
                          p['title'] as String,
                          style: AppTextStyles.displayMedium(context),
                          textAlign: TextAlign.center,
                        ),
                        AppGap.md(context),
                        Text(
                          p['desc'] as String,
                          style: AppTextStyles.bodyLarge(
                            context,
                          ).copyWith(color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Indicator and Buttons
            Padding(
              padding: EdgeInsets.all(AppSpacing.xl(context)),
              child: Column(
                children: [
                  SmoothPageIndicator(
                    controller: _pageController,
                    count: _pages.length,
                    effect: const ExpandingDotsEffect(
                      activeDotColor: AppColors.primary,
                      dotColor: AppColors.cardBorder,
                      dotHeight: 8.0,
                      dotWidth: 8.0,
                      expansionFactor: 3.0,
                    ),
                  ),
                  AppGap.xl(context),
                  AppButton(
                    text: _currentIndex == _pages.length - 1
                        ? 'Get Started'
                        : 'Continue',
                    onPressed: () {
                      if (_currentIndex == _pages.length - 1) {
                        _onFinish();
                      } else {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
