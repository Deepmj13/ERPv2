import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../shared/formatters/formatters.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';

final _warehousesProvider =
    FutureProvider.autoDispose<List<Warehouse>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.get('/warehouses', query: {'limit': 200});
  return (res['items'] as List)
      .map((w) => Warehouse.fromJson(Map<String, dynamic>.from(w as Map)))
      .toList();
});

final _movementsProvider =
    FutureProvider.autoDispose<PageResult<StockMovement>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.get('/inventory/movements', query: {'limit': 100});
  return PageResult.fromJsonList(
    Map<String, dynamic>.from(res as Map),
    StockMovement.fromJson,
  );
});

final _lowStockProvider = FutureProvider.autoDispose<List<Product>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.get('/inventory/low-stock');
  final items = (res['items'] as List?) ?? (res as List?) ?? [];
  return items
      .map((p) => Product.fromJson(Map<String, dynamic>.from(p as Map)))
      .toList();
});

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Inventory'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.warehouse_outlined), text: 'Warehouses'),
              Tab(icon: Icon(Icons.low_priority), text: 'Low stock'),
              Tab(icon: Icon(Icons.history), text: 'Movements'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const _WarehousesTab(),
            const _LowStockTab(),
            const _MovementsTab(),
          ],
        ),
      ),
    );
  }
}

class _WarehousesTab extends ConsumerWidget {
  const _WarehousesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncDataView(
      provider: _warehousesProvider,
      onRetry: () => ref.invalidate(_warehousesProvider),
      builder: (warehouses) {
        if (warehouses.isEmpty) {
          return const EmptyState(
            icon: Icons.warehouse_outlined,
            message: 'No warehouses yet.',
          );
        }
        return Card(
          margin: const EdgeInsets.all(16),
          child: Column(
            children: [
              for (final w in warehouses)
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.warehouse)),
                  title: Text(w.name),
                  subtitle: Text(w.location ?? ''),
                  trailing: const Icon(Icons.chevron_right),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LowStockTab extends ConsumerWidget {
  const _LowStockTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncDataView(
      provider: _lowStockProvider,
      onRetry: () => ref.invalidate(_lowStockProvider),
      builder: (products) {
        if (products.isEmpty) {
          return const EmptyState(
            icon: Icons.check_circle_outline,
            message: 'No low-stock products.',
          );
        }
        return Card(
          margin: const EdgeInsets.all(16),
          child: Column(
            children: [
              for (final p in products)
                ListTile(
                  leading: Icon(
                    Icons.inventory_2_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(p.name),
                  subtitle: Text(p.sku ?? ''),
                  trailing: Text(
                    '${p.stockQuantity ?? 0}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MovementsTab extends ConsumerWidget {
  const _MovementsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncDataView(
      provider: _movementsProvider,
      onRetry: () => ref.invalidate(_movementsProvider),
      builder: (result) {
        if (result.items.isEmpty) {
          return const EmptyState(
            icon: Icons.history,
            message: 'No stock movements yet.',
          );
        }
        return Card(
          margin: const EdgeInsets.all(16),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: result.items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final m = result.items[i];
              final negative = m.quantity < 0;
              return ListTile(
                leading: Icon(
                  negative ? Icons.arrow_upward : Icons.arrow_downward,
                  color: negative
                      ? Theme.of(context).colorScheme.error
                      : Colors.green,
                ),
                title: Text(
                  m.productName ?? m.productId ?? 'Product',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  [m.type, m.reference, dateTime(m.createdAt)]
                      .where((v) => v != null && v.isNotEmpty)
                      .join(' · '),
                ),
                trailing: Text(
                  '${negative ? '' : '+'}${m.quantity}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: negative
                        ? Theme.of(context).colorScheme.error
                        : Colors.green,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}