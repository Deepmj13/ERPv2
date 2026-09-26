import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../errors/error_text.dart';
import '../formatters/formatters.dart';
import 'common.dart';

enum SaleKind { quotation, order, invoice }

class SaleItem {
  SaleItem({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.taxRate,
  });

  final String productId;
  final String name;
  final double quantity;
  final double unitPrice;
  final double taxRate;

  double get subtotal => quantity * unitPrice;
  double get tax => subtotal * taxRate / 100;
  double get total => subtotal + tax;
}

class SaleComposer extends ConsumerStatefulWidget {
  const SaleComposer({
    super.key,
    required this.kind,
    required this.onCreated,
    this.customerId,
    this.invoice,
  });

  final SaleKind kind;
  final void Function(Map<String, dynamic> created) onCreated;
  final String? customerId;
  final Map<String, dynamic>? invoice;

  @override
  ConsumerState<SaleComposer> createState() => _SaleComposerState();
}

class _SaleComposerState extends ConsumerState<SaleComposer> {
  final _formKey = GlobalKey<FormState>();
  String? _customerId;
  final List<SaleItem> _items = [];
  bool _submitting = false;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _products = [];

  @override
  void initState() {
    super.initState();
    _customerId = widget.customerId;
    _loadLookups();
  }

  Future<void> _loadLookups() async {
    final api = ref.read(apiClientProvider);
    setState(() => _loading = true);
    try {
      final customers = await api.get('/customers', query: {'limit': 200});
      final products = await api.get('/products', query: {'limit': 200});
      final customersList = (customers['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final productsList = (products['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _customers = customersList;
        _products = productsList;
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _addItem(Map<String, dynamic> product) {
    setState(() {
      _items.add(SaleItem(
        productId: product['id'] as String,
        name: product['name'] as String,
        quantity: 1,
        unitPrice: num.tryParse(product['salePrice']?.toString() ?? '')?.toDouble() ?? 0,
        taxRate:
            num.tryParse(product['taxRate']?.toString() ?? '0')?.toDouble() ?? 0,
      ));
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_customerId == null || _customerId!.isEmpty) {
      showMessage(context, 'Select a customer first', error: true);
      return;
    }
    if (_items.isEmpty) {
      showMessage(context, 'Add at least one line item', error: true);
      return;
    }
    final payload = {
      'customerId': _customerId,
      'items': [
        for (final i in _items)
          {
            'productId': i.productId,
            'quantity': i.quantity,
            'unitPrice': i.unitPrice,
            'taxRate': i.taxRate,
          },
      ],
    };
    setState(() => _submitting = true);
    try {
      final api = ref.read(apiClientProvider);
      final String path = switch (widget.kind) {
        SaleKind.quotation => '/quotations',
        SaleKind.order => '/sales-orders',
        SaleKind.invoice => '/invoices',
      };
      final res = await api.post(path, body: payload);
      if (mounted) {
        Navigator.pop(context);
        widget.onCreated(Map<String, dynamic>.from(res as Map));
      }
    } on Exception catch (e) {
      if (mounted) {
        showErrorDialog(context, e, title: 'Could not create');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  double get _subtotal => _items.fold(0, (a, b) => a + b.subtotal);
  double get _tax => _items.fold(0, (a, b) => a + b.tax);
  double get _total => _subtotal + _tax;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(switch (widget.kind) {
        SaleKind.quotation => 'New quotation',
        SaleKind.order => 'New sales order',
        SaleKind.invoice => 'New invoice',
      }),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      content: SizedBox(
        width: 640,
        child: _loading
            ? const SizedBox(
                height: 200, child: Center(child: CircularProgressIndicator()))
            : _error != null
                ? ErrorView(message: _error!, onRetry: _loadLookups)
                : Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _customerId,
                            decoration: const InputDecoration(
                                labelText: 'Customer *'),
                            items: [
                              for (final c in _customers)
                                DropdownMenuItem(
                                  value: c['id'] as String,
                                  child: Text(c['name'] as String),
                                ),
                            ],
                            onChanged: (v) =>
                                setState(() => _customerId = v),
                          ),
                          if (_customers.isEmpty)
                            const Text(
                              'No customers yet. Add a customer first.',
                              style: TextStyle(color: Colors.orange),
                            ),
                          const SizedBox(height: 16),
                          Text('Line items',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          const Divider(height: 8),
                          for (var i = 0; i < _items.length; i++) ...[
                            _LineItemRow(
                              item: _items[i],
                              products: _products,
                              onChanged: (updated) =>
                                  setState(() => _items[i] = updated),
                              onRemove: () =>
                                  setState(() => _items.removeAt(i)),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (_items.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text('No items yet.'),
                            ),
                          DropdownButtonFormField<String>(
                            decoration:
                                const InputDecoration(labelText: 'Add product'),
                            items: [
                              for (final p in _products)
                                DropdownMenuItem(
                                  value: p['id'] as String,
                                  child: Text(
                                    '${p['name']} '
                                    '(stock: ${p['stockQuantity'] ?? p['quantity'] ?? 0})',
                                  ),
                                ),
                            ],
                            onChanged: (id) {
                              if (id == null) return;
                              final product =
                                  _products.firstWhere((p) => p['id'] == id);
                              _addItem(product);
                            },
                          ),
                          const Divider(height: 24),
                          Row(
                            children: [
                              const Spacer(),
                              Text('Subtotal ', style: _labelStyle),
                              SizedBox(
                                width: 100,
                                child: Text(
                                  money(_subtotal),
                                  textAlign: TextAlign.right,
                                  style: _labelStyle,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              const Spacer(),
                              Text('Tax ', style: _labelStyle),
                              SizedBox(
                                width: 100,
                                child: Text(
                                  money(_tax),
                                  textAlign: TextAlign.right,
                                  style: _labelStyle,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              const Spacer(),
                              Text('Total ',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                          fontWeight: FontWeight.w700)),
                              SizedBox(
                                width: 100,
                                child: Text(
                                  money(_total),
                                  textAlign: TextAlign.right,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                          fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(switch (widget.kind) {
                  SaleKind.quotation => 'Create quotation',
                  SaleKind.order => 'Create order',
                  SaleKind.invoice => 'Create invoice',
                }),
        ),
      ],
    );
  }

  TextStyle? get _labelStyle => Theme.of(context).textTheme.bodyMedium;
}

class _LineItemRow extends StatelessWidget {
  const _LineItemRow({
    required this.item,
    required this.products,
    required this.onChanged,
    required this.onRemove,
  });

  final SaleItem item;
  final List<Map<String, dynamic>> products;
  final ValueChanged<SaleItem> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Row(
            children: [
              _Field(
                label: 'Qty',
                initial: item.quantity.toString(),
                width: 70,
                onChanged: (v) => onChanged(SaleItem(
                  productId: item.productId,
                  name: item.name,
                  quantity: num.tryParse(v)?.toDouble() ?? 0,
                  unitPrice: item.unitPrice,
                  taxRate: item.taxRate,
                )),
              ),
              const SizedBox(width: 8),
              _Field(
                label: 'Unit price',
                initial: item.unitPrice.toString(),
                width: 100,
                onChanged: (v) => onChanged(SaleItem(
                  productId: item.productId,
                  name: item.name,
                  quantity: item.quantity,
                  unitPrice: num.tryParse(v)?.toDouble() ?? 0,
                  taxRate: item.taxRate,
                )),
              ),
              const SizedBox(width: 8),
              _Field(
                label: 'Tax %',
                initial: item.taxRate.toString(),
                width: 70,
                onChanged: (v) => onChanged(SaleItem(
                  productId: item.productId,
                  name: item.name,
                  quantity: item.quantity,
                  unitPrice: item.unitPrice,
                  taxRate: num.tryParse(v)?.toDouble() ?? 0,
                )),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  money(item.total),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.initial,
    required this.width,
    required this.onChanged,
  });

  final String label;
  final String initial;
  final double width;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextFormField(
        initialValue: initial,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
        ),
        onChanged: onChanged,
      ),
    );
  }
}