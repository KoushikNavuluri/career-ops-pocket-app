import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/api/api_client.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';
import '../../core/util/json.dart';

const kCompetencies = ['Ownership', 'Problem solving', 'Collaboration', 'Leadership', 'Learning'];
const _starFields = [
  ('situation', 'Situation'),
  ('task', 'Task'),
  ('action', 'Action'),
  ('result', 'Result'),
  ('reflection', 'Reflection'),
];

final storiesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await ref.watch(apiClientProvider).get('/v1/stories');
  return objList(obj(data)['items']);
});

class StoriesScreen extends ConsumerWidget {
  const StoriesScreen({super.key});

  Future<void> _edit(BuildContext context, [Map<String, dynamic>? story]) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _StoryEditor(story: story),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stories = ref.watch(storiesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Story bank')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(context), icon: const Icon(Icons.add), label: const Text('Story')),
      body: stories.when(
        loading: () => const SkeletonList(),
        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(storiesProvider)),
        data: (items) => items.isEmpty
            ? EmptyState(
                icon: Icons.menu_book_outlined,
                title: 'No stories yet',
                message: 'Capture proof stories in STAR + Reflection form. The AI uses them for interview prep and drafts.',
                actionLabel: 'Add a story',
                onAction: () => _edit(context),
              )
            : ContentWidth(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final s = items[i];
                    return PocketCard(
                      onTap: () => _edit(context, s),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Eyebrow(str(s['competency'])),
                        const SizedBox(height: 6),
                        Text(str(s['title']), style: context.text.titleSmall),
                        const SizedBox(height: 4),
                        Text(str(s['result']), maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: context.pocket.mutedForeground)),
                      ]),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _StoryEditor extends ConsumerStatefulWidget {
  const _StoryEditor({this.story});
  final Map<String, dynamic>? story;

  @override
  ConsumerState<_StoryEditor> createState() => _StoryEditorState();
}

class _StoryEditorState extends ConsumerState<_StoryEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final Map<String, TextEditingController> _fields;
  late String _competency;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final s = widget.story ?? const <String, dynamic>{};
    _title = TextEditingController(text: str(s['title']));
    _fields = {for (final f in _starFields) f.$1: TextEditingController(text: str(s[f.$1]))};
    final c = str(s['competency']);
    _competency = kCompetencies.contains(c) ? c : kCompetencies.first;
  }

  @override
  void dispose() {
    _title.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final body = {
      'title': _title.text.trim(),
      'competency': _competency,
      for (final e in _fields.entries) e.key: e.value.text.trim(),
    };
    final api = ref.read(apiClientProvider);
    try {
      final id = strOrNull(widget.story?['id']);
      if (id == null) {
        await api.post('/v1/stories', body);
      } else {
        await api.put('/v1/stories/$id', body);
      }
      ref.invalidate(storiesProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, friendlyError(e));
      }
    }
  }

  Future<void> _delete() async {
    final id = strOrNull(widget.story?['id']);
    if (id == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).delete('/v1/stories/$id');
      ref.invalidate(storiesProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, friendlyError(e));
      }
    }
  }

  String? _required(String? v, int max) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Required.';
    if (t.length > max) return 'Keep this under $max characters.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(widget.story == null ? 'New story' : 'Edit story', style: context.text.headlineSmall),
            const SizedBox(height: 14),
            TextFormField(controller: _title, decoration: pocketInput(context, label: 'Title'), validator: (v) => _required(v, 200)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _competency,
              decoration: pocketInput(context, label: 'Competency'),
              items: [for (final c in kCompetencies) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _competency = v ?? _competency),
            ),
            for (final f in _starFields) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _fields[f.$1],
                minLines: 2,
                maxLines: 6,
                decoration: pocketInput(context, label: f.$2),
                validator: (v) => _required(v, 4000),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving' : 'Save story')),
            if (widget.story != null) TextButton(onPressed: _busy ? null : _delete, child: const Text('Delete story')),
          ],
        ),
      ),
    );
  }
}
