import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/api/api_client.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';
import '../../core/util/json.dart';

final documentsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await ref.watch(apiClientProvider).get('/v1/documents');
  return objList(obj(data)['items']);
});

final documentProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  return obj(await ref.watch(apiClientProvider).get('/v1/documents/$id'));
});

const _typeLabels = {
  'report': 'Report', 'application': 'Application', 'resume': 'Resume', 'cover': 'Cover letter',
  'email': 'Email', 'draft': 'Draft', 'interview': 'Interview prep', 'digest': 'Digest', 'other': 'Other',
};

class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(documentsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: docs.when(
        loading: () => const SkeletonList(),
        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(documentsProvider)),
        data: (items) => items.isEmpty
            ? EmptyState(
                icon: Icons.folder_open_outlined,
                title: 'No documents yet',
                message: 'Drafts from the Writing studio are saved here.',
                actionLabel: 'Open Studio',
                onAction: () => context.go('/studio'),
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(documentsProvider.future),
                child: ContentWidth(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final d = items[i];
                      final created = dateOrNull(d['created_at']);
                      return PocketCard(
                        onTap: () => context.push('/documents/${str(d['id'])}'),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Eyebrow(_typeLabels[str(d['type'])] ?? 'Document'),
                          const SizedBox(height: 6),
                          Text(str(d['title']), style: context.text.titleSmall),
                          if (created != null)
                            Text(DateFormat.yMMMd().format(created), style: context.text.bodySmall?.copyWith(color: context.pocket.mutedForeground)),
                        ]),
                      );
                    },
                  ),
                ),
              ),
      ),
    );
  }
}

class DocumentScreen extends ConsumerWidget {
  const DocumentScreen({super.key, required this.documentId});
  final String documentId;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this document?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).delete('/v1/documents/$documentId');
      ref.invalidate(documentsProvider);
      if (context.mounted) context.pop();
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = ref.watch(documentProvider(documentId));
    final body = doc.asData == null ? '' : str(doc.asData!.value['body_md']);
    return Scaffold(
      appBar: AppBar(
        title: Text(doc.asData == null ? 'Document' : str(doc.asData!.value['title']), overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: body.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: body));
                    if (context.mounted) showMessage(context, 'Copied as Markdown.');
                  },
          ),
          IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(context, ref)),
        ],
      ),
      body: doc.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(documentProvider(documentId))),
        data: (_) => ContentWidth(child: Markdown(data: body, selectable: true, padding: const EdgeInsets.all(20))),
      ),
    );
  }
}
