import 'package:flutter/material.dart';
import '../../dashboard/views/dashboard_view.dart';
import '../../kitchen/views/kitchen_view.dart';
import '../../scan/views/scan_view.dart';
import '../../grocery_list/views/grocery_list_view.dart';
import '../../profile/views/profile_view.dart';
import '../../../config/app_colors.dart';
import '../../../core/extensions/responsive_context_extension.dart';
import '../../../core/widgets/responsive_layout.dart';

class TabNotifier extends ValueNotifier<int> {
  TabNotifier(super.value);

  int previousTab = 0;

  void switchTab(int index) {
    if (value != index) {
      previousTab = value;
      value = index;
    } else {
      notifyListeners();
    }
  }

  void navigateBack() {
    final target = (previousTab != value) ? previousTab : 0;
    switchTab(target);
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  static final TabNotifier activeTabNotifier = TabNotifier(0);
  static void switchTab(int index) {
    activeTabNotifier.switchTab(index);
  }

  static void navigateBack() {
    activeTabNotifier.navigateBack();
  }

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = HomeShell.activeTabNotifier.value;
    HomeShell.activeTabNotifier.addListener(_onTabNotification);
  }

  @override
  void dispose() {
    HomeShell.activeTabNotifier.removeListener(_onTabNotification);
    super.dispose();
  }

  void _onTabNotification() {
    if (mounted && _currentIndex != HomeShell.activeTabNotifier.value) {
      setState(() {
        _currentIndex = HomeShell.activeTabNotifier.value;
      });
    }
  }

  void _onTabSelected(int index) {
    HomeShell.switchTab(index);
  }

  final List<Widget> _pages = [
    const DashboardView(),
    const KitchenView(),
    const ScanView(),
    const GroceryListView(),
    const ProfileView(),
  ];

  @override
  Widget build(BuildContext context) {
    final double navLabelSize = context.scaleFont(11.0);

    return ResponsiveLayout(
      mobile: Scaffold(
        body: IndexedStack(index: _currentIndex, children: _pages),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabSelected,
          type: BottomNavigationBarType.fixed,
          backgroundColor: AppColors.surface,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textSecondary,
          selectedLabelStyle: TextStyle(
            fontFamily: 'Outfit',
            fontSize: navLabelSize,
            fontWeight: FontWeight.bold,
          ),
          unselectedLabelStyle: TextStyle(
            fontFamily: 'Outfit',
            fontSize: navLabelSize,
          ),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.kitchen_outlined),
              activeIcon: Icon(Icons.kitchen),
              label: 'Kitchen',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.qr_code_scanner_outlined),
              activeIcon: Icon(Icons.qr_code_scanner),
              label: 'Scan',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.shopping_basket_outlined),
              activeIcon: Icon(Icons.shopping_basket),
              label: 'List',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
      tablet: Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _currentIndex,
              onDestinationSelected: _onTabSelected,
              backgroundColor: AppColors.surface,
              selectedIconTheme: const IconThemeData(color: AppColors.primary),
              unselectedIconTheme: const IconThemeData(
                color: AppColors.textSecondary,
              ),
              labelType: NavigationRailLabelType.all,
              selectedLabelTextStyle: TextStyle(
                fontFamily: 'Outfit',
                color: AppColors.primary,
                fontSize: navLabelSize,
                fontWeight: FontWeight.bold,
              ),
              unselectedLabelTextStyle: TextStyle(
                fontFamily: 'Outfit',
                color: AppColors.textSecondary,
                fontSize: navLabelSize,
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: Text('Dashboard'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.kitchen_outlined),
                  selectedIcon: Icon(Icons.kitchen),
                  label: Text('Kitchen'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.qr_code_scanner_outlined),
                  selectedIcon: Icon(Icons.qr_code_scanner),
                  label: Text('Scan'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.shopping_basket_outlined),
                  selectedIcon: Icon(Icons.shopping_basket),
                  label: Text('List'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: Text('Profile'),
                ),
              ],
            ),
            const VerticalDivider(
              thickness: 1,
              width: 1,
              color: AppColors.cardBorder,
            ),
            Expanded(
              child: IndexedStack(index: _currentIndex, children: _pages),
            ),
          ],
        ),
      ),
    );
  }
}
