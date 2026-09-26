import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../shared/models/models.dart';
import '../../shared/state/string_notifier.dart';
import '../../shared/widgets/common.dart';

final _productsProvider =
    FutureProvider.autoDispose<PageResult<Product>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final search = ref.watch(_searchProvider);
  final res = await api.get('/products', query: {
    'search': search.isEmpty ? null : search,
    'limit': 200,
  });
  return PageResult.fromJsonList(
    Map<String, dynamic>.from(res as Map),
    Product.fromJson,
  );
});

final _searchProvider =
    NotifierProvider<StringNotifier, String>(StringNotifier.new);

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  late final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _save(
    Map<String, dynamic>? existing,
    Map<String, dynamic> data,
  ) async {
    final api = ref.read(apiClientProvider);
    try {
      if (existing == null) {
        await api.post('/products', body: data);
      } else {
        await api.patch('/products/${existing['id']}', body: data);
      }
      if (mounted) {
        ref.invalidate(_productsProvider);
        showMessage(context, existing == null ? 'Product created' : 'Saved');
      }
    } on Exception catch (e) {
      if (mounted) showErrorDialog(context, e);
    }
  }

  void _openForm(Map<String, dynamic>? product) {
    showDialog(
      context: context,
      builder: (context) => _ProductForm(product: product, onSave: _save),
    );
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(_searchProvider);
    return ListPageScaffold(
      title: 'Products',
      onRefresh: () async => ref.invalidate(_productsProvider),
      onAdd: () => _openForm(null),
      search: SearchField(
        controller: _search,
        hint: 'Search products',
        onChanged: (v) => ref.read(_searchProvider.notifier).set(v.trim()),
      ),
      child: AsyncDataView(
        provider: _productsProvider,
        builder: (result) {
          final products = result.items;
          if (products.isEmpty) {
            return EmptyState(
              icon: Icons.inventory_2_outlined,
              message: search.isEmpty
                  ? 'No products yet. Add your first product.'
                  : 'No products match "$search".',
              action: search.isEmpty
                  ? FilledButton.icon(
                      onPressed: () => _openForm(null),
                      icon: const Icon(Icons.add),
                      label: const Text('Add product'),
                    )
                  : null,
            );
          }
          return Card(
            margin: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 800;
                if (wide) {
                  return DataTable(
                    columns: const [
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('SKU')),
                      DataColumn(label: Text('Category')),
                      DataColumn(label: Text('Unit')),
                      DataColumn(label: Text('Price'), numeric: true),
                      DataColumn(label: Text('Stock'), numeric: true),
                      DataColumn(label: Text('')),
                    ],
                    rows: [
                      for (final p in products)
                        DataRow(
                          cells: [
                            DataCell(Text(p.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600))),
                            DataCell(Text(p.sku ?? '-')),
                            DataCell(Text(p.category ?? '-')),
                            DataCell(Text(p.unit ?? '-')),
                            DataCell(MoneyText(p.salePrice)),
                            DataCell(Text(
                              '${p.stockQuantity ?? 0}',
                              style: TextStyle(
                                color: (p.stockQuantity ?? 0) <= 0
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                              ),
                            )),
                            DataCell(IconButton(
                              icon: const Icon(Icons.more_vert),
                              onPressed: () => _openForm(_toMap(p)),
                            )),
                          ],
                        ),
                    ],
                  );
                }
                return ListView.separated(
                  itemCount: products.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final p = products[i];
                    return ListTile(
                      leading: const CircleAvatar(
                          child: Icon(Icons.inventory_2)),
                      title: Text(p.name),
                      subtitle: Text([
                        if (p.sku != null) p.sku!,
                        if (p.category != null) p.category!,
                        '${p.stockQuantity ?? 0} in stock',
                      ].join(' · ')),
                      trailing: MoneyText(p.salePrice,
                          style: Theme.of(context).textTheme.bodyMedium),
                      onTap: () => _openForm(_toMap(p)),
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

  static Map<String, dynamic> _toMap(Product p) => {
        'id': p.id,
        'name': p.name,
        'sku': p.sku,
      };
}

class _ProductForm extends ConsumerStatefulWidget {
  const _ProductForm({this.product, required this.onSave});
  final Map<String, dynamic>? product;
  final void Function(Map<String, dynamic>? existing, Map<String, dynamic> data)
      onSave;

  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name =
      TextEditingController(text: widget.product?['name'] ?? '');
  late final _sku = TextEditingController(text: widget.product?['sku'] ?? '');
  late final _price = TextEditingController(
      text: widget.product?['salePrice']?.toString() ?? '');
  late final _cost = TextEditingController(
      text: widget.product?['costPrice']?.toString() ?? '');
  late final _tax = TextEditingController(
      text: widget.product?['taxRate']?.toString() ?? '0');
  String? _categoryId;

  List<Category> _categories = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.product?['categoryId'] as String?;
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/categories', query: {'limit': 200});
      if (!mounted) return;
      setState(() {
        _categories = (res['items'] as List)
            .map((c) => Category.fromJson(Map<String, dynamic>.from(c as Map)))
            .toList();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in [_name, _sku, _price, _cost, _tax]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    widget.onSave(widget.product, {
      'name': _name.text.trim(),
      'sku': _sku.text.trim().isEmpty ? null : _sku.text.trim(),
      'categoryId': _categoryId,
      'salePrice': double.tryParse(_price.text),
      'costPrice': _cost.text.isEmpty ? null : double.tryParse(_cost.text),
      'taxRate': double.tryParse(_tax.text) ?? 0,
    });
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: widget.product == null ? 'Add product' : 'Edit product',
      submitLabel: widget.product == null ? 'Create' : 'Save',
      submitting: _submitting,
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name *'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _sku,
              decoration: const InputDecoration(labelText: 'SKU'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Category'),
              hint: const Text('None'),
              items: [
                for (final c in _categories)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(labelText: 'Sale price *'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (double.tryParse(v) == null) return 'Invalid';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _cost,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(labelText: 'Cost price'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _tax,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Tax rate (%)',
                helperText: '0 = tax excluded, 10 = 10%',
              ),
            ),
          ],
        ),
      ),
    );
  }
}