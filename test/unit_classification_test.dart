import 'package:flutter_test/flutter_test.dart';
import 'package:grocery_track/core/services/unit_classification_service.dart';
import 'package:grocery_track/data/models/scan_candidate_model.dart';
import 'package:grocery_track/features/kitchen/model/grocery_model.dart';

void main() {
  group('Smart Quantity & Unit Classification Tests', () {
    // Scenario 1: Loose potato detected by camera -> weight-based unit (kg/g)
    test('Scenario 1: Loose potato defaults to weight unit (kg), never pcs', () {
      final result = UnitClassificationService.classifyProduct(
        productName: 'Potato',
        category: 'Vegetables',
      );

      expect(result.unit, equals('kg'));
      expect(result.unitCategory, equals('weight'));
      expect(result.unit, isNot(equals('pcs')));
      expect(result.displayQuantityText, equals('1 kg'));
    });

    // Scenario 2: Onion retrieved from barcode/API -> weight-based unit (kg/g)
    test('Scenario 2: Onion retrieved from barcode defaults to weight unit, never pcs', () {
      final result = UnitClassificationService.classifyProduct(
        productName: 'Red Onion',
        category: 'Vegetables',
      );

      expect(['kg', 'g'].contains(result.unit), isTrue);
      expect(result.unitCategory, equals('weight'));
      expect(result.unit, isNot(equals('pcs')));
    });

    // Scenario 3: Branded 50 g chips packet -> 1 packet, net weight 50 g
    test('Scenario 3: Branded 50g chips packet parses as 1 packet with 50g net content', () {
      final result = UnitClassificationService.classifyProduct(
        productName: 'Lay\'s Classic Potato Chips',
        category: 'Snacks',
        explicitQuantityStr: '50 g',
      );

      expect(result.quantity, equals(1.0));
      expect(result.unit, equals('packet'));
      expect(result.unitCategory, equals('package'));
      expect(result.netContentValue, equals(50.0));
      expect(result.netContentUnit, equals('g'));
      expect(result.displayQuantityText, contains('1 packet'));
      expect(result.displayQuantityText, contains('50 g'));
    });

    // Scenario 4: Two packets of biscuits -> 2 packets
    test('Scenario 4: Two packets of biscuits detected as 2 packets', () {
      final result = UnitClassificationService.classifyProduct(
        productName: 'Oreo Biscuit 2 pack',
        category: 'Snacks',
      );

      expect(result.quantity, equals(2.0));
      expect(result.unit, equals('packet'));
      expect(result.packageCount, equals(2));
      expect(result.displayQuantityText, equals('2 packet'));
    });

    // Scenario 5: Cooking oil in a 1 L bottle -> 1 bottle, volume 1 L
    test('Scenario 5: Cooking oil in 1L bottle detected as 1 bottle (1 L)', () {
      final result = UnitClassificationService.classifyProduct(
        productName: 'Fortune Sunflower Cooking Oil 1L Bottle',
        category: 'Beverages',
        explicitQuantityStr: '1 L',
      );

      expect(result.quantity, equals(1.0));
      expect(result.unit, equals('bottle'));
      expect(result.unitCategory, equals('package'));
      expect(result.netContentValue, equals(1.0));
      expect(result.netContentUnit, equals('L'));
      expect(result.displayQuantityText, equals('1 bottle (1 L)'));
    });

    // Scenario 6: Loose dal -> weight-based unit (g)
    test('Scenario 6: Loose dal defaults to weight unit (g)', () {
      final result = UnitClassificationService.classifyProduct(
        productName: 'Toor Dal',
        category: 'Grains',
      );

      expect(result.unit, equals('g'));
      expect(result.unitCategory, equals('weight'));
      expect(result.unit, isNot(equals('pcs')));
    });

    // Scenario 7: Six eggs -> 6 pcs
    test('Scenario 7: Six eggs detected as count/pcs', () {
      final result = UnitClassificationService.classifyProduct(
        productName: 'Farm Fresh Brown Eggs 6 pcs',
        category: 'Dairy',
      );

      expect(result.unit, equals('pcs'));
      expect(result.quantity, equals(6.0));
      expect(result.unitCategory, equals('count'));
    });

    // Scenario 8: Product with missing category -> safe fallback with isUncertain = true
    test('Scenario 8: Product with unknown name/category flags uncertainty and defaults safely', () {
      final result = UnitClassificationService.classifyProduct(
        productName: 'XyZ Unknown Item 98213',
        category: '',
      );

      expect(result.isUncertain, isTrue);
      expect(result.unitConfidence, equals('uncertain'));
    });

    // Scenario 9: Low-confidence camera detection -> marked with low confidence
    test('Scenario 9: Low-confidence detection flags uncertainty', () {
      final result = UnitClassificationService.classifyProduct(
        productName: 'Something blurry',
        category: 'Vegetables',
        aiConfidence: 'Low',
      );

      expect(result.unitConfidence, equals('Low'));
      expect(result.isUncertain, isTrue);
    });

    // Scenario 10: Quantity conversion from g to kg (500 g -> 0.5 kg)
    test('Scenario 10: Accurate conversion between g and kg', () {
      final toKg = UnitClassificationService.convertQuantity(500.0, 'g', 'kg');
      expect(toKg, equals(0.5));

      final toG = UnitClassificationService.convertQuantity(1.5, 'kg', 'g');
      expect(toG, equals(1500.0));
    });

    // Scenario 11: Quantity conversion from ml to L (500 ml -> 0.5 L)
    test('Scenario 11: Accurate conversion between ml and L', () {
      final toL = UnitClassificationService.convertQuantity(500.0, 'ml', 'L');
      expect(toL, equals(0.5));

      final toMl = UnitClassificationService.convertQuantity(2.0, 'L', 'ml');
      expect(toMl, equals(2000.0));
    });

    // Prevention of cross-category conversion
    test('Cross-category conversions are safely rejected', () {
      final invalidWeightToVol = UnitClassificationService.convertQuantity(500.0, 'g', 'L');
      expect(invalidWeightToVol, isNull);

      final invalidCountToWeight = UnitClassificationService.convertQuantity(3.0, 'pcs', 'kg');
      expect(invalidCountToWeight, isNull);
    });

    // Scenario 12: Existing product records remain readable and editable
    test('Scenario 12: Legacy grocery records with pcs remain readable and editable', () {
      final legacyItem = GroceryModel(
        id: 'legacy-1',
        name: 'Legacy Apples',
        brand: 'Generic',
        description: '',
        iconKey: 'apple',
        category: 'Fruits',
        quantity: 4.0,
        unit: 'pcs',
        storageZone: 'fridge',
        purchaseDate: DateTime.now(),
      );

      expect(legacyItem.quantity, equals(4.0));
      expect(legacyItem.unit, equals('pcs'));
      expect(legacyItem.displayQuantityText, equals('4 pcs'));

      // Updating unit to kg works seamlessly
      final updatedItem = legacyItem.copyWith(unit: 'kg', quantity: 1.0);
      expect(updatedItem.unit, equals('kg'));
      expect(updatedItem.quantity, equals(1.0));
      expect(updatedItem.displayQuantityText, equals('1 kg'));
    });

    // Scenario 13: ScanCandidateModel supports smart packaging and display
    test('Scenario 13: ScanCandidateModel correctly handles smart unit classification from JSON', () {
      final json = {
        'id': 'cand-1',
        'detected_label': 'chips',
        'suggested_name': 'Potato Chips',
        'confidence_score': 0.88,
        'quantity': 1.0,
        'unit': 'packet',
        'unit_category': 'package',
        'package_type': 'packet',
        'net_content_value': 50.0,
        'net_content_unit': 'g',
        'storage_zone': 'pantry',
      };

      final candidate = ScanCandidateModel.fromJson(json);
      expect(candidate.unit, equals('packet'));
      expect(candidate.unitCategory, equals('package'));
      expect(candidate.netContentValue, equals(50.0));
      expect(candidate.netContentUnit, equals('g'));
      expect(candidate.displayQuantityText, equals('1 packet (50 g)'));
    });

    // Scenario 14: Barcode / API failures fallback gracefully
    test('Scenario 14: Raw string parser handles complex strings without throwing', () {
      final parse1 = UnitClassificationService.parseNetContentString('Net Wt. 750g');
      expect(parse1?['netContentValue'], equals(750.0));
      expect(parse1?['netContentUnit'], equals('g'));

      final parse2 = UnitClassificationService.parseNetContentString('1.5 L e');
      expect(parse2?['netContentValue'], equals(1.5));
      expect(parse2?['netContentUnit'], equals('L'));

      final parseEmpty = UnitClassificationService.parseNetContentString('');
      expect(parseEmpty, isNull);

      final parseGibberish = UnitClassificationService.parseNetContentString('XYZ @@??');
      expect(parseGibberish, isNull);
    });
  });
}
