import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../config/app_radius.dart';
import '../../../config/app_text_styles.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../providers/meal_provider.dart';
import 'meal_confirm_view.dart';

class MealLogView extends StatefulWidget {
  const MealLogView({super.key});

  @override
  State<MealLogView> createState() => _MealLogViewState();
}

class _MealLogViewState extends State<MealLogView> {
  final TextEditingController _descController = TextEditingController();
  XFile? _image;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 70);
    if (picked != null) {
      setState(() {
        _image = picked;
      });
    }
  }

  void _analyzeMeal() async {
    if (_image == null && _descController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add a photo or description of your meal'),
        ),
      );
      return;
    }

    final provider = context.read<MealProvider>();
    await provider.logMeal(
      image: _image,
      description: _descController.text.trim(),
    );

    if (mounted && provider.uiState == MealUIState.review) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MealConfirmView()),
      );
    } else if (mounted && provider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage!),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MealProvider>();
    final isLoading = provider.uiState == MealUIState.analyzing;

    return AppScaffold(
      appBar: AppBar(
        title: const Text('Log Meal'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(AppSpacing.md(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'What did you eat?',
              style: AppTextStyles.headingMedium(context),
            ),
            AppGap.sm(context),
            Text(
              'Snap a photo or describe your meal so FreshTrack can deduct the used ingredients from your pantry.',
              style: AppTextStyles.bodyMedium(
                context,
              ).copyWith(color: AppColors.textSecondary),
            ),
            AppGap.lg(context),

            // Image Picker Area
            GestureDetector(
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: AppColors.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(AppRadius.card(context)),
                    ),
                  ),
                  builder: (_) => SafeArea(
                    child: Wrap(
                      children: [
                        ListTile(
                          leading: const Icon(
                            Icons.camera_alt,
                            color: AppColors.primary,
                          ),
                          title: const Text('Take a photo'),
                          onTap: () {
                            Navigator.pop(context);
                            _pickImage(ImageSource.camera);
                          },
                        ),
                        ListTile(
                          leading: const Icon(
                            Icons.photo_library,
                            color: AppColors.primary,
                          ),
                          title: const Text('Choose from gallery'),
                          onTap: () {
                            Navigator.pop(context);
                            _pickImage(ImageSource.gallery);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppRadius.card(context)),
                  border: Border.all(color: AppColors.cardBorder, width: 2),
                  image: _image != null
                      ? DecorationImage(
                          image: FileImage(File(_image!.path)),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _image == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_a_photo,
                            size: 48,
                            color: AppColors.primary.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap to add photo',
                            style: AppTextStyles.labelMedium(context),
                          ),
                        ],
                      )
                    : null,
              ),
            ),
            if (_image != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => setState(() => _image = null),
                  icon: const Icon(Icons.clear, color: AppColors.danger),
                  label: const Text(
                    'Remove Photo',
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
              ),
            ],

            AppGap.lg(context),

            // Description Field
            TextField(
              controller: _descController,
              maxLines: 3,
              style: AppTextStyles.bodyMedium(context),
              decoration: InputDecoration(
                hintText:
                    'e.g., I cooked chicken biryani with rice and tomatoes',
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card(context)),
                  borderSide: const BorderSide(color: AppColors.cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card(context)),
                  borderSide: const BorderSide(color: AppColors.cardBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card(context)),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 2,
                  ),
                ),
              ),
            ),

            AppGap.xl(context),

            // Action Button
            ElevatedButton(
              onPressed: isLoading ? null : _analyzeMeal,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card(context)),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'Analyze Meal',
                      style: AppTextStyles.labelLarge(
                        context,
                      ).copyWith(color: Colors.white),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
