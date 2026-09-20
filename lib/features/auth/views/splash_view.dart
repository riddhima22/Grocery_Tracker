import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import '../providers/auth_provider.dart';
import '../../onboarding/providers/onboarding_provider.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../config/app_radius.dart';
import '../../../config/app_icon_sizes.dart';
import '../../../config/app_text_styles.dart';
import '../../../config/app_routes.dart';
import '../../../config/app_pages.dart';
import '../../../core/extensions/responsive_context_extension.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotationAnim;
  late Animation<double> _pulseAnim;
  late Animation<double> _particleAnim;
  late List<Offset> _particlePositions;

  @override
  void initState() {
    super.initState();

    // Single controller drives all animations for better performance
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    // Derived animations from the single controller
    _rotationAnim = _controller; // Full rotation over 4s
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeInOut),
      ),
    );
    _particleAnim = _controller;

    final random = math.Random();
    _particlePositions = List.generate(
      4, // Reduced from 7 to 4 for better performance
      (index) => Offset(
        random.nextDouble() * 240.0 - 120.0,
        random.nextDouble() * 400.0 - 200.0,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initAndNavigate();
    });
  }

  Future<void> _initAndNavigate() async {
    final auth = context.read<AuthProvider>();
    final onboarding = context.read<OnboardingProvider>();

    await Future.wait([
      auth.checkAuthStatus(),
      onboarding.checkOnboardingStatus(),
      Future.delayed(const Duration(milliseconds: 200)),
    ]);

    if (!mounted) return;

    // Stop animation before navigating to prevent jank during transition
    _controller.stop();

    String targetRoute;
    if (!onboarding.onboardingComplete) {
      targetRoute = AppRoutes.onboarding;
    } else if (auth.isAuthenticated) {
      if (auth.state == AuthState.unverified) {
        targetRoute = AppRoutes.verifyEmail;
      } else {
        targetRoute = AppRoutes.home;
      }
    } else {
      targetRoute = AppRoutes.login;
    }

    // Use a fast, smooth fade transition for instant navigation
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) {
          // Build the target page from the route map
          final builder = _getRouteBuilder(targetRoute);
          return builder(context);
        },
        transitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        settings: RouteSettings(name: targetRoute),
      ),
    );
  }

  /// Resolve a route name to its builder to enable custom page transitions
  WidgetBuilder _getRouteBuilder(String route) {
    final routes = AppPages.routes;
    if (routes.containsKey(route)) {
      return routes[route]!;
    }
    // Fallback: just push named (shouldn't happen)
    return (context) => const SizedBox.shrink();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double centerLogoBoxSize = context.scaleWidth(200.0);
    final double ringSizeBase = context.scaleWidth(140.0);
    final double innerRingSizeBase = context.scaleWidth(100.0);
    final double logoContainerSize = context.scaleWidth(70.0);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.splashGradient,
        ),
        child: Stack(
          children: [
            // Floating green particles with RepaintBoundary for isolation
            RepaintBoundary(
              child: Stack(
                children: List.generate(4, (index) {
                  return AnimatedBuilder(
                    animation: _particleAnim,
                    builder: (context, child) {
                      final phase = (index * 2 * math.pi / 4);
                      final offset = math.sin(_particleAnim.value * 2 * math.pi + phase) * 15.0;
                      return Positioned(
                        left: context.screenSize.width / 2.0 + _particlePositions[index].dx,
                        top: context.screenSize.height / 2.0 + _particlePositions[index].dy + offset,
                        child: Container(
                          width: 6.0 + (index % 3) * 2.0,
                          height: 6.0 + (index % 3) * 2.0,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.3 + (index % 3) * 0.15),
                            shape: BoxShape.circle,
                          ),
                        ),
                      );
                    },
                  );
                }),
              ),
            ),

            // Center logo and text
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated Pulsing Rings & Rotating Logo
                  SizedBox(
                    width: centerLogoBoxSize,
                    height: centerLogoBoxSize,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer Pulsing Ring
                        AnimatedBuilder(
                          animation: _pulseAnim,
                          builder: (context, child) {
                            final pulseVal = (math.sin(_controller.value * 2 * math.pi) + 1) / 2;
                            return Container(
                              width: ringSizeBase + (pulseVal * context.scaleWidth(40.0)),
                              height: ringSizeBase + (pulseVal * context.scaleWidth(40.0)),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary.withValues(alpha: 0.15 * (1.0 - pulseVal)),
                                  width: 2.0,
                                ),
                              ),
                            );
                          },
                        ),
                        // Inner Pulsing Ring
                        AnimatedBuilder(
                          animation: _pulseAnim,
                          builder: (context, child) {
                            final pulseVal = (math.sin(_controller.value * 2 * math.pi) + 1) / 2;
                            return Container(
                              width: innerRingSizeBase + (pulseVal * context.scaleWidth(25.0)),
                              height: innerRingSizeBase + (pulseVal * context.scaleWidth(25.0)),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary.withValues(alpha: 0.3 * (1.0 - pulseVal)),
                                  width: 1.5,
                                ),
                              ),
                            );
                          },
                        ),
                        // Rotating 3D Logo (Eco Icon)
                        AnimatedBuilder(
                          animation: _rotationAnim,
                          builder: (context, child) {
                            final double angle = _rotationAnim.value * 2 * math.pi;
                            return Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.002) // perspective mapping
                                ..rotateY(angle)
                                ..rotateX(0.15),
                              child: Container(
                                width: logoContainerSize,
                                height: logoContainerSize,
                                decoration: BoxDecoration(
                                  gradient: AppColors.primaryGradient,
                                  borderRadius: BorderRadius.circular(AppRadius.card(context)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(alpha: 0.4),
                                      blurRadius: 16,
                                      offset: const Offset(0, 8),
                                    )
                                  ],
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.eco_rounded,
                                    size: AppIconSizes.lg(context) * 1.25,
                                    color: AppColors.white,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  AppGap.lg(context),
                  
                  // Wordmark
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'Fresh',
                          style: AppTextStyles.displayLarge(context).copyWith(color: AppColors.white),
                        ),
                        TextSpan(
                          text: 'Track',
                          style: AppTextStyles.displayLarge(context).copyWith(color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                  AppGap.xs(context),
                  
                  // Subtitle
                  Text(
                    'Smart Grocery Intelligence',
                    style: AppTextStyles.bodyMedium(context).copyWith(
                      color: AppColors.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  AppGap.xl(context),

                  // Three loading dots
                  const _LoadingDots(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingDots extends StatefulWidget {
  const _LoadingDots();

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _animations = List.generate(3, (index) {
      final start = index * 0.2;
      final end = start + 0.6;
      return TweenSequence([
        TweenSequenceItem(
          tween: Tween<double>(begin: 0.0, end: -8.0).chain(CurveTween(curve: Curves.easeOut)),
          weight: 50,
        ),
        TweenSequenceItem(
          tween: Tween<double>(begin: -8.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
          weight: 50,
        ),
      ]).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(start, end.clamp(0.0, 1.0), curve: Curves.linear),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _animations[index],
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, _animations[index].value),
              child: Container(
                margin: EdgeInsets.symmetric(horizontal: AppSpacing.xxs(context)),
                width: 7.0,
                height: 7.0,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
