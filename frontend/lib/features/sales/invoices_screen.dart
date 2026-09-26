import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../shared/formatters/formatters.dart';
import '../../shared/models/models.dart';
import '../../shared/state/string_notifier.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/sale_composer.dart';

final _invoicesProvider =
    FutureProvider.autoDispose<PageResult<Invoice>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final status = ref.watch(_invoiceStatusFilter);
  final res = await api.get('/invoices', query: {
    'limit': 200,
    'status': ?status,
  });
  return PageResult.fromJsonList(
    Map<String, dynamic>.from(res as Map),
    Invoice.fromJson,
  );
});

final _invoiceStatusFilter =
    NotifierProvider<NullableStringNotifier, String?>(NullableStringNotifier.new);

const _filterOptions = [
  (null, 'All'),
  ('OPEN', 'Open'),
  ('PARTIALLY_PAID', 'Partially paid'),
  ('PAID', 'Paid'),
  ('CANCELLED', 'Cancelled'),
];

class InvoicesScreen extends ConsumerWidget {
  const InvoicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(_invoiceStatusFilter);
    return ListPageScaffold(
      title: 'Invoices',
      onRefresh: () async => ref.invalidate(_invoicesProvider),
      onAdd: () => showDialog(
        context: context,
        builder: (context) => SaleComposer(
          kind: SaleKind.invoice,
          onCreated: (created) {
            ref.invalidate(_invoicesProvider);
            showMessage(context, '${created['number']} created');
            context.go('/invoices/${created['id']}');
          },
        ),
      ),
      actions: [
        PopupMenuButton<String?>(
          initialValue: filter,
          tooltip: 'Filter by status',
          onSelected: (v) => ref.read(_invoiceStatusFilter.notifier).set(v),
          itemBuilder: (context) => [
            for (final (value, label) in _filterOptions)
              PopupMenuItem(value: value, child: Text(label)),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.filter_list),
                const SizedBox(width: 4),
                Text(
                  _filterOptions.firstWhere((o) => o.$1 == filter).$2,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
          ),
        ),
      ],
      child: AsyncDataView(
        provider: _invoicesProvider,
        onRetry: () => ref.invalidate(_invoicesProvider),
        builder: (result) {
          if (result.items.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              message: 'No invoices yet. Create an invoice to get started.',
            );
          }
          return Card(
            margin: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 700;
                if (wide) {
                  return DataTable(
                    columns: const [
                      DataColumn(label: Text('Number')),
                      DataColumn(label: Text('Customer')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Total'), numeric: true),
                      DataColumn(label: Text('Due')),
                    ],
                    rows: [
                      for (final inv in result.items)
                        DataRow(
                          onSelectChanged: (_) =>
                              context.go('/invoices/${inv.id}'),
                          cells: [
                            DataCell(Text(inv.number,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600))),
                            DataCell(Text(inv.customerName ?? '-')),
                            DataCell(StatusChip(status: inv.status)),
                            DataCell(MoneyText(inv.total)),
                            DataCell(Text(money(inv.outstanding))),
                          ],
                        ),
                    ],
                  );
                }
                return ListView.separated(
                  itemCount: result.items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final inv = result.items[i];
                    return ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(
                        inv.number,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(inv.customerName ?? ''),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MoneyText(inv.total,
                              style: Theme.of(context).textTheme.bodyMedium),
                          const SizedBox(width: 4),
                          StatusChip(status: inv.status),
                        ],
                      ),
                      onTap: () => context.go('/invoices/${inv.id}'),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}