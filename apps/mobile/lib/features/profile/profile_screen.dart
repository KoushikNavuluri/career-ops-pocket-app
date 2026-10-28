import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/config.dart';
import '../../app/providers.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';
import '../../core/util/json.dart';

const _markets = ['Europe', 'United States', 'India', 'Global'];
const _workModels = ['Remote', 'Hybrid', 'On-site'];

final consentsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await ref.watch(apiClientProvider).get('/v1/consents');
  return objList(obj(data)['items']);
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('You')),
      body: me.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(meProvider)),
        data: (m) => ContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(m.email ?? 'Signed in', style: context.text.titleMedium),
              Text('${m.plan.toUpperCase()} plan', style: context.text.bodySmall?.copyWith(color: context.pocket.mutedForeground)),
              const SizedBox(height: 20),
              const Eyebrow('Direction'),
              const SizedBox(height: 8),
              _DirectionForm(profile: m.profile),
              const SizedBox(height: 24),
              const Eyebrow('Appearance'),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'system', label: Text('System')),
                  ButtonSegment(value: 'light', label: Text('Light')),
                  ButtonSegment(value: 'evening', label: Text('Evening')),
                ],
                selected: {m.preferences.theme},
                onSelectionChanged: (s) async {
                  final v = s.first;
                  ref.read(themeOverrideProvider.notifier).set(themeModeFromPreference(v));
                  try {
                    await ref.read(apiClientProvider).patch('/v1/preferences', {'theme': v});
                    ref.invalidate(meProvider);
                  } catch (e) {
                    if (context.mounted) showMessage(context, friendlyError(e));
                  } finally {
                    ref.read(themeOverrideProvider.notifier).set(null);
                  }
                },
              ),
              const SizedBox(height: 24),
              const Eyebrow('AI usage'),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: m.usage.fraction, minHeight: 8, borderRadius: BorderRadius.circular(4)),
              const SizedBox(height: 6),
              Text('${m.usage.remaining} of ${m.usage.limit} credits left this month · ${AppConfig.aiModelLabel}', style: context.text.bodySmall),
              const SizedBox(height: 24),
              const Eyebrow('Data & privacy'),
              const _ConsentsList(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.download_outlined),
                title: const Text('Export my data'),
                subtitle: const Text('Copies everything as JSON'),
                onTap: () async {
                  try {
                    final data = await ref.read(apiClientProvider).get('/v1/account/export');
                    await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(data)));
                    if (context.mounted) showMessage(context, 'Your data was copied as JSON.');
                  } catch (e) {
                    if (context.mounted) showMessage(context, friendlyError(e));
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: () => ref.read(authControllerProvider.notifier).signOut(),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_forever_outlined, color: context.colors.error),
                title: Text('Delete account', style: TextStyle(color: context.colors.error)),
                subtitle: const Text('Permanently deletes your account and all career data'),
                onTap: () => _deleteAccount(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Roles, evaluations, CVs, stories, documents and conversations are deleted permanently. Type DELETE to confirm.'),
          const SizedBox(height: 12),
          TextField(controller: controller, decoration: pocketInput(ctx, label: 'Type DELETE')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim() == 'DELETE'), child: const Text('Delete')),
        ],
      ),
    );
    controller.dispose();
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).delete('/v1/account', {'confirm': 'DELETE'});
      await ref.read(authControllerProvider.notifier).signOut();
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e));
    }
  }
}

class _DirectionForm extends ConsumerStatefulWidget {
  const _DirectionForm({required this.profile});
  final Profile profile;

  @override
  ConsumerState<_DirectionForm> createState() => _DirectionFormState();
}

class _DirectionFormState extends ConsumerState<_DirectionForm> {
  late final TextEditingController _role = TextEditingController(text: widget.profile.targetRole ?? '');
  late final TextEditingController _north = TextEditingController(text: widget.profile.northStar ?? '');
  late String? _market = _markets.contains(widget.profile.targetMarket) ? widget.profile.targetMarket : null;
  late String? _workModel = _workModels.contains(widget.profile.workModel) ? widget.profile.workModel : null;
  bool _busy = false;

  @override
  void dispose() {
    _role.dispose();
    _north.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).patch('/v1/profile', {
        'target_role': _role.text.trim().isEmpty ? null : _role.text.trim(),
        'north_star': _north.text.trim().isEmpty ? null : _north.text.trim(),
        'target_market': _market,
        'work_model': _workModel,
      });
      ref.invalidate(meProvider);
      if (mounted) showMessage(context, 'Direction saved.');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(controller: _role, decoration: pocketInput(context, label: 'Target role')),
      const SizedBox(height: 12),
      TextField(controller: _north, minLines: 2, maxLines: 5, decoration: pocketInput(context, label: 'North star', hint: 'What a great next role looks like')),
      const SizedBox(height: 12),
      DropdownButtonFormField<String?>(
        initialValue: _market,
        decoration: pocketInput(context, label: 'Target market'),
        items: [const DropdownMenuItem<String?>(value: null, child: Text('Not set')), for (final m in _markets) DropdownMenuItem<String?>(value: m, child: Text(m))],
        onChanged: (v) => setState(() => _market = v),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String?>(
        initialValue: _workModel,
        decoration: pocketInput(context, label: 'Work model'),
        items: [const DropdownMenuItem<String?>(value: null, child: Text('Not set')), for (final m in _workModels) DropdownMenuItem<String?>(value: m, child: Text(m))],
        onChanged: (v) => setState(() => _workModel = v),
      ),
      const SizedBox(height: 12),
      FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving' : 'Save direction')),
    ]);
  }
}

class _ConsentsList extends ConsumerWidget {
  const _ConsentsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consents = ref.watch(consentsProvider);
    final items = consents.asData?.value ?? const [];
    if (items.isEmpty) {
      return const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.shield_outlined), title: Text('No AI consents granted yet'));
    }
    return Column(children: [
      for (final c in items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.shield_outlined),
          title: Text('AI consent: ${str(c['feature'])}'),
          trailing: TextButton(
            onPressed: () async {
              try {
                await ref.read(apiClientProvider).delete('/v1/consents/${str(c['feature'])}');
                ref.invalidate(consentsProvider);
              } catch (e) {
                if (context.mounted) showMessage(context, friendlyError(e));
              }
            },
            child: const Text('Revoke'),
          ),
        ),
    ]);
  }
}
