import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../../config/app_icon_sizes.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../config/app_radius.dart';
import '../../../config/app_text_styles.dart';
import '../../../config/app_routes.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/extensions/responsive_context_extension.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _newAllergyController = TextEditingController();

  String _dietType = 'any';
  List<String> _allergies = [];
  bool _notify3Days = true;
  bool _notify1Day = true;
  bool _notifyDailyRecipe = true;

  bool _initialized = false;

  final List<String> _commonAllergens = [
    'Dairy',
    'Nuts',
    'Gluten',
    'Soy',
    'Seafood',
    'Egg',
  ];

  Future<void> _pickAvatar() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );

    if (image != null) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      await auth.updatePreferences(avatarPath: image.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile picture updated successfully.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _newAllergyController.dispose();
    super.dispose();
  }

  void _initFields(AuthProvider auth) {
    if (_initialized || auth.user == null) return;
    final user = auth.user!;
    _displayNameController.text = user.displayName;
    _dietType = user.dietType;
    _allergies = List<String>.from(user.allergies);
    _notify3Days = user.notify3Days;
    _notify1Day = user.notify1Day;
    _notifyDailyRecipe = user.notifyDailyRecipe;
    _initialized = true;
  }

  Future<void> _save() async {
    final auth = context.read<AuthProvider>();
    await auth.updatePreferences(
      displayName: _displayNameController.text.trim(),
      dietType: _dietType,
      allergies: _allergies,
      notify3Days: _notify3Days,
      notify1Day: _notify1Day,
      notifyDailyRecipe: _notifyDailyRecipe,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preferences saved successfully.'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (ctx) => ConfirmDialog(
        title: 'Sign Out',
        content: 'Are you sure you want to sign out of FreshTrack?',
        confirmLabel: 'Sign Out',
        cancelLabel: 'Cancel',
        onConfirm: () async {
          await context.read<AuthProvider>().logout();
          if (mounted) {
            Navigator.pushNamedAndRemoveUntil(
              context,
              AppRoutes.login,
              (route) => false,
            );
          }
        },
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final confirmed = await ConfirmDialog.show(
      context: context,
      title: 'Delete Account',
      content:
          'WARNING: Deleting your account is completely irreversible. All your inventory, stats, and recipes will be deleted forever.',
      confirmLabel: 'Permanently Delete',
      cancelLabel: 'Cancel',
      isDestructive: true,
    );

    if (!mounted || confirmed != true) return;

    final success = await context.read<AuthProvider>().deleteAccount();
    if (success && mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.login,
        (route) => false,
      );
    }
  }

  void _addAllergy() {
    final val = _newAllergyController.text.trim();
    if (val.isNotEmpty && !_allergies.contains(val)) {
      setState(() {
        _allergies.add(val);
        _newAllergyController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    _initFields(auth);

    final totalTracked = auth.user?.totalTracked ?? 0;
    final savedFromWaste = auth.user?.savedFromWaste ?? 0;
    final recipesCooked = auth.user?.recipesCooked ?? 0;

    return AppScaffold(
      isLoading: auth.isLoading,
      appBar: AppBar(
        title: Text(
          'Profile Preferences',
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
          padding: EdgeInsets.all(AppSpacing.md(context)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar Block
                  Center(
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: context.scaleWidth(50.0),
                          backgroundColor: AppColors.primary.withValues(
                            alpha: 0.12,
                          ),
                          backgroundImage:
                              auth.user?.avatarUrl != null &&
                                  auth.user!.avatarUrl!.isNotEmpty
                              ? NetworkImage(auth.user!.avatarUrl!)
                              : null,
                          child:
                              auth.user?.avatarUrl == null ||
                                  auth.user!.avatarUrl!.isEmpty
                              ? Text(
                                  auth.user?.displayName.isNotEmpty == true
                                      ? auth.user!.displayName[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: context.scaleFont(32.0),
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                    fontFamily: 'Outfit',
                                  ),
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _pickAvatar,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AppGap.md(context),

                  // Stats Overview Row
                  _buildStatsRow(totalTracked, savedFromWaste, recipesCooked),
                  AppGap.md(context),
                  const Divider(),
                  AppGap.sm(context),

                  // Profile Fields
                  AppTextField(
                    controller: _displayNameController,
                    label: 'Display Name',
                    hint: 'Your display name',
                    validator: (val) => val == null || val.trim().isEmpty
                        ? 'Name is required'
                        : null,
                  ),
                  AppGap.sm(context),

                  // Diet Preferences dropdown
                  Text(
                    'Dietary Type',
                    style: AppTextStyles.labelMedium(context),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: _dietType,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    dropdownColor: AppColors.surface,
                    items: const [
                      DropdownMenuItem(
                        value: 'any',
                        child: Text('Any (No dietary restriction)'),
                      ),
                      DropdownMenuItem(value: 'veg', child: Text('Vegetarian')),
                      DropdownMenuItem(
                        value: 'non-veg',
                        child: Text('Non-Vegetarian'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _dietType = val);
                    },
                  ),
                  AppGap.sm(context),

                  // Allergies checklist
                  Text(
                    'Allergies & Sensitivities',
                    style: AppTextStyles.labelMedium(context),
                  ),
                  AppGap.xs(context),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: [
                      ..._commonAllergens.map((allergy) {
                        final hasAllergy = _allergies.contains(
                          allergy.toLowerCase(),
                        );
                        return FilterChip(
                          label: Text(
                            allergy,
                            style: AppTextStyles.bodyMedium(context),
                          ),
                          selected: hasAllergy,
                          selectedColor: AppColors.primary.withValues(
                            alpha: 0.12,
                          ),
                          checkmarkColor: AppColors.primary,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _allergies.add(allergy.toLowerCase());
                              } else {
                                _allergies.remove(allergy.toLowerCase());
                              }
                            });
                          },
                        );
                      }),
                      ..._allergies
                          .where(
                            (a) => !_commonAllergens
                                .map((c) => c.toLowerCase())
                                .contains(a),
                          )
                          .map((allergy) {
                            final displayName = allergy.isNotEmpty
                                ? allergy.substring(0, 1).toUpperCase() +
                                      allergy.substring(1)
                                : '';
                            return InputChip(
                              label: Text(
                                displayName,
                                style: AppTextStyles.bodyMedium(context),
                              ),
                              selected: true,
                              selectedColor: AppColors.primary.withValues(
                                alpha: 0.12,
                              ),
                              checkmarkColor: AppColors.primary,
                              onDeleted: () {
                                setState(() {
                                  _allergies.remove(allergy);
                                });
                              },
                            );
                          }),
                    ],
                  ),
                  AppGap.xs(context),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newAllergyController,
                          decoration: const InputDecoration(
                            hintText: 'Add custom allergy (e.g. Garlic)',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                          ),
                          style: AppTextStyles.bodyMedium(context),
                          onSubmitted: (_) => _addAllergy(),
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      IconButton(
                        icon: Icon(
                          Icons.add_circle_outline,
                          color: AppColors.primary,
                          size: AppIconSizes.md(context),
                        ),
                        onPressed: _addAllergy,
                      ),
                    ],
                  ),
                  AppGap.md(context),
                  const Divider(),
                  AppGap.sm(context),

                  // Notifications Toggle list
                  Text(
                    'Notification Alerts',
                    style: AppTextStyles.headingMedium(context),
                  ),
                  AppGap.xs(context),
                  _buildNotificationSwitch(
                    '3 Days Prior Alert',
                    'Alert me when a grocery is expiring in 3 days.',
                    _notify3Days,
                    (val) => setState(() => _notify3Days = val),
                  ),
                  _buildNotificationSwitch(
                    '1 Day Prior Alert',
                    'Alert me when a grocery is expiring tomorrow.',
                    _notify1Day,
                    (val) => setState(() => _notify1Day = val),
                  ),
                  _buildNotificationSwitch(
                    'Daily Recipe Suggestion',
                    'Recommend recipe ideas using expiring ingredients.',
                    _notifyDailyRecipe,
                    (val) => setState(() => _notifyDailyRecipe = val),
                  ),
                  AppGap.md(context),

                  // Actions Buttons
                  AppButton(text: 'Save Profile Preferences', onPressed: _save),
                  AppGap.sm(context),
                  AppButton(
                    text: 'Log Out',
                    onPressed: _logout,
                    style: AppButtonStyle.outline,
                  ),
                  AppGap.md(context),

                  // Double destructive deletion link
                  Center(
                    child: TextButton(
                      onPressed: _deleteAccount,
                      child: Text(
                        'Delete My FreshTrack Account permanently',
                        style: AppTextStyles.caption(context).copyWith(
                          color: AppColors.danger,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24.0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow(int total, int saved, int cooked) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        Expanded(child: _buildStatsBlock('Tracked', '$total')),
        const SizedBox(width: 8.0),
        Expanded(child: _buildStatsBlock('Saved Waste', '$saved')),
        const SizedBox(width: 8.0),
        Expanded(child: _buildStatsBlock('Cooked Meals', '$cooked')),
      ],
    );
  }

  Widget _buildStatsBlock(String label, String val) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: AppSpacing.sm(context),
        horizontal: AppSpacing.xs(context),
      ),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card(context) * 0.75),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              val,
              style: AppTextStyles.displayMedium(context).copyWith(
                fontSize: context.scaleFont(20.0),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 4.0),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: AppTextStyles.caption(
                context,
              ).copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationSwitch(
    String title,
    String desc,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      title: Text(title, style: AppTextStyles.labelMedium(context)),
      subtitle: Text(desc, style: AppTextStyles.caption(context)),
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
    );
  }
}
