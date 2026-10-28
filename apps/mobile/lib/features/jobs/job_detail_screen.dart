import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';
import 'evaluation_view.dart';
import 'jobs_repository.dart';
import 'models.dart';
import 'widgets.dart';

class JobDetailScreen extends ConsumerWidget {
  const JobDetailScreen({super.key, required this.jobId});
  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(jobDetailProvider(jobId));
    return detail.when(
      loading: () => Scaffold(appBar: AppBar(), body: const LoadingView()),
      error: (e, _) => Scaffold(appBar: AppBar(), body: ErrorState(error: e, onRetry: () => ref.invalidate(jobDetailProvider(jobId)))),
      data: (d) => _JobDetailBody(detail: d),
    );
  }
}

class _JobDetailBody extends ConsumerStatefulWidget {
  const _JobDetailBody({required this.detail});
  final JobDetail detail;

  @override
  ConsumerState<_JobDetailBody> createState() => _JobDetailBodyState();
}

class _JobDetailBodyState extends ConsumerState<_JobDetailBody> {
  bool _evaluating = false;

  Job get job => widget.detail.job;

  Future<void> _evaluate() async {
    setState(() => _evaluating = true);
    try {
      await withAiConsent<void>(
        context,
        title: 'Evaluate this role',
        sends: const ['This role\'s posting and details', 'Your saved profile and direction', 'Your master CV and story bank'],
        run: (consent) => ref.read(jobsActionsProvider).evaluate(job.id, consent: consent),
      );
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _evaluating = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this role?'),
        content: const Text('Its evaluation, history and archived posting are removed from your workspace. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final router = GoRouter.of(context);
    try {
      await ref.read(jobsActionsProvider).delete(job.id);
      if (router.canPop()) {
        router.pop();
      } else {
        router.go('/pipeline');
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final muted = context.pocket.mutedForeground;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              tooltip: job.saved ? 'Saved' : 'Save',
              icon: Icon(job.saved ? Icons.bookmark : Icons.bookmark_border),
              onPressed: () => ref.read(jobsActionsProvider).setSaved(job.id, !job.saved).catchError((Object e) {
                if (mounted) showMessage(context, friendlyError(e));
              }),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'delete') _delete();
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete role'))],
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'The fit'), Tab(text: 'Your next moves'), Tab(text: 'History')]),
          title: Text(job.company, overflow: TextOverflow.ellipsis),
        ),
        body: TabBarView(
          children: [
            _tab(ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _header(context, muted),
                const SizedBox(height: 16),
                if (d.evaluation != null) ...[
                  EvaluationView(evaluation: d.evaluation!),
                  if (d.canEvaluate) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _evaluating ? null : _evaluate,
                      icon: const Icon(Icons.refresh),
                      label: Text(_evaluating ? 'Re-evaluating…' : 'Re-evaluate with current CV'),
                    ),
                  ],
                ] else
                  PocketCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Not evaluated yet', style: context.text.titleMedium),
                        const SizedBox(height: 6),
                        Text(
                          d.canEvaluate
                              ? 'Get a structured A-H fit report scored against your CV and direction. It takes about half a minute.'
                              : 'Evaluation is available for Inbox roles.',
                          style: context.text.bodyMedium?.copyWith(color: muted),
                        ),
                        if (d.canEvaluate) ...[
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: _evaluating ? null : _evaluate,
                            icon: _evaluating
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.auto_awesome),
                            label: Text(_evaluating ? 'Evaluating…' : 'Evaluate this role'),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Card(
                  child: ExpansionTile(
                    title: const Text('Job description'),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [SelectableText(job.description)],
                  ),
                ),
              ],
            )),
            _tab(ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _action(context, Icons.swap_horiz, 'Update stage', 'Record what actually happened.', () => showOutcomeSheet(context, ref, d)),
                _action(context, Icons.mail_outline, 'Draft a cover letter', 'Evidence-backed, for this role.', () => context.push('/tools/writing-cover?jobId=${job.id}')),
                _action(context, Icons.alternate_email, 'Application or follow-up email', 'A short draft you send yourself.', () => context.push('/tools/writing-email?jobId=${job.id}')),
                _action(context, Icons.forum_outlined, 'Ask about this role', 'Open the assistant with this role selected.', () => context.push('/assistant?jobId=${job.id}')),
                _action(context, Icons.description_outlined, 'Tailor your CV', 'Open your resume workspace.', () => context.push('/cv')),
              ],
            )),
            _tab(ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final e in d.events.reversed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(e.actor == 'system' ? Icons.memory : Icons.person_outline),
                    title: Text(e.from == null ? e.to : '${e.from} → ${e.to}'),
                    subtitle: Text([DateFormat.yMMMd().add_jm().format(e.at), if (e.note != null) e.note!, if (e.feedback != null) '"${e.feedback!}"'].join('\n')),
                  ),
              ],
            )),
          ],
        ),
      ),
    );
  }

  Widget _tab(Widget child) => RefreshIndicator(onRefresh: () => ref.refresh(jobDetailProvider(job.id).future), child: ContentWidth(child: child));

  Widget _header(BuildContext context, Color muted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(job.company),
        const SizedBox(height: 6),
        Text(job.role, style: context.text.displaySmall),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusChip(job.status),
            ScoreBadge(job.score),
            if (job.location != null) Chip(label: Text(job.location!)),
            if (job.workModel != null) Chip(label: Text(job.workModel!)),
            if (job.salaryText != null) Chip(label: Text(job.salaryText!)),
          ],
        ),
        const SizedBox(height: 8),
        Text('Added ${DateFormat.yMMMd().format(job.createdAt)} · posting unverified until you check the employer site.',
            style: context.text.bodySmall?.copyWith(color: muted)),
      ],
    );
  }

  Widget _action(BuildContext context, IconData icon, String title, String subtitle, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PocketCard(
        onTap: onTap,
        child: Row(children: [
          Icon(icon, color: context.colors.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: context.text.titleSmall),
              Text(subtitle, style: context.text.bodySmall?.copyWith(color: context.pocket.mutedForeground)),
            ]),
          ),
          const Icon(Icons.chevron_right),
        ]),
      ),
    );
  }
}

/// Stage update. Only transitions the server allows are offered.
Future<void> showOutcomeSheet(BuildContext context, WidgetRef ref, JobDetail d) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _OutcomeSheet(detail: d),
  );
}

class _OutcomeSheet extends ConsumerStatefulWidget {
  const _OutcomeSheet({required this.detail});
  final JobDetail detail;

  @override
  ConsumerState<_OutcomeSheet> createState() => _OutcomeSheetState();
}

class _OutcomeSheetState extends ConsumerState<_OutcomeSheet> {
  String? _to;
  bool _confirmedExternal = false;
  bool _saving = false;
  final _note = TextEditingController();
  final _feedback = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    _feedback.dispose();
    super.dispose();
  }

  bool get _needsExternalConfirm => _to == 'Applied';

  Future<void> _save() async {
    final to = _to;
    if (to == null) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    try {
      await ref.read(jobsActionsProvider).transition(widget.detail.job.id, to, note: _note.text.trim(), feedback: _feedback.text.trim());
      navigator.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed = widget.detail.allowedTransitions;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Record an outcome', style: context.text.headlineSmall),
            const SizedBox(height: 6),
            Text('This updates your tracker only. It never submits an application or accepts an offer.',
                style: context.text.bodySmall?.copyWith(color: context.pocket.mutedForeground)),
            const SizedBox(height: 16),
            if (allowed.isEmpty)
              const Text('This role is at a final stage.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in allowed)
                    ChoiceChip(label: Text(s == 'Inbox' ? 'Reopen' : s), selected: _to == s, onSelected: (_) => setState(() => _to = s)),
                ],
              ),
            const SizedBox(height: 16),
            TextField(controller: _note, decoration: pocketInput(context, label: 'Note (optional)')),
            const SizedBox(height: 12),
            TextField(controller: _feedback, maxLines: 3, decoration: pocketInput(context, label: 'Feedback, verbatim (optional)')),
            if (_needsExternalConfirm)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _confirmedExternal,
                onChanged: (v) => setState(() => _confirmedExternal = v ?? false),
                title: const Text('I submitted the application myself on the employer\'s site.'),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _to == null || _saving || (_needsExternalConfirm && !_confirmedExternal) ? null : _save,
              child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Confirm outcome'),
            ),
          ],
        ),
      ),
    );
  }
}
