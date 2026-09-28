import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../shared/errors/error_text.dart';
import '../../shared/formatters/formatters.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';

final _warehousesProvider = FutureProvider.autoDispose<List<Warehouse>>((
  ref,
) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.get('/warehouses', query: {'limit': 200});
  return (res['items'] as List)
      .map((w) => Warehouse.fromJson(Map<String, dynamic>.from(w as Map)))
      .toList();
});

final _productsProvider = FutureProvider.autoDispose<List<Product>>((
  ref,
) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.get('/products', query: {'limit': 200});
  return (res['items'] as List)
      .map((p) => Product.fromJson(Map<String, dynamic>.from(p as Map)))
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

final _lowStockProvider = FutureProvider.autoDispose<List<Product>>((
  ref,
) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.get('/inventory/low-stock');
  final items = (res['items'] as List?) ?? (res as List?) ?? [];
  return items
      .map((p) => Product.fromJson(Map<String, dynamic>.from(p as Map)))
      .toList();
});

enum StockAction { receive, adjust, transfer }

extension StockActionLabel on StockAction {
  String get title => switch (this) {
    StockAction.receive => 'Receive stock',
    StockAction.adjust => 'Adjust stock',
    StockAction.transfer => 'Transfer stock',
  };

  String get submitLabel => switch (this) {
    StockAction.receive => 'Receive',
    StockAction.adjust => 'Apply adjustment',
    StockAction.transfer => 'Transfer',
  };

  String get successMessage => switch (this) {
    StockAction.receive => 'Stock received',
    StockAction.adjust => 'Stock adjusted',
    StockAction.transfer => 'Stock transferred',
  };

  String get quantityHint => switch (this) {
    StockAction.receive => 'Quantity received (positive)',
    StockAction.adjust => 'Use a negative number to remove stock',
    StockAction.transfer => 'Quantity to move',
  };
}

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  void _openAction(BuildContext context, WidgetRef ref, StockAction action) {
    showDialog<bool>(
      context: context,
      builder: (_) => StockActionDialog(
        action: action,
        onSaved: () {
          ref.invalidate(_movementsProvider);
          ref.invalidate(_lowStockProvider);
          ref.invalidate(_productsProvider);
        },
      ),
    ).then((ok) {
      if (ok == true && context.mounted) {
        showMessage(context, action.successMessage);
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Inventory'),
          actions: [
            PopupMenuButton<StockAction>(
              tooltip: 'Stock actions',
              icon: const Icon(Icons.playlist_add),
              onSelected: (a) => _openAction(context, ref, a),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: StockAction.receive,
                  child: Text('Receive stock'),
                ),
                PopupMenuItem(
                  value: StockAction.adjust,
                  child: Text('Adjust stock'),
                ),
                PopupMenuItem(
                  value: StockAction.transfer,
                  child: Text('Transfer stock'),
                ),
              ],
            ),
          ],
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

class StockActionDialog extends ConsumerStatefulWidget {
  const StockActionDialog({
    super.key,
    required this.action,
    required this.onSaved,
  });

  final StockAction action;
  final VoidCallback onSaved;

  @override
  ConsumerState<StockActionDialog> createState() => _StockActionDialogState();
}

class _StockActionDialogState extends ConsumerState<StockActionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _note = TextEditingController();

  String? _productId;
  String? _warehouseId;
  String? _fromWarehouseId;
  String? _toWarehouseId;
  String _movementType = 'ADJUSTMENT';
  List<Product> _products = [];
  List<Warehouse> _warehouses = [];
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  bool get _isTransfer => widget.action == StockAction.transfer;

  @override
  void initState() {
    super.initState();
    _loadLookups();
  }

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadLookups() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final results = await Future.wait([
        api.get('/products', query: {'limit': 200}),
        api.get('/warehouses', query: {'limit': 200}),
      ]);
      final products = (results[0]['items'] as List)
          .map((e) => Product.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final warehouses = (results[1]['items'] as List)
          .map((e) => Warehouse.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (!mounted) return;
      setState(() {
        _products = products;
        _warehouses = warehouses;
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_productId == null) {
      showMessage(context, 'Select a product first', error: true);
      return;
    }
    if (_isTransfer) {
      if (_fromWarehouseId == null || _toWarehouseId == null) {
        showMessage(context, 'Select both warehouses', error: true);
        return;
      }
      if (_fromWarehouseId == _toWarehouseId) {
        showMessage(context, 'Source and destination must differ', error: true);
        return;
      }
    }
    final quantity = num.tryParse(_quantity.text.trim());
    if (quantity == null || quantity == 0) {
      showMessage(context, 'Enter a quantity other than zero', error: true);
      return;
    }

    final note = _note.text.trim();
    setState(() => _submitting = true);
    try {
      final api = ref.read(apiClientProvider);
      if (_isTransfer) {
        await api.post(
          '/inventory/transfers',
          body: {
            'productId': _productId,
            'quantity': quantity.abs().toDouble(),
            'fromWarehouseId': _fromWarehouseId,
            'toWarehouseId': _toWarehouseId,
          },
        );
      } else {
        await api.post(
          '/inventory/adjustments',
          body: {
            'productId': _productId,
            if (_warehouseId != null) 'warehouseId': _warehouseId,
            'quantity': widget.action == StockAction.receive
                ? quantity.abs().toDouble()
                : quantity.toDouble(),
            'movementType': widget.action == StockAction.receive
                ? 'PURCHASE'
                : _movementType,
            if (note.isNotEmpty) 'note': note,
          },
        );
      }
      if (!mounted) return;
      widget.onSaved();
      Navigator.pop(context, true);
    } on Exception catch (e) {
      if (mounted) showErrorDialog(context, e, title: 'Could not save');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.action.title),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      content: SizedBox(
        width: 480,
        child: _loading
            ? const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              )
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
                        initialValue: _productId,
                        decoration: const InputDecoration(
                          labelText: 'Product *',
                        ),
                        items: [
                          for (final p in _products)
                            DropdownMenuItem(
                              value: p.id,
                              child: Text('${p.name} (${p.sku ?? ''})'),
                            ),
                        ],
                        onChanged: (v) => setState(() => _productId = v),
                      ),
                      if (_products.isEmpty)
                        const Text(
                          'No products yet. Add a product first.',
                          style: TextStyle(color: Colors.orange),
                        ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _quantity,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Quantity *',
                          helperText: widget.action.quantityHint,
                        ),
                        validator: (v) {
                          final parsed = num.tryParse((v ?? '').trim());
                          if (parsed == null) return 'Enter a number';
                          if (parsed == 0) return 'Must not be zero';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      if (_isTransfer) ...[
                        DropdownButtonFormField<String>(
                          initialValue: _fromWarehouseId,
                          decoration: const InputDecoration(
                            labelText: 'From warehouse *',
                          ),
                          items: [
                            for (final w in _warehouses)
                              DropdownMenuItem(
                                value: w.id,
                                child: Text(w.name),
                              ),
                          ],
                          onChanged: (v) =>
                              setState(() => _fromWarehouseId = v),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: _toWarehouseId,
                          decoration: const InputDecoration(
                            labelText: 'To warehouse *',
                          ),
                          items: [
                            for (final w in _warehouses)
                              DropdownMenuItem(
                                value: w.id,
                                child: Text(w.name),
                              ),
                          ],
                          onChanged: (v) => setState(() => _toWarehouseId = v),
                        ),
                      ] else ...[
                        DropdownButtonFormField<String>(
                          initialValue: _warehouseId,
                          decoration: const InputDecoration(
                            labelText: 'Warehouse',
                            helperText: 'Leave empty to adjust all',
                          ),
                          items: [
                            for (final w in _warehouses)
                              DropdownMenuItem(
                                value: w.id,
                                child: Text(w.name),
                              ),
                          ],
                          onChanged: (v) => setState(() => _warehouseId = v),
                        ),
                        const SizedBox(height: 16),
                        if (widget.action == StockAction.adjust)
                          DropdownButtonFormField<String>(
                            initialValue: _movementType,
                            decoration: const InputDecoration(
                              labelText: 'Movement type',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'ADJUSTMENT',
                                child: Text('Adjustment'),
                              ),
                              DropdownMenuItem(
                                value: 'RETURN',
                                child: Text('Return'),
                              ),
                            ],
                            onChanged: (v) => setState(
                              () => _movementType = v ?? 'ADJUSTMENT',
                            ),
                          ),
                        if (widget.action == StockAction.adjust)
                          const SizedBox(height: 16),
                        TextFormField(
                          controller: _note,
                          maxLength: 300,
                          decoration: const InputDecoration(
                            labelText: 'Note',
                            counterText: '',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.action.submitLabel),
        ),
      ],
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
                  [
                    m.type,
                    m.reference,
                    dateTime(m.createdAt),
                  ].where((v) => v != null && v.isNotEmpty).join(' · '),
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
