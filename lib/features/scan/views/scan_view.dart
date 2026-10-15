import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../providers/scan_provider.dart';
import '../../kitchen/providers/kitchen_provider.dart';
import '../../home/views/home_shell.dart';
import '../../../data/models/scan_candidate_model.dart';
import '../../../core/services/image_picker_service.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../config/app_radius.dart';
import '../../../config/app_icon_sizes.dart';
import '../../../config/app_text_styles.dart';
import '../../../config/app_routes.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/scan_candidate_card.dart';
import '../../../core/services/unit_classification_service.dart';
import '../../../core/extensions/responsive_context_extension.dart';

class ScanView extends StatefulWidget {
  const ScanView({super.key});

  @override
  State<ScanView> createState() => _ScanViewState();
}

class _ScanViewState extends State<ScanView>
    with SingleTickerProviderStateMixin {
  final ImagePickerService _pickerService = ImagePickerService();
  late AnimationController _laserController;

  @override
  void initState() {
    super.initState();
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ScanProvider>().resetIfError();
      }
    });
  }

  @override
  void dispose() {
    _laserController.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    final photo = await _pickerService.capturePhoto();
    if (photo != null && mounted) {
      context.read<ScanProvider>().addImages([photo]);
    }
  }

  Future<void> _pickGallery() async {
    final photos = await _pickerService.selectMultipleImagesFromGallery();
    if (photos.isNotEmpty && mounted) {
      context.read<ScanProvider>().addImages(photos);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scan = context.watch<ScanProvider>();

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) scan.clearImages();
      },
      child: AppScaffold(body: _buildUIStateBody(scan)),
    );
  }

  Widget _buildUIStateBody(ScanProvider scan) {
    switch (scan.uiState) {
      case ScanUIState.uploading:
        return _buildStageProgress(scan.scanStageMessage, scan.scanProgress);
      case ScanUIState.analyzing:
        return _buildStageProgress(scan.scanStageMessage, scan.scanProgress);
      case ScanUIState.review:
        return _buildReviewList(scan);
      case ScanUIState.success:
        return _buildSuccessState(scan);
      case ScanUIState.error:
        return _buildErrorState(scan);
      case ScanUIState.idle:
      default:
        return _buildCameraCameraSelector(scan);
    }
  }

  Widget _buildCameraCameraSelector(ScanProvider scan) {
    return Column(
      children: [
        // Camera Viewfinder Simulation
        Expanded(
          flex: 4,
          child: GestureDetector(
            onTap: scan.selectedImages.isEmpty ? _capturePhoto : null,
            child: Container(
              margin: EdgeInsets.all(AppSpacing.md(context)),
              decoration: BoxDecoration(
                color: AppColors.black,
                borderRadius: BorderRadius.circular(AppRadius.card(context)),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.5),
                  width: 2.0,
                ),
              ),
              child: Stack(
                children: [
                  // Scan Grid Custom Paint overlay
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ScanFramePainter(context: context),
                    ),
                  ),

                  if (scan.selectedImages.isNotEmpty)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          AppRadius.card(context) * 0.95,
                        ),
                        child: Image.file(
                          File(scan.selectedImages.last.path),
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                  else
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.camera_enhance_outlined,
                            size: AppIconSizes.lg(context) * 1.5,
                            color: AppColors.textSecondary,
                          ),
                          AppGap.xs(context),
                          Text(
                            'Tap here or use controls to scan package',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              color: AppColors.textSecondary,
                              fontSize: context.scaleFont(14.0),
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),

                  // Scanning Laser Line Animation
                  if (scan.selectedImages.isEmpty)
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return AnimatedBuilder(
                            animation: _laserController,
                            builder: (context, child) {
                              final double top =
                                  _laserController.value *
                                  constraints.maxHeight;
                              return Stack(
                                children: [
                                  Positioned(
                                    top: top,
                                    left: 4,
                                    right: 4,
                                    child: Container(
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.primary.withValues(
                                              alpha: 0.6,
                                            ),
                                            blurRadius: 8.0,
                                            spreadRadius: 2.0,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        // Photo Preview strip
        if (scan.selectedImages.isNotEmpty) ...[
          SizedBox(
            height: context.scaleHeight(72.0),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.md(context)),
              itemCount: scan.selectedImages.length,
              itemBuilder: (ctx, index) {
                return Stack(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(right: 8.0),
                      width: context.scaleWidth(72.0),
                      height: context.scaleHeight(72.0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          AppRadius.chip(context),
                        ),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          AppRadius.chip(context) * 0.75,
                        ),
                        child: Image.file(
                          File(scan.selectedImages[index].path),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 2.0,
                      right: 10.0,
                      child: GestureDetector(
                        onTap: () => scan.removeImage(index),
                        child: Container(
                          padding: const EdgeInsets.all(2.0),
                          decoration: const BoxDecoration(
                            color: AppColors.danger,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close,
                            size: AppIconSizes.sm(context) * 0.7,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          AppGap.xs(context),
        ],

        // Controls bar
        Flexible(
          flex: 2,
          fit: FlexFit.loose,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg(context)),
            child: Column(
              children: [
                if (scan.selectedImages.isEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildControlBtn(
                        'Camera',
                        Icons.camera_alt_rounded,
                        _capturePhoto,
                      ),
                      _buildControlBtn(
                        'Gallery',
                        Icons.photo_library_rounded,
                        _pickGallery,
                      ),
                      _buildControlBtn(
                        'Barcode',
                        Icons.qr_code_scanner_rounded,
                        () {
                          Navigator.pushNamed(context, AppRoutes.barcodeScan);
                        },
                      ),
                      _buildControlBtn('Manual', Icons.edit_note_rounded, () {
                        Navigator.pushNamed(context, AppRoutes.manualAdd);
                      }),
                    ],
                  ),
                ] else ...[
                  AppButton(
                    text: 'Analyze ${scan.selectedImages.length} Image(s)',
                    onPressed: () => scan.startAnalysis(),
                  ),
                  AppGap.xs(context),
                  AppButton(
                    text: 'Cancel',
                    onPressed: () => scan.clearImages(),
                    style: AppButtonStyle.outline,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlBtn(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(AppSpacing.md(context)),
            decoration: BoxDecoration(
              color: AppColors.card,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Icon(
              icon,
              size: AppIconSizes.lg(context),
              color: AppColors.primary,
            ),
          ),
          AppGap.xs(context),
          Text(label, style: AppTextStyles.labelMedium(context)),
        ],
      ),
    );
  }

  Widget _buildStageProgress(String stageText, double progress) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xl(context)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            AppGap.md(context),
            Text(
              stageText,
              style: AppTextStyles.headingMedium(context),
              textAlign: TextAlign.center,
            ),
            AppGap.sm(context),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: AppColors.card,
                color: AppColors.primary,
                minHeight: 6.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewList(ScanProvider scan) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(AppSpacing.md(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AI Detected', style: AppTextStyles.headingLarge(context)),
              AppGap.xxs(context),
              Text(
                'Review and edit the details before adding them to your kitchen.',
                style: AppTextStyles.bodyMedium(context),
              ),
            ],
          ),
        ),
        if (scan.errorMessage != null && scan.errorMessage!.isNotEmpty)
          Container(
            margin: EdgeInsets.symmetric(
              horizontal: AppSpacing.md(context),
              vertical: AppSpacing.xs(context),
            ),
            padding: EdgeInsets.all(AppSpacing.sm(context)),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(
                AppRadius.card(context) * 0.7,
              ),
              border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: AppColors.danger,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    scan.errorMessage!,
                    style: AppTextStyles.bodySmall(
                      context,
                    ).copyWith(color: AppColors.danger),
                  ),
                ),
              ],
            ),
          ),
        const Divider(),

        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm(context)),
            itemCount: scan.candidates.length,
            itemBuilder: (ctx, index) {
              final candidate = scan.candidates[index];
              final isSelected = scan.candidateSelection[candidate.id] ?? true;

              return ScanCandidateCard(
                candidate: candidate,
                isSelected: isSelected,
                onSelectedChanged: (val) {
                  scan.toggleCandidateSelection(candidate.id, val ?? true);
                },
                onQuantityChanged: (qty) {
                  scan.updateCandidateQuantity(candidate.id, qty);
                },
                onUnitChanged: (unit) {
                  scan.updateCandidateUnit(candidate.id, unit);
                },
                onExpiryChanged: (date) {
                  scan.updateCandidate(candidate.id, {
                    'expiry_date': date.toIso8601String().substring(0, 10),
                  });
                },
                onEdit: () {
                  _showEditCandidateDialog(candidate);
                },
                onRemove: () {
                  scan.removeCandidate(candidate.id);
                },
              );
            },
          ),
        ),

        Padding(
          padding: EdgeInsets.all(AppSpacing.md(context)),
          child: AppButton(
            text: 'Add Selected Items to Kitchen',
            onPressed: () async {
              final success = await scan.confirmSelectedCandidates(context);
              if (success && mounted) {
                // Fetch kitchen items with forceRefresh to update list & UI counts
                context.read<KitchenProvider>().fetchKitchenItems(
                  forceRefresh: true,
                );
              }
            },
          ),
        ),
      ],
    );
  }

  void _showEditCandidateDialog(ScanCandidateModel candidate) {
    final nameController = TextEditingController(text: candidate.name);
    final brandController = TextEditingController(text: candidate.brand);
    final descController = TextEditingController(text: candidate.description);
    final qtyController = TextEditingController(
      text: candidate.quantity % 1 == 0
          ? candidate.quantity.toInt().toString()
          : candidate.quantity.toString(),
    );
    final netValController = TextEditingController(
      text: candidate.netContentValue != null
          ? (candidate.netContentValue! % 1 == 0
                ? candidate.netContentValue!.toInt().toString()
                : candidate.netContentValue!.toString())
          : '',
    );
    final zoneController = TextEditingController(text: candidate.storageZone);

    String selectedCategory = candidate.category;
    String selectedUnit = candidate.unit;
    String selectedNetUnit = candidate.netContentUnit;
    DateTime? selectedExpiry = candidate.expiryDate;

    const categories = [
      'Vegetables',
      'Fruits',
      'Dairy',
      'Bakery',
      'Meat',
      'Grains',
      'Snacks',
      'Beverages',
      'Spices',
      'Other',
    ];
    const units = UnitClassificationService.allUnits;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card(ctx)),
            side: const BorderSide(color: AppColors.cardBorder),
          ),
          title: Text(
            'Edit Candidate Details',
            style: AppTextStyles.headingMedium(ctx),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(controller: nameController, label: 'Item Name'),
                AppGap.sm(ctx),
                AppTextField(controller: brandController, label: 'Brand Name'),
                AppGap.sm(ctx),

                // Category Selector
                Text(
                  'Category',
                  style: AppTextStyles.labelMedium(
                    ctx,
                  ).copyWith(color: AppColors.textSecondary),
                ),
                AppGap.xs(ctx),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: categories.contains(selectedCategory)
                          ? selectedCategory
                          : 'Other',
                      dropdownColor: AppColors.surface,
                      items: categories
                          .map(
                            (cat) => DropdownMenuItem(
                              value: cat,
                              child: Text(
                                cat,
                                style: AppTextStyles.bodyMedium(ctx),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (newCat) {
                        if (newCat != null) {
                          setDialogState(() {
                            selectedCategory = newCat;
                            // Smart auto-suggest unit if current was uncertain
                            if (candidate.isUncertain) {
                              final suggested =
                                  UnitClassificationService.classifyProduct(
                                    productName: nameController.text,
                                    category: newCat,
                                  );
                              selectedUnit = suggested.unit;
                            }
                          });
                        }
                      },
                    ),
                  ),
                ),
                AppGap.sm(ctx),

                // Quantity and Unit Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: AppTextField(
                        controller: qtyController,
                        label: 'Quantity',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Unit',
                            style: AppTextStyles.labelMedium(
                              ctx,
                            ).copyWith(color: AppColors.textSecondary),
                          ),
                          AppGap.xs(ctx),
                          Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.cardBorder),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                value: units.contains(selectedUnit)
                                    ? selectedUnit
                                    : units.first,
                                dropdownColor: AppColors.surface,
                                items: units
                                    .map(
                                      (u) => DropdownMenuItem(
                                        value: u,
                                        child: Text(
                                          u,
                                          style: AppTextStyles.bodyMedium(ctx),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (newUnit) {
                                  if (newUnit != null) {
                                    final currentVal = double.tryParse(
                                      qtyController.text,
                                    );
                                    if (currentVal != null) {
                                      final converted =
                                          UnitClassificationService.convertQuantity(
                                            currentVal,
                                            selectedUnit,
                                            newUnit,
                                          );
                                      if (converted != null) {
                                        qtyController.text = converted % 1 == 0
                                            ? converted.toInt().toString()
                                            : converted.toString();
                                      }
                                    }
                                    setDialogState(() {
                                      selectedUnit = newUnit;
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                AppGap.sm(ctx),

                // Package Net Content (e.g. 50 g or 1 L)
                if (UnitClassificationService.unitCategories[selectedUnit] ==
                    UnitClassificationService.categoryPackage) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: AppTextField(
                          controller: netValController,
                          label: 'Net Size/Weight',
                          hint: 'e.g. 50 or 500',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Size Unit',
                              style: AppTextStyles.labelMedium(
                                ctx,
                              ).copyWith(color: AppColors.textSecondary),
                            ),
                            AppGap.xs(ctx),
                            Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.cardBorder),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value:
                                      [
                                        'g',
                                        'kg',
                                        'ml',
                                        'L',
                                        '',
                                      ].contains(selectedNetUnit)
                                      ? selectedNetUnit
                                      : '',
                                  dropdownColor: AppColors.surface,
                                  items: const [
                                    DropdownMenuItem(
                                      value: '',
                                      child: Text('None'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'g',
                                      child: Text('g'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'kg',
                                      child: Text('kg'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'ml',
                                      child: Text('ml'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'L',
                                      child: Text('L'),
                                    ),
                                  ],
                                  onChanged: (u) => setDialogState(
                                    () => selectedNetUnit = u ?? '',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  AppGap.sm(ctx),
                ],

                AppTextField(
                  controller: descController,
                  label: 'Description',
                  maxLines: 2,
                ),
                AppGap.sm(ctx),
                AppTextField(
                  controller: zoneController,
                  label: 'Storage Zone (fridge, pantry, basket etc.)',
                ),
                AppGap.sm(ctx),
                Text('Expiry Date', style: AppTextStyles.labelMedium(ctx)),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate:
                          selectedExpiry ??
                          DateTime.now().add(const Duration(days: 7)),
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 365),
                      ),
                      lastDate: DateTime.now().add(
                        const Duration(days: 365 * 5),
                      ),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        selectedExpiry = picked;
                      });
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          selectedExpiry != null
                              ? selectedExpiry!.toIso8601String().substring(
                                  0,
                                  10,
                                )
                              : 'Select Expiry Date',
                          style: AppTextStyles.bodyMedium(ctx).copyWith(
                            color: selectedExpiry != null
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                        ),
                        const Icon(
                          Icons.calendar_month,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: AppTextStyles.labelMedium(
                  ctx,
                ).copyWith(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () {
                final qtyParsed =
                    double.tryParse(qtyController.text) ?? candidate.quantity;
                final netValParsed = double.tryParse(netValController.text);
                final unitCat =
                    UnitClassificationService.unitCategories[selectedUnit] ??
                    'count';
                final pType =
                    unitCat == UnitClassificationService.categoryPackage
                    ? selectedUnit
                    : '';

                final Map<String, dynamic> updateData = {
                  'name': nameController.text.trim(),
                  'brand': brandController.text.trim(),
                  'category': selectedCategory,
                  'quantity': qtyParsed,
                  'unit': selectedUnit,
                  'unit_category': unitCat,
                  'package_type': pType,
                  'net_content_value': netValParsed,
                  'net_content_unit': selectedNetUnit,
                  'unit_confidence': 'High',
                  'is_uncertain': false,
                  'description': descController.text.trim(),
                  'storage_zone': zoneController.text.toLowerCase().trim(),
                };
                if (selectedExpiry != null) {
                  updateData['expiry_date'] = selectedExpiry!
                      .toIso8601String()
                      .substring(0, 10);
                }
                context.read<ScanProvider>().updateCandidate(
                  candidate.id,
                  updateData,
                );
                Navigator.pop(ctx);
              },
              child: Text(
                'Save',
                style: AppTextStyles.labelMedium(
                  ctx,
                ).copyWith(color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessState(ScanProvider scan) {
    final double iconBoxSize = context.scaleWidth(80.0);

    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xl(context)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: iconBoxSize,
              height: iconBoxSize,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_rounded,
                size: AppIconSizes.lg(context) * 1.5,
                color: AppColors.success,
              ),
            ),
            AppGap.md(context),
            Text('Items Added!', style: AppTextStyles.displayMedium(context)),
            AppGap.sm(context),
            Text(
              'Successfully validated and saved items to your active pantry inventory.',
              style: AppTextStyles.bodyLarge(context),
              textAlign: TextAlign.center,
            ),
            AppGap.lg(context),
            AppButton(
              text: 'Go to Kitchen',
              onPressed: () {
                scan.clearImages();
                context.read<KitchenProvider>().fetchKitchenItems(
                  forceRefresh: true,
                );
                HomeShell.switchTab(1);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(ScanProvider scan) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.md(context)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: AppIconSizes.lg(context) * 2.0,
              color: AppColors.danger,
            ),
            AppGap.md(context),
            Text('Scan Failed', style: AppTextStyles.headingLarge(context)),
            AppGap.xs(context),
            Text(
              scan.errorMessage ??
                  'An unexpected error occurred during image processing.',
              style: AppTextStyles.bodyMedium(context),
              textAlign: TextAlign.center,
            ),
            AppGap.md(context),
            AppButton(text: 'Try Again', onPressed: () => scan.clearImages()),
          ],
        ),
      ),
    );
  }
}

// Scanner corners painter
class _ScanFramePainter extends CustomPainter {
  final BuildContext context;
  _ScanFramePainter({required this.context});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final double len = context.scaleWidth(24.0);

    // Top Left Corner
    canvas.drawPath(
      Path()
        ..moveTo(len, 0)
        ..lineTo(0, 0)
        ..lineTo(0, len),
      paint,
    );

    // Top Right Corner
    canvas.drawPath(
      Path()
        ..moveTo(size.width - len, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, len),
      paint,
    );

    // Bottom Left Corner
    canvas.drawPath(
      Path()
        ..moveTo(len, size.height)
        ..lineTo(0, size.height)
        ..lineTo(0, size.height - len),
      paint,
    );

    // Bottom Right Corner
    canvas.drawPath(
      Path()
        ..moveTo(size.width - len, size.height)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width, size.height - len),
      paint,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}
