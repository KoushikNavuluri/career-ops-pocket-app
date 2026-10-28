import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/api/api_client.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';
import '../../core/util/json.dart';
import '../documents/documents_screen.dart';
import '../jobs/jobs_repository.dart';
import '../jobs/widgets.dart';
import 'tools_repository.dart';

class WritingToolScreen extends ConsumerWidget {
  const WritingToolScreen({super.key, required this.feature, this.initialJobId});
  final String feature;
  final String? initialJobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tools = ref.watch(writingToolsProvider);
    return tools.when(
      loading: () => Scaffold(appBar: AppBar(), body: const LoadingView()),
      error: (e, _) => Scaffold(appBar: AppBar(), body: ErrorState(error: e, onRetry: () => ref.invalidate(writingToolsProvider))),
      data: (items) {
        final tool = items.where((t) => t.id == feature).firstOrNull;
        if (tool == null) {
          return Scaffold(
            appBar: AppBar(),
            body: EmptyState(
              icon: Icons.search_off,
              title: 'Tool not found',
              message: 'This writing tool is not available.',
              actionLabel: 'Back to Studio',
              onAction: () => context.go('/studio'),
            ),
          );
        }
        return _ToolForm(tool: tool, initialJobId: initialJobId);
      },
    );
  }
}

class _ToolForm extends ConsumerStatefulWidget {
  const _ToolForm({required this.tool, this.initialJobId});
  final WritingTool tool;
  final String? initialJobId;

  @override
  ConsumerState<_ToolForm> createState() => _ToolFormState();
}

class _ToolFormState extends ConsumerState<_ToolForm> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _text = {};
  final Map<String, String?> _choices = {};
  Map<String, String> _serverErrors = const {};
  String? _jobId;
  bool _busy = false;
  _Draft? _draft;

  @override
  void initState() {
    super.initState();
    _jobId = widget.initialJobId;
    for (final f in widget.tool.fields) {
      if (f.kind == 'choice') {
        _choices[f.key] = f.required && f.choices.isNotEmpty ? f.choices.first : null;
      } else {
        _text[f.key] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validate(ToolField f, String? value) {
    final v = (value ?? '').trim();
    if (f.required && v.isEmpty) return 'Required.';
    if (v.isEmpty) return null;
    final min = f.minLength;
    final max = f.maxLength;
    if (min != null && v.length < min) return 'Add a little more detail (at least $min characters).';
    if (max != null && v.length > max) return 'Keep this under $max characters.';
    return _serverErrors[f.key];
  }

  Map<String, String> _fieldValues() {
    final out = <String, String>{};
    _text.forEach((k, c) {
      final v = c.text.trim();
      if (v.isNotEmpty) out[k] = v;
    });
    _choices.forEach((k, v) {
      if (v != null) out[k] = v;
    });
    return out;
  }

  Future<void> _generate() async {
    setState(() => _serverErrors = const {});
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (widget.tool.needsJob == 'required' && _jobId == null) {
      showMessage(context, 'Pick the role this is for.');
      return;
    }
    setState(() => _busy = true);
    final api = ref.read(apiClientProvider);
    try {
      final result = await withAiConsent<Map<String, dynamic>>(
        context,
        title: 'Draft with ${widget.tool.title}?',
        sends: [
          'What you typed in this form',
          'Your profile, master CV and up to 8 proof stories',
          if (_jobId != null) 'The selected role and its posting text',
        ],
        run: (consent) async => obj(await api.post('/v1/ai/drafts/${widget.tool.id}', {
          'jobId': _jobId,
          'fields': _fieldValues(),
          'save': true,
          if (consent) 'consent': true,
        })),
      );
      if (result != null && mounted) {
        setState(() => _draft = _Draft(text: str(result['text']), documentId: strOrNull(result['documentId']), aiRunId: strOrNull(result['aiRunId'])));
        ref.invalidate(documentsProvider);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.fieldErrors.isNotEmpty) {
        setState(() => _serverErrors = e.fieldErrors);
        _formKey.currentState?.validate();
      }
      showMessage(context, e.message);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        ref.invalidate(meProvider);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tool = widget.tool;
    final jobs = ref.watch(jobsProvider).asData?.value ?? const [];
    final selected = _jobId != null && jobs.any((j) => j.id == _jobId) ? _jobId : null;
    final draft = _draft;

    return Scaffold(
      appBar: AppBar(title: Text(tool.title)),
      body: ContentWidth(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(tool.description, style: context.text.bodyMedium?.copyWith(color: context.pocket.mutedForeground)),
              const SizedBox(height: 16),
              if (tool.needsJob != 'none') ...[
                DropdownButtonFormField<String?>(
                  key: ValueKey('job-$selected-${jobs.length}'),
                  initialValue: selected,
                  isExpanded: true,
                  decoration: pocketInput(context, label: tool.needsJob == 'required' ? 'Role' : 'Role (optional)'),
                  validator: (v) => tool.needsJob == 'required' && v == null ? 'Pick the role this is for.' : null,
                  items: [
                    if (tool.needsJob == 'optional') const DropdownMenuItem<String?>(value: null, child: Text('No specific role')),
                    for (final j in jobs) DropdownMenuItem<String?>(value: j.id, child: Text('${j.company} · ${j.role}', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _jobId = v),
                ),
                if (jobs.isEmpty && tool.needsJob == 'required')
                  const Padding(padding: EdgeInsets.only(top: 8), child: Notice('Add a role in Explore first. This tool writes for a specific role.')),
                const SizedBox(height: 14),
              ],
              for (final f in tool.fields) ...[
                if (f.kind == 'choice')
                  DropdownButtonFormField<String?>(
                    initialValue: _choices[f.key],
                    isExpanded: true,
                    decoration: pocketInput(context, label: f.required ? f.label : '${f.label} (optional)'),
                    validator: (v) => f.required && v == null ? 'Required.' : _serverErrors[f.key],
                    items: [
                      if (!f.required) const DropdownMenuItem<String?>(value: null, child: Text('Any')),
                      for (final c in f.choices) DropdownMenuItem<String?>(value: c, child: Text(c)),
                    ],
                    onChanged: _busy ? null : (v) => setState(() => _choices[f.key] = v),
                  )
                else
                  TextFormField(
                    controller: _text[f.key],
                    enabled: !_busy,
                    minLines: f.kind == 'multiline' ? 3 : 1,
                    maxLines: f.kind == 'multiline' ? 10 : 1,
                    maxLength: f.maxLength,
                    validator: (v) => _validate(f, v),
                    decoration: pocketInput(context, label: f.required ? f.label : '${f.label} (optional)'),
                  ),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                onPressed: _busy ? null : _generate,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome),
                label: Text(_busy ? 'Drafting' : (draft == null ? 'Draft it' : 'Draft again')),
              ),
              const SizedBox(height: 8),
              Text('Review every draft before you use it. Nothing is ever sent for you.',
                  style: context.text.bodySmall?.copyWith(color: context.pocket.mutedForeground)),
              if (draft != null) ...[
                const SizedBox(height: 20),
                const Eyebrow('Draft'),
                const SizedBox(height: 8),
                PocketCard(child: MarkdownBody(data: draft.text, selectable: true)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: draft.text));
                        if (context.mounted) showMessage(context, 'Draft copied.');
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy'),
                    ),
                    if (draft.documentId != null)
                      OutlinedButton.icon(
                        onPressed: () => context.push('/documents/${draft.documentId}'),
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('Open in Documents'),
                      ),
                    if (draft.aiRunId != null)
                      TextButton.icon(
                        onPressed: () => reportAiResponse(context, ref, draft.aiRunId!),
                        icon: const Icon(Icons.flag_outlined),
                        label: const Text('Report'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Draft {
  const _Draft({required this.text, this.documentId, this.aiRunId});
  final String text;
  final String? documentId;
  final String? aiRunId;
}
