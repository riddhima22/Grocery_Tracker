import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/recipe_provider.dart';
import '../../kitchen/providers/kitchen_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../config/app_radius.dart';
import '../../../config/app_icon_sizes.dart';
import '../../../config/app_text_styles.dart';
import '../../../config/app_routes.dart';
import '../../../config/recipe_icon_mapper.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_retry_state.dart';
import '../../../core/extensions/responsive_context_extension.dart';

class RecipesView extends StatefulWidget {
  final bool initialExpiringOnly;

  const RecipesView({super.key, this.initialExpiringOnly = false});

  @override
  State<RecipesView> createState() => _RecipesViewState();
}

class _RecipesViewState extends State<RecipesView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RecipeProvider>().fetchRecipes();
      if (widget.initialExpiringOnly && mounted) {
        _showZeroWasteGeneratorSheet(context, defaultExpiringOnly: true);
      }
    });
  }

  void _showZeroWasteGeneratorSheet(BuildContext context, {bool defaultExpiringOnly = false}) {
    final authUser = context.read<AuthProvider>().user;
    final initialAllergies = Set<String>.from(authUser?.allergies ?? []);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _ZeroWasteGeneratorModal(
          initialExpiringOnly: defaultExpiringOnly,
          initialAllergies: initialAllergies,
          initialDiet: authUser?.dietType ?? 'any',
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final recipe = context.watch<RecipeProvider>();
    final kitchen = context.watch<KitchenProvider>();

    return AppScaffold(
      isLoading: recipe.isLoading,
      appBar: AppBar(
        title: Text(
          'Smart Recipes',
          style: TextStyle(
            fontFamily: 'Outfit',
            fontWeight: FontWeight.bold,
            fontSize: context.scaleFont(20.0),
          ),
        ),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: AppColors.primary),
            tooltip: 'Zero-Waste Chef',
            onPressed: () => _showZeroWasteGeneratorSheet(context, defaultExpiringOnly: true),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showZeroWasteGeneratorSheet(context, defaultExpiringOnly: true),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.auto_awesome, color: Colors.white),
        label: Text(
          'Zero-Waste Chef',
          style: TextStyle(
            fontFamily: 'Outfit',
            fontWeight: FontWeight.bold,
            fontSize: context.scaleFont(13.0),
            color: Colors.white,
          ),
        ),
      ),
      body: recipe.errorMessage != null
          ? AppRetryState(
              errorMessage: recipe.errorMessage!,
              onRetry: () => recipe.fetchRecipes(),
            )
          : Column(
              children: [
                // Top Zero-Waste Expiring Items Notice Bar
                _buildZeroWasteNotice(context),

                // Filter Tab Bar
                _buildFiltersBar(recipe),
                const Divider(),

                // Recipe List
                Expanded(
                  child: recipe.recipes.isEmpty
                      ? _buildEmptyState(recipe, kitchen)
                      : ListView.builder(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.md(context),
                            vertical: AppSpacing.sm(context),
                          ),
                          itemCount: recipe.recipes.length,
                          itemBuilder: (ctx, index) {
                            final r = recipe.recipes[index];
                            return _buildRecipeCard(r);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildZeroWasteNotice(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: AppSpacing.md(context),
        vertical: AppSpacing.xs(context),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.md(context),
        vertical: AppSpacing.xs(context),
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card(context) * 0.75),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.eco_rounded, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Zero-Waste AI: Cooks near-expiry food with 0 extra shopping materials.',
              style: AppTextStyles.caption(context).copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _showZeroWasteGeneratorSheet(context, defaultExpiringOnly: true),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              'Cook Now',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontWeight: FontWeight.bold,
                fontSize: context.scaleFont(12.0),
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersBar(RecipeProvider provider) {
    final filters = [
      {'key': 'all', 'label': 'All Recipes'},
      {'key': 'veg', 'label': 'Vegetarian'},
      {'key': 'non-veg', 'label': 'Meat/Fish'},
      {'key': 'quick', 'label': 'Quick (<30m)'},
    ];

    return SizedBox(
      height: context.scaleHeight(48.0),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm(context)),
        itemCount: filters.length,
        itemBuilder: (ctx, index) {
          final f = filters[index];
          final isSelected = provider.filter == f['key'];
          return GestureDetector(
            onTap: () => provider.setFilter(f['key']!),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 8.0),
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 4.0),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.chip(context) * 2.0),
                border: Border.all(color: isSelected ? AppColors.primary : AppColors.cardBorder),
              ),
              child: Center(
                child: Text(
                  f['label']!,
                  style: AppTextStyles.labelMedium(context).copyWith(
                    color: isSelected ? AppColors.white : AppColors.textPrimary,
                    fontSize: context.scaleFont(12.0),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecipeCard(dynamic r) {
    // Check if recipe needs no extra grocery purchases (strict zero-waste)
    final bool isZeroWaste = r.otherIngredients.isEmpty ||
        r.otherIngredients.every((i) {
          final name = i.toString().toLowerCase();
          return name.contains('salt') ||
              name.contains('water') ||
              name.contains('oil') ||
              name.contains('pepper') ||
              name.contains('sugar');
        });

    return Card(
      color: AppColors.card,
      margin: EdgeInsets.symmetric(vertical: AppSpacing.xxs(context)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card(context)),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(context, AppRoutes.recipeDetail, arguments: r);
        },
        borderRadius: BorderRadius.circular(AppRadius.card(context)),
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.sm(context)),
          child: Row(
            children: [
              // Recipe Icon Box
              Container(
                width: context.scaleWidth(56.0),
                height: context.scaleWidth(56.0),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.card(context) * 0.75),
                ),
                child: Center(
                  child: Icon(
                    RecipeIconMapper.fromKey(r.iconKey),
                    size: AppIconSizes.md(context),
                    color: AppColors.primary,
                  ),
                ),
              ),
              AppGap.sm(context),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      style: AppTextStyles.headingMedium(context).copyWith(fontSize: context.scaleFont(16.0)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6.0,
                      runSpacing: 4.0,
                      children: [
                        Text(
                          '${r.prepTimeMins} mins',
                          style: AppTextStyles.caption(context).copyWith(color: AppColors.textSecondary),
                        ),
                        Text(
                          '${r.caloriesPerServing} kcal',
                          style: AppTextStyles.caption(context).copyWith(color: AppColors.textSecondary),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 2.0),
                          decoration: BoxDecoration(
                            color: r.dietType.toLowerCase() == 'veg'
                                ? AppColors.success.withValues(alpha: 0.1)
                                : AppColors.danger.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4.0),
                          ),
                          child: Text(
                            r.dietType.toUpperCase(),
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: context.scaleFont(8.0),
                              color: r.dietType.toLowerCase() == 'veg' ? AppColors.success : AppColors.danger,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isZeroWaste)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 2.0),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4.0),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.eco_rounded, size: 9, color: AppColors.primary),
                                SizedBox(width: 2),
                                Text(
                                  'ZERO-WASTE',
                                  style: TextStyle(
                                    fontFamily: 'Outfit',
                                    fontSize: 8.0,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: AppIconSizes.sm(context) * 0.8, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(RecipeProvider recipe, KitchenProvider kitchen) {
    final bool hasKitchenItems = kitchen.items.isNotEmpty;

    return Padding(
      padding: EdgeInsets.all(AppSpacing.xl(context)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.soup_kitchen_rounded,
            size: AppIconSizes.lg(context) * 2.0,
            color: AppColors.textSecondary,
          ),
          AppGap.md(context),
          Text(
            'No Recipes Yet',
            style: AppTextStyles.headingMedium(context),
          ),
          AppGap.xs(context),
          Text(
            hasKitchenItems
                ? 'Generate delicious zero-waste recipes using ingredients already in your kitchen.'
                : 'Add groceries to your kitchen to enable zero-waste recipe generation.',
            style: AppTextStyles.bodyMedium(context),
            textAlign: TextAlign.center,
          ),
          AppGap.lg(context),
          if (hasKitchenItems)
            SizedBox(
              width: context.scaleWidth(240.0),
              child: AppButton(
                text: 'Zero-Waste Chef',
                onPressed: () => _showZeroWasteGeneratorSheet(context, defaultExpiringOnly: true),
              ),
            ),
        ],
      ),
    );
  }
}

class _ZeroWasteGeneratorModal extends StatefulWidget {
  final bool initialExpiringOnly;
  final Set<String> initialAllergies;
  final String initialDiet;

  const _ZeroWasteGeneratorModal({
    required this.initialExpiringOnly,
    required this.initialAllergies,
    required this.initialDiet,
  });

  @override
  State<_ZeroWasteGeneratorModal> createState() => _ZeroWasteGeneratorModalState();
}

class _ZeroWasteGeneratorModalState extends State<_ZeroWasteGeneratorModal> {
  late bool _expiringOnly;
  bool _strictPantryOnly = true;
  String _selectedFitness = 'High Protein';
  late String _selectedDiet;
  late Set<String> _selectedAllergies;
  bool _isGenerating = false;

  final List<String> _fitnessOptions = [
    'High Protein',
    'Low Calorie',
    'Muscle Gain',
    'Keto / Low Carb',
    'Balanced',
  ];

  final List<String> _allergyOptions = [
    'Dairy',
    'Gluten',
    'Peanuts',
    'Tree Nuts',
    'Eggs',
    'Soy',
    'Shellfish',
  ];

  @override
  void initState() {
    super.initState();
    _expiringOnly = widget.initialExpiringOnly;
    _selectedDiet = widget.initialDiet;
    _selectedAllergies = Set<String>.from(widget.initialAllergies);
  }

  Future<void> _generate() async {
    setState(() {
      _isGenerating = true;
    });

    final provider = context.read<RecipeProvider>();
    final success = await provider.generateNewRecipes(
      preferences: {
        'expiring_only': _expiringOnly,
        'strict_pantry_only': _strictPantryOnly,
        'fitness_goal': _selectedFitness,
        'allergies': _selectedAllergies.toList(),
        'diet_type': _selectedDiet,
      },
    );

    if (!mounted) return;
    setState(() {
      _isGenerating = false;
    });

    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Zero-waste recipes generated successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Failed to generate recipes. Please try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle Bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Modal Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.soup_kitchen_rounded, color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Zero-Waste Chef Studio',
                        style: AppTextStyles.headingSmall(context).copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Cook with what you have. No extra materials needed!',
                        style: AppTextStyles.caption(context).copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),

            // 1. Zero-Waste Constraints Toggles
            Text('Kitchen Sourcing Rules', style: AppTextStyles.labelLarge(context).copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Prioritize Expiring Groceries'),
              subtitle: const Text('Rescues items expiring soonest first to eliminate waste.'),
              value: _expiringOnly,
              activeThumbColor: AppColors.primary,
              onChanged: (val) => setState(() => _expiringOnly = val),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Strict Kitchen Only (No extra shopping)'),
              subtitle: const Text('Uses strictly what is in your kitchen (only salt/water/oil assumed).'),
              value: _strictPantryOnly,
              activeThumbColor: AppColors.primary,
              onChanged: (val) => setState(() => _strictPantryOnly = val),
            ),
            const SizedBox(height: 12),

            // 2. Fitness Goal Choice
            Text('Fitness & Nutrition Goal', style: AppTextStyles.labelLarge(context).copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _fitnessOptions.map((goal) {
                final isSelected = _selectedFitness == goal;
                return ChoiceChip(
                  label: Text(goal),
                  selected: isSelected,
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedFitness = goal);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // 3. Allergy Protection Choice
            Text('Strict Allergy Filter (Never include)', style: AppTextStyles.labelLarge(context).copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allergyOptions.map((allergy) {
                final isSelected = _selectedAllergies.contains(allergy.toLowerCase()) ||
                    _selectedAllergies.contains(allergy);
                return FilterChip(
                  label: Text(allergy),
                  selected: isSelected,
                  selectedColor: AppColors.danger.withValues(alpha: 0.15),
                  checkmarkColor: AppColors.danger,
                  labelStyle: TextStyle(
                    color: isSelected ? AppColors.danger : AppColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedAllergies.add(allergy.toLowerCase());
                      } else {
                        _selectedAllergies.remove(allergy.toLowerCase());
                        _selectedAllergies.remove(allergy);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // 4. Diet Choice
            Text('Diet Preference', style: AppTextStyles.labelLarge(context).copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildDietChoice('veg', 'Vegetarian'),
                const SizedBox(width: 8),
                _buildDietChoice('non-veg', 'Non-Veg'),
                const SizedBox(width: 8),
                _buildDietChoice('any', 'Any Diet'),
              ],
            ),
            const SizedBox(height: 24),

            // Action Button
            AppButton(
              text: 'Generate Zero-Waste Recipes',
              isLoading: _isGenerating,
              onPressed: _generate,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDietChoice(String key, String label) {
    final isSelected = _selectedDiet == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedDiet = key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? AppColors.primary : AppColors.cardBorder),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 12,
                color: isSelected ? Colors.white : AppColors.textPrimary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
