import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../shared/formatters/formatters.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';

class _SummaryData {
  const _SummaryData({required this.summary, required this.recent});
  final DashboardSummary summary;
  final List<Map<String, dynamic>> recent;
}

final _dashboardProvider = FutureProvider<_SummaryData>((ref) async {
  final api = ref.watch(apiClientProvider);
  final summary = await api.get('/dashboard/summary');
  final recent = List<Map<String, dynamic>>.from(
    (await api.get(
          '/invoices',
          query: {'limit': 6, 'sort': 'createdAt:desc'},
        ))['items']
        as List,
  );
  return _SummaryData(
    summary: DashboardSummary.fromJson(
      Map<String, dynamic>.from(summary as Map),
    ),
    recent: recent,
  );
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_dashboardProvider),
          ),
        ],
      ),
      body: AsyncDataView(
        provider: _dashboardProvider,
        builder: (data) {
          final s = data.summary;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final itemCount = 4;
                  final spacing = 12.0;
                  final itemWidth =
                      (constraints.maxWidth - (spacing * (itemCount - 1))) /
                      itemCount;
                  final horizontal = itemWidth >= 130;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      _StatCard(
                        width: horizontal ? itemWidth : null,
                        label: 'Total revenue',
                        icon: Icons.payments_outlined,
                        color: Colors.green,
                        child: MoneyText(s.totalRevenue),
                      ),
                      _StatCard(
                        width: horizontal ? itemWidth : null,
                        label: 'Sales this month',
                        icon: Icons.trending_up,
                        color: Colors.indigo,
                        child: MoneyText(s.salesThisMonth),
                      ),
                      _StatCard(
                        width: horizontal ? itemWidth : null,
                        label: 'Amount due',
                        icon: Icons.hourglass_top,
                        color: Colors.orange,
                        child: MoneyText(s.dueAmount),
                      ),
                      _StatCard(
                        width: horizontal ? itemWidth : null,
                        label: 'Low stock items',
                        icon: Icons.warning_amber_outlined,
                        color: Colors.red,
                        child: Text(
                          '${s.lowStock ?? 0}',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Customers',
                      icon: Icons.people_outline,
                      color: Colors.teal,
                      child: Text(
                        '${s.totalCustomers ?? 0}',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'Products',
                      icon: Icons.inventory_2_outlined,
                      color: Colors.blueGrey,
                      child: Text(
                        '${s.totalProducts ?? 0}',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'Invoices',
                      icon: Icons.receipt_long_outlined,
                      color: Colors.deepPurple,
                      child: Text(
                        '${s.totalInvoices ?? 0}',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Text(
                    'Recent invoices',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => context.go('/invoices'),
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('View all'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Card(
                child: data.recent.isEmpty
                    ? const EmptyState(
                        icon: Icons.receipt_long_outlined,
                        message:
                            'No invoices yet. Create your first invoice '
                            'from the Customers or Invoices section.',
                      )
                    : Column(
                        children: [
                          for (final inv in data.recent)
                            ListTile(
                              leading: const Icon(Icons.receipt_long_outlined),
                              title: Text(
                                inv['number'] as String,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${(inv['customer'] as Map?)?['name'] ?? '-'}'
                                ' · ${dateOnly(inv['createdAt'] as String?)}',
                              ),
                              trailing: MoneyText(inv['totalAmount']),
                              onTap: () => context.go('/invoices/${inv['id']}'),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.child,
    this.width,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 12),
              child,
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
