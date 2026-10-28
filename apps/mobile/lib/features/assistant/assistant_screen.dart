import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/api/api_client.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';
import '../../core/util/json.dart';
import '../jobs/jobs_repository.dart';
import '../jobs/widgets.dart';

class AssistantThread {
  const AssistantThread({required this.id, required this.title, required this.contextJobId, required this.updatedAt});
  final String id;
  final String title;
  final String? contextJobId;
  final DateTime? updatedAt;

  factory AssistantThread.fromJson(Map<String, dynamic> j) => AssistantThread(
        id: str(j['id']),
        title: strOrNull(j['title']) ?? 'Conversation',
        contextJobId: strOrNull(j['context_job_id']),
        updatedAt: dateOrNull(j['updated_at']),
      );
}

class ChatEntry {
  ChatEntry({required this.role, required this.content, this.aiRunId, this.pending = false, this.failed = false});
  final String role;
  String content;
  String? aiRunId;
  bool pending;
  bool failed;
  bool get isUser => role == 'user';
}

final assistantThreadsProvider = FutureProvider<List<AssistantThread>>((ref) async {
  final data = await ref.watch(apiClientProvider).get('/v1/assistant/threads');
  return objList(obj(data)['items']).map(AssistantThread.fromJson).toList();
});

const kAssistantSuggestions = [
  'What should I focus on this week?',
  'Which roles in my pipeline fit me best, and why?',
  'Help me prepare for my next interview.',
  'What is missing from my CV for my target role?',
];

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key, this.initialJobId});
  final String? initialJobId;

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatEntry> _entries = [];
  String? _threadId;
  String? _jobId;
  bool _loadingThread = false;
  bool _streaming = false;
  bool _stopRequested = false;

  @override
  void initState() {
    super.initState();
    _jobId = widget.initialJobId;
  }

  @override
  void dispose() {
    _stopRequested = true;
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  ApiClient get _api => ref.read(apiClientProvider);

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  Future<void> _openThread(AssistantThread t) async {
    setState(() {
      _loadingThread = true;
      _threadId = t.id;
      _jobId = t.contextJobId;
      _entries.clear();
    });
    try {
      final data = obj(await _api.get('/v1/assistant/threads/${t.id}/messages'));
      final items = objList(data['items']);
      if (!mounted) return;
      setState(() {
        _entries.addAll(items.map((m) => ChatEntry(role: str(m['role']), content: str(m['content']))));
        _loadingThread = false;
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingThread = false);
      showMessage(context, friendlyError(e));
    }
  }

  void _newConversation() {
    if (_streaming) return;
    setState(() {
      _threadId = null;
      _entries.clear();
      _jobId = widget.initialJobId;
    });
  }

  Future<String> _ensureThread() async {
    final existing = _threadId;
    if (existing != null) return existing;
    final created = obj(await _api.post('/v1/assistant/threads', {'contextJobId': _jobId}));
    final id = str(created['id']);
    _threadId = id;
    ref.invalidate(assistantThreadsProvider);
    return id;
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _streaming) return;
    if (text.length > 8000) {
      showMessage(context, 'Keep messages under 8,000 characters.');
      return;
    }
    final user = ChatEntry(role: 'user', content: text);
    final reply = ChatEntry(role: 'assistant', content: '', pending: true);
    setState(() {
      _entries.addAll([user, reply]);
      _streaming = true;
      _stopRequested = false;
      _input.clear();
    });
    _scrollToEnd();

    try {
      final threadId = await _ensureThread();
      if (!mounted) return;
      final done = await withAiConsent<bool>(
        context,
        title: 'Use the career assistant?',
        sends: const [
          'Your message and recent conversation',
          'Your profile and direction',
          'A summary of your pipeline (companies, roles, statuses, scores)',
          'Your master CV and, if selected, the role and its latest evaluation',
        ],
        run: (consent) => _stream(threadId, text, reply, consent),
      );
      if (done == null && mounted) {
        // Consent declined: put the message back so nothing is lost.
        setState(() {
          _entries.remove(reply);
          _entries.remove(user);
          _input.text = text;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        reply.pending = false;
        reply.failed = true;
        if (reply.content.isEmpty) reply.content = friendlyError(e);
      });
      if (e is ApiException && e.isQuotaExceeded) ref.invalidate(meProvider);
    } finally {
      if (mounted) {
        setState(() => _streaming = false);
        ref.invalidate(meProvider);
        ref.invalidate(assistantThreadsProvider);
      }
    }
  }

  Future<bool> _stream(String threadId, String text, ChatEntry reply, bool consent) async {
    final events = _api.postStream('/v1/assistant/threads/$threadId/messages', {
      'content': text,
      'contextJobId': _jobId,
      if (consent) 'consent': true,
    });
    await for (final ev in events) {
      if (_stopRequested || !mounted) break;
      switch (ev.event) {
        case 'delta':
          setState(() => reply.content += str(ev.json['text']));
          _scrollToEnd();
        case 'done':
          setState(() {
            reply.aiRunId = strOrNull(ev.json['aiRunId']);
            reply.pending = false;
          });
        case 'error':
          throw ApiException.fromBody(intOr(ev.json['status'], 500), ev.json);
      }
    }
    if (mounted) setState(() => reply.pending = false);
    return true;
  }

  Future<void> _exportConversation() async {
    if (_entries.isEmpty) return;
    final md = StringBuffer('# Career assistant conversation\n\n');
    for (final e in _entries) {
      md.writeln(e.isUser ? '**You:**' : '**Assistant:**');
      md.writeln(e.content);
      md.writeln();
    }
    await Clipboard.setData(ClipboardData(text: md.toString()));
    if (mounted) showMessage(context, 'Conversation copied as Markdown.');
  }

  Future<void> _showThreads() async {
    final picked = await showModalBottomSheet<AssistantThread>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _ThreadsSheet(),
    );
    if (picked != null && mounted) await _openThread(picked);
  }

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(jobsProvider).asData?.value ?? const [];
    final jobIds = jobs.map((j) => j.id).toSet();
    final selectedJob = _jobId != null && jobIds.contains(_jobId) ? _jobId : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Career assistant'),
        actions: [
          IconButton(tooltip: 'Conversations', icon: const Icon(Icons.history), onPressed: _streaming ? null : _showThreads),
          IconButton(tooltip: 'New conversation', icon: const Icon(Icons.add_comment_outlined), onPressed: _streaming ? null : _newConversation),
          IconButton(tooltip: 'Copy conversation', icon: const Icon(Icons.copy_all_outlined), onPressed: _entries.isEmpty ? null : _exportConversation),
        ],
      ),
      body: SafeArea(
        child: ContentWidth(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: DropdownButtonFormField<String?>(
                  key: ValueKey('ctx-$selectedJob-${jobs.length}'),
                  initialValue: selectedJob,
                  isExpanded: true,
                  decoration: pocketInput(context, label: 'Context'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Whole pipeline')),
                    for (final j in jobs)
                      DropdownMenuItem<String?>(value: j.id, child: Text('${j.company} · ${j.role}', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: _streaming ? null : (v) => setState(() => _jobId = v),
                ),
              ),
              Expanded(
                child: _loadingThread
                    ? const LoadingView(label: 'Opening conversation')
                    : _entries.isEmpty
                        ? _Suggestions(onPick: _send)
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            itemCount: _entries.length,
                            itemBuilder: (_, i) => _Bubble(
                              entry: _entries[i],
                              onReport: _entries[i].aiRunId == null ? null : () => reportAiResponse(context, ref, _entries[i].aiRunId!),
                            ),
                          ),
              ),
              _Composer(
                controller: _input,
                streaming: _streaming,
                onSend: _send,
                onStop: () => setState(() => _stopRequested = true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.onPick});
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(Icons.auto_awesome, color: context.colors.primary, size: 32),
        const SizedBox(height: 12),
        Text('Ask about your search', style: context.text.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Answers are grounded in your profile, CV and pipeline. The assistant never applies or sends anything for you.',
          style: context.text.bodyMedium?.copyWith(color: context.pocket.mutedForeground),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final s in kAssistantSuggestions) ActionChip(label: Text(s), onPressed: () => onPick(s))],
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.entry, this.onReport});
  final ChatEntry entry;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final p = context.pocket;
    final isUser = entry.isUser;
    final bg = isUser ? context.colors.primary : (entry.failed ? p.peach : context.colors.surface);
    final fg = isUser ? context.colors.onPrimary : context.colors.onSurface;
    final body = entry.pending && entry.content.isEmpty
        ? Row(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text('Thinking', style: context.text.bodyMedium),
          ])
        : isUser || entry.failed
            ? SelectableText(entry.content, style: context.text.bodyMedium?.copyWith(color: entry.failed ? p.lowScoreText : fg))
            : MarkdownBody(data: entry.content, selectable: true);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.86),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(Radii.card),
            border: isUser ? null : Border.all(color: p.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              body,
              if (!isUser && !entry.pending && onReport != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onReport,
                    icon: const Icon(Icons.flag_outlined, size: 16),
                    label: const Text('Report'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.streaming, required this.onSend, required this.onStop});
  final TextEditingController controller;
  final bool streaming;
  final void Function([String?]) onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: context.pocket.border))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              enabled: !streaming,
              textInputAction: TextInputAction.newline,
              decoration: pocketInput(context, hint: 'Ask about your roles, CV or next steps'),
            ),
          ),
          const SizedBox(width: 8),
          streaming
              ? IconButton.filledTonal(tooltip: 'Stop', onPressed: onStop, icon: const Icon(Icons.stop_rounded))
              : IconButton.filled(tooltip: 'Send', onPressed: () => onSend(), icon: const Icon(Icons.arrow_upward_rounded)),
        ],
      ),
    );
  }
}

class _ThreadsSheet extends ConsumerWidget {
  const _ThreadsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threads = ref.watch(assistantThreadsProvider);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 8), child: Text('Conversations', style: context.text.titleLarge)),
          Expanded(
            child: threads.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(assistantThreadsProvider)),
              data: (items) => items.isEmpty
                  ? const EmptyState(icon: Icons.forum_outlined, title: 'No conversations yet', message: 'Your saved conversations appear here.')
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final t = items[i];
                        return ListTile(
                          title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: t.contextJobId == null ? const Text('Whole pipeline') : const Text('About a specific role'),
                          onTap: () => Navigator.pop(context, t),
                          trailing: IconButton(
                            tooltip: 'Delete conversation',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              try {
                                await ref.read(apiClientProvider).delete('/v1/assistant/threads/${t.id}');
                                ref.invalidate(assistantThreadsProvider);
                              } catch (e) {
                                if (context.mounted) showMessage(context, friendlyError(e));
                              }
                            },
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
