import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../kitchen/providers/kitchen_provider.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../config/app_constraints.dart';
import '../../../config/app_text_styles.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/extensions/responsive_context_extension.dart';

class ManualAddView extends StatefulWidget {
  final String? initialZone;
  final Map<String, dynamic>? initialData;

  const ManualAddView({super.key, this.initialZone, this.initialData});

  @override
  State<ManualAddView> createState() => _ManualAddViewState();
}

class _ManualAddViewState extends State<ManualAddView> {
  final _formKey = GlobalKey<FormState>();
  
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _descController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _qtyController = TextEditingController(text: '1.0');
  
  String _category = 'Vegetables';
  String _unit = 'pcs';
  String _storageZone = 'pantry';
  DateTime? _expiryDate;
  final DateTime _purchaseDate = DateTime.now();

  final List<String> _categories = [
    'Vegetables', 'Fruits', 'Dairy', 'Bakery', 'Meat', 'Grains', 'Snacks', 'Beverages', 'Spices', 'Other'
  ];

  final List<String> _units = ['kg', 'g', 'L', 'ml', 'pcs', 'pack', 'bottle', 'box', 'dozen'];

  final List<String> _zones = ['fridge', 'freezer', 'pantry', 'counter', 'cabinet', 'basket', 'spice'];

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onNameChanged);
    if (widget.initialZone != null && _zones.contains(widget.initialZone!.toLowerCase())) {
      _storageZone = widget.initialZone!.toLowerCase();
    }
    
    if (widget.initialData != null) {
      final d = widget.initialData!;
      if (d['name'] != null) _nameController.text = d['name'];
      if (d['brand'] != null) _brandController.text = d['brand'];
      if (d['barcode'] != null) _barcodeController.text = d['barcode'];
      if (d['category'] != null && _categories.contains(d['category'])) {
        _category = d['category'];
      }
      if (d['unit'] != null && _units.contains(d['unit'])) {
        _unit = d['unit'];
      }
      if (d['storage_zone'] != null && _zones.contains(d['storage_zone'].toString().toLowerCase())) {
        _storageZone = d['storage_zone'].toString().toLowerCase();
      }
    }
  }

  void _onNameChanged() {
    final text = _nameController.text.toLowerCase().trim();
    if (text.isEmpty) return;
    final isBeverage = [
      'soda', 'coke', 'coca-cola', 'pepsi', 'sprite', 'fanta', 'carbonated',
      'cold drink', 'soft drink', 'energy drink', 'red bull', 'sting', 'beer',
      'limca', 'thums up', 'dew', '7up', 'mirinda'
    ].any((k) => text.contains(k));

    if (isBeverage && (_category != 'Beverages' || _storageZone != 'fridge')) {
      setState(() {
        _category = 'Beverages';
        _storageZone = 'fridge';
      });
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _brandController.dispose();
    _descController.dispose();
    _barcodeController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  String _getIconKeyForCategory(String category) {
    switch (category.toLowerCase()) {
      case 'vegetables':
        return 'vegetables';
      case 'fruits':
        return 'fruits';
      case 'dairy':
        return 'dairy';
      case 'grains':
      case 'bakery':
        return 'grains';
      case 'beverages':
        return 'beverage';
      case 'spices':
        return 'spices';
      default:
        return 'grocery';
    }
  }

  Future<void> _selectExpiryDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            surface: AppColors.surface,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _expiryDate = picked;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final kitchen = context.read<KitchenProvider>();
    final double? qty = double.tryParse(_qtyController.text);
    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid positive quantity.')),
      );
      return;
    }

    final data = {
      'name': _nameController.text.trim(),
      'brand': _brandController.text.trim(),
      'description': _descController.text.trim(),
      'icon_key': _getIconKeyForCategory(_category),
      'category': _category,
      'barcode': _barcodeController.text.trim(),
      'quantity': qty,
      'unit': _unit,
      'storage_zone': _storageZone,
      'expiry_date': _expiryDate?.toIso8601String().substring(0, 10),
      'purchase_date': _purchaseDate.toIso8601String().substring(0, 10),
    };

    await kitchen.addItemManually(data);

    if (kitchen.errorMessage == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully added ${_nameController.text} to pantry.')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kitchen = context.watch<KitchenProvider>();

    return AppScaffold(
      isLoading: kitchen.isLoading,
      appBar: AppBar(
        title: Text(
          'Add Grocery Item', 
          style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: context.scaleFont(20.0)),
        ),
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(AppSpacing.md(context)),
          child: Container(
            constraints: BoxConstraints(maxWidth: AppConstraints.formMaxWidth),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    controller: _nameController,
                    label: 'Item Name',
                    hint: 'e.g. Tomatoes',
                    validator: (val) => val == null || val.isEmpty ? 'Item name is required' : null,
                  ),
                  AppGap.sm(context),
                  AppTextField(
                    controller: _brandController,
                    label: 'Brand',
                    hint: 'e.g. Organic Farms',
                  ),
                  AppGap.sm(context),
                  
                  // Category Selection Dropdown
                  Text('Category', style: AppTextStyles.labelMedium(context)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    key: ValueKey('cat_$_category'),
                    initialValue: _category,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    dropdownColor: AppColors.surface,
                    items: _categories.map((c) {
                      return DropdownMenuItem(value: c, child: Text(c, style: AppTextStyles.bodyMedium(context)));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _category = val;
                          final lower = val.toLowerCase();
                          if (lower == 'beverages' || lower == 'dairy' || lower == 'meat') {
                            _storageZone = 'fridge';
                          } else if (lower == 'spices') {
                            _storageZone = 'spice';
                          } else if (lower == 'fruits') {
                            _storageZone = 'counter';
                          } else if (lower == 'vegetables') {
                            _storageZone = 'fridge';
                          } else if (lower == 'grains' || lower == 'snacks') {
                            _storageZone = 'pantry';
                          }
                        });
                      }
                    },
                  ),
                  AppGap.sm(context),

                  // Quantity & Unit
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _qtyController,
                          label: 'Quantity',
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: (val) => val == null || val.isEmpty ? 'Quantity is required' : null,
                        ),
                      ),
                      AppGap.sm(context),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Unit', style: AppTextStyles.labelMedium(context)),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              initialValue: _unit,
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                              dropdownColor: AppColors.surface,
                              items: _units.map((u) {
                                return DropdownMenuItem(value: u, child: Text(u, style: AppTextStyles.bodyMedium(context)));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _unit = val);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  AppGap.sm(context),

                  // Storage Zone selection
                  Text('Storage Zone', style: AppTextStyles.labelMedium(context)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    key: ValueKey('zone_$_storageZone'),
                    initialValue: _storageZone,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    dropdownColor: AppColors.surface,
                    items: _zones.map((z) {
                      return DropdownMenuItem(value: z, child: Text(z.toUpperCase(), style: AppTextStyles.bodyMedium(context)));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _storageZone = val);
                    },
                  ),
                  AppGap.sm(context),

                  // Expiry Date picker
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Expiry Date', style: AppTextStyles.labelMedium(context)),
                          const SizedBox(height: 4),
                          Text(
                            _expiryDate != null 
                                ? _expiryDate!.toIso8601String().substring(0, 10) 
                                : 'No Expiry Set',
                            style: AppTextStyles.bodyLarge(context).copyWith(
                              color: _expiryDate != null ? AppColors.primary : AppColors.textSecondary,
                            ),
                          )
                        ],
                      ),
                      GestureDetector(
                        onTap: _selectExpiryDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.primary),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Pick Date',
                            style: AppTextStyles.labelMedium(context).copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  AppGap.sm(context),
                  AppTextField(
                    controller: _descController,
                    label: 'Storage Notes / Description',
                    hint: 'e.g. Keep in airtight container.',
                    maxLines: 2,
                  ),
                  AppGap.md(context),
                  
                  AppButton(
                    text: 'Add to Pantry',
                    onPressed: _submit,
                  ),
                  AppGap.sm(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
