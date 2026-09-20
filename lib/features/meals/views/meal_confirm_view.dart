import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../config/app_radius.dart';
import '../../../config/app_text_styles.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../providers/meal_provider.dart';

class MealConfirmView extends StatelessWidget {
  const MealConfirmView({super.key});

  void _confirmAndDeduct(BuildContext context) async {
    final provider = context.read<MealProvider>();
    final success = await provider.confirmDeduction();
    
    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Meal logged and pantry updated!'), backgroundColor: AppColors.success),
      );
      Navigator.pop(context);
    } else if (context.mounted && provider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.errorMessage!), backgroundColor: AppColors.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MealProvider>();
    final mealLog = provider.currentMealLog;
    final isLoading = provider.uiState == MealUIState.analyzing;

    if (mealLog == null) {
      return const AppScaffold(body: Center(child: Text('No meal data available.')));
    }

    return AppScaffold(
      appBar: AppBar(
        title: const Text('Confirm Ingredients'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.all(AppSpacing.md(context)),
              itemCount: mealLog.candidates.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      'We detected these ingredients in your meal. Review and adjust quantities to deduct from your pantry.',
                      style: AppTextStyles.bodyMedium(context).copyWith(color: AppColors.textSecondary),
                    ),
                  );
                }
                final candidate = mealLog.candidates[index - 1];
                final editData = provider.deductionEdits[candidate.id] ?? {};
                final isConfirmed = editData['confirmed'] ?? candidate.confirmed;
                final quantity = editData['quantity'] ?? candidate.deductQuantity;
                
                final isMatched = candidate.pantryItemId != null;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: AppColors.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card(context)),
                    side: const BorderSide(color: AppColors.cardBorder),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: isConfirmed,
                              onChanged: (val) {
                                if (val != null) {
                                  provider.updateCandidateConfirmation(candidate.id, val);
                                }
                              },
                              activeColor: AppColors.primary,
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    candidate.name,
                                    style: AppTextStyles.labelLarge(context).copyWith(
                                      decoration: !isConfirmed ? TextDecoration.lineThrough : null,
                                      color: !isConfirmed ? AppColors.textSecondary : AppColors.textPrimary,
                                    ),
                                  ),
                                  if (isMatched)
                                    Text(
                                      'Matched with Pantry Item',
                                      style: AppTextStyles.caption(context).copyWith(color: AppColors.success),
                                    )
                                  else
                                    Text(
                                      'Not found in pantry',
                                      style: AppTextStyles.caption(context).copyWith(color: AppColors.warning),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (isConfirmed && isMatched) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text('Quantity (${candidate.unit}):', style: AppTextStyles.bodyMedium(context)),
                              const SizedBox(width: 16),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: AppColors.primary),
                                onPressed: quantity > 0.5 
                                    ? () => provider.updateCandidateQuantity(candidate.id, quantity - 0.5)
                                    : null,
                              ),
                              Text(
                                quantity.toStringAsFixed(1),
                                style: AppTextStyles.labelLarge(context),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                                onPressed: () => provider.updateCandidateQuantity(candidate.id, quantity + 0.5),
                              ),
                            ],
                          ),
                        ]
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.md(context)),
              child: ElevatedButton(
                onPressed: isLoading ? null : () => _confirmAndDeduct(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card(context)),
                  ),
                ),
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        'Confirm & Deduct Pantry',
                        style: AppTextStyles.labelLarge(context).copyWith(color: Colors.white),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
