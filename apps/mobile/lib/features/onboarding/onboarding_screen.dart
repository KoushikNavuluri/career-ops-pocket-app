import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/api/api_client.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';

const kTargetRoles = ['Senior Product Engineer', 'Frontend Engineer', 'Design Engineer', 'Full-stack Engineer', 'AI Engineer'];
const kMarkets = ['Europe', 'United States', 'India', 'Global'];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  String? _role;
  String? _market;
  bool _saving = false;

  Future<void> _finish({required bool withDirection}) async {
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).patch('/v1/profile', {
        'onboarded': true,
        if (withDirection && _role != null) 'target_role': _role,
        if (withDirection && _market != null) 'target_market': _market,
      });
      ref.invalidate(meProvider);
      if (mounted) context.go('/today');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = [_intro(context), _direction(context), _promises(context)];
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          maxWidth: 560,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (var i = 0; i < 3; i++)
                      Expanded(
                        child: Container(
                          height: 4,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: i <= _step ? context.colors.primary : context.pocket.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 32),
                Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: KeyedSubtree(key: ValueKey(_step), child: steps[_step]))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _intro(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('A more intentional search'),
        const SizedBox(height: 12),
        Text('Find the roles worth your time.', style: context.text.displayMedium),
        const SizedBox(height: 14),
        Text(
          'Career Ops helps you evaluate opportunities against your own evidence, prepare deliberately and keep track of what really happened.',
          style: context.text.bodyLarge?.copyWith(color: context.pocket.mutedForeground),
        ),
        const Spacer(),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () => setState(() => _step = 1), child: const Text('Find my direction'))),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton(onPressed: _saving ? null : () => _finish(withDirection: false), child: const Text('Skip for now')),
        ),
      ],
    );
  }

  Widget _direction(BuildContext context) {
    return ListView(
      children: [
        const Eyebrow('Set your direction'),
        const SizedBox(height: 12),
        Text('What are you aiming for?', style: context.text.displaySmall),
        const SizedBox(height: 24),
        Text('Target role', style: context.text.titleSmall),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in kTargetRoles) ChoiceChip(label: Text(r), selected: _role == r, onSelected: (_) => setState(() => _role = r)),
          ],
        ),
        const SizedBox(height: 24),
        Text('Target market', style: context.text.titleSmall),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in kMarkets) ChoiceChip(label: Text(m), selected: _market == m, onSelected: (_) => setState(() => _market = m)),
          ],
        ),
        const SizedBox(height: 12),
        Text('You can change these any time in You → Direction.', style: context.text.bodySmall?.copyWith(color: context.pocket.mutedForeground)),
        const SizedBox(height: 32),
        FilledButton(onPressed: () => setState(() => _step = 2), child: const Text('Continue')),
        const SizedBox(height: 8),
        TextButton(onPressed: () => setState(() => _step = 0), child: const Text('Go back')),
      ],
    );
  }

  Widget _promises(BuildContext context) {
    Widget promise(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: PocketCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: context.colors.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.text.titleMedium),
                      const SizedBox(height: 4),
                      Text(body, style: context.text.bodyMedium?.copyWith(color: context.pocket.mutedForeground)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    return ListView(
      children: [
        const Eyebrow('Your workspace, your rules'),
        const SizedBox(height: 12),
        Text('Three promises.', style: context.text.displaySmall),
        const SizedBox(height: 24),
        promise(Icons.explore_outlined, 'A search with direction', 'Every role is judged against your north star, not a generic keyword list.'),
        promise(Icons.fact_check_outlined, 'Your story, backed by evidence', 'AI only works from your CV and stories. It never invents experience.'),
        promise(Icons.pan_tool_outlined, 'Human decisions, always', 'Nothing is applied for, sent or scheduled without you doing it yourself.'),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _saving ? null : () => _finish(withDirection: true),
          child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Open my workspace'),
        ),
        TextButton(onPressed: () => setState(() => _step = 1), child: const Text('Go back')),
      ],
    );
  }
}
