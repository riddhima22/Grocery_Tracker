class GroceryListItemModel {
  final String id;
  final String groceryList;
  final String name;
  final double suggestedQuantity;
  final double quantity;
  final String unit;
  
  final String reason;
  final String confidence;
  final String sourceSignal;
  final String feedback;
  final bool purchased;

  const GroceryListItemModel({
    required this.id,
    required this.groceryList,
    required this.name,
    required this.suggestedQuantity,
    required this.quantity,
    required this.unit,
    required this.reason,
    required this.confidence,
    required this.sourceSignal,
    required this.feedback,
    required this.purchased,
  });

  factory GroceryListItemModel.fromJson(Map<String, dynamic> json) {
    return GroceryListItemModel(
      id: json['id'] ?? '',
      groceryList: json['grocery_list'] ?? '',
      name: json['name'] ?? '',
      suggestedQuantity: double.tryParse(json['suggested_quantity']?.toString() ?? '1.0') ?? 1.0,
      quantity: double.tryParse(json['quantity']?.toString() ?? '1.0') ?? 1.0,
      unit: json['unit'] ?? 'pcs',
      reason: json['reason'] ?? '',
      confidence: json['confidence'] ?? 'Medium',
      sourceSignal: json['source_signal'] ?? '',
      feedback: json['feedback'] ?? 'pending',
      purchased: json['purchased'] ?? false,
    );
  }
}

class GroceryListModel {
  final String id;
  final String status;
  final String generationReason;
  final DateTime createdAt;
  final List<GroceryListItemModel> items;

  const GroceryListModel({
    required this.id,
    required this.status,
    required this.generationReason,
    required this.createdAt,
    required this.items,
  });

  factory GroceryListModel.fromJson(Map<String, dynamic> json) {
    return GroceryListModel(
      id: json['id'] ?? '',
      status: json['status'] ?? 'active',
      generationReason: json['generation_reason'] ?? '',
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
      items: (json['items'] as List?)?.map((i) => GroceryListItemModel.fromJson(i)).toList() ?? const [],
    );
  }
}
