import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../features/auth/auth_controller.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';

final _usersProvider =
    FutureProvider.autoDispose<PageResult<User>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.get('/users', query: {'limit': 200});
  return PageResult.fromJsonList(
    Map<String, dynamic>.from(res as Map),
    User.fromJson,
  );
});

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final isAdmin = auth.user?['role'] == 'ADMIN';
    return ListPageScaffold(
      title: 'Users',
      onRefresh: () async => ref.invalidate(_usersProvider),
      onAdd: isAdmin
          ? () => showDialog(
                context: context,
                builder: (context) => _UserForm(
                  user: const {},
                  isNew: true,
                ),
              )
          : null,
      child: AsyncDataView(
        provider: _usersProvider,
        onRetry: () => ref.invalidate(_usersProvider),
        builder: (result) {
          final me = auth.user?['id'];
          return Card(
            margin: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final u in result.items)
                  ListTile(
                    leading: CircleAvatar(
                        child: Text(u.name.isEmpty ? '?' : u.name[0])),
                    title: Text(u.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(u.email),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusChip(status: u.role),
                        if (u.id == me) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.person, size: 18),
                        ],
                      ],
                    ),
                    onTap: isAdmin && u.id != me
                        ? () => showDialog(
                              context: context,
                              builder: (context) =>
                                  _UserForm(user: _toMap(u), isNew: false),
                            )
                        : null,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  static Map<String, dynamic> _toMap(User u) => {
        'id': u.id,
        'name': u.name,
        'email': u.email,
        'role': u.role,
        'status': u.status,
      };
}

class _UserForm extends ConsumerStatefulWidget {
  const _UserForm({required this.user, required this.isNew});
  final Map<String, dynamic> user;
  final bool isNew;

  @override
  ConsumerState<_UserForm> createState() => _UserFormState();
}

class _UserFormState extends ConsumerState<_UserForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name =
      TextEditingController(text: widget.user['name'] ?? '');
  late final _email =
      TextEditingController(text: widget.user['email'] ?? '');
  late String? _role = widget.user['role'] ?? 'MEMBER';
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final api = ref.read(apiClientProvider);
    try {
      final data = {
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'role': _role,
      };
      if (widget.isNew) {
        await api.post('/users', body: data);
      } else {
        await api.patch('/users/${widget.user['id']}', body: data);
      }
      if (mounted) {
        ref.invalidate(_usersProvider);
        Navigator.pop(context);
        showMessage(context, widget.isNew ? 'User invited' : 'Saved');
      }
    } on Exception catch (e) {
      if (mounted) showErrorDialog(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: widget.isNew ? 'Invite user' : 'Edit user',
      submitting: _submitting,
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name *'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email *'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: const [
                DropdownMenuItem(value: 'ADMIN', child: Text('Admin')),
                DropdownMenuItem(value: 'MEMBER', child: Text('Member')),
              ],
              onChanged: (v) => setState(() => _role = v),
            ),
          ],
        ),
      ),
    );
  }
}