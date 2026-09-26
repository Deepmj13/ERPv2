import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  void _goBranch(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final shell = widget.navigationShell;
        return Scaffold(
          body: Row(
            children: [
              if (wide)
                NavigationRail(
                  selectedIndex: shell.currentIndex,
                  onDestinationSelected: _goBranch,
                  groupAlignment: -0.9,
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard),
                      label: Text('Dashboard'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.people_outline),
                      selectedIcon: Icon(Icons.people),
                      label: Text('Customers'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.inventory_2_outlined),
                      selectedIcon: Icon(Icons.inventory_2),
                      label: Text('Products'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.warehouse_outlined),
                      selectedIcon: Icon(Icons.warehouse),
                      label: Text('Inventory'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.assignment_outlined),
                      selectedIcon: Icon(Icons.assignment),
                      label: Text('Orders'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.receipt_long_outlined),
                      selectedIcon: Icon(Icons.receipt_long),
                      label: Text('Invoices'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.payments_outlined),
                      selectedIcon: Icon(Icons.payments),
                      label: Text('Payments'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.account_balance_wallet_outlined),
                      selectedIcon: Icon(Icons.account_balance_wallet),
                      label: Text('Expenses'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.group_outlined),
                      selectedIcon: Icon(Icons.group),
                      label: Text('Users'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.history_outlined),
                      selectedIcon: Icon(Icons.history),
                      label: Text('Audit'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('Settings'),
                    ),
                  ],
                ),
              Expanded(child: shell),
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: shell.currentIndex.clamp(0, 3),
                  onDestinationSelected: (i) {
                    _goBranch(i);
                    context.go([ActionItem.dashboard, ActionItem.customers,
                              ActionItem.products, ActionItem.inventory][i]
                        .path);
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.people_outline),
                      selectedIcon: Icon(Icons.people),
                      label: 'Customers',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.inventory_2_outlined),
                      selectedIcon: Icon(Icons.inventory_2),
                      label: 'Products',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.warehouse_outlined),
                      selectedIcon: Icon(Icons.warehouse),
                      label: 'Inventory',
                    ),
                  ],
                ),
        );
      },
    );
  }
}

enum ActionItem {
  dashboard('/'),
  customers('/customers'),
  products('/products'),
  inventory('/inventory');

  const ActionItem(this.path);
  final String path;
}