import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/config.dart';
import '../../core/api/api_client.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';
import 'jobs_repository.dart';
import 'models.dart';

class JobCard extends ConsumerWidget {
  const JobCard({super.key, required this.job});
  final JobSummary job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PocketCard(
      onTap: () => context.push('/job/${job.id}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow(job.company),
                const SizedBox(height: 4),
                Text(job.role, style: context.text.titleMedium),
                if (job.meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(job.meta, style: context.text.bodySmall?.copyWith(color: context.pocket.mutedForeground)),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [StatusChip(job.status), ScoreBadge(job.score)],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: job.saved ? 'Remove from saved' : 'Save to your shortlist',
            icon: Icon(job.saved ? Icons.bookmark : Icons.bookmark_border),
            onPressed: () async {
              try {
                await ref.read(jobsActionsProvider).setSaved(job.id, !job.saved);
                if (context.mounted) showMessage(context, job.saved ? 'Removed from saved' : 'Saved to your shortlist');
              } catch (e) {
                if (context.mounted) showMessage(context, friendlyError(e));
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Opens the "Add an opportunity" sheet. Navigates to the new (or existing) role.
Future<void> showAddJobSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _AddJobSheet(),
  );
}

class _AddJobSheet extends ConsumerStatefulWidget {
  const _AddJobSheet();

  @override
  ConsumerState<_AddJobSheet> createState() => _AddJobSheetState();
}

class _AddJobSheetState extends ConsumerState<_AddJobSheet> {
  final _form = GlobalKey<FormState>();
  final _company = TextEditingController();
  final _role = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  final _salary = TextEditingController();
  String? _workModel;
  bool _saving = false;
  Map<String, String> _serverErrors = const {};

  @override
  void dispose() {
    for (final c in [_company, _role, _description, _location, _salary]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _serverErrors = const {});
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    try {
      final id = await ref.read(jobsActionsProvider).create(
            company: _company.text.trim(),
            role: _role.text.trim(),
            description: _description.text,
            location: _location.text.trim(),
            workModel: _workModel,
            salaryText: _salary.text.trim(),
          );
      navigator.pop();
      router.push('/job/$id');
    } on DuplicateJob catch (d) {
      setState(() => _saving = false);
      if (!mounted) return;
      final open = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Already in your workspace'),
          content: const Text('You already have this company and role. Open the existing record instead?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open existing')),
          ],
        ),
      );
      if (open == true) {
        navigator.pop();
        router.push('/job/${d.existingId}');
      }
    } on ApiException catch (e) {
      setState(() {
        _saving = false;
        _serverErrors = e.fieldErrors;
      });
      if (e.fieldErrors.isEmpty && mounted) showMessage(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _description.text.trim().length;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add an opportunity', style: context.text.headlineSmall),
              const SizedBox(height: 6),
              Text(
                'Paste the posting you reviewed. It is added to your inbox unverified; check the source, eligibility and pay on the employer site.',
                style: context.text.bodySmall?.copyWith(color: context.pocket.mutedForeground),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _company,
                textCapitalization: TextCapitalization.words,
                decoration: pocketInput(context, label: 'Company', error: _serverErrors['company']),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Add the company.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _role,
                textCapitalization: TextCapitalization.words,
                decoration: pocketInput(context, label: 'Role title', error: _serverErrors['role']),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Add the role title.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                minLines: 6,
                maxLines: 14,
                onChanged: (_) => setState(() {}),
                decoration: pocketInput(
                  context,
                  label: 'Job description',
                  helper: '$count characters · at least 60. Live URLs can\'t be read in this version.',
                  error: _serverErrors['description'],
                ),
                validator: (v) => (v ?? '').trim().length < 60 ? 'Paste at least 60 characters of the job description.' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: TextFormField(controller: _location, decoration: pocketInput(context, label: 'Location (optional)'))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _workModel,
                      isExpanded: true,
                      decoration: pocketInput(context, label: 'Work model'),
                      items: [for (final w in kWorkModels) DropdownMenuItem(value: w, child: Text(w))],
                      onChanged: (v) => setState(() => _workModel = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _salary, decoration: pocketInput(context, label: 'Advertised pay (optional, as written)')),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Add to inbox'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Explains exactly what will be sent before the first AI request for a feature.
Future<bool> showAiConsentSheet(BuildContext context, {required String title, required List<String> sends}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _ConsentSheet(title: title, sends: sends),
  );
  return result ?? false;
}

class _ConsentSheet extends StatefulWidget {
  const _ConsentSheet({required this.title, required this.sends});
  final String title;
  final List<String> sends;

  @override
  State<_ConsentSheet> createState() => _ConsentSheetState();
}

class _ConsentSheetState extends State<_ConsentSheet> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: context.text.headlineSmall),
          const SizedBox(height: 12),
          Text('This request sends:', style: context.text.titleSmall),
          const SizedBox(height: 6),
          for (final s in widget.sends)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [const Text('•  '), Expanded(child: Text(s, style: context.text.bodyMedium))],
              ),
            ),
          const SizedBox(height: 12),
          Notice(
            'Processed by ${AppConfig.aiModelLabel} inside the Career Ops Azure environment. It is not used to train models. '
            'Output can be wrong: review it before you rely on it. Nothing is applied for or sent.',
            icon: Icons.shield_outlined,
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _agreed,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (v) => setState(() => _agreed = v ?? false),
            title: const Text('I consent to send this context to the AI service for this feature.'),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _agreed ? () => Navigator.pop(context, true) : null, child: const Text('Continue')),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ],
      ),
    );
  }
}

/// Runs an AI action, asking for consent the first time the server requires it.
Future<T?> withAiConsent<T>(
  BuildContext context, {
  required String title,
  required List<String> sends,
  required Future<T> Function(bool consent) run,
}) async {
  try {
    return await run(false);
  } on ApiException catch (e) {
    if (!e.isConsentRequired) rethrow;
    if (!context.mounted) return null;
    final ok = await showAiConsentSheet(context, title: title, sends: sends);
    if (!ok) return null;
    return run(true);
  }
}

/// Lets the user flag an AI response (required for generative AI apps on Google Play).
Future<void> reportAiResponse(BuildContext context, WidgetRef ref, String aiRunId) async {
  final controller = TextEditingController();
  final reason = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Report this response'),
      content: TextField(
        controller: controller,
        maxLines: 3,
        decoration: pocketInput(ctx, label: 'What was wrong?', hint: 'Inaccurate, offensive, made something up...'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Report')),
      ],
    ),
  );
  controller.dispose();
  if (reason == null || reason.length < 3) return;
  try {
    await ref.read(jobsActionsProvider).reportAiOutput(aiRunId, reason);
    if (context.mounted) showMessage(context, 'Thanks. The response was reported.');
  } catch (e) {
    if (context.mounted) showMessage(context, friendlyError(e));
  }
}
