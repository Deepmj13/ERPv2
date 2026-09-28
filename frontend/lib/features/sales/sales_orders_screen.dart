import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/sale_composer.dart';

final _quotationsProvider = FutureProvider.autoDispose<PageResult<Quotation>>((
  ref,
) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.get('/quotations', query: {'limit': 200});
  return PageResult.fromJsonList(
    Map<String, dynamic>.from(res as Map),
    Quotation.fromJson,
  );
});

final _ordersProvider = FutureProvider.autoDispose<PageResult<SalesOrder>>((
  ref,
) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.get('/sales-orders', query: {'limit': 200});
  return PageResult.fromJsonList(
    Map<String, dynamic>.from(res as Map),
    SalesOrder.fromJson,
  );
});

class SalesOrdersScreen extends ConsumerWidget {
  const SalesOrdersScreen({super.key});

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<dynamic> Function(ApiClient) call,
    String success,
  ) async {
    final api = ref.read(apiClientProvider);
    try {
      await call(api);
      if (context.mounted) {
        ref.invalidate(_quotationsProvider);
        ref.invalidate(_ordersProvider);
        showMessage(context, success);
      }
    } on Exception catch (e) {
      if (context.mounted) showErrorDialog(context, e);
    }
  }

  void _openComposer(BuildContext context, WidgetRef ref, SaleKind kind) {
    showDialog(
      context: context,
      builder: (context) => SaleComposer(
        kind: kind,
        onCreated: (created) {
          ref.invalidate(_quotationsProvider);
          ref.invalidate(_ordersProvider);
          showMessage(context, '${created['number']} created');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Orders & Quotes'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.request_quote_outlined), text: 'Quotations'),
              Tab(icon: Icon(Icons.assignment_outlined), text: 'Sales orders'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _QuoteTab(
              onRun: (call, success) => _run(context, ref, call, success),
            ),
            _OrdersTab(
              onRun: (call, success) => _run(context, ref, call, success),
              onNewInvoice: () => _openComposer(context, ref, SaleKind.invoice),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openComposer(context, ref, SaleKind.quotation),
          icon: const Icon(Icons.add),
          label: const Text('New quote / order'),
        ),
      ),
    );
  }
}

class _QuoteTab extends ConsumerWidget {
  const _QuoteTab({required this.onRun});

  final void Function(Future<dynamic> Function(ApiClient) call, String success)
  onRun;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncDataView(
      provider: _quotationsProvider,
      onRetry: () => ref.invalidate(_quotationsProvider),
      builder: (result) {
        if (result.items.isEmpty) {
          return const EmptyState(
            icon: Icons.request_quote_outlined,
            message: 'No quotations yet. Create one with "New quote / order".',
          );
        }
        return Card(
          margin: const EdgeInsets.all(16),
          child: Column(
            children: [
              for (final q in result.items)
                ListTile(
                  leading: const Icon(Icons.request_quote_outlined),
                  title: Text(
                    q.number,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(q.customerName ?? ''),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusChip(status: q.status),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        onSelected: (action) {
                          if (action == 'submit') {
                            onRun(
                              (a) => a.post('/quotations/${q.id}/submit'),
                              'Quotation submitted',
                            );
                          } else if (action == 'convert') {
                            onRun(
                              (a) => a.post('/quotations/${q.id}/convert'),
                              'Converted to sales order',
                            );
                          }
                        },
                        itemBuilder: (context) => [
                          if (q.status == 'DRAFT')
                            const PopupMenuItem(
                              value: 'submit',
                              child: Text('Submit'),
                            ),
                          if (q.status == 'SUBMITTED')
                            const PopupMenuItem(
                              value: 'convert',
                              child: Text('Convert to order'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _OrdersTab extends ConsumerWidget {
  const _OrdersTab({required this.onRun, required this.onNewInvoice});

  final void Function(Future<dynamic> Function(ApiClient) call, String success)
  onRun;
  final VoidCallback onNewInvoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncDataView(
      provider: _ordersProvider,
      onRetry: () => ref.invalidate(_ordersProvider),
      builder: (result) {
        if (result.items.isEmpty) {
          return const EmptyState(
            icon: Icons.assignment_outlined,
            message: 'No sales orders yet.',
          );
        }
        return Card(
          margin: const EdgeInsets.all(16),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: result.items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final o = result.items[i];
              return ListTile(
                leading: const Icon(Icons.assignment_outlined),
                title: Text(
                  o.number,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(o.customerName ?? ''),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusChip(status: o.status),
                    const SizedBox(width: 8),
                    if (o.status == 'CONFIRMED')
                      PopupMenuButton<String>(
                        onSelected: (_) {
                          onRun(
                            (a) =>
                                a.post('/sales-orders/${o.id}/create-invoice'),
                            'Invoice created',
                          );
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'invoice',
                            child: Text('Create invoice'),
                          ),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
