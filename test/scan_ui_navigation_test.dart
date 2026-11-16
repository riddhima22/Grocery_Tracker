import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grocery_track/features/scan/views/scan_view.dart';
import 'package:grocery_track/features/scan/providers/scan_provider.dart';
import 'package:grocery_track/features/scan/repository/scan_repository.dart';
import 'package:grocery_track/features/scan/model/scan_candidate_model.dart';
import 'package:grocery_track/features/home/views/home_shell.dart';
import 'package:grocery_track/features/kitchen/providers/kitchen_provider.dart';

class FakeScanRepository extends ScanRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScanProvider scanProvider;
  late KitchenProvider kitchenProvider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    scanProvider = ScanProvider(scanRepository: FakeScanRepository());
    kitchenProvider = KitchenProvider();
    HomeShell.activeTabNotifier.value = 2; // on scan tab
  });

  Widget buildTestableWidget({required Widget child}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ScanProvider>.value(value: scanProvider),
        ChangeNotifierProvider<KitchenProvider>.value(value: kitchenProvider),
      ],
      child: MaterialApp(
        home: child,
      ),
    );
  }

  testWidgets('ScanView shows back arrow and navigates appropriately', (WidgetTester tester) async {
    await tester.pumpWidget(buildTestableWidget(child: const ScanView()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify AppBar and Back Arrow button exist
    final backButtonFinder = find.byTooltip('Back');
    expect(backButtonFinder, findsOneWidget);

    final backIconFinder = find.byIcon(Icons.arrow_back_rounded);
    expect(backIconFinder, findsOneWidget);

    // Verify Title
    expect(find.text('Scan Groceries'), findsOneWidget);

    // Tap back button when embedded in HomeShell (cannot pop route)
    await tester.tap(backButtonFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify it switched tab to 0 (Dashboard)
    expect(HomeShell.activeTabNotifier.value, 0);
  });

  testWidgets('ScanView displays Items Detected label and accurate item count', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Populate candidates in scanProvider
    final candidates = [
      const ScanCandidateModel(
        id: 'cand-1',
        scanSession: 'sess-123',
        name: 'Organic Milk',
        brand: 'Horizon',
        description: 'Organic whole milk',
        category: 'Dairy',
        quantity: 1.0,
        unit: 'L',
        storageZone: 'fridge',
        confidence: 'High',
        validationWarnings: [],
        selected: true,
      ),
      const ScanCandidateModel(
        id: 'cand-2',
        scanSession: 'sess-123',
        name: 'Whole Grain Bread',
        brand: 'Wonder',
        description: 'Sliced bread',
        category: 'Bakery',
        quantity: 2.0,
        unit: 'pcs',
        storageZone: 'pantry',
        confidence: 'High',
        validationWarnings: [],
        selected: true,
      ),
      const ScanCandidateModel(
        id: 'cand-3',
        scanSession: 'sess-123',
        name: 'Red Apples',
        brand: 'Farm Fresh',
        description: 'Crisp red apples',
        category: 'Fruits',
        quantity: 6.0,
        unit: 'pcs',
        storageZone: 'counter',
        confidence: 'High',
        validationWarnings: [],
        selected: true,
      ),
    ];

    scanProvider.setCandidatesForTesting(candidates);
    scanProvider.setUIStateForTesting(ScanUIState.review);

    await tester.pumpWidget(buildTestableWidget(child: const ScanView()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Verify "Items Detected" label is present (NOT "AI Detected")
    expect(find.text('Items Detected'), findsOneWidget);
    expect(find.text('AI Detected'), findsNothing);

    // 2. Verify accurate item count badge
    expect(find.text('3 items'), findsOneWidget);

    // 3. Verify all candidate items rendered
    expect(find.text('Organic Milk'), findsOneWidget);
    expect(find.text('Whole Grain Bread'), findsOneWidget);
    expect(find.text('Red Apples'), findsOneWidget);
  });

  testWidgets('TabNotifier accurately tracks previous tab and navigates back', (WidgetTester tester) async {
    // 1. Initial tab is 0
    HomeShell.switchTab(0);
    expect(HomeShell.activeTabNotifier.value, 0);

    // 2. Switch to Kitchen tab 1
    HomeShell.switchTab(1);
    expect(HomeShell.activeTabNotifier.value, 1);
    expect(HomeShell.activeTabNotifier.previousTab, 0);

    // 3. Switch to Scan tab 2
    HomeShell.switchTab(2);
    expect(HomeShell.activeTabNotifier.value, 2);
    expect(HomeShell.activeTabNotifier.previousTab, 1);

    // 4. Navigate back from ScanView
    HomeShell.navigateBack();
    expect(HomeShell.activeTabNotifier.value, 1);

    // 5. From Dashboard (0) to Scan (2) and navigate back
    HomeShell.switchTab(0);
    HomeShell.switchTab(2);
    expect(HomeShell.activeTabNotifier.previousTab, 0);
    HomeShell.navigateBack();
    expect(HomeShell.activeTabNotifier.value, 0);
  });

  testWidgets('ScanView Back Arrow returns to previous tab in HomeShell', (WidgetTester tester) async {
    // User came from Kitchen (tab 1) to Scan (tab 2)
    HomeShell.switchTab(1);
    HomeShell.switchTab(2);

    await tester.pumpWidget(buildTestableWidget(child: const ScanView()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final backButtonFinder = find.byTooltip('Back');
    expect(backButtonFinder, findsOneWidget);

    // Tap back button
    await tester.tap(backButtonFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Navigates back to Kitchen (tab 1)
    expect(HomeShell.activeTabNotifier.value, 1);
  });
}
