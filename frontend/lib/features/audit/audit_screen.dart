import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../shared/formatters/formatters.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';

final _auditProvider =
    FutureProvider.autoDispose<PageResult<AuditLogEntry>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.get('/audit-logs', query: {'limit': 100});
  return PageResult.fromJsonList(
    Map<String, dynamic>.from(res as Map),
    AuditLogEntry.fromJson,
  );
});

class AuditScreen extends ConsumerWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListPageScaffold(
      title: 'Audit log',
      onRefresh: () async => ref.invalidate(_auditProvider),
      child: AsyncDataView(
        provider: _auditProvider,
        onRetry: () => ref.invalidate(_auditProvider),
        builder: (result) {
          if (result.items.isEmpty) {
            return const EmptyState(
              icon: Icons.history,
              message: 'No audit events yet.',
            );
          }
          return Card(
            margin: const EdgeInsets.all(16),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: result.items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final e = result.items[i];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(e.actorName == null || e.actorName!.isEmpty
                        ? '?'
                        : e.actorName![0]),
                  ),
                  title: Text(
                    '${e.action ?? ''} ${e.entityType ?? ''}'
                    '${e.entityId != null ? ' · ${_short(e.entityId!)}' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('by ${e.actorName ?? '-'}'),
                  trailing: Text(
                    dateTime(e.createdAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  static String _short(String id) =>
      id.length <= 12 ? id : '${id.substring(0, 6)}…';
}