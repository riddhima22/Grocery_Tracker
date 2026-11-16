import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/recipe_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../data/models/recipe_model.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../config/app_radius.dart';
import '../../../config/app_icon_sizes.dart';
import '../../../config/app_text_styles.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/extensions/responsive_context_extension.dart';

class RecipeDetailView extends StatefulWidget {
  final RecipeModel recipe;

  const RecipeDetailView({super.key, required this.recipe});

  @override
  State<RecipeDetailView> createState() => _RecipeDetailViewState();
}

class _RecipeDetailViewState extends State<RecipeDetailView> {
  final Set<int> _checkedSteps = {};

  void _toggleStep(int index) {
    setState(() {
      if (_checkedSteps.contains(index)) {
        _checkedSteps.remove(index);
      } else {
        _checkedSteps.add(index);
      }
    });
  }

  Future<void> _markCooked() async {
    final success = await context.read<RecipeProvider>().markAsCooked(
      widget.recipe.id,
    );
    if (success && mounted) {
      // Re-fetch profile to sync cooked count stats
      context.read<AuthProvider>().checkAuthStatus();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cook logged! Great job preparing ${widget.recipe.name}.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(
        title: Text(
          widget.recipe.name,
          style: TextStyle(
            fontFamily: 'Outfit',
            fontWeight: FontWeight.bold,
            fontSize: context.scaleFont(20.0),
          ),
        ),
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.pageHorizontal(context),
            vertical: AppSpacing.pageVertical(context),
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header stats block
                _buildStatsHeader(),
                AppGap.md(context),

                // Allergen Warning banner
                if (widget.recipe.allergenWarning.isNotEmpty) ...[
                  _buildAllergenBanner(),
                  AppGap.md(context),
                ],

                // Ingredients
                Text(
                  'Ingredients Used',
                  style: AppTextStyles.headingMedium(context),
                ),
                AppGap.xs(context),
                _buildIngredientsList(),
                AppGap.md(context),

                // Other ingredients needed
                if (widget.recipe.otherIngredients.isNotEmpty) ...[
                  Text(
                    'Other Needed Ingredients',
                    style: AppTextStyles.headingMedium(context),
                  ),
                  AppGap.xs(context),
                  _buildOtherIngredientsList(),
                  AppGap.md(context),
                ] else ...[
                  Container(
                    padding: EdgeInsets.all(AppSpacing.sm(context)),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(
                        AppRadius.card(context) * 0.75,
                      ),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '100% Zero-Waste: All ingredients are available in your kitchen! No extra shopping needed.',
                            style: AppTextStyles.caption(context).copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AppGap.md(context),
                ],

                // Chef Tip & Fitness Highlight
                if (widget.recipe.tip.isNotEmpty) ...[
                  Container(
                    padding: EdgeInsets.all(AppSpacing.sm(context)),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(
                        AppRadius.card(context) * 0.75,
                      ),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.tips_and_updates_outlined,
                          color: AppColors.warning,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Chef & Fitness Tip',
                                style: AppTextStyles.labelMedium(context)
                                    .copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.warning,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.recipe.tip,
                                style: AppTextStyles.bodyMedium(context),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  AppGap.md(context),
                ],

                // Steps
                Text(
                  'Preparation Steps',
                  style: AppTextStyles.headingMedium(context),
                ),
                AppGap.sm(context),
                _buildStepsList(),
                AppGap.lg(context),

                // Mark cooked button
                AppButton(text: 'Mark Cooked', onPressed: _markCooked),
                AppGap.lg(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        Expanded(
          child: _buildStatItem(
            'Prep Time',
            '${widget.recipe.prepTimeMins} mins',
            Icons.timer_outlined,
          ),
        ),
        const SizedBox(width: 8.0),
        Expanded(
          child: _buildStatItem(
            'Calories',
            '${widget.recipe.caloriesPerServing} kcal',
            Icons.local_fire_department_outlined,
          ),
        ),
        const SizedBox(width: 8.0),
        Expanded(
          child: _buildStatItem(
            'Servings',
            '${widget.recipe.servings} portions',
            Icons.restaurant_outlined,
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.sm(context),
        vertical: AppSpacing.xs(context),
      ),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card(context) * 0.75),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: AppIconSizes.sm(context),
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4.0),
              Text(
                label,
                style: AppTextStyles.caption(
                  context,
                ).copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 4.0),
          Text(
            value,
            style: AppTextStyles.labelMedium(
              context,
            ).copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildAllergenBanner() {
    return Container(
      padding: EdgeInsets.all(AppSpacing.sm(context)),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.card(context) * 0.75),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: AppColors.danger,
            size: AppIconSizes.md(context),
          ),
          AppGap.sm(context),
          Expanded(
            child: Text(
              widget.recipe.allergenWarning,
              style: AppTextStyles.bodyMedium(
                context,
              ).copyWith(color: AppColors.danger, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIngredientsList() {
    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      children: widget.recipe.ingredientsUsed.map((i) {
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: context.scaleWidth(12.0),
            vertical: context.scaleHeight(6.0),
          ),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.chip(context)),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Text(
            '✓ $i',
            style: AppTextStyles.bodyMedium(
              context,
            ).copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildOtherIngredientsList() {
    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      children: widget.recipe.otherIngredients.map((i) {
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: context.scaleWidth(12.0),
            vertical: context.scaleHeight(6.0),
          ),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.chip(context)),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Text(
            '+ $i',
            style: AppTextStyles.bodyMedium(
              context,
            ).copyWith(color: AppColors.textSecondary),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStepsList() {
    return Column(
      children: List.generate(widget.recipe.steps.length, (index) {
        final step = widget.recipe.steps[index];
        final isChecked = _checkedSteps.contains(index);

        return Card(
          color: isChecked
              ? AppColors.card.withValues(alpha: 0.4)
              : AppColors.card,
          margin: EdgeInsets.symmetric(vertical: AppSpacing.xxs(context)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card(context) * 0.75),
            side: BorderSide(
              color: isChecked
                  ? AppColors.cardBorder.withValues(alpha: 0.5)
                  : AppColors.cardBorder,
            ),
          ),
          child: ListTile(
            leading: CircleAvatar(
              radius: 12.0,
              backgroundColor: isChecked
                  ? AppColors.primary.withValues(alpha: 0.2)
                  : AppColors.surface,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: context.scaleFont(11.0),
                  color: isChecked ? AppColors.primary : AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              step,
              style: AppTextStyles.bodyMedium(context).copyWith(
                decoration: isChecked ? TextDecoration.lineThrough : null,
                color: isChecked ? AppColors.textHint : AppColors.textPrimary,
              ),
            ),
            trailing: Checkbox(
              value: isChecked,
              onChanged: (_) => _toggleStep(index),
              activeColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4.0),
              ),
            ),
          ),
        );
      }),
    );
  }
}
