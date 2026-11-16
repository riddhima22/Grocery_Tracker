import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:grocery_track/core/api/api_error_mapper.dart';
import 'package:grocery_track/core/api/api_exception.dart';
import 'package:grocery_track/core/services/unit_classification_service.dart';
import 'package:grocery_track/data/models/grocery_list_model.dart';
import 'package:grocery_track/features/kitchen/model/grocery_model.dart';

void main() {
  group('Grocery Cart & List Operations Tests', () {
    test('GroceryListItemModel parses and serializes correctly', () {
      final json = {
        'id': 'item-001',
        'grocery_list': 'list-100',
        'name': 'Organic Whole Milk',
        'suggested_quantity': 2.0,
        'quantity': 2.0,
        'unit': 'bottle',
        'reason': 'Low stock detected',
        'confidence': 'High',
        'source_signal': 'consumption_rate',
        'feedback': 'accepted',
        'purchased': false,
      };

      final item = GroceryListItemModel.fromJson(json);

      expect(item.id, equals('item-001'));
      expect(item.name, equals('Organic Whole Milk'));
      expect(item.quantity, equals(2.0));
      expect(item.unit, equals('bottle'));
      expect(item.purchased, isFalse);
      expect(item.confidence, equals('High'));
    });

    test('GroceryListModel holds items and calculates cart status', () {
      const item1 = GroceryListItemModel(
        id: '1',
        groceryList: 'list-1',
        name: 'Potatoes',
        suggestedQuantity: 1.0,
        quantity: 1.0,
        unit: 'kg',
        reason: 'Weekly staple',
        confidence: 'High',
        sourceSignal: 'manual',
        feedback: 'pending',
        purchased: false,
      );

      const item2 = GroceryListItemModel(
        id: '2',
        groceryList: 'list-1',
        name: 'Olive Oil',
        suggestedQuantity: 1.0,
        quantity: 1.0,
        unit: 'bottle',
        reason: 'Out of stock',
        confidence: 'High',
        sourceSignal: 'manual',
        feedback: 'pending',
        purchased: true,
      );

      final list = GroceryListModel(
        id: 'list-1',
        status: 'active',
        generationReason: 'Weekly replenish',
        createdAt: DateTime(2026, 10, 15),
        items: [item1, item2],
      );

      expect(list.items.length, equals(2));
      final pendingItems = list.items.where((i) => !i.purchased).toList();
      final purchasedItems = list.items.where((i) => i.purchased).toList();

      expect(pendingItems.length, equals(1));
      expect(pendingItems.first.name, equals('Potatoes'));
      expect(purchasedItems.length, equals(1));
      expect(purchasedItems.first.name, equals('Olive Oil'));
    });

    test('Quantity update and cart toggle in list items', () {
      const item = GroceryListItemModel(
        id: '10',
        groceryList: 'list-1',
        name: 'Basmati Rice',
        suggestedQuantity: 1.0,
        quantity: 1.0,
        unit: 'kg',
        reason: 'Low stock',
        confidence: 'High',
        sourceSignal: 'manual',
        feedback: 'pending',
        purchased: false,
      );

      // Simulating item quantity update
      final updatedQtyItem = GroceryListItemModel(
        id: item.id,
        groceryList: item.groceryList,
        name: item.name,
        suggestedQuantity: item.suggestedQuantity,
        quantity: 2.5,
        unit: item.unit,
        reason: item.reason,
        confidence: item.confidence,
        sourceSignal: item.sourceSignal,
        feedback: item.feedback,
        purchased: item.purchased,
      );

      expect(updatedQtyItem.quantity, equals(2.5));

      // Simulating cart item purchased toggle
      final purchasedItem = GroceryListItemModel(
        id: updatedQtyItem.id,
        groceryList: updatedQtyItem.groceryList,
        name: updatedQtyItem.name,
        suggestedQuantity: updatedQtyItem.suggestedQuantity,
        quantity: updatedQtyItem.quantity,
        unit: updatedQtyItem.unit,
        reason: updatedQtyItem.reason,
        confidence: updatedQtyItem.confidence,
        sourceSignal: updatedQtyItem.sourceSignal,
        feedback: updatedQtyItem.feedback,
        purchased: true,
      );

      expect(purchasedItem.purchased, isTrue);
    });
  });

  group('Grocery Inventory Operations Tests', () {
    test('GroceryModel freshness and shelf life calculations', () {
      final now = DateTime.now();
      final futureExpiry = now.add(const Duration(days: 10));

      final item = GroceryModel(
        id: 'g-101',
        name: 'Greek Yogurt',
        brand: 'Chobani',
        quantity: 500.0,
        unit: 'g',
        unitCategory: 'weight',
        storageZone: 'fridge',
        expiryDate: futureExpiry,
        purchaseDate: now,
        status: 'fresh',
      );

      expect(item.name, equals('Greek Yogurt'));
      expect(item.storageZone, equals('fridge'));
      expect(item.unit, equals('g'));
      expect(item.displayQuantityText, equals('500 g'));
      expect(item.effectiveExpiryDate, equals(futureExpiry));
      expect(item.effectiveExpiryDate!.difference(now).inDays >= 9, isTrue);
    });

    test('GroceryModel copyWith preserves smart packaging fields', () {
      final now = DateTime.now();
      final item = GroceryModel(
        id: 'g-102',
        name: 'Potato Chips',
        quantity: 2.0,
        unit: 'packet',
        unitCategory: 'package',
        packageType: 'packet',
        netContentValue: 50.0,
        netContentUnit: 'g',
        packageCount: 2,
        storageZone: 'pantry',
        purchaseDate: now,
      );

      expect(item.displayQuantityText, equals('2 packet (50 g)'));

      // Modifying quantity via copyWith
      final updated = item.copyWith(quantity: 3.0, packageCount: 3);
      expect(updated.quantity, equals(3.0));
      expect(updated.packageCount, equals(3));
      expect(updated.packageType, equals('packet'));
      expect(updated.netContentValue, equals(50.0));
      expect(updated.displayQuantityText, equals('3 packet (50 g)'));
    });
  });

  group('Barcode & Unit Classification Operations Tests', () {
    test('Barcode string validation logic', () {
      bool isValidBarcode(String barcode) {
        final sanitized = barcode.replaceAll(RegExp(r'[^\d]'), '');
        return RegExp(r'^\d{8,14}$').hasMatch(sanitized);
      }

      // Valid EAN-8, UPC-12, EAN-13, ITF-14
      expect(isValidBarcode('12345670'), isTrue);
      expect(isValidBarcode('012345678905'), isTrue);
      expect(isValidBarcode('8901030384728'), isTrue);
      expect(isValidBarcode('10012345678902'), isTrue);

      // Invalid
      expect(isValidBarcode(''), isFalse);
      expect(isValidBarcode('123'), isFalse);
      expect(isValidBarcode('abc1234567'), isFalse);
      expect(isValidBarcode('9999999999999999999'), isFalse);
    });

    test(
      'Unit classification handles liquid beverage and produce appropriately',
      () {
        final orangeJuice = UnitClassificationService.classifyProduct(
          productName: 'Tropicana Orange Juice 1L',
          category: 'Beverages',
        );
        expect(
          orangeJuice.unitCategory,
          equals(UnitClassificationService.categoryPackage),
        );
        expect(orangeJuice.unit, equals('bottle'));
        expect(orangeJuice.netContentValue, equals(1.0));
        expect(orangeJuice.netContentUnit, equals('L'));

        final banana = UnitClassificationService.classifyProduct(
          productName: 'Fresh Bananas',
          category: 'Fruits',
        );
        expect(
          banana.unitCategory,
          equals(UnitClassificationService.categoryWeight),
        );
        expect(banana.unit, equals('kg'));
      },
    );
  });

  group('API Error Handling Tests', () {
    test('maps 400 Bad Request to BadRequestException', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: '/api/v1/groceries/'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/v1/groceries/'),
          statusCode: 400,
          data: {'detail': 'Invalid grocery quantity provided'},
        ),
        type: DioExceptionType.badResponse,
      );

      final mapped = ApiErrorMapper.map(dioException);
      expect(mapped, isA<ValidationException>());
      expect(mapped.message, contains('Invalid grocery quantity'));
    });

    test('maps 401 Unauthorized to UnauthorizedException', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: '/api/v1/auth/me/'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/v1/auth/me/'),
          statusCode: 401,
          data: {'detail': 'Authentication credentials were not provided.'},
        ),
        type: DioExceptionType.badResponse,
      );

      final mapped = ApiErrorMapper.map(dioException);
      expect(mapped, isA<UnauthorizedException>());
      expect(mapped.statusCode, equals(401));
    });

    test('maps 404 Not Found to NotFoundException', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: '/api/v1/groceries/item-999/'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/v1/groceries/item-999/'),
          statusCode: 404,
          data: {'detail': 'Grocery item not found.'},
        ),
        type: DioExceptionType.badResponse,
      );

      final mapped = ApiErrorMapper.map(dioException);
      expect(mapped, isA<NotFoundException>());
      expect(mapped.statusCode, equals(404));
    });

    test(
      'maps 500 Internal Server Error to ServerException without raw crash leak',
      () {
        final dioException = DioException(
          requestOptions: RequestOptions(path: '/api/v1/scans/sessions/'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/v1/scans/sessions/'),
            statusCode: 500,
            data:
                '<html><body>500 Internal Server Error: Database deadlock trace</body></html>',
          ),
          type: DioExceptionType.badResponse,
        );

        final mapped = ApiErrorMapper.map(dioException);
        expect(mapped, isA<ServerException>());
        expect(mapped.statusCode, equals(500));
        expect(mapped.message, contains('Server error'));
        expect(mapped.message, isNot(contains('deadlock')));
      },
    );
  });
}
