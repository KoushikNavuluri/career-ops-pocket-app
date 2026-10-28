import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';
import '../jobs/jobs_repository.dart';
import '../jobs/models.dart';
import '../jobs/widgets.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  void _openMove(BuildContext context, NextMove m) {
    switch (m.kind) {
      case 'add_cv':
        context.push('/cv');
      case 'add_first_role':
        showAddJobSheet(context);
      case 'review_inbox':
        context.go('/pipeline');
      default:
        if (m.jobId != null) context.push('/job/${m.jobId}');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final alias = ref.watch(meProvider).asData?.value.profile.alias;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/assistant'),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Ask Career Ops'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(todayProvider.future),
          child: ContentWidth(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
              children: [
                const Align(alignment: Alignment.centerLeft, child: BrandMark(size: 26)),
                const SizedBox(height: 28),
                const Eyebrow('Your search, in focus'),
                const SizedBox(height: 8),
                Text(alias == null ? 'Good to see you.' : 'Good to see you, $alias.', style: context.text.displayMedium),
                const SizedBox(height: 20),
                today.when(
                  loading: () => const SizedBox(height: 240, child: SkeletonList(rows: 2)),
                  error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(todayProvider)),
                  data: (t) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Counts(counts: t.counts),
                      const SizedBox(height: 20),
                      PocketCard(
                        onTap: () => showAddJobSheet(context),
                        child: Row(
                          children: [
                            Icon(Icons.add_circle_outline, color: context.colors.primary),
                            const SizedBox(width: 12),
                            Expanded(child: Text('Add or review an opportunity', style: context.text.titleMedium)),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      SectionHeader('Your next best moves'),
                      if (t.nextMoves.isEmpty)
                        Text('Nothing urgent. A good day to add a story or tidy your CV.', style: context.text.bodyMedium)
                      else
                        for (final m in t.nextMoves)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: PocketCard(
                              onTap: () => _openMove(context, m),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(m.title, style: context.text.titleSmall),
                                        const SizedBox(height: 4),
                                        Text(m.detail, style: context.text.bodySmall?.copyWith(color: context.pocket.mutedForeground)),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                            ),
                          ),
                      if (t.strongMatches.isNotEmpty) ...[
                        SectionHeader('Worth a closer look', action: 'Explore', onAction: () => context.go('/explore')),
                        for (final j in t.strongMatches) Padding(padding: const EdgeInsets.only(bottom: 10), child: JobCard(job: j)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Counts extends StatelessWidget {
  const _Counts({required this.counts});
  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    Widget tile(String label, String key, VoidCallback onTap) => Expanded(
          child: PocketCard(
            onTap: onTap,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${counts[key] ?? 0}', style: context.text.displaySmall),
                const SizedBox(height: 2),
                Text(label, style: context.text.bodySmall?.copyWith(color: context.pocket.mutedForeground)),
              ],
            ),
          ),
        );
    return Row(
      children: [
        tile('In your pipeline', 'pipeline', () => context.go('/pipeline')),
        const SizedBox(width: 10),
        tile('Interview underway', 'interview', () => context.go('/pipeline')),
        const SizedBox(width: 10),
        tile('Offer on the table', 'offer', () => context.go('/pipeline')),
      ],
    );
  }
}
