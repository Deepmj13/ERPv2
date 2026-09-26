import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../shared/models/models.dart';
import '../../shared/state/string_notifier.dart';
import '../../shared/widgets/common.dart';

final _customersProvider =
    FutureProvider.autoDispose<PageResult<Customer>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final search = ref.watch(_searchProvider);
  final res = await api.get('/customers', query: {
    'search': search.isEmpty ? null : search,
    'limit': 200,
  });
  return PageResult.fromJsonList(
    Map<String, dynamic>.from(res as Map),
    Customer.fromJson,
  );
});

final _searchProvider =
    NotifierProvider<StringNotifier, String>(StringNotifier.new);

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
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
        await api.post('/customers', body: data);
      } else {
        await api.patch('/customers/${existing['id']}', body: data);
      }
      if (mounted) {
        ref.invalidate(_customersProvider);
        showMessage(context, existing == null ? 'Customer created' : 'Saved');
      }
    } on Exception catch (e) {
      if (mounted) showErrorDialog(context, e);
    }
  }

  void _openForm(Map<String, dynamic>? existing) {
    showDialog(
      context: context,
      builder: (context) => _CustomerForm(existing: existing, onSave: _save),
    );
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(_searchProvider);
    return ListPageScaffold(
      title: 'Customers',
      onRefresh: () async => ref.invalidate(_customersProvider),
      onAdd: () => _openForm(null),
      search: SearchField(
        controller: _search,
        hint: 'Search customers',
        onChanged: (v) => ref.read(_searchProvider.notifier).set(v.trim()),
      ),
      child: AsyncDataView(
        provider: _customersProvider,
        builder: (result) {
          final customers = result.items;
          if (customers.isEmpty) {
            return EmptyState(
              icon: Icons.people_outline,
              message: search.isEmpty
                  ? 'No customers yet. Add your first customer.'
                  : 'No customers match "$search".',
              action: search.isEmpty
                  ? FilledButton.icon(
                      onPressed: () => _openForm(null),
                      icon: const Icon(Icons.add),
                      label: const Text('Add customer'),
                    )
                  : null,
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
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('Email')),
                      DataColumn(label: Text('Phone')),
                      DataColumn(label: Text('Address')),
                      DataColumn(label: Text('')),
                    ],
                    rows: [
                      for (final c in customers)
                        DataRow(
                          onSelectChanged: (_) => _openForm(
                            _toMap(c),
                          ),
                          cells: [
                            DataCell(Text(c.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600))),
                            DataCell(Text(c.email ?? '-')),
                            DataCell(Text(c.phone ?? '-')),
                            DataCell(Text(c.address ?? '-')),
                            DataCell(IconButton(
                              icon: const Icon(Icons.more_vert),
                              onPressed: () => _openForm(_toMap(c)),
                            )),
                          ],
                        ),
                    ],
                  );
                }
                return ListView.separated(
                  itemCount: customers.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final c = customers[i];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(c.name),
                      subtitle: Text(
                        [c.email, c.phone, c.address]
                            .where((v) => v != null && v.isNotEmpty)
                            .join(' · '),
                      ),
                      onTap: () => _openForm(_toMap(c)),
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

  static Map<String, dynamic> _toMap(Customer c) => {
        'id': c.id,
        'name': c.name,
        'email': c.email,
        'phone': c.phone,
        'address': c.address,
      };
}

class _CustomerForm extends StatefulWidget {
  const _CustomerForm({this.existing, required this.onSave});
  final Map<String, dynamic>? existing;
  final Future<void> Function(
      Map<String, dynamic>? existing, Map<String, dynamic> data) onSave;

  @override
  State<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<_CustomerForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?['name'] ?? '');
  late final _email =
      TextEditingController(text: widget.existing?['email'] ?? '');
  late final _phone =
      TextEditingController(text: widget.existing?['phone'] ?? '');
  late final _address =
      TextEditingController(text: widget.existing?['address'] ?? '');
  bool _submitting = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    widget.onSave(widget.existing, {
      'name': _name.text.trim(),
      'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
      'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
    }).then((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: widget.existing == null ? 'Add customer' : 'Edit customer',
      submitting: _submitting,
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name *'),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Required'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
          ],
        ),
      ),
    );
  }
}