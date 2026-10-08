import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/kitchen_provider.dart';
import '../../../data/models/grocery_model.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../config/app_spacing.dart';
import '../../../config/app_radius.dart';
import '../../../config/app_icon_sizes.dart';
import '../../../config/category_icon_mapper.dart';
import '../../../core/extensions/responsive_context_extension.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/services/ai_service.dart';
import '../../../core/utils/date_helpers.dart';

class KitchenItemDetailView extends StatefulWidget {
  final GroceryModel item;

  const KitchenItemDetailView({super.key, required this.item});

  @override
  State<KitchenItemDetailView> createState() => _KitchenItemDetailViewState();
}

class _KitchenItemDetailViewState extends State<KitchenItemDetailView> with SingleTickerProviderStateMixin {
  late GroceryModel _currentItem;
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;
  final IAIService _aiService = AIServiceImpl();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _currentItem = widget.item;

    _progressController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _progressAnimation = Tween<double>(
      begin: 0.0,
      end: _currentItem.freshnessScore / 100.0,
    ).animate(CurvedAnimation(parent: _progressController, curve: Curves.fastOutSlowIn));

    _progressController.forward();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  Color _getFreshnessColor(int score) {
    if (score >= 80) return AppColors.success;
    if (score >= 50) return const Color(0xFFFFA726); // Good/Orange
    if (score >= 25) return AppColors.warning;      // Use Soon/Amber
    return AppColors.danger;                         // Spoiled/Overripe
  }

  String _getFreshnessLabel(int score) {
    if (score >= 80) return 'Fresh';
    if (score >= 50) return 'Good';
    if (score >= 25) return 'Use Soon';
    return _currentItem.ripeness == 'overripe' ? 'Overripe' : 'Spoiled';
  }

  Future<void> _updateItemParameters({
    String? ripeness,
    bool? isOpened,
    double? temperature,
    double? humidity,
  }) async {
    setState(() => _isSaving = true);
    
    // 1. Calculate prediction from AI Service
    final updatedData = await _aiService.predictShelfLife({
      'category': _currentItem.category,
      'storage_zone': _currentItem.storageZone,
      'temperature': temperature ?? _currentItem.temperature,
      'humidity': humidity ?? _currentItem.humidity,
      'ripeness': ripeness ?? _currentItem.ripeness,
      'is_opened': isOpened ?? _currentItem.isOpened,
      'freshness_score': _currentItem.freshnessScore,
      'purchase_date': _currentItem.purchaseDate.toIso8601String().substring(0, 10),
    });

    if (!mounted) return;
    // 2. Save updates to database
    final kitchenProvider = context.read<KitchenProvider>();
    final success = await kitchenProvider.updateItem(
      _currentItem.id,
      {
        'ripeness': ripeness ?? _currentItem.ripeness,
        'is_opened': isOpened ?? _currentItem.isOpened,
        'temperature': temperature ?? _currentItem.temperature,
        'humidity': humidity ?? _currentItem.humidity,
        'expiry_date': updatedData['predicted_expiry'],
        'predicted_expiry': updatedData['predicted_expiry'],
        'recommended_consumption_date': updatedData['recommended_consumption_date'],
        'confidence_score': updatedData['confidence_score'] ?? 0.92,
        'storage_recommendation_why': updatedData['storage_recommendation_why'],
        'storage_recommendation_how': updatedData['storage_recommendation_how'],
        'storage_recommendation_shelf_life': updatedData['storage_recommendation_shelf_life'],
        'ai_explanation': updatedData['ai_explanation'],
      },
    );

    if (!mounted) return;
    if (success) {
      // Find the updated item in list
      final updatedItem = kitchenProvider.items.firstWhere((i) => i.id == _currentItem.id);
      setState(() {
        _currentItem = updatedItem;
        _isSaving = false;
        
        _progressAnimation = Tween<double>(
          begin: 0.0,
          end: _currentItem.freshnessScore / 100.0,
        ).animate(CurvedAnimation(parent: _progressController, curve: Curves.fastOutSlowIn));
        _progressController.reset();
        _progressController.forward();
      });
    } else {
      setState(() => _isSaving = false);
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => ConfirmDialog(
        title: 'Delete Item',
        content: 'Are you sure you want to delete ${_currentItem.name} from your pantry?',
        confirmLabel: 'Delete',
        cancelLabel: 'Cancel',
        isDestructive: true,
        onConfirm: () async {
          final success = await context.read<KitchenProvider>().deleteItem(_currentItem.id);
          if (success && mounted) {
            Navigator.pop(context); // Close details page
          }
        },
      ),
    );
  }

  Future<void> _consumeAll() async {
    final success = await context.read<KitchenProvider>().consumeItem(_currentItem.id);
    if (success && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _markWasted() async {
    final success = await context.read<KitchenProvider>().wasteItem(_currentItem.id);
    if (success && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double cardPadding = AppSpacing.md(context);
    final freshnessColor = _getFreshnessColor(_currentItem.freshnessScore);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Grocery Intelligence',
          style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: context.scaleFont(20.0)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: AppColors.danger,
            onPressed: _confirmDelete,
          )
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.all(cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Hero Panel
                _buildHeaderPanel(freshnessColor),
                AppGap.md(context),

                // Description card
                _buildDescriptionCard(),
                AppGap.md(context),

                // Freshness circular progress meter
                _buildFreshnessMeter(freshnessColor),
                AppGap.md(context),

                // Ripeness and Opened parameters row
                _buildParametersCard(),
                AppGap.md(context),

                // Storage recommendations card
                _buildStorageRecommendationCard(),
                AppGap.md(context),

                // AI Explanation & Timeline
                _buildAIExplanationCard(),
                AppGap.md(context),

                // Nutritional & Allergens Panel
                _buildNutritionAllergensCard(),
                AppGap.xl(context),
                
                // Actions
                _buildActionButtons(),
                const SizedBox(height: 48),
              ],
            ),
          ),
          if (_isSaving)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderPanel(Color freshnessColor) {
    return Container(
      padding: EdgeInsets.all(AppSpacing.md(context)),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card(context)),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Hero(
            tag: 'item_icon_${_currentItem.id}',
            child: Container(
              width: context.scaleWidth(72.0),
              height: context.scaleWidth(72.0),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card(context) * 0.8),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Center(
                child: Icon(
                  CategoryIconMapper.fromKey(_currentItem.iconKey),
                  size: AppIconSizes.lg(context),
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          AppGap.md(context),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentItem.name,
                  style: AppTextStyles.headingLarge(context),
                ),
                if (_currentItem.brand.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    _currentItem.brand,
                    style: AppTextStyles.bodyMedium(context).copyWith(color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _currentItem.storageZone.toUpperCase(),
                        style: AppTextStyles.caption(context).copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      decoration: BoxDecoration(
                        color: freshnessColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _getFreshnessLabel(_currentItem.freshnessScore).toUpperCase(),
                        style: AppTextStyles.caption(context).copyWith(color: freshnessColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildDescriptionCard() {
    final desc = _currentItem.description.isNotEmpty 
        ? _currentItem.description 
        : 'Smart tracked ${_currentItem.category.toLowerCase()} item stored in ${_currentItem.storageZone.toLowerCase()} zone.';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.md(context)),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card(context)),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_outlined, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                'Description',
                style: AppTextStyles.labelMedium(context).copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            desc,
            style: AppTextStyles.bodyMedium(context).copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildFreshnessMeter(Color freshnessColor) {
    final remainingDays = _currentItem.effectiveExpiryDate != null
        ? DateHelpers.calendarDaysDifference(_currentItem.effectiveExpiryDate!)
        : 0;


    return Container(
      padding: EdgeInsets.all(AppSpacing.md(context)),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card(context)),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Animated circular progress indicator
          Column(
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: AnimatedBuilder(
                  animation: _progressAnimation,
                  builder: (context, child) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: _progressAnimation.value,
                          strokeWidth: 8.0,
                          backgroundColor: AppColors.cardBorder,
                          color: freshnessColor,
                        ),
                        Text(
                          '${(_progressAnimation.value * 100).toInt()}%',
                          style: AppTextStyles.headingLarge(context).copyWith(fontSize: 22.0),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text('Freshness Index', style: AppTextStyles.caption(context)),
            ],
          ),

          // Remaining shelf life days
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _currentItem.effectiveExpiryDate != null
                    ? DateHelpers.formatRemainingDaysCount(_currentItem.effectiveExpiryDate!)
                    : 'No Expiry',
                style: AppTextStyles.displayMedium(context).copyWith(
                  fontSize: 28.0,
                  fontWeight: FontWeight.bold,
                  color: remainingDays <= 2 ? AppColors.danger : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Predicted Remaining Life',
                style: AppTextStyles.caption(context).copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.psychology_outlined, size: 16, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text(
                    'AI Confidence: ${(_currentItem.confidenceScore * 100).toStringAsFixed(0)}%',
                    style: AppTextStyles.caption(context).copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                  ),
                ],
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildParametersCard() {
    return Container(
      padding: EdgeInsets.all(AppSpacing.md(context)),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card(context)),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ML Regression Parameters', style: AppTextStyles.labelMedium(context)),
          AppGap.sm(context),
          
          // Packaging opened status switch
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Packaging Status', style: AppTextStyles.bodyMedium(context)),
                  Text(
                    _currentItem.isOpened ? 'Opened (Spoils faster)' : 'Unopened',
                    style: AppTextStyles.caption(context).copyWith(color: AppColors.textSecondary),
                  )
                ],
              ),
              Switch(
                value: _currentItem.isOpened,
                activeThumbColor: AppColors.primary,
                onChanged: (val) {
                  _updateItemParameters(isOpened: val);
                },
              )
            ],
          ),
          const Divider(),
          const SizedBox(height: 4),

          // Ripeness status dropdown
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Ripeness State', style: AppTextStyles.bodyMedium(context)),
              DropdownButton<String>(
                value: _currentItem.ripeness,
                underline: const SizedBox(),
                dropdownColor: AppColors.surface,
                items: const [
                  DropdownMenuItem(value: 'not_applicable', child: Text('N/A')),
                  DropdownMenuItem(value: 'unripe', child: Text('Unripe')),
                  DropdownMenuItem(value: 'ripe', child: Text('Ripe')),
                  DropdownMenuItem(value: 'overripe', child: Text('Overripe')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    _updateItemParameters(ripeness: val);
                  }
                },
              )
            ],
          ),
          const Divider(),
          const SizedBox(height: 4),

          // Temperature & Humidity metrics
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Storage Metrics', style: AppTextStyles.bodyMedium(context)),
              Row(
                children: [
                  const Icon(Icons.thermostat, size: 16, color: AppColors.primary),
                  Text('${_currentItem.temperature}°C', style: AppTextStyles.bodyMedium(context)),
                  const SizedBox(width: 12),
                  const Icon(Icons.water_drop_outlined, size: 16, color: AppColors.primary),
                  Text('${_currentItem.humidity}% RH', style: AppTextStyles.bodyMedium(context)),
                ],
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildStorageRecommendationCard() {
    return Container(
      padding: EdgeInsets.all(AppSpacing.md(context)),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.card(context)),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tips_and_updates_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'AI Storage Recommendation',
                style: AppTextStyles.labelMedium(context).copyWith(color: AppColors.primary),
              ),
            ],
          ),
          AppGap.sm(context),
          
          Text(
            'Recommended Storage: ${_currentItem.storageZone.toUpperCase()}',
            style: AppTextStyles.bodyMedium(context).copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            _currentItem.storageRecommendationWhy.isNotEmpty 
                ? _currentItem.storageRecommendationWhy 
                : 'Optimal storage slows bacterial decay.',
            style: AppTextStyles.bodySmall(context),
          ),
          AppGap.xs(context),

          Text(
            'Storage Guidance:',
            style: AppTextStyles.bodySmall(context).copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            _currentItem.storageRecommendationHow.isNotEmpty 
                ? _currentItem.storageRecommendationHow 
                : 'Store in standard breathable conditions.',
            style: AppTextStyles.bodySmall(context),
          ),
        ],
      ),
    );
  }

  Widget _buildAIExplanationCard() {
    return Container(
      padding: EdgeInsets.all(AppSpacing.md(context)),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card(context)),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Shelf Life Explanation', style: AppTextStyles.labelMedium(context)),
          AppGap.xs(context),
          Text(
            _currentItem.aiExplanation.isNotEmpty 
                ? _currentItem.aiExplanation 
                : 'Regression estimate computed using standard environmental variables.',
            style: AppTextStyles.bodyMedium(context).copyWith(color: AppColors.textSecondary),
          ),
          AppGap.md(context),

          const Divider(),
          AppGap.xs(context),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Purchase Date', style: AppTextStyles.caption(context)),
              Text(
                _currentItem.purchaseDate.toIso8601String().substring(0, 10),
                style: AppTextStyles.bodySmall(context).copyWith(fontWeight: FontWeight.bold),
              )
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _currentItem.isExpiryEstimated ? 'Estimated Consumption' : 'Printed Expiry Date',
                  style: AppTextStyles.caption(context),
                ),
              ),
              Text(
                _currentItem.effectiveExpiryDate?.toIso8601String().substring(0, 10) ?? 'N/A',
                style: AppTextStyles.bodySmall(context).copyWith(fontWeight: FontWeight.bold),
              )
            ],
          )
        ],
      ),
    );

  }

  Widget _buildNutritionAllergensCard() {
    return Container(
      padding: EdgeInsets.all(AppSpacing.md(context)),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card(context)),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nutritional Information', style: AppTextStyles.labelMedium(context)),
          AppGap.sm(context),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Calories (per 100g)', style: AppTextStyles.bodyMedium(context)),
              Text(
                _currentItem.caloriesPer100g != null ? '${_currentItem.caloriesPer100g} kcal' : 'Not Available',
                style: AppTextStyles.bodyMedium(context).copyWith(fontWeight: FontWeight.bold),
              )
            ],
          ),
          const Divider(),
          const SizedBox(height: 8),

          Text('Allergens Warning', style: AppTextStyles.bodySmall(context).copyWith(color: AppColors.danger, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          _currentItem.allergens.isEmpty
              ? Text('No known allergens detected.', style: AppTextStyles.caption(context))
              : Wrap(
                  spacing: 6.0,
                  runSpacing: 6.0,
                  children: _currentItem.allergens.map((allergy) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        allergy.toUpperCase(),
                        style: AppTextStyles.caption(context).copyWith(color: AppColors.danger, fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                )
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: AppButton(
                text: 'Mark Consumed',
                onPressed: _consumeAll,
              ),
            ),
            AppGap.sm(context),
            Expanded(
              child: AppButton(
                text: 'Mark Wasted',
                onPressed: _markWasted,
                style: AppButtonStyle.secondary,
              ),
            ),
          ],
        )
      ],
    );
  }
}
