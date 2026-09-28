import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/network/api_client.dart';
import '../../shared/formatters/formatters.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';

final _expensesProvider = FutureProvider.autoDispose<PageResult<Expense>>((
  ref,
) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.get('/expenses', query: {'limit': 200});
  return PageResult.fromJsonList(
    Map<String, dynamic>.from(res as Map),
    Expense.fromJson,
  );
});

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  Future<void> _openAdd(WidgetRef ref, BuildContext context) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => const _ExpenseForm(),
    );
    if (saved == true) {
      ref.invalidate(_expensesProvider);
      if (context.mounted) showMessage(context, 'Expense recorded');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListPageScaffold(
      title: 'Expenses',
      onRefresh: () async => ref.invalidate(_expensesProvider),
      onAdd: () => _openAdd(ref, context),
      child: AsyncDataView(
        provider: _expensesProvider,
        onRetry: () => ref.invalidate(_expensesProvider),
        builder: (result) {
          if (result.items.isEmpty) {
            return const EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              message: 'No expenses recorded yet. Add your first expense.',
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
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Category')),
                      DataColumn(label: Text('Description')),
                      DataColumn(label: Text('Recorded by')),
                      DataColumn(label: Text('Amount'), numeric: true),
                    ],
                    rows: [
                      for (final e in result.items)
                        DataRow(
                          cells: [
                            DataCell(Text(dateOnly(e.expenseDate))),
                            DataCell(Text(e.category ?? '-')),
                            DataCell(Text(e.description ?? '-')),
                            DataCell(Text(e.createdBy ?? '-')),
                            DataCell(MoneyText(e.amount)),
                          ],
                        ),
                    ],
                  );
                }
                return ListView.separated(
                  itemCount: result.items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = result.items[i];
                    return ListTile(
                      leading: const Icon(
                        Icons.account_balance_wallet_outlined,
                      ),
                      title: Text(
                        [
                          if (e.category != null) e.category!,
                          if (e.description != null) e.description!,
                        ].join(' · '),
                      ),
                      subtitle: Text(dateTime(e.expenseDate)),
                      trailing: MoneyText(
                        e.amount,
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

class _ExpenseForm extends ConsumerStatefulWidget {
  const _ExpenseForm();

  @override
  ConsumerState<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<_ExpenseForm> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _category = TextEditingController();
  final _description = TextEditingController();
  DateTime _date = DateTime.now();
  bool _submitting = false;

  @override
  void dispose() {
    _amount.dispose();
    _category.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final dateOnly = DateFormat('yyyy-MM-dd').format(_date);
    final api = ref.read(apiClientProvider);
    try {
      await api.post(
        '/expenses',
        body: {
          'amount': double.tryParse(_amount.text.trim()),
          'category': _category.text.trim().isEmpty
              ? null
              : _category.text.trim(),
          'description': _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
          'expenseDate': dateOnly,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        showErrorDialog(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Add expense',
      submitLabel: 'Submit',
      submitting: _submitting,
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Amount *'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (double.tryParse(v) == null) return 'Invalid';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _category,
              decoration: const InputDecoration(
                labelText: 'Category',
                hintText: 'e.g. Rent, Utilities, Supplies',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text('Date: ${DateFormat('yyyy-MM-dd').format(_date)}'),
            ),
          ],
        ),
      ),
    );
  }
}
