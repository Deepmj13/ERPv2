import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../shared/formatters/formatters.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';

final _paymentsProvider = FutureProvider.autoDispose<PageResult<Payment>>((
  ref,
) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.get('/payments', query: {'limit': 200});
  return PageResult.fromJsonList(
    Map<String, dynamic>.from(res as Map),
    Payment.fromJson,
  );
});

class PaymentsScreen extends ConsumerWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_paymentsProvider),
          ),
        ],
      ),
      body: AsyncDataView(
        provider: _paymentsProvider,
        onRetry: () => ref.invalidate(_paymentsProvider),
        builder: (result) {
          if (result.items.isEmpty) {
            return const EmptyState(
              icon: Icons.payments_outlined,
              message: 'No payments recorded yet. Record one from an invoice.',
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
                      DataColumn(label: Text('Invoice')),
                      DataColumn(label: Text('Method')),
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Amount'), numeric: true),
                      DataColumn(label: Text('Status')),
                    ],
                    rows: [
                      for (final p in result.items)
                        DataRow(
                          cells: [
                            DataCell(
                              Text(
                                p.number,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            DataCell(Text(p.invoiceNumber ?? '-')),
                            DataCell(Text(p.method)),
                            DataCell(Text(dateTime(p.createdAt))),
                            DataCell(MoneyText(p.amount)),
                            DataCell(
                              StatusChip(status: p.status ?? 'COMPLETED'),
                            ),
                          ],
                        ),
                    ],
                  );
                }
                return ListView.separated(
                  itemCount: result.items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final p = result.items[i];
                    return ListTile(
                      leading: const Icon(Icons.payments_outlined),
                      title: Text(
                        p.number,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        [
                          if (p.invoiceNumber != null) p.invoiceNumber!,
                          p.method,
                          dateTime(p.createdAt),
                        ].join(' · '),
                      ),
                      trailing: MoneyText(
                        p.amount,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
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
