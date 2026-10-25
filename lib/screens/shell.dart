import 'package:flutter/material.dart';

import '../app_state.dart';
import '../ui.dart';
import 'clients_screen.dart';
import 'dashboard_screen.dart';
import 'products_screen.dart';
import 'sale_screen.dart';
import 'sales_screen.dart';
import 'settings_screen.dart';

/// Menu principal : barre latérale sur tablette / terminal large, barre du bas sur téléphone.
class Shell extends StatelessWidget {
  const Shell({super.key});

  static const _items = [
    (Icons.dashboard_outlined, Icons.dashboard, 'Accueil'),
    (Icons.point_of_sale_outlined, Icons.point_of_sale, 'Vente'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Factures'),
    (Icons.groups_outlined, Icons.groups, 'Clients'),
    (Icons.inventory_2_outlined, Icons.inventory_2, 'Produits'),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = const [
      DashboardScreen(),
      SaleScreen(),
      SalesScreen(),
      ClientsScreen(),
      ProductsScreen(),
    ];
    return ValueListenableBuilder<int>(
      valueListenable: AppState.i.tab,
      builder: (context, index, _) {
        final body = IndexedStack(index: index, children: pages);
        void go(int i) => AppState.i.tab.value = i;
        if (MediaQuery.sizeOf(context).width >= kWide) {
          return Scaffold(
            body: Row(children: [
              NavigationRail(
                selectedIndex: index,
                onDestinationSelected: go,
                labelType: NavigationRailLabelType.all,
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Icon(Icons.menu_book, size: 32),
                ),
                trailing: Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: IconButton(
                        tooltip: 'Réglages',
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: () => openSettings(context),
                      ),
                    ),
                  ),
                ),
                destinations: [
                  for (final it in _items)
                    NavigationRailDestination(icon: Icon(it.$1), selectedIcon: Icon(it.$2), label: Text(it.$3)),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ]),
          );
        }
        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: go,
            destinations: [
              for (final it in _items)
                NavigationDestination(icon: Icon(it.$1), selectedIcon: Icon(it.$2), label: it.$3),
            ],
          ),
        );
      },
    );
  }
}

void openSettings(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
