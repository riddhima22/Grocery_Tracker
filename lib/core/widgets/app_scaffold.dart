import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import 'app_loading_overlay.dart';

class AppScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool isLoading;
  final String? loadingMessage;
  final bool useSplashBg;

  const AppScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.isLoading = false,
    this.loadingMessage,
    this.useSplashBg = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      body: Container(
        decoration: BoxDecoration(
          gradient: useSplashBg
              ? AppColors.splashGradient
              : AppColors.bgGradient,
        ),
        child: AppLoadingOverlay(
          isLoading: isLoading,
          message: loadingMessage,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Only center and constrain width on wider screens (tablets/desktop).
                // On phones, let content use the full width to avoid wasted space.
                if (constraints.maxWidth > 600.0) {
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600.0),
                      child: body,
                    ),
                  );
                }
                return body;
              },
            ),
          ),
        ),
      ),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }
}
