import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/api/api_client.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';
import '../../core/util/json.dart';
import '../jobs/jobs_repository.dart';

class CvVersion {
  const CvVersion({required this.id, required this.source, required this.isCurrent, required this.createdAt, required this.chars});
  final String id;
  final String source;
  final bool isCurrent;
  final DateTime createdAt;
  final int chars;
}

final masterCvProvider = FutureProvider<String?>((ref) async {
  final data = await ref.watch(apiClientProvider).get('/v1/cv/master');
  final cv = obj(data)['cv'];
  return cv is Map ? str(cv['markdown']) : null;
});

final cvVersionsProvider = FutureProvider<List<CvVersion>>((ref) async {
  final data = await ref.watch(apiClientProvider).get('/v1/cv/versions');
  return objList(obj(data)['items'])
      .map((v) => CvVersion(
            id: str(v['id']),
            source: str(v['source']),
            isCurrent: boolOr(v['is_current'], false),
            createdAt: dateOrNull(v['created_at']) ?? DateTime.now(),
            chars: intOr(v['chars'], 0),
          ))
      .toList();
});

class CvScreen extends ConsumerStatefulWidget {
  const CvScreen({super.key});

  @override
  ConsumerState<CvScreen> createState() => _CvScreenState();
}

class _CvScreenState extends ConsumerState<CvScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final _editor = TextEditingController();
  String? _loaded;
  bool _saving = false;

  @override
  void dispose() {
    _tabs.dispose();
    _editor.dispose();
    super.dispose();
  }

  bool get _dirty => _loaded != null && _editor.text != _loaded;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).put('/v1/cv/master', {'markdown': _editor.text});
      _loaded = _editor.text;
      ref.invalidate(masterCvProvider);
      ref.invalidate(cvVersionsProvider);
      ref.invalidate(todayProvider);
      if (mounted) {
        showMessage(context, 'Master CV saved.');
        _tabs.animateTo(0);
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restore(CvVersion v) async {
    try {
      await ref.read(apiClientProvider).post('/v1/cv/versions/${v.id}/restore');
      _loaded = null;
      ref.invalidate(masterCvProvider);
      ref.invalidate(cvVersionsProvider);
      if (mounted) showMessage(context, 'Version restored as your master CV.');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cv = ref.watch(masterCvProvider);
    cv.whenData((md) {
      if (_loaded == null) {
        _loaded = md ?? '';
        _editor.text = _loaded!;
      }
    });
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Discard your edits?'),
            content: const Text('Your unsaved CV changes will be lost.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
            ],
          ),
        );
        if (leave == true && context.mounted) {
          _editor.text = _loaded ?? '';
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Resume workspace'),
          bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Preview'), Tab(text: 'Edit'), Tab(text: 'Versions')]),
        ),
        body: cv.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(masterCvProvider)),
          data: (md) => TabBarView(
            controller: _tabs,
            children: [
              (md == null || md.trim().isEmpty)
                  ? EmptyState(
                      icon: Icons.description_outlined,
                      title: 'No master CV yet',
                      message: 'Paste your CV as Markdown. Evaluations and drafts only use facts from it.',
                      actionLabel: 'Write my CV',
                      onAction: () => _tabs.animateTo(1),
                    )
                  : ContentWidth(child: Markdown(data: md, selectable: true, padding: const EdgeInsets.all(20))),
              ContentWidth(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Notice('Use your own, verified facts. Tailored versions never overwrite this master copy.'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _editor,
                      minLines: 18,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      onChanged: (_) => setState(() {}),
                      style: AppTheme.mono(const TextStyle(fontSize: 14, height: 1.5)),
                      decoration: pocketInput(context, label: 'Master CV · Markdown', hint: '# Your Name\n\n## Experience\n...'),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      TextButton(onPressed: _dirty ? () => setState(() => _editor.text = _loaded ?? '') : null, child: const Text('Discard edits')),
                      const Spacer(),
                      FilledButton(
                        onPressed: _dirty && !_saving ? _save : null,
                        child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save and preview'),
                      ),
                    ]),
                  ],
                ),
              ),
              Consumer(builder: (context, ref, _) {
                final versions = ref.watch(cvVersionsProvider);
                return versions.when(
                  loading: () => const LoadingView(),
                  error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(cvVersionsProvider)),
                  data: (items) => items.isEmpty
                      ? const EmptyState(icon: Icons.history, title: 'No versions yet', message: 'Every save creates a version you can restore.')
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            for (final v in items)
                              ListTile(
                                title: Text(DateFormat.yMMMd().add_jm().format(v.createdAt)),
                                subtitle: Text('${v.chars} characters · ${v.source}'),
                                trailing: v.isCurrent
                                    ? Text('Current', style: context.text.labelLarge?.copyWith(color: context.colors.primary))
                                    : TextButton(onPressed: () => _restore(v), child: const Text('Restore')),
                              ),
                          ],
                        ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
