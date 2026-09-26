import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../shared/errors/error_text.dart';
import '../../shared/formatters/formatters.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/sale_composer.dart' show SaleComposer, SaleKind;

final _invoiceProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final api = ref.watch(apiClientProvider);
  return Map<String, dynamic>.from(await api.get('/invoices/$id') as Map);
});

class InvoiceDetailScreen extends ConsumerWidget {
  const InvoiceDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(apiClientProvider);
    final async = ref.watch(_invoiceProvider(id));

    Future<void> action(
      Future<dynamic> Function() call,
      String success,
    ) async {
      try {
        await call();
        if (context.mounted) {
          ref.invalidate(_invoiceProvider(id));
          showMessage(context, success);
        }
      } on Exception catch (e) {
        if (context.mounted) showErrorDialog(context, e);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_invoiceProvider(id)),
          ),
        ],
      ),
      body: async.when(
        data: (inv) {
          final status = inv['status'] as String? ?? '';
          final canPost = status == 'DRAFT';
          final canCancel = status == 'DRAFT' || status == 'OPEN' || status == 'PARTIALLY_PAID';
          final canPay = status == 'OPEN' || status == 'PARTIALLY_PAID';

          final items = (inv['items'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();

          final customer = inv['customer'] as Map?;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              inv['number'] as String? ?? '',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          StatusChip(status: status),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text('Customer: ${customer?['name'] ?? '-'}'),
                      if (customer?['email'] != null)
                        Text('Email: ${customer?['email']}'),
                      const SizedBox(height: 8),
                      Text('Issued: ${dateTime(inv['issueDate'] as String?)}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    for (final item in items)
                      ListTile(
                        dense: true,
                        title: Text(
                          ((item['product'] as Map?)?['name'] ?? 'Item')
                              .toString(),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${item['quantity']} × ${money(item['unitPrice'])}'
                          '${(num.tryParse(item['taxRate']?.toString() ?? '0') ?? 0) > 0
                              ? '   tax ${item['taxRate']}%'
                              : ''}',
                        ),
                        trailing: Text(money(item['lineTotal'])),
                      ),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _SumRow(label: 'Subtotal', value: inv['subtotal']),
                          _SumRow(
                              label: 'Tax', value: inv['taxTotal']),
                          _SumRow(label: 'Total', value: inv['totalAmount'], bold: true),
                          const Divider(height: 16),
                          _SumRow(
                              label: 'Paid', value: inv['amountPaid']),
                          _SumRow(
                              label: 'Outstanding',
                              value: inv['outstanding'],
                              bold: true,
                              color: Theme.of(context).colorScheme.error),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (canPost || canCancel || canPay)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (canPost)
                      FilledButton.icon(
                        onPressed: () => action(
                          () => api.post('/invoices/${inv['id']}/post'),
                          'Invoice posted',
                        ),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Post invoice'),
                      ),
                    if (canPay)
                      FilledButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => _PaymentDialog(
                              invoice: inv,
                              onDone: () =>
                                  ref.invalidate(_invoiceProvider(id)),
                            ),
                          );
                        },
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text('Record payment'),
                      ),
                    if (canCancel)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).colorScheme.error,
                        ),
                        onPressed: () async {
                          final ok = await confirmDialog(
                            context,
                            title: 'Cancel invoice',
                            message:
                                'This will reverse posted stock. Continue?',
                            confirmLabel: 'Cancel invoice',
                            destructive: true,
                          );
                          if (ok) {
                            await action(
                              () => api.post('/invoices/${inv['id']}/cancel'),
                              'Invoice cancelled',
                            );
                          }
                        },
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Cancel invoice'),
                      ),
                  ],
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(message: '$e'),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => showDialog(
                context: context,
                builder: (context) => SaleComposer(
                  kind: SaleKind.invoice,
                  onCreated: (created) {
                    ref.invalidate(_invoiceProvider(id));
                    showMessage(
                        context, '${created['number']} created');
                  },
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('New invoice'),
            ),
          ),
        ),
      ),
    );
  }
}

class _SumRow extends StatelessWidget {
  const _SumRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.color,
  });

  final String label;
  final dynamic value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = (bold
            ? Theme.of(context).textTheme.titleMedium
            : Theme.of(context).textTheme.bodyMedium)
        ?.copyWith(
          fontWeight: bold ? FontWeight.w700 : null,
          color: color,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Text(money(value), style: style),
        ],
      ),
    );
  }
}

class _PaymentDialog extends ConsumerStatefulWidget {
  const _PaymentDialog({required this.invoice, required this.onDone});
  final Map<String, dynamic> invoice;
  final VoidCallback onDone;

  @override
  ConsumerState<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<_PaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount = TextEditingController(
      text: (widget.invoice['outstanding'] ?? 0).toString());
  String? _method = 'BANK_TRANSFER';
  bool _submitting = false;

  static const _methods = [
    ('CASH', 'Cash'),
    ('BANK_TRANSFER', 'Bank transfer'),
    ('CARD', 'Card'),
    ('CHEQUE', 'Cheque'),
    ('CREDIT', 'Credit'),
  ];

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(apiClientProvider)
          .post('/payments', body: {
            'invoiceId': widget.invoice['id'],
            'amount': double.tryParse(_amount.text) ?? 0,
            'method': _method,
          });
      if (mounted) {
        showMessage(context, 'Payment recorded');
        widget.onDone();
        Navigator.pop(context);
      }
    } on Exception catch (e) {
      if (mounted) {
        showErrorDialog(context, e, title: 'Payment failed');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Record payment',
      submitLabel: 'Record',
      submitting: _submitting,
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Invoice ${widget.invoice['number']}'),
            const SizedBox(height: 4),
            Text(
              'Outstanding: ${money(widget.invoice['outstanding'])}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount *'),
              validator: (v) {
                final n = num.tryParse(v ?? '');
                if (n == null || n <= 0) return 'Enter a valid amount';
                final outstanding =
                    num.tryParse(widget.invoice['outstanding'].toString()) ?? 0;
                if (n > outstanding) {
                  return 'Cannot exceed outstanding amount';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Method *'),
              items: [
                for (final (value, label) in _methods)
                  DropdownMenuItem(value: value, child: Text(label)),
              ],
              onChanged: (v) => setState(() => _method = v),
            ),
          ],
        ),
      ),
    );
  }
}